#include "rcpp_dcmtk.h"
#include <cctype>

namespace dicomtk {

static inline uint16_t read_u16(const uint8_t* p, bool big_endian) {
  if (big_endian) {
    return (static_cast<uint16_t>(p[0]) << 8) | static_cast<uint16_t>(p[1]);
  }
  return static_cast<uint16_t>(p[0]) | (static_cast<uint16_t>(p[1]) << 8);
}

static inline int16_t read_s16(const uint8_t* p, bool big_endian) {
  return static_cast<int16_t>(read_u16(p, big_endian));
}

static inline uint32_t read_u32(const uint8_t* p, bool big_endian) {
  if (big_endian) {
    return (static_cast<uint32_t>(p[0]) << 24) |
           (static_cast<uint32_t>(p[1]) << 16) |
           (static_cast<uint32_t>(p[2]) << 8) |
           static_cast<uint32_t>(p[3]);
  }
  return static_cast<uint32_t>(p[0]) |
         (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) |
         (static_cast<uint32_t>(p[3]) << 24);
}

static inline int32_t read_s32(const uint8_t* p, bool big_endian) {
  return static_cast<int32_t>(read_u32(p, big_endian));
}

static inline float read_f32(const uint8_t* p, bool big_endian) {
  uint32_t u = read_u32(p, big_endian);
  float f = 0.0f;
  std::memcpy(&f, &u, sizeof(float));
  return f;
}

static inline double read_f64(const uint8_t* p, bool big_endian) {
  uint64_t u = 0;
  if (big_endian) {
    for (int i = 0; i < 8; ++i) u = (u << 8) | p[i];
  } else {
    for (int i = 7; i >= 0; --i) u = (u << 8) | p[i];
  }
  double d = 0.0;
  std::memcpy(&d, &u, sizeof(double));
  return d;
}

static bool is_valid_vr_code(const char* vr) {
  static const char* const kValidVRs[] = {
    "AE", "AS", "AT", "CS", "DA", "DS", "DT", "FL", "FD", "IS",
    "LO", "LT", "OB", "OD", "OF", "OL", "OV", "OW", "PN", "SH",
    "SL", "SQ", "SS", "ST", "SV", "TM", "UC", "UI", "UL", "UN",
    "UR", "US", "UT", "UV", "ox", "xs"
  };
  for (const char* v : kValidVRs) {
    if (vr[0] == v[0] && vr[1] == v[1]) return true;
  }
  return false;
}

static bool is_long_length_vr(const std::string& vr) {
  return (vr == "OB" || vr == "OD" || vr == "OF" || vr == "OL" ||
          vr == "OV" || vr == "OW" || vr == "SQ" || vr == "SV" ||
          vr == "UC" || vr == "UN" || vr == "UR" || vr == "UT" ||
          vr == "UV");
}

static bool is_string_vr(const std::string& vr) {
  return (vr == "AE" || vr == "AS" || vr == "CS" || vr == "DA" ||
          vr == "DS" || vr == "DT" || vr == "IS" || vr == "LO" ||
          vr == "LT" || vr == "PN" || vr == "SH" || vr == "ST" ||
          vr == "TM" || vr == "UC" || vr == "UI" || vr == "UR" ||
          vr == "UT");
}

static std::string decode_element_value(const std::string& vr,
                                        const uint8_t* data,
                                        uint32_t len,
                                        bool big_endian) {
  if (len == 0 || data == nullptr) return "";

  if (is_string_vr(vr)) {
    std::string s(reinterpret_cast<const char*>(data), len);
    while (!s.empty() && (s.back() == '\0' || s.back() == ' ' || s.back() == '\r' || s.back() == '\n')) {
      s.pop_back();
    }
    while (!s.empty() && s.front() == ' ' && vr != "LT" && vr != "UT" && vr != "ST") {
      s.erase(s.begin());
    }
    // Replace internal NULs if any
    for (char& c : s) {
      if (c == '\0') c = ' ';
    }
    return s;
  }

  std::ostringstream oss;
  if (vr == "US") {
    uint32_t n = len / 2;
    for (uint32_t i = 0; i < n && i < 64; ++i) {
      if (i > 0) oss << "\\";
      oss << read_u16(data + i * 2, big_endian);
    }
    return oss.str();
  }
  if (vr == "SS") {
    uint32_t n = len / 2;
    for (uint32_t i = 0; i < n && i < 64; ++i) {
      if (i > 0) oss << "\\";
      oss << read_s16(data + i * 2, big_endian);
    }
    return oss.str();
  }
  if (vr == "UL") {
    uint32_t n = len / 4;
    for (uint32_t i = 0; i < n && i < 64; ++i) {
      if (i > 0) oss << "\\";
      oss << read_u32(data + i * 4, big_endian);
    }
    return oss.str();
  }
  if (vr == "SL") {
    uint32_t n = len / 4;
    for (uint32_t i = 0; i < n && i < 64; ++i) {
      if (i > 0) oss << "\\";
      oss << read_s32(data + i * 4, big_endian);
    }
    return oss.str();
  }
  if (vr == "FL" || vr == "OF") {
    uint32_t n = len / 4;
    for (uint32_t i = 0; i < n && i < 32; ++i) {
      if (i > 0) oss << "\\";
      oss << read_f32(data + i * 4, big_endian);
    }
    return oss.str();
  }
  if (vr == "FD" || vr == "OD") {
    uint32_t n = len / 8;
    for (uint32_t i = 0; i < n && i < 32; ++i) {
      if (i > 0) oss << "\\";
      oss << read_f64(data + i * 8, big_endian);
    }
    return oss.str();
  }
  if (vr == "AT") {
    uint32_t n = len / 4;
    for (uint32_t i = 0; i < n && i < 32; ++i) {
      if (i > 0) oss << "\\";
      uint16_t g = read_u16(data + i * 4, big_endian);
      uint16_t e = read_u16(data + i * 4 + 2, big_endian);
      oss << format_tag(g, e);
    }
    return oss.str();
  }

  // For UN/OB/OW: if all bytes are printable ASCII, return string; otherwise hex preview
  bool all_printable = (len <= 128);
  if (all_printable) {
    for (uint32_t i = 0; i < len; ++i) {
      uint8_t b = data[i];
      if (b != 0 && (b < 32 || b > 126)) {
        all_printable = false;
        break;
      }
    }
  }
  if (all_printable && len > 0) {
    std::string s(reinterpret_cast<const char*>(data), len);
    while (!s.empty() && (s.back() == '\0' || s.back() == ' ')) s.pop_back();
    if (!s.empty()) return s;
  }

  uint32_t show = std::min<uint32_t>(len, 16);
  oss << std::hex << std::uppercase << std::setfill('0');
  for (uint32_t i = 0; i < show; ++i) {
    if (i > 0) oss << "\\";
    oss << std::setw(2) << static_cast<int>(data[i]);
  }
  if (len > show) oss << "...";
  return oss.str();
}

bool check_is_dicom_file(const std::string& path) {
  std::ifstream ifs(path, std::ios::binary);
  if (!ifs.good()) return false;

  uint8_t header[136];
  std::memset(header, 0, sizeof(header));
  ifs.read(reinterpret_cast<char*>(header), sizeof(header));
  std::streamsize n = ifs.gcount();
  if (n < 8) return false;

  if (n >= 132 && header[128] == 'D' && header[129] == 'I' &&
      header[130] == 'C' && header[131] == 'M') {
    return true;
  }

  // Check if starts with valid group 0x0002 or 0x0008
  uint16_t g_le = read_u16(header, false);
  uint16_t e_le = read_u16(header + 2, false);
  if ((g_le == 0x0002 || g_le == 0x0008) && e_le <= 0x0100) {
    return true;
  }
  return false;
}

static void parse_dataset_range(const std::vector<uint8_t>& buf,
                                std::size_t& pos,
                                std::size_t end_pos,
                                DcmParsedFile& out,
                                bool stop_at_pixels,
                                int depth,
                                int max_depth,
                                const std::string& seq_prefix) {
  while (pos + 8 <= end_pos && pos + 8 <= buf.size()) {
    uint16_t group_le = read_u16(&buf[pos], false);
    bool in_meta = (group_le == 0x0002);
    bool big_endian = in_meta ? false : out.big_endian;
    bool explicit_vr = in_meta ? true : out.explicit_vr;

    uint16_t group = read_u16(&buf[pos], big_endian);
    uint16_t element = read_u16(&buf[pos + 2], big_endian);
    pos += 4;

    // Handle Item / Sequence Delimitation tags (FFFE,E000 / FFFE,E00D / FFFE,E0DD)
    if (group == 0xFFFE) {
      if (pos + 4 > buf.size()) break;
      uint32_t item_len = read_u32(&buf[pos], big_endian);
      pos += 4;
      if (element == 0xE00D || element == 0xE0DD) {
        // End of item or sequence
        break;
      }
      if (element == 0xE000) {
        if (item_len == 0xFFFFFFFFU) {
          parse_dataset_range(buf, pos, end_pos, out, stop_at_pixels, depth, max_depth, seq_prefix);
        } else {
          std::size_t item_end = std::min<std::size_t>(pos + item_len, buf.size());
          parse_dataset_range(buf, pos, item_end, out, stop_at_pixels, depth, max_depth, seq_prefix);
          pos = item_end;
        }
        continue;
      }
    }

    const DcmDictEntry* dict = lookup_dict_tag(group, element);
    std::string vr;
    uint32_t length = 0;

    // Group length (gggg,0000) is always UL
    if (explicit_vr) {
      char vr_chars[3] = {
        static_cast<char>(buf[pos]),
        static_cast<char>(buf[pos + 1]),
        '\0'
      };
      if (is_valid_vr_code(vr_chars)) {
        vr = vr_chars;
        pos += 2;
        if (is_long_length_vr(vr)) {
          if (pos + 6 > buf.size()) break;
          pos += 2; // skip 2 reserved bytes
          length = read_u32(&buf[pos], big_endian);
          pos += 4;
        } else {
          length = read_u16(&buf[pos], big_endian);
          pos += 2;
        }
      } else {
        // Fallback if implicit VR encountered inside explicit stream
        vr = dict ? dict->vr : (element == 0x0000 ? "UL" : "UN");
        length = read_u32(&buf[pos], big_endian);
        pos += 4;
      }
    } else {
      vr = dict ? dict->vr : (element == 0x0000 ? "UL" : "UN");
      length = read_u32(&buf[pos], big_endian);
      pos += 4;
    }

    // Handle Pixel Data (7FE0,0010) at top level
    if (group == 0x7FE0 && element == 0x0010 && depth == 0) {
      if (stop_at_pixels) {
        DcmElementRecord rec;
        rec.group = group;
        rec.element = element;
        rec.vr = vr;
        rec.length = length;
        rec.name = dict ? dict->name : "Pixel Data";
        rec.keyword = dict ? dict->keyword : "PixelData";
        rec.vm = dict ? dict->vm : "1";
        rec.value_str = "[Pixel Data]";
        rec.depth = depth;
        rec.seq_path = seq_prefix;
        out.elements.push_back(std::move(rec));
        return;
      }

      if (length == 0xFFFFFFFFU) {
        out.encapsulated_pixels = true;
        // Parse encapsulated fragments (FFFE,E000) until Sequence Delimitation (FFFE,E0DD)
        bool first_item = true;
        while (pos + 8 <= buf.size()) {
          uint16_t fg = read_u16(&buf[pos], big_endian);
          uint16_t fe = read_u16(&buf[pos + 2], big_endian);
          uint32_t flen = read_u32(&buf[pos + 4], big_endian);
          pos += 8;
          if (fg == 0xFFFE && fe == 0xE0DD) {
            break;
          }
          if (fg == 0xFFFE && fe == 0xE000) {
            if (pos + flen > buf.size()) flen = static_cast<uint32_t>(buf.size() - pos);
            if (!first_item && flen > 0) {
              out.pixel_fragments.emplace_back(buf.begin() + pos, buf.begin() + pos + flen);
            }
            first_item = false;
            pos += flen;
          } else {
            break;
          }
        }
        DcmElementRecord rec;
        rec.group = group;
        rec.element = element;
        rec.vr = vr;
        rec.length = static_cast<uint32_t>(out.pixel_fragments.size());
        rec.name = dict ? dict->name : "Pixel Data";
        rec.keyword = dict ? dict->keyword : "PixelData";
        rec.vm = dict ? dict->vm : "1";
        rec.value_str = "[Encapsulated Pixel Data]";
        rec.depth = depth;
        rec.seq_path = seq_prefix;
        out.elements.push_back(std::move(rec));
        continue;
      } else {
        std::size_t avail = (pos <= buf.size()) ? (buf.size() - pos) : 0;
        std::size_t actual_len = std::min<std::size_t>(length, avail);
        out.pixel_data.assign(buf.begin() + pos, buf.begin() + pos + actual_len);
        pos += actual_len;

        DcmElementRecord rec;
        rec.group = group;
        rec.element = element;
        rec.vr = vr;
        rec.length = static_cast<uint32_t>(actual_len);
        rec.name = dict ? dict->name : "Pixel Data";
        rec.keyword = dict ? dict->keyword : "PixelData";
        rec.vm = dict ? dict->vm : "1";
        rec.value_str = "[Pixel Data]";
        rec.depth = depth;
        rec.seq_path = seq_prefix;
        out.elements.push_back(std::move(rec));
        continue;
      }
    }

    // Sequence (SQ) or undefined length element
    if (vr == "SQ" || length == 0xFFFFFFFFU) {
      DcmElementRecord rec;
      rec.group = group;
      rec.element = element;
      rec.vr = "SQ";
      rec.length = (length == 0xFFFFFFFFU) ? 0 : length;
      rec.name = dict ? dict->name : "Sequence";
      rec.keyword = dict ? dict->keyword : "Sequence";
      rec.vm = dict ? dict->vm : "1";
      rec.value_str = "[Sequence]";
      rec.depth = depth;
      rec.seq_path = seq_prefix;
      out.elements.push_back(rec);

      std::string next_prefix = seq_prefix.empty()
                                  ? format_tag(group, element)
                                  : (seq_prefix + "/" + format_tag(group, element));
      if (length == 0xFFFFFFFFU) {
        parse_dataset_range(buf, pos, end_pos, out, stop_at_pixels, depth + 1, std::max(max_depth, depth + 1), next_prefix);
      } else {
        std::size_t sq_end = std::min<std::size_t>(pos + length, buf.size());
        if (depth < max_depth && length > 0) {
          parse_dataset_range(buf, pos, sq_end, out, stop_at_pixels, depth + 1, max_depth, next_prefix);
        }
        pos = sq_end;
      }
      continue;
    }

    if (pos + length > buf.size()) {
      break;
    }

    DcmElementRecord rec;
    rec.group = group;
    rec.element = element;
    rec.vr = vr;
    rec.length = length;
    if (dict) {
      rec.name = dict->name;
      rec.keyword = dict->keyword;
      rec.vm = dict->vm;
    } else if (element == 0x0000) {
      rec.name = "Group Length";
      rec.keyword = "GroupLength";
      rec.vm = "1";
    } else if (group % 2 == 1) {
      rec.name = "Private Tag";
      rec.keyword = "PrivateTag";
      rec.vm = "1";
    } else {
      rec.name = "Unknown Tag & Data";
      rec.keyword = "UnknownTag";
      rec.vm = "1";
    }
    rec.depth = depth;
    rec.seq_path = seq_prefix;
    rec.value_str = decode_element_value(vr, &buf[pos], length, big_endian);
    if (length <= 65536 || (group == 0x0042 && element == 0x0011)) {
      rec.raw_bytes.assign(buf.begin() + pos, buf.begin() + pos + length);
    }

    // Update transfer syntax from (0002,0010)
    if (group == 0x0002 && element == 0x0010) {
      out.transfer_syntax = rec.value_str;
      if (out.transfer_syntax == "1.2.840.10008.1.2") {
        out.explicit_vr = false;
        out.big_endian = false;
      } else if (out.transfer_syntax == "1.2.840.10008.1.2.2") {
        out.explicit_vr = true;
        out.big_endian = true;
      } else {
        out.explicit_vr = true;
        out.big_endian = false;
      }
    }

    out.elements.push_back(std::move(rec));
    pos += length;
  }
}

DcmParsedFile parse_dicom_file(const std::string& path, bool stop_at_pixels, int max_depth) {
  DcmParsedFile result;
  result.filepath = path;

  std::ifstream ifs(path, std::ios::binary | std::ios::ate);
  if (!ifs.good()) {
    Rcpp::stop("Cannot open DICOM file: " + path);
  }
  std::streamsize file_size = ifs.tellg();
  if (file_size < 8) {
    Rcpp::stop("File is too small to be a valid DICOM file: " + path);
  }
  ifs.seekg(0, std::ios::beg);

  std::vector<uint8_t> buf(static_cast<std::size_t>(file_size));
  if (!ifs.read(reinterpret_cast<char*>(buf.data()), file_size)) {
    Rcpp::stop("Failed reading DICOM file: " + path);
  }

  std::size_t pos = 0;
  if (buf.size() >= 132 && buf[128] == 'D' && buf[129] == 'I' &&
      buf[130] == 'C' && buf[131] == 'M') {
    result.has_preamble = true;
    result.valid_dicom = true;
    pos = 132;
  } else {
    uint16_t g = read_u16(&buf[0], false);
    uint16_t e = read_u16(&buf[2], false);
    if ((g == 0x0002 || g == 0x0008) && e <= 0x0100) {
      result.has_preamble = false;
      result.valid_dicom = true;
      // Check if first tag has explicit VR
      char vr_c[3] = {static_cast<char>(buf[4]), static_cast<char>(buf[5]), '\0'};
      result.explicit_vr = is_valid_vr_code(vr_c);
      pos = 0;
    } else {
      Rcpp::stop("File does not appear to be a valid DICOM file (missing DICM magic or valid initial tag): " + path);
    }
  }

  parse_dataset_range(buf, pos, buf.size(), result, stop_at_pixels, 0, max_depth, "");
  return result;
}

} // namespace dicomtk

