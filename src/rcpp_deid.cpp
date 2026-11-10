#include "rcpp_dcmtk.h"
#include "rcpp_crypto.h"
#include <regex>
#include <set>
#include <map>
#include <sstream>
#include <fstream>
#include <algorithm>
#include <cctype>

namespace dicomtk {

// Civil calendar date algorithms (Howard Hinnant / libc++)
struct CivilDate {
  int year;
  int month;
  int day;
};

inline int days_from_civil(int y, unsigned m, unsigned d) noexcept {
  y -= (m <= 2);
  const int era = (y >= 0 ? y : y - 399) / 400;
  const unsigned yoe = static_cast<unsigned>(y - era * 400);
  const unsigned doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return era * 146097 + static_cast<int>(doe) - 719468;
}

inline CivilDate civil_from_days(int z) noexcept {
  z += 719468;
  const int era = (z >= 0 ? z : z - 146096) / 146097;
  const unsigned doe = static_cast<unsigned>(z - era * 146097);
  const unsigned yoe = (doe - doe / 1024 + doe / 1168 - doe / 146096) / 365;
  const int y = static_cast<int>(yoe) + era * 400;
  const unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  const unsigned mp = (5 * doy + 2) / 153;
  const unsigned d = doy - (153 * mp + 2) / 5 + 1;
  const unsigned m = mp < 10 ? mp + 3 : mp - 9;
  return CivilDate{y + (m <= 2), static_cast<int>(m), static_cast<int>(d)};
}

static std::string shift_da(const std::string& da, int shift_days) {
  if (shift_days == 0 || da.size() < 8) return da;
  for (int i = 0; i < 8; ++i) {
    if (!std::isdigit(static_cast<unsigned char>(da[i]))) return da;
  }
  try {
    int y = std::stoi(da.substr(0, 4));
    int m = std::stoi(da.substr(4, 2));
    int d = std::stoi(da.substr(6, 2));
    if (m < 1 || m > 12 || d < 1 || d > 31) return da;
    int cur_days = days_from_civil(y, static_cast<unsigned>(m), static_cast<unsigned>(d));
    cur_days += shift_days;
    CivilDate res = civil_from_days(cur_days);
    char buf[16];
    std::snprintf(buf, sizeof(buf), "%04d%02d%02d", res.year, res.month, res.day);
    return std::string(buf);
  } catch (...) {
    return da;
  }
}

static std::string shift_dt(const std::string& dt, int shift_days) {
  if (shift_days == 0 || dt.size() < 8) return dt;
  std::string da_part = dt.substr(0, 8);
  std::string shifted_da = shift_da(da_part, shift_days);
  return shifted_da + dt.substr(8);
}

static std::string year_only_da(const std::string& da) {
  if (da.size() < 4) return da;
  return da.substr(0, 4) + "0101";
}

static std::string year_only_dt(const std::string& dt) {
  if (dt.size() < 4) return dt;
  std::string res = dt.substr(0, 4) + "0101";
  if (dt.size() > 8) res += dt.substr(8);
  return res;
}

static std::string year_month_da(const std::string& da) {
  if (da.size() < 6) return da;
  return da.substr(0, 6) + "01";
}

static std::string year_month_dt(const std::string& dt) {
  if (dt.size() < 6) return dt;
  std::string res = dt.substr(0, 6) + "01";
  if (dt.size() > 8) res += dt.substr(8);
  return res;
}

static std::string apply_dob_policy(const std::string& da, const std::string& dob_policy, int shift_days) {
  if (dob_policy == "keep") return da;
  if (dob_policy == "dummy") return "19000101";
  if (dob_policy == "year_only") return year_only_da(da);
  if (dob_policy == "year_month") return year_month_da(da);
  if (dob_policy == "shift_per_patient") return shift_da(da, shift_days);
  return da;
}

static bool apply_age_cap(std::string& age_str, int age_cap_years) {
  if (age_cap_years < 0 || age_str.size() < 4) return false;
  char unit = static_cast<char>(std::toupper(static_cast<unsigned char>(age_str.back())));
  if (unit != 'Y') return false; // Infants / weeks / months unaffected

  std::string num_part = age_str.substr(0, age_str.size() - 1);
  for (char c : num_part) {
    if (!std::isdigit(static_cast<unsigned char>(c))) return false;
  }
  try {
    int age = std::stoi(num_part);
    if (age > age_cap_years) {
      int cap = age_cap_years + 1;
      char buf[16];
      std::snprintf(buf, sizeof(buf), "%03dY", cap);
      age_str = buf;
      return true;
    }
  } catch (...) {}
  return false;
}

static inline bool is_text_vr_scrub(const std::string& vr) {
  return (vr == "LT" || vr == "ST" || vr == "UT" || vr == "UC" ||
          vr == "LO" || vr == "SH" || vr == "PN");
}

static std::string normalize_creator_str(const std::string& str) {
  size_t start = 0;
  while (start < str.size() && std::isspace(static_cast<unsigned char>(str[start]))) start++;
  size_t end = str.size();
  while (end > start && (std::isspace(static_cast<unsigned char>(str[end - 1])) || str[end - 1] == '\0')) end--;
  std::string s = str.substr(start, end - start);
  std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) {
    return static_cast<char>(std::toupper(c));
  });
  return s;
}

