#include "rcpp_dcmtk.h"

namespace dicomtk {

static void append_u16_le(std::vector<uint8_t>& buf, uint16_t v) {
  buf.push_back(static_cast<uint8_t>(v & 0xFF));
  buf.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
}

static void append_u32_le(std::vector<uint8_t>& buf, uint32_t v) {
  buf.push_back(static_cast<uint8_t>(v & 0xFF));
  buf.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
  buf.push_back(static_cast<uint8_t>((v >> 16) & 0xFF));
  buf.push_back(static_cast<uint8_t>((v >> 24) & 0xFF));
}

static bool is_long_vr_write(const std::string& vr) {
  return (vr == "OB" || vr == "OD" || vr == "OF" || vr == "OL" ||
          vr == "OV" || vr == "OW" || vr == "SQ" || vr == "SV" ||
          vr == "UC" || vr == "UN" || vr == "UR" || vr == "UT" ||
          vr == "UV");
}

static bool is_string_vr_write(const std::string& vr) {
  return (vr == "AE" || vr == "AS" || vr == "CS" || vr == "DA" ||
          vr == "DS" || vr == "DT" || vr == "IS" || vr == "LO" ||
          vr == "LT" || vr == "PN" || vr == "SH" || vr == "ST" ||
          vr == "TM" || vr == "UC" || vr == "UI" || vr == "UR" ||
          vr == "UT");
}

static std::vector<uint8_t> encode_element_bytes(const DcmElementRecord& el) {
  if (!el.raw_bytes.empty()) {
    std::vector<uint8_t> b = el.raw_bytes;
    if (b.size() % 2 == 1) {
      b.push_back(el.vr == "UI" || el.vr == "OB" ? 0 : ' ');
    }
    return b;
  }

  std::vector<uint8_t> out;
  const std::string& vr = el.vr;
  const std::string& s = el.value_str;

  if (is_string_vr_write(vr)) {
    out.assign(s.begin(), s.end());
    if (out.size() % 2 == 1) {
      out.push_back(vr == "UI" ? '\0' : ' ');
    }
    return out;
  }

  if (vr == "US") {
    std::stringstream ss(s);
    std::string tok;
    while (std::getline(ss, tok, '\\')) {
      uint16_t v = 0;
      try { v = static_cast<uint16_t>(std::stoul(tok)); } catch (...) {}
      append_u16_le(out, v);
    }
    return out;
  }
  if (vr == "SS") {
    std::stringstream ss(s);
    std::string tok;
    while (std::getline(ss, tok, '\\')) {
      int16_t v = 0;
      try { v = static_cast<int16_t>(std::stoi(tok)); } catch (...) {}
      append_u16_le(out, static_cast<uint16_t>(v));
    }
    return out;
  }
  if (vr == "UL") {
    std::stringstream ss(s);
    std::string tok;
    while (std::getline(ss, tok, '\\')) {
      uint32_t v = 0;
      try { v = static_cast<uint32_t>(std::stoul(tok)); } catch (...) {}
      append_u32_le(out, v);
    }
    return out;
  }
  if (vr == "SL") {
    std::stringstream ss(s);
    std::string tok;
    while (std::getline(ss, tok, '\\')) {
      int32_t v = 0;
      try { v = static_cast<int32_t>(std::stol(tok)); } catch (...) {}
      append_u32_le(out, static_cast<uint32_t>(v));
    }
    return out;
  }
  if (vr == "FL") {
    std::stringstream ss(s);
    std::string tok;
    while (std::getline(ss, tok, '\\')) {
      float f = 0.0f;
      try { f = std::stof(tok); } catch (...) {}
      uint32_t u = 0;
      std::memcpy(&u, &f, 4);
      append_u32_le(out, u);
    }
    return out;
  }
  if (vr == "FD") {
    std::stringstream ss(s);
    std::string tok;
    while (std::getline(ss, tok, '\\')) {
      double d = 0.0;
      try { d = std::stod(tok); } catch (...) {}
      uint64_t u = 0;
      std::memcpy(&u, &d, 8);
      append_u32_le(out, static_cast<uint32_t>(u & 0xFFFFFFFFULL));
      append_u32_le(out, static_cast<uint32_t>((u >> 32) & 0xFFFFFFFFULL));
    }
    return out;
  }

  out.assign(s.begin(), s.end());
  if (out.size() % 2 == 1) out.push_back(0);
  return out;
}

static void write_explicit_element(std::vector<uint8_t>& buf,
                                   uint16_t group,
                                   uint16_t element,
                                   const std::string& vr_in,
                                   const std::vector<uint8_t>& val_bytes) {
  std::string vr = (vr_in.size() == 2) ? vr_in : "UN";
  append_u16_le(buf, group);
  append_u16_le(buf, element);
  buf.push_back(static_cast<uint8_t>(vr[0]));
  buf.push_back(static_cast<uint8_t>(vr[1]));

  std::vector<uint8_t> padded = val_bytes;
  if (padded.size() % 2 == 1) {
    padded.push_back(vr == "UI" || !is_string_vr_write(vr) ? 0 : ' ');
  }

  if (is_long_vr_write(vr)) {
    append_u16_le(buf, 0);
    append_u32_le(buf, static_cast<uint32_t>(padded.size()));
  } else {
    append_u16_le(buf, static_cast<uint16_t>(padded.size()));
  }
  buf.insert(buf.end(), padded.begin(), padded.end());
}

bool write_dicom_file(const DcmParsedFile& dcm, const std::string& out_path) {
  std::vector<DcmElementRecord> meta_elems;
  std::vector<DcmElementRecord> body_elems;

  for (const auto& el : dcm.elements) {
    if (el.depth > 0) continue; // Top-level elements
    if (el.group == 0x7FE0 && el.element == 0x0010) continue;
    if (el.element == 0x0000) continue; // Skip group lengths, recalculated for 0002
    if (el.group == 0x0002) {
      meta_elems.push_back(el);
    } else if (el.group > 0x0002) {
      body_elems.push_back(el);
    }
  }

  auto cmp = [](const DcmElementRecord& a, const DcmElementRecord& b) {
    if (a.group != b.group) return a.group < b.group;
    return a.element < b.element;
  };
  std::sort(meta_elems.begin(), meta_elems.end(), cmp);
  std::sort(body_elems.begin(), body_elems.end(), cmp);

  // Ensure (0002,0010) TransferSyntaxUID is present in meta_elems
  bool has_ts = false;
  for (auto& m : meta_elems) {
    if (m.element == 0x0010) {
      m.value_str = dcm.transfer_syntax;
      m.raw_bytes.clear();
      has_ts = true;
    }
  }
  if (!has_ts) {
    DcmElementRecord ts_el;
    ts_el.group = 0x0002;
    ts_el.element = 0x0010;
    ts_el.vr = "UI";
    ts_el.value_str = dcm.transfer_syntax;
    meta_elems.push_back(ts_el);
    std::sort(meta_elems.begin(), meta_elems.end(), cmp);
  }

  std::vector<uint8_t> meta_buf;
  for (const auto& el : meta_elems) {
    if (el.vr == "SQ") continue;
    write_explicit_element(meta_buf, el.group, el.element, el.vr, encode_element_bytes(el));
  }

  std::vector<uint8_t> file_buf(128, 0);
  file_buf.push_back('D');
  file_buf.push_back('I');
  file_buf.push_back('C');
  file_buf.push_back('M');

  // Write (0002,0000) FileMetaInformationGroupLength
  std::vector<uint8_t> gl_bytes;
  append_u32_le(gl_bytes, static_cast<uint32_t>(meta_buf.size()));
  write_explicit_element(file_buf, 0x0002, 0x0000, "UL", gl_bytes);
  file_buf.insert(file_buf.end(), meta_buf.begin(), meta_buf.end());

  // Write dataset elements
  for (const auto& el : body_elems) {
    if (el.vr == "SQ") continue;
    write_explicit_element(file_buf, el.group, el.element, el.vr, encode_element_bytes(el));
  }

  // Write Pixel Data (7FE0,0010) if present
  if (dcm.encapsulated_pixels && !dcm.pixel_fragments.empty()) {
    append_u16_le(file_buf, 0x7FE0);
    append_u16_le(file_buf, 0x0010);
    file_buf.push_back('O');
    file_buf.push_back('B');
    append_u16_le(file_buf, 0);
    append_u32_le(file_buf, 0xFFFFFFFFU);

    // Basic Offset Table item (empty)
    append_u16_le(file_buf, 0xFFFE);
    append_u16_le(file_buf, 0xE000);
    append_u32_le(file_buf, 0);

    for (const auto& frag : dcm.pixel_fragments) {
      append_u16_le(file_buf, 0xFFFE);
      append_u16_le(file_buf, 0xE000);
      uint32_t flen = static_cast<uint32_t>(frag.size() + (frag.size() % 2));
      append_u32_le(file_buf, flen);
      file_buf.insert(file_buf.end(), frag.begin(), frag.end());
      if (frag.size() % 2 == 1) file_buf.push_back(0);
    }

    // Sequence Delimitation Item (FFFE,E0DD)
    append_u16_le(file_buf, 0xFFFE);
    append_u16_le(file_buf, 0xE0DD);
    append_u32_le(file_buf, 0);
  } else if (!dcm.pixel_data.empty()) {
    write_explicit_element(file_buf, 0x7FE0, 0x0010, "OW", dcm.pixel_data);
  }

  std::ofstream ofs(out_path, std::ios::binary | std::ios::trunc);
  if (!ofs.good()) {
    Rcpp::stop("Cannot open output path for writing DICOM: " + out_path);
  }
  ofs.write(reinterpret_cast<const char*>(file_buf.data()), static_cast<std::streamsize>(file_buf.size()));
  return ofs.good();
}

static void upsert_tag(DcmParsedFile& dcm,
                       uint16_t group,
                       uint16_t element,
                       const std::string& val_str) {
  const DcmDictEntry* dict = lookup_dict_tag(group, element);
  std::string vr = dict ? dict->vr : "LO";

  for (auto& el : dcm.elements) {
    if (el.depth == 0 && el.group == group && el.element == element) {
      el.value_str = val_str;
      el.raw_bytes.clear();
      return;
    }
  }

  DcmElementRecord rec;
  rec.group = group;
  rec.element = element;
  rec.vr = vr;
  rec.name = dict ? dict->name : "Custom Tag";
  rec.keyword = dict ? dict->keyword : "CustomTag";
  rec.vm = dict ? dict->vm : "1";
  rec.value_str = val_str;
  rec.depth = 0;
  dcm.elements.push_back(std::move(rec));
}

} // namespace dicomtk