// [[Rcpp::export]]
bool cpp_is_dicom(const std::string& path) {
  return dicomtk::check_is_dicom_file(path);
}

// [[Rcpp::export]]
Rcpp::DataFrame cpp_read_dicom_header(const std::string& path,
                                      bool include_sequences = false,
                                      bool stop_at_pixels = true) {
  dicomtk::DcmParsedFile dcm = dicomtk::parse_dicom_file(path, stop_at_pixels, include_sequences ? 8 : 0);

  std::vector<std::string> files;
  std::vector<std::string> tags;
  std::vector<std::string> groups;
  std::vector<std::string> elements;
  std::vector<std::string> vrs;
  std::vector<int> lengths;
  std::vector<std::string> vms;
  std::vector<std::string> keywords;
  std::vector<std::string> names;
  std::vector<std::string> values;
  std::vector<int> depths;
  std::vector<std::string> seq_paths;

  for (const auto& el : dcm.elements) {
    if (!include_sequences && el.depth > 0) continue;
    char g_buf[8], e_buf[8];
    std::snprintf(g_buf, sizeof(g_buf), "%04X", el.group);
    std::snprintf(e_buf, sizeof(e_buf), "%04X", el.element);

    files.push_back(path);
    tags.push_back(dicomtk::format_tag(el.group, el.element));
    groups.push_back(g_buf);
    elements.push_back(e_buf);
    vrs.push_back(el.vr);
    lengths.push_back(static_cast<int>(el.length));
    vms.push_back(el.vm);
    keywords.push_back(el.keyword);
    names.push_back(el.name);
    values.push_back(el.value_str);
    depths.push_back(el.depth);
    seq_paths.push_back(el.seq_path);
  }

  return Rcpp::DataFrame::create(
    Rcpp::_["file"] = files,
    Rcpp::_["tag"] = tags,
    Rcpp::_["group"] = groups,
    Rcpp::_["element"] = elements,
    Rcpp::_["vr"] = vrs,
    Rcpp::_["length"] = lengths,
    Rcpp::_["vm"] = vms,
    Rcpp::_["keyword"] = keywords,
    Rcpp::_["name"] = names,
    Rcpp::_["value"] = values,
    Rcpp::_["depth"] = depths,
    Rcpp::_["sequence_path"] = seq_paths,
    Rcpp::_["stringsAsFactors"] = false
  );
}

// [[Rcpp::export]]
Rcpp::CharacterVector cpp_get_tag_values(const std::string& path,
                                         const Rcpp::CharacterVector& queries) {
  dicomtk::DcmParsedFile dcm = dicomtk::parse_dicom_file(path, true, 2);
  Rcpp::CharacterVector out(queries.size(), NA_STRING);
  Rcpp::CharacterVector out_names(queries.size());

  for (R_xlen_t i = 0; i < queries.size(); ++i) {
    std::string q = Rcpp::as<std::string>(queries[i]);
    out_names[i] = q;

    uint16_t target_g = 0, target_e = 0;
    bool has_tag = dicomtk::parse_tag_string(q, target_g, target_e);
    if (!has_tag) {
      const auto* entry = dicomtk::lookup_dict_keyword(q);
      if (entry) {
        target_g = entry->group;
        target_e = entry->element;
        has_tag = true;
      }
    }

    for (const auto& el : dcm.elements) {
      if (has_tag) {
        if (el.group == target_g && el.element == target_e) {
          out[i] = el.value_str;
          break;
        }
      } else {
        if (el.keyword == q || el.name == q) {
          out[i] = el.value_str;
          break;
        }
      }
    }
  }
  out.attr("names") = out_names;
  return out;
}