static std::string trim_trailing_spaces_and_nuls(const std::string& str) {
  size_t end = str.size();
  while (end > 0 && (std::isspace(static_cast<unsigned char>(str[end - 1])) || str[end - 1] == '\0')) {
    end--;
  }
  return str.substr(0, end);
}

static uint16_t parse_group_hex(const std::string& grp_str) {
  if (grp_str.empty()) return 0;
  try {
    return static_cast<uint16_t>(std::stoul(grp_str, nullptr, 16));
  } catch (...) {
    return 0;
  }
}

static std::string lookup_cid7050_meaning(const std::string& code) {
  if (code == "113100") return "Basic Application Confidentiality Profile";
  if (code == "113101") return "Clean Pixel Data Option";
  if (code == "113102") return "Clean Recognizable Visual Features Option";
  if (code == "113103") return "Clean Graphics Option";
  if (code == "113104") return "Clean Structured Content Option";
  if (code == "113105") return "Clean Descriptors Option";
  if (code == "113106") return "Retain Longitudinal Temporal Information Full Dates Option";
  if (code == "113107") return "Retain Longitudinal Temporal Information Modified Dates Option";
  if (code == "113108") return "Retain Patient Characteristics Option";
  if (code == "113109") return "Retain Device Identity Option";
  if (code == "113110") return "Retain Institution Identity Option";
  if (code == "113111") return "Retain Safe Private Option";
  if (code == "113112") return "Retain UIDs Option";
  return "De-identification Method Option";
}

struct DeidContext {
  std::map<std::string, char> tag_actions;
  std::map<std::pair<uint16_t, std::string>, std::set<uint8_t>> safe_private_map;
  bool retain_safe_private = false;
  std::string date_policy = "dummy";
  std::string dob_policy = "";
  int shift_days = 0;
  int age_cap_years = -1;
  std::vector<std::string> regex_patterns;
  bool patient_deid = true;
  std::string pseudo_patient_id;
  std::array<uint8_t, 32> uid_key{};
  std::map<std::string, std::string> uid_map;
  std::vector<std::string> orig_uids;
  std::vector<std::string> new_uids;
  std::map<char, int> action_counts;

  std::string map_uid_single(const std::string& u) {
    if (u.empty()) return "";
    if (u.rfind("1.2.840.10008.", 0) == 0) return u;
    auto it = uid_map.find(u);
    if (it != uid_map.end()) return it->second;
    std::string pseudo = dicomtk::crypto::hmac_dicom_uid(uid_key, u);
    uid_map[u] = pseudo;
    orig_uids.push_back(u);
    new_uids.push_back(pseudo);
    return pseudo;
  }

  std::string map_uid_multi(const std::string& u) {
    if (u.empty()) return "";
    if (u.find('\\') != std::string::npos) {
      std::stringstream ss(u);
      std::string item;
      std::string res;
      bool first = true;
      while (std::getline(ss, item, '\\')) {
        if (!first) res += "\\";
        first = false;
        if (!item.empty()) res += map_uid_single(item);
      }
      return res;
    }
    return map_uid_single(u);
  }
};