// [[Rcpp::export]]
bool cpp_modify_dicom(const std::string& in_path,
                      const std::string& out_path,
                      const Rcpp::CharacterVector& mod_tags,
                      const Rcpp::CharacterVector& mod_values,
                      const Rcpp::CharacterVector& del_tags,
                      bool erase_private = false,
                      bool regenerate_uids = false) {
  dicomtk::DcmParsedFile dcm = dicomtk::parse_dicom_file(in_path, false, 0);
  if (!dcm.encapsulated_pixels) {
    dcm.transfer_syntax = "1.2.840.10008.1.2.1";
    dcm.explicit_vr = true;
    dcm.big_endian = false;
  }

  // Delete requested tags and optionally private tags
  std::vector<std::pair<uint16_t, uint16_t>> del_list;
  for (R_xlen_t i = 0; i < del_tags.size(); ++i) {
    std::string q = Rcpp::as<std::string>(del_tags[i]);
    uint16_t g = 0, e = 0;
    if (dicomtk::parse_tag_string(q, g, e)) {
      del_list.emplace_back(g, e);
    } else {
      const auto* entry = dicomtk::lookup_dict_keyword(q);
      if (entry) del_list.emplace_back(entry->group, entry->element);
    }
  }

  dcm.elements.erase(
      std::remove_if(dcm.elements.begin(), dcm.elements.end(),
                     [&](const dicomtk::DcmElementRecord& el) {
                       if (erase_private && (el.group % 2 == 1)) return true;
                       for (const auto& p : del_list) {
                         if (el.group == p.first && el.element == p.second) return true;
                       }
                       return false;
                     }),
      dcm.elements.end());

  // Modify / insert tags
  R_xlen_t nmod = std::min(mod_tags.size(), mod_values.size());
  for (R_xlen_t i = 0; i < nmod; ++i) {
    std::string q = Rcpp::as<std::string>(mod_tags[i]);
    std::string val = Rcpp::as<std::string>(mod_values[i]);
    uint16_t g = 0, e = 0;
    if (!dicomtk::parse_tag_string(q, g, e)) {
      const auto* entry = dicomtk::lookup_dict_keyword(q);
      if (!entry) {
        Rcpp::stop("Unknown DICOM tag or keyword in dicom_modify: " + q);
      }
      g = entry->group;
      e = entry->element;
    }
    dicomtk::upsert_tag(dcm, g, e, val);
  }

  if (regenerate_uids) {
    std::string sop_uid = dicomtk::generate_dicom_uid();
    std::string study_uid = dicomtk::generate_dicom_uid();
    std::string series_uid = dicomtk::generate_dicom_uid();
    dicomtk::upsert_tag(dcm, 0x0008, 0x0018, sop_uid);    // SOPInstanceUID
    dicomtk::upsert_tag(dcm, 0x0002, 0x0003, sop_uid);    // MediaStorageSOPInstanceUID
    dicomtk::upsert_tag(dcm, 0x0020, 0x000D, study_uid);  // StudyInstanceUID
    dicomtk::upsert_tag(dcm, 0x0020, 0x000E, series_uid); // SeriesInstanceUID
  }

  return dicomtk::write_dicom_file(dcm, out_path);
}

