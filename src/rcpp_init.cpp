#include "rcpp_dcmtk.h"
#include <cctype>

namespace dicomtk {

static bool g_codecs_registered = false;

std::string format_tag(uint16_t group, uint16_t element) {
  char buf[16];
  std::snprintf(buf, sizeof(buf), "(%04X,%04X)", group, element);
  return std::string(buf);
}

const DcmDictEntry* lookup_dict_tag(uint16_t group, uint16_t element) {
  std::size_t lo = 0;
  std::size_t hi = kBuiltinDictSize;
  while (lo < hi) {
    std::size_t mid = lo + (hi - lo) / 2;
    const DcmDictEntry& e = kBuiltinDict[mid];
    if (e.group < group || (e.group == group && e.element < element)) {
      lo = mid + 1;
    } else if (e.group > group || (e.group == group && e.element > element)) {
      hi = mid;
    } else {
      return &e;
    }
  }
  // Fallback linear scan in case any entries in dicom.dic were out of order
  for (std::size_t i = 0; i < kBuiltinDictSize; ++i) {
    if (kBuiltinDict[i].group == group && kBuiltinDict[i].element == element) {
      return &kBuiltinDict[i];
    }
  }
  return nullptr;
}

static std::string to_lower_str(const std::string& s) {
  std::string out = s;
  for (char& c : out) {
    c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  }
  return out;
}

bool parse_tag_string(const std::string& str, uint16_t& group, uint16_t& element) {
  std::string s;
  for (char c : str) {
    if (std::isxdigit(static_cast<unsigned char>(c))) {
      s.push_back(c);
    }
  }
  if (s.size() == 8 && (str.find(',') != std::string::npos || str.front() == '(' || str.size() == 8)) {
    try {
      group = static_cast<uint16_t>(std::stoul(s.substr(0, 4), nullptr, 16));
      element = static_cast<uint16_t>(std::stoul(s.substr(4, 4), nullptr, 16));
      return true;
    } catch (...) {
      return false;
    }
  }
  return false;
}

const DcmDictEntry* lookup_dict_keyword(const std::string& keyword_or_tag) {
  uint16_t g = 0, e = 0;
  if (parse_tag_string(keyword_or_tag, g, e)) {
    return lookup_dict_tag(g, e);
  }
  std::string needle = to_lower_str(keyword_or_tag);
  for (std::size_t i = 0; i < kBuiltinDictSize; ++i) {
    if (to_lower_str(kBuiltinDict[i].keyword) == needle ||
        to_lower_str(kBuiltinDict[i].name) == needle) {
      return &kBuiltinDict[i];
    }
  }
  return nullptr;
}

std::string generate_dicom_uid(const std::string& prefix) {
  static std::mt19937_64 rng(
      static_cast<uint64_t>(std::chrono::high_resolution_clock::now().time_since_epoch().count()));
  uint64_t a = rng();
  uint64_t b = rng();
  std::ostringstream oss;
  oss << prefix << "." << (a % 9000000000000000000ULL + 100000000000000000ULL)
      << "." << (b % 900000000000ULL + 10000000000ULL);
  std::string uid = oss.str();
  if (uid.size() > 64) {
    uid.resize(64);
    if (uid.back() == '.') uid.pop_back();
  }
  return uid;
}

} // namespace dicomtk

// [[Rcpp::export]]
void cpp_dcmtk_init() {
  if (!dicomtk::g_codecs_registered) {
#ifdef DICOMTK_HAVE_DCMTK
    DcmRLEDecoderRegistration::registerCodecs();
    DcmRLEEncoderRegistration::registerCodecs();
    DJDecoderRegistration::registerCodecs();
    DJEncoderRegistration::registerCodecs();
#endif
    dicomtk::g_codecs_registered = true;
  }
}

// [[Rcpp::export]]
void cpp_dcmtk_cleanup() {
  if (dicomtk::g_codecs_registered) {
#ifdef DICOMTK_HAVE_DCMTK
    DcmRLEDecoderRegistration::cleanup();
    DcmRLEEncoderRegistration::cleanup();
    DJDecoderRegistration::cleanup();
    DJEncoderRegistration::cleanup();
#endif
    dicomtk::g_codecs_registered = false;
  }
}

// [[Rcpp::export]]
Rcpp::List cpp_dcmtk_version() {
#ifdef DICOMTK_HAVE_DCMTK
  std::string backend = "DCMTK C++ Library + Native C++17 Engine";
#else
  std::string backend = "Bundled DCMTK 3.7.1 Dictionary & Native C++17 Engine";
#endif
  return Rcpp::List::create(
    Rcpp::_["dcmtk_version"] = "3.7.1",
    Rcpp::_["dictionary_standard"] = "PS 3.6-2026d / PS 3.7-2026d",
    Rcpp::_["dictionary_entries"] = static_cast<int>(dicomtk::kBuiltinDictSize),
    Rcpp::_["backend"] = backend,
    Rcpp::_["codecs_registered"] = dicomtk::g_codecs_registered
  );
}

// [[Rcpp::export]]
Rcpp::DataFrame cpp_dict_lookup(const std::string& query) {
  std::vector<std::string> tags;
  std::vector<std::string> names;
  std::vector<std::string> keywords;
  std::vector<std::string> vrs;
  std::vector<std::string> vms;

  std::string q_lower = query;
  for (char& c : q_lower) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));

  uint16_t g = 0, e = 0;
  bool is_exact_tag = dicomtk::parse_tag_string(query, g, e);

  for (std::size_t i = 0; i < dicomtk::kBuiltinDictSize; ++i) {
    const auto& entry = dicomtk::kBuiltinDict[i];
    bool match = false;
    if (is_exact_tag) {
      match = (entry.group == g && entry.element == e);
    } else if (q_lower.empty()) {
      match = true;
    } else {
      std::string kw = entry.keyword;
      std::string nm = entry.name;
      std::string tg = dicomtk::format_tag(entry.group, entry.element);
      for (char& c : kw) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
      for (char& c : nm) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
      for (char& c : tg) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
      if (kw.find(q_lower) != std::string::npos ||
          nm.find(q_lower) != std::string::npos ||
          tg.find(q_lower) != std::string::npos) {
        match = true;
      }
    }
    if (match) {
      tags.push_back(dicomtk::format_tag(entry.group, entry.element));
      names.push_back(entry.name);
      keywords.push_back(entry.keyword);
      vrs.push_back(entry.vr);
      vms.push_back(entry.vm);
    }
  }

  return Rcpp::DataFrame::create(
    Rcpp::_["tag"] = tags,
    Rcpp::_["name"] = names,
    Rcpp::_["keyword"] = keywords,
    Rcpp::_["vr"] = vrs,
    Rcpp::_["vm"] = vms,
    Rcpp::_["stringsAsFactors"] = false
  );
}