static void mutate_element_list(std::vector<DcmElementRecord>& elements,
                               DeidContext& ctx,
                               int depth) {
  if (depth > 64) return;

  // Step A: Discover local private creators in this dataset / item scope
  // Key: (group << 8) | block_number (0x10..0xFF)
  std::map<uint32_t, std::string> local_creators;
  std::map<uint32_t, int> surviving_counts;

  for (const auto& el : elements) {
    if ((el.group % 2 == 1) && el.group > 0x0007) {
      if (el.element >= 0x0010 && el.element <= 0x00FF) {
        uint32_t key = (static_cast<uint32_t>(el.group) << 8) | static_cast<uint32_t>(el.element & 0xFF);
        local_creators[key] = normalize_creator_str(el.value_str);
      }
    }
  }

  // Step B: Filter and mutate elements
  std::vector<DcmElementRecord> new_elements;
  new_elements.reserve(elements.size());
  static const Rcpp::Function r_gsub("gsub");

  for (auto& el : elements) {
    // 1. Private tag handling (odd groups > 0x0007)
    if ((el.group % 2 == 1) && el.group > 0x0007) {
      if (!ctx.retain_safe_private) {
        ctx.action_counts['X']++;
        continue; // Purge all odd group tags
      }
      // Creator reservation tag (0x0010..0x00FF)
      if (el.element >= 0x0010 && el.element <= 0x00FF) {
        // Retain provisionally; orphan creators pruned in Step C
        new_elements.push_back(std::move(el));
        continue;
      }
      // Private data element (0x1000..0xFFFF)
      if (el.element >= 0x1000) {
        uint8_t block = static_cast<uint8_t>((el.element >> 8) & 0xFF);
        uint8_t offset = static_cast<uint8_t>(el.element & 0xFF);
        uint32_t key = (static_cast<uint32_t>(el.group) << 8) | static_cast<uint32_t>(block);
        auto it = local_creators.find(key);
        if (it == local_creators.end()) {
          ctx.action_counts['X']++;
          continue; // Missing creator tag
        }
        const std::string& creator = it->second;
        auto sp_it = ctx.safe_private_map.find({el.group, creator});
        if (sp_it == ctx.safe_private_map.end()) {
          sp_it = ctx.safe_private_map.find({0, creator});
        }
        if (sp_it == ctx.safe_private_map.end()) {
          ctx.action_counts['X']++;
          continue; // Creator not allowlisted for this group
        }
        if (sp_it->second.find(offset) == sp_it->second.end()) {
          ctx.action_counts['X']++;
          continue; // Offset not allowlisted
        }
        // Survives allowlist check!
        surviving_counts[key]++;
        ctx.action_counts['K']++;
        if (el.vr == "SQ" || !el.items.empty()) {
          for (auto& item : el.items) {
            mutate_element_list(item, ctx, depth + 1);
          }
        }
        new_elements.push_back(std::move(el));
        continue;
      }
      // Any other private element < 0x0010
      ctx.action_counts['X']++;
      continue;
    }

    // 2. Wildcard repeating groups (50xx and 60xx)
    if ((el.group & 0xFF00) == 0x5000 || (el.group & 0xFF00) == 0x6000) {
      std::string tag_str = format_tag(el.group, el.element);
      char r_act = 'K';
      auto act_it = ctx.tag_actions.find(tag_str);
      if (act_it != ctx.tag_actions.end()) {
        r_act = act_it->second;
      } else {
        std::string wc = ((el.group & 0xFF00) == 0x5000) ? "(50XX,XXXX)" : "(60XX,XXXX)";
        auto w_it = ctx.tag_actions.find(wc);
        if (w_it != ctx.tag_actions.end()) {
          r_act = w_it->second;
        }
      }
      if (r_act == 'X') {
        ctx.action_counts['X']++;
        continue;
      }
      if (r_act == 'Z') {
        el.value_str = "";
        el.raw_bytes.clear();
        el.items.clear();
        ctx.action_counts['Z']++;
        new_elements.push_back(std::move(el));
        continue;
      }
    }

    // 3. Sequences (SQ)
    if (el.vr == "SQ" || !el.items.empty()) {
      for (auto& item : el.items) {
        mutate_element_list(item, ctx, depth + 1);
      }
      new_elements.push_back(std::move(el));
      continue;
    }

    // 4. Standard Tag Action Lookup
    std::string tag_str = format_tag(el.group, el.element);
    char action = 'K';
    auto act_it = ctx.tag_actions.find(tag_str);
    if (act_it != ctx.tag_actions.end()) {
      action = act_it->second;
    }

    // If patient identity de-identification is disabled, keep (0010,xxxx)
    if (!ctx.patient_deid && el.group == 0x0010) {
      action = 'K';
    }

    // PatientID (0010,0020) replacement with pseudonymous ID if action != 'K'
    if (ctx.patient_deid && el.group == 0x0010 && el.element == 0x0020) {
      if (action != 'K') {
        el.value_str = ctx.pseudo_patient_id;
        el.raw_bytes.clear();
        ctx.action_counts['D']++;
        new_elements.push_back(std::move(el));
        continue;
      }
    }

    // PatientAge (0010,1010) under statutory age cap (e.g. HIPAA Safe Harbor)
    if (el.group == 0x0010 && el.element == 0x1010 && ctx.age_cap_years >= 0 && action != 'K') {
      apply_age_cap(el.value_str, ctx.age_cap_years);
      el.raw_bytes.clear();
      ctx.action_counts['C']++;
      new_elements.push_back(std::move(el));
      continue;
    }

    // Action X: drop tag
    if (action == 'X') {
      ctx.action_counts['X']++;
      continue;
    }

    // Action Z: zero tag
    if (action == 'Z') {
      el.value_str = "";
      el.raw_bytes.clear();
      ctx.action_counts['Z']++;
      new_elements.push_back(std::move(el));
      continue;
    }

    // UIDs: only apply hmac_dicom_uid if action != 'K'
    if (action != 'K' && (action == 'U' || el.vr == "UI")) {
      if (action == 'U' || el.group == 0x0008 || el.group == 0x0020) {
        el.value_str = ctx.map_uid_multi(el.value_str);
        el.raw_bytes.clear();
        ctx.action_counts['U']++;
        new_elements.push_back(std::move(el));
        continue;
      }
    }

    if (action == 'D') {
      if (el.vr == "PN") {
        el.value_str = "ANONYMOUS";
      } else if (el.vr == "DA") {
        el.value_str = "19000101";
      } else if (el.vr == "TM") {
        el.value_str = "000000";
      } else if (el.vr == "DT") {
        el.value_str = "19000101000000";
      } else if (el.vr == "UI") {
        el.value_str = ctx.map_uid_multi(el.value_str);
      } else if (el.vr == "AS") {
        el.value_str = "000Y";
      } else if (el.vr == "IS" || el.vr == "DS") {
        el.value_str = "0";
      } else {
        el.value_str = "ANONYMOUS";
      }
      el.raw_bytes.clear();
      ctx.action_counts['D']++;
      new_elements.push_back(std::move(el));
      continue;
    }

    // Action 'C' or general date/regex cleaning
    bool mutated = false;

    // PatientAge cap
    if (el.group == 0x0010 && el.element == 0x1010 && ctx.age_cap_years >= 0) {
      if (apply_age_cap(el.value_str, ctx.age_cap_years)) {
        mutated = true;
      }
    }

    // Date/Time handling: only shift or dummy if action != 'K'
    if (action != 'K') {
      if (el.vr == "DA") {
        if (el.group == 0x0010 && el.element == 0x0030 && !ctx.dob_policy.empty()) {
          std::string new_da = apply_dob_policy(el.value_str, ctx.dob_policy, ctx.shift_days);
          if (new_da != el.value_str) { el.value_str = new_da; mutated = true; }
        } else if (action == 'C' || ctx.date_policy != "keep") {
          if (ctx.date_policy == "shift_per_patient") {
            std::string new_da = shift_da(el.value_str, ctx.shift_days);
            if (new_da != el.value_str) { el.value_str = new_da; mutated = true; }
          } else if (ctx.date_policy == "year_only") {
            el.value_str = year_only_da(el.value_str); mutated = true;
          } else if (ctx.date_policy == "year_month") {
            el.value_str = year_month_da(el.value_str); mutated = true;
          } else if (ctx.date_policy == "dummy") {
            el.value_str = "19000101"; mutated = true;
          }
        }
      } else if (el.vr == "DT") {
        if (action == 'C' || ctx.date_policy != "keep") {
          if (ctx.date_policy == "shift_per_patient") {
            std::string new_dt = shift_dt(el.value_str, ctx.shift_days);
            if (new_dt != el.value_str) { el.value_str = new_dt; mutated = true; }
          } else if (ctx.date_policy == "year_only") {
            el.value_str = year_only_dt(el.value_str); mutated = true;
          } else if (ctx.date_policy == "year_month") {
            el.value_str = year_month_dt(el.value_str); mutated = true;
          } else if (ctx.date_policy == "dummy") {
            el.value_str = "19000101000000"; mutated = true;
          }
        }
      }
    }

    // Regex text scrubbing for free-text string VRs
    if (!ctx.regex_patterns.empty() && !el.value_str.empty() && is_text_vr_scrub(el.vr)) {
      std::string orig = el.value_str;
      for (const auto& pat : ctx.regex_patterns) {
        try {
          Rcpp::CharacterVector res = r_gsub(Rcpp::Named("pattern") = pat,
                                             Rcpp::Named("replacement") = "[REDACTED]",
                                             Rcpp::Named("x") = el.value_str,
                                             Rcpp::Named("perl") = true);
          if (res.size() > 0 && !Rcpp::CharacterVector::is_na(res[0])) {
            el.value_str = Rcpp::as<std::string>(res[0]);
          }
        } catch (...) {}
      }
      if (el.value_str != orig) mutated = true;
    }

    if (mutated) {
      el.raw_bytes.clear();
      ctx.action_counts['C']++;
    } else {
      ctx.action_counts['K']++;
    }
    new_elements.push_back(std::move(el));
  }

  // Step C: Prune orphan creator tags
  if (ctx.retain_safe_private) {
    std::vector<DcmElementRecord> pruned;
    pruned.reserve(new_elements.size());
    for (auto& el : new_elements) {
      if ((el.group % 2 == 1) && el.group > 0x0007 && el.element >= 0x0010 && el.element <= 0x00FF) {
        uint32_t key = (static_cast<uint32_t>(el.group) << 8) | static_cast<uint32_t>(el.element & 0xFF);
        if (surviving_counts[key] == 0) {
          ctx.action_counts['X']++;
          continue; // Pruned orphan creator
        }
      }
      pruned.push_back(std::move(el));
    }
    elements = std::move(pruned);
  } else {
    elements = std::move(new_elements);
  }
}

} // namespace dicomtk