// [[Rcpp::export]]
bool cpp_write_dicom_matrix(const Rcpp::NumericVector& pixels,
                            const std::string& out_path,
                            const Rcpp::CharacterVector& meta_tags,
                            const Rcpp::CharacterVector& meta_values) {
  Rcpp::IntegerVector dims = pixels.attr("dim");
  if (dims.size() < 2) {
    Rcpp::stop("pixels must be at least a 2D matrix [rows, cols]");
  }
  int rows = dims[0];
  int cols = dims[1];
  int frames = (dims.size() >= 3) ? dims[2] : 1;

  dicomtk::DcmParsedFile dcm;
  dcm.valid_dicom = true;
  dcm.has_preamble = true;
  dcm.transfer_syntax = "1.2.840.10008.1.2.1";
  dcm.explicit_vr = true;
  dcm.big_endian = false;

  std::string sop_class = "1.2.840.10008.5.1.4.1.1.7"; // Secondary Capture Image Storage
  std::string sop_uid = dicomtk::generate_dicom_uid();
  std::string study_uid = dicomtk::generate_dicom_uid();
  std::string series_uid = dicomtk::generate_dicom_uid();

  dicomtk::upsert_tag(dcm, 0x0002, 0x0002, sop_class);
  dicomtk::upsert_tag(dcm, 0x0002, 0x0003, sop_uid);
  dicomtk::upsert_tag(dcm, 0x0002, 0x0010, dcm.transfer_syntax);
  dicomtk::upsert_tag(dcm, 0x0002, 0x0012, "1.2.276.0.7230010.3.0.3.7.1");
  dicomtk::upsert_tag(dcm, 0x0002, 0x0013, "DICOMTK_371");

  dicomtk::upsert_tag(dcm, 0x0008, 0x0016, sop_class);
  dicomtk::upsert_tag(dcm, 0x0008, 0x0018, sop_uid);
  dicomtk::upsert_tag(dcm, 0x0008, 0x0060, "OT");
  dicomtk::upsert_tag(dcm, 0x0020, 0x000D, study_uid);
  dicomtk::upsert_tag(dcm, 0x0020, 0x000E, series_uid);

  dicomtk::upsert_tag(dcm, 0x0028, 0x0002, "1");
  dicomtk::upsert_tag(dcm, 0x0028, 0x0004, "MONOCHROME2");
  if (frames > 1) {
    dicomtk::upsert_tag(dcm, 0x0028, 0x0008, std::to_string(frames));
  }
  dicomtk::upsert_tag(dcm, 0x0028, 0x0010, std::to_string(rows));
  dicomtk::upsert_tag(dcm, 0x0028, 0x0011, std::to_string(cols));
  dicomtk::upsert_tag(dcm, 0x0028, 0x0100, "16");
  dicomtk::upsert_tag(dcm, 0x0028, 0x0101, "16");
  dicomtk::upsert_tag(dcm, 0x0028, 0x0102, "15");

  // Determine if signed pixels are present
  bool has_negative = false;
  for (R_xlen_t i = 0; i < pixels.size(); ++i) {
    if (pixels[i] < 0) {
      has_negative = true;
      break;
    }
  }
  dicomtk::upsert_tag(dcm, 0x0028, 0x0103, has_negative ? "1" : "0");

  // Apply user metadata overrides
  R_xlen_t nmeta = std::min(meta_tags.size(), meta_values.size());
  for (R_xlen_t i = 0; i < nmeta; ++i) {
    std::string q = Rcpp::as<std::string>(meta_tags[i]);
    std::string val = Rcpp::as<std::string>(meta_values[i]);
    uint16_t g = 0, e = 0;
    if (!dicomtk::parse_tag_string(q, g, e)) {
      const auto* entry = dicomtk::lookup_dict_keyword(q);
      if (entry) {
        g = entry->group;
        e = entry->element;
      } else {
        continue;
      }
    }
    dicomtk::upsert_tag(dcm, g, e, val);
  }

  // Pack 16-bit pixels row-by-row
  std::size_t npix = static_cast<std::size_t>(rows) * cols * frames;
  dcm.pixel_data.resize(npix * 2);
  std::size_t out_idx = 0;
  for (int f = 0; f < frames; ++f) {
    for (int r = 0; r < rows; ++r) {
      for (int c = 0; c < cols; ++c) {
        std::size_t r_idx = static_cast<std::size_t>(r) +
                            static_cast<std::size_t>(c) * rows +
                            static_cast<std::size_t>(f) * rows * cols;
        double v = pixels[r_idx];
        if (!R_finite(v)) v = 0.0;
        uint16_t u = has_negative
                       ? static_cast<uint16_t>(static_cast<int16_t>(std::round(v)))
                       : static_cast<uint16_t>(std::max(0.0, std::min(65535.0, std::round(v))));
        dcm.pixel_data[out_idx++] = static_cast<uint8_t>(u & 0xFF);
        dcm.pixel_data[out_idx++] = static_cast<uint8_t>((u >> 8) & 0xFF);
      }
    }
  }

  return dicomtk::write_dicom_file(dcm, out_path);
}