// [[Rcpp::export]]
Rcpp::List cpp_deid_file(const std::string& in_path,
                         const std::string& out_path,
                         const Rcpp::List& profile_spec,
                         const Rcpp::RawVector& uid_key,
                         const Rcpp::RawVector& pid_key,
                         const Rcpp::RawVector& date_key,
                         bool drop_wsi_labels = true) {
  if (uid_key.size() != 32 || pid_key.size() != 32 || date_key.size() != 32) {
    Rcpp::stop("Cryptographic subkeys (uid_key, pid_key, date_key) must all be exactly 32 raw bytes.");
  }

  dicomtk::DcmParsedFile dcm = dicomtk::parse_dicom_file(in_path, false, 64);
  if (!dcm.valid_dicom) {
    Rcpp::stop("Failed to parse valid DICOM file: " + in_path);
  }

  // Extract core metadata before mutation
  std::string orig_sop_class_uid;
  std::string orig_sop_instance_uid;
  std::string orig_study_uid;
  std::string orig_series_uid;
  std::string orig_patient_id;
  std::string orig_patient_name;
  std::string orig_image_type;

  for (const auto& el : dcm.elements) {
    if (el.depth == 0) {
      if (el.group == 0x0008 && el.element == 0x0016) orig_sop_class_uid = el.value_str;
      else if (el.group == 0x0008 && el.element == 0x0018) orig_sop_instance_uid = el.value_str;
      else if (el.group == 0x0020 && el.element == 0x000D) orig_study_uid = el.value_str;
      else if (el.group == 0x0020 && el.element == 0x000E) orig_series_uid = el.value_str;
      else if (el.group == 0x0010 && el.element == 0x0020) orig_patient_id = el.value_str;
      else if (el.group == 0x0010 && el.element == 0x0010) orig_patient_name = el.value_str;
      else if (el.group == 0x0008 && el.element == 0x0008) orig_image_type = el.value_str;
    }
  }
  orig_patient_id = dicomtk::trim_trailing_spaces_and_nuls(orig_patient_id);
  if (orig_sop_instance_uid.empty()) {
    for (const auto& el : dcm.elements) {
      if (el.depth == 0 && el.group == 0x0002 && el.element == 0x0003) {
        orig_sop_instance_uid = el.value_str;
        break;
      }
    }
  }

  // WSI Detection (VL Whole Slide Microscopy Image Storage)
  const std::string wsi_sop_class = "1.2.840.10008.5.1.4.1.1.77.1.6";
  if (drop_wsi_labels && orig_sop_class_uid == wsi_sop_class) {
    std::string img_type_upper = orig_image_type;
    std::transform(img_type_upper.begin(), img_type_upper.end(), img_type_upper.begin(), ::toupper);
    if (img_type_upper.find("LABEL") != std::string::npos ||
        img_type_upper.find("OVERVIEW") != std::string::npos) {
      return Rcpp::List::create(
        Rcpp::Named("status") = "skipped_wsi_label",
        Rcpp::Named("skipped_wsi_label") = true,
        Rcpp::Named("orig_patient_id") = orig_patient_id,
        Rcpp::Named("pseudo_patient_id") = "",
        Rcpp::Named("orig_study_uid") = orig_study_uid,
        Rcpp::Named("pseudo_study_uid") = "",
        Rcpp::Named("orig_series_uid") = orig_series_uid,
        Rcpp::Named("pseudo_series_uid") = "",
        Rcpp::Named("orig_sop_uid") = orig_sop_instance_uid,
        Rcpp::Named("pseudo_sop_uid") = "",
        Rcpp::Named("orig_uids") = Rcpp::CharacterVector::create(),
        Rcpp::Named("new_uids") = Rcpp::CharacterVector::create(),
        Rcpp::Named("shift_days") = 0L,
        Rcpp::Named("in_sha256") = dicomtk::crypto::sha256_file_hex(in_path),
        Rcpp::Named("out_sha256") = "",
        Rcpp::Named("actions_applied") = Rcpp::IntegerVector::create(
          Rcpp::Named("X") = 0, Rcpp::Named("Z") = 0, Rcpp::Named("D") = 0,
          Rcpp::Named("U") = 0, Rcpp::Named("C") = 0, Rcpp::Named("K") = 0
        )
      );
    }
  }

  // Setup DeidContext
  dicomtk::DeidContext ctx;
  std::memcpy(ctx.uid_key.data(), uid_key.begin(), 32);
  std::array<uint8_t, 32> pid_k{};
  std::memcpy(pid_k.data(), pid_key.begin(), 32);
  std::array<uint8_t, 32> date_k{};
  std::memcpy(date_k.data(), date_key.begin(), 32);

  // Initialize action counts
  ctx.action_counts['X'] = 0;
  ctx.action_counts['Z'] = 0;
  ctx.action_counts['D'] = 0;
  ctx.action_counts['U'] = 0;
  ctx.action_counts['C'] = 0;
  ctx.action_counts['K'] = 0;

  // Unpack profile_spec
  if (profile_spec.containsElementNamed("tag_actions")) {
    Rcpp::CharacterVector ta = profile_spec["tag_actions"];
    Rcpp::CharacterVector ta_names = ta.names();
    for (R_xlen_t i = 0; i < ta.size(); ++i) {
      std::string t = Rcpp::as<std::string>(ta_names[i]);
      std::string a = Rcpp::as<std::string>(ta[i]);
      if (!a.empty()) ctx.tag_actions[t] = a[0];
    }
  } else if (profile_spec.containsElementNamed("tags")) {
    SEXP tags_sexp = profile_spec["tags"];
    if (TYPEOF(tags_sexp) == VECSXP) {
      Rcpp::List tags_list(tags_sexp);
      if (tags_list.containsElementNamed("tag") && tags_list.containsElementNamed("action")) {
        Rcpp::CharacterVector tg_vec = tags_list["tag"];
        Rcpp::CharacterVector act_vec = tags_list["action"];
        for (R_xlen_t i = 0; i < tg_vec.size(); ++i) {
          std::string t = Rcpp::as<std::string>(tg_vec[i]);
          std::string a = Rcpp::as<std::string>(act_vec[i]);
          if (!a.empty()) ctx.tag_actions[t] = a[0];
        }
      }
    }
  }

  // Safe private allowlist
  if (profile_spec.containsElementNamed("safe_private")) {
    SEXP sp_sexp = profile_spec["safe_private"];
    if (TYPEOF(sp_sexp) == VECSXP) {
      Rcpp::List sp_list(sp_sexp);
      if (sp_list.size() > 0) {
        Rcpp::CharacterVector sp_names = sp_list.names();
        for (R_xlen_t i = 0; i < sp_list.size(); ++i) {
          std::string creator = dicomtk::normalize_creator_str(Rcpp::as<std::string>(sp_names[i]));
          uint16_t grp = 0;
          SEXP val = sp_list[i];
          if (TYPEOF(val) == VECSXP) {
            Rcpp::List val_list(val);
            if (val_list.containsElementNamed("group")) {
              SEXP g_sexp = val_list["group"];
              if (TYPEOF(g_sexp) == STRSXP && LENGTH(g_sexp) > 0) {
                std::string g_str = Rcpp::as<std::string>(g_sexp);
                grp = dicomtk::parse_group_hex(g_str);
              } else if (TYPEOF(g_sexp) == INTSXP || TYPEOF(g_sexp) == REALSXP) {
                grp = static_cast<uint16_t>(Rcpp::as<int>(g_sexp));
              }
            }
            if (val_list.containsElementNamed("offsets")) {
              Rcpp::IntegerVector offs = val_list["offsets"];
              for (int off : offs) {
                ctx.safe_private_map[{grp, creator}].insert(static_cast<uint8_t>(off & 0xFF));
              }
            }
          } else if (TYPEOF(val) == INTSXP || TYPEOF(val) == REALSXP) {
            Rcpp::IntegerVector offs(val);
            for (int off : offs) {
              ctx.safe_private_map[{grp, creator}].insert(static_cast<uint8_t>(off & 0xFF));
            }
          }
        }
      }
    }
  }

  if (profile_spec.containsElementNamed("retain_safe_private")) {
    ctx.retain_safe_private = Rcpp::as<bool>(profile_spec["retain_safe_private"]);
  } else if (profile_spec.containsElementNamed("options")) {
    Rcpp::CharacterVector opts = profile_spec["options"];
    for (R_xlen_t i = 0; i < opts.size(); ++i) {
      if (opts[i] == "retain_safe_private") {
        ctx.retain_safe_private = true;
        break;
      }
    }
  } else if (!ctx.safe_private_map.empty()) {
    ctx.retain_safe_private = true;
  }

  if (profile_spec.containsElementNamed("date_policy")) {
    ctx.date_policy = Rcpp::as<std::string>(profile_spec["date_policy"]);
  }
  if (profile_spec.containsElementNamed("dob_policy") && !Rf_isNull(profile_spec["dob_policy"])) {
    ctx.dob_policy = Rcpp::as<std::string>(profile_spec["dob_policy"]);
  }
  if (profile_spec.containsElementNamed("age_cap_years") && !Rf_isNull(profile_spec["age_cap_years"])) {
    ctx.age_cap_years = Rcpp::as<int>(profile_spec["age_cap_years"]);
  }
  if (profile_spec.containsElementNamed("patient_deid")) {
    ctx.patient_deid = Rcpp::as<bool>(profile_spec["patient_deid"]);
  }

  // Regex patterns
  if (profile_spec.containsElementNamed("regex_patterns")) {
    Rcpp::CharacterVector rp = profile_spec["regex_patterns"];
    for (R_xlen_t i = 0; i < rp.size(); ++i) {
      std::string pat = Rcpp::as<std::string>(rp[i]);
      if (!pat.empty()) ctx.regex_patterns.push_back(std::move(pat));
    }
  } else if (profile_spec.containsElementNamed("regex_scrubbers")) {
    Rcpp::CharacterVector rp = profile_spec["regex_scrubbers"];
    for (R_xlen_t i = 0; i < rp.size(); ++i) {
      std::string pat = Rcpp::as<std::string>(rp[i]);
      if (!pat.empty()) ctx.regex_patterns.push_back(std::move(pat));
    }
  }

  // Deterministic Pseudonym & Date Shift calculation
  std::string patient_key_str = orig_patient_id.empty() ? orig_study_uid : orig_patient_id;
  auto pid_mac = dicomtk::crypto::hmac_sha256(pid_k.data(), pid_k.size(),
                                              reinterpret_cast<const uint8_t*>(patient_key_str.data()),
                                              patient_key_str.size());
  ctx.pseudo_patient_id = "SUBJ-" + dicomtk::crypto::to_hex(pid_mac.data(), 6);
  std::transform(ctx.pseudo_patient_id.begin(), ctx.pseudo_patient_id.end(), ctx.pseudo_patient_id.begin(), ::toupper);

  if (profile_spec.containsElementNamed("explicit_shift_days") && !Rf_isNull(profile_spec["explicit_shift_days"])) {
    ctx.shift_days = Rcpp::as<int>(profile_spec["explicit_shift_days"]);
  } else if (ctx.date_policy == "shift_per_patient") {
    ctx.shift_days = dicomtk::crypto::hmac_patient_shift_days(date_k, patient_key_str, -3650, -30);
  } else {
    ctx.shift_days = 0;
  }

  // Execute recursive mutation
  dicomtk::mutate_element_list(dcm.elements, ctx, 0);

  // Synchronize File Meta MediaStorageSOPInstanceUID (0002,0003) with SOPInstanceUID (0008,0018)
  std::string final_sop_uid;
  for (const auto& el : dcm.elements) {
    if (el.depth == 0 && el.group == 0x0008 && el.element == 0x0018) {
      final_sop_uid = el.value_str;
      break;
    }
  }
  if (!final_sop_uid.empty()) {
    dicomtk::upsert_tag(dcm, 0x0002, 0x0003, final_sop_uid);
  }

  // Stamp CID 7050 metadata
  dicomtk::upsert_tag(dcm, 0x0012, 0x0062, "YES"); // PatientIdentityRemoved

  std::string deid_method_str = "DICOM PS 3.15 Annex E / dicomtk";
  if (profile_spec.containsElementNamed("deid_method_str") && !Rf_isNull(profile_spec["deid_method_str"])) {
    deid_method_str = Rcpp::as<std::string>(profile_spec["deid_method_str"]);
  } else if (profile_spec.containsElementNamed("description") && !Rf_isNull(profile_spec["description"])) {
    deid_method_str = Rcpp::as<std::string>(profile_spec["description"]);
  }
  dicomtk::upsert_tag(dcm, 0x0012, 0x0063, deid_method_str);

  // CID 7050 code items
  std::vector<std::string> cid_codes;
  std::map<std::string, std::string> custom_meanings;
  if (profile_spec.containsElementNamed("cid7050_codes")) {
    Rcpp::CharacterVector cv = profile_spec["cid7050_codes"];
    SEXP names_sexp = cv.names();
    bool has_names = !Rf_isNull(names_sexp);
    Rcpp::CharacterVector cv_names;
    if (has_names) cv_names = Rcpp::CharacterVector(names_sexp);
    for (R_xlen_t i = 0; i < cv.size(); ++i) {
      std::string val = Rcpp::as<std::string>(cv[i]);
      if (has_names && cv_names.size() > i && !Rcpp::as<std::string>(cv_names[i]).empty()) {
        std::string code = Rcpp::as<std::string>(cv_names[i]);
        cid_codes.push_back(code);
        custom_meanings[code] = val;
      } else {
        cid_codes.push_back(val);
      }
    }
  }
  if (cid_codes.empty()) {
    cid_codes.push_back("113100");
  }

  std::vector<std::vector<dicomtk::DcmElementRecord>> code_items;
  code_items.reserve(cid_codes.size());
  for (const auto& code : cid_codes) {
    std::string meaning = custom_meanings.count(code) ? custom_meanings[code] : dicomtk::lookup_cid7050_meaning(code);
    std::vector<dicomtk::DcmElementRecord> item_elems;

    dicomtk::DcmElementRecord r_code;
    r_code.group = 0x0008; r_code.element = 0x0100; r_code.vr = "SH";
    r_code.name = "Code Value"; r_code.keyword = "CodeValue"; r_code.vm = "1";
    r_code.value_str = code; r_code.depth = 1;
    item_elems.push_back(std::move(r_code));

    dicomtk::DcmElementRecord r_sch;
    r_sch.group = 0x0008; r_sch.element = 0x0102; r_sch.vr = "SH";
    r_sch.name = "Coding Scheme Designator"; r_sch.keyword = "CodingSchemeDesignator"; r_sch.vm = "1";
    r_sch.value_str = "DCM"; r_sch.depth = 1;
    item_elems.push_back(std::move(r_sch));

    dicomtk::DcmElementRecord r_mean;
    r_mean.group = 0x0008; r_mean.element = 0x0104; r_mean.vr = "LO";
    r_mean.name = "Code Meaning"; r_mean.keyword = "CodeMeaning"; r_mean.vm = "1";
    r_mean.value_str = meaning; r_mean.depth = 1;
    item_elems.push_back(std::move(r_mean));

    code_items.push_back(std::move(item_elems));
  }
  dicomtk::upsert_sq_tag(dcm, 0x0012, 0x0064, std::move(code_items));

  // Write output DICOM file
  bool ok = dicomtk::write_dicom_file(dcm, out_path);
  if (!ok) {
    Rcpp::stop("Failed to write de-identified DICOM file to: " + out_path);
  }

  // Digest calculations
  std::string in_hash = dicomtk::crypto::sha256_file_hex(in_path);
  std::string out_hash = dicomtk::crypto::sha256_file_hex(out_path);

  // Primary UIDs and PatientID extraction from final dataset
  std::string pseudo_sop_uid = orig_sop_instance_uid;
  std::string pseudo_study_uid = orig_study_uid;
  std::string pseudo_series_uid = orig_series_uid;
  std::string final_pseudo_patient_id = ctx.pseudo_patient_id;

  for (const auto& el : dcm.elements) {
    if (el.depth == 0) {
      if (el.group == 0x0008 && el.element == 0x0018) pseudo_sop_uid = el.value_str;
      else if (el.group == 0x0020 && el.element == 0x000D) pseudo_study_uid = el.value_str;
      else if (el.group == 0x0020 && el.element == 0x000E) pseudo_series_uid = el.value_str;
      else if (el.group == 0x0010 && el.element == 0x0020) final_pseudo_patient_id = el.value_str;
    }
  }
  if (pseudo_sop_uid.empty() && !orig_sop_instance_uid.empty()) {
    pseudo_sop_uid = ctx.map_uid_single(orig_sop_instance_uid);
  }

  return Rcpp::List::create(
    Rcpp::Named("status") = "ok",
    Rcpp::Named("skipped_wsi_label") = false,
    Rcpp::Named("orig_patient_id") = orig_patient_id,
    Rcpp::Named("pseudo_patient_id") = final_pseudo_patient_id,
    Rcpp::Named("orig_study_uid") = orig_study_uid,
    Rcpp::Named("pseudo_study_uid") = pseudo_study_uid,
    Rcpp::Named("orig_series_uid") = orig_series_uid,
    Rcpp::Named("pseudo_series_uid") = pseudo_series_uid,
    Rcpp::Named("orig_sop_uid") = orig_sop_instance_uid,
    Rcpp::Named("pseudo_sop_uid") = pseudo_sop_uid,
    Rcpp::Named("orig_uids") = Rcpp::wrap(ctx.orig_uids),
    Rcpp::Named("new_uids") = Rcpp::wrap(ctx.new_uids),
    Rcpp::Named("shift_days") = ctx.shift_days,
    Rcpp::Named("in_sha256") = in_hash,
    Rcpp::Named("out_sha256") = out_hash,
    Rcpp::Named("actions_applied") = Rcpp::IntegerVector::create(
      Rcpp::Named("X") = ctx.action_counts['X'],
      Rcpp::Named("Z") = ctx.action_counts['Z'],
      Rcpp::Named("D") = ctx.action_counts['D'],
      Rcpp::Named("U") = ctx.action_counts['U'],
      Rcpp::Named("C") = ctx.action_counts['C'],
      Rcpp::Named("K") = ctx.action_counts['K']
    )
  );
}
