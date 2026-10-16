#include "rcpp_dcmtk.h"

// [[Rcpp::export]]
Rcpp::DataFrame cpp_read_dicom_sr(const std::string& path) {
  dicomtk::DcmParsedFile dcm = dicomtk::parse_dicom_file(path, true, 12);

  std::vector<int> depths;
  std::vector<std::string> seq_paths;
  std::vector<std::string> tags;
  std::vector<std::string> keywords;
  std::vector<std::string> vrs;
  std::vector<std::string> values;

  for (const auto& el : dcm.elements) {
    // Include SR Content Sequence (0040,A730), Concept Name Code Sequence (0040,A043),
    // ValueType (0040,A040), TextValue (0040,A160), CodeValue (0008,0100), CodeMeaning (0008,0104),
    // and top-level document headers (0008,xxxx), (0010,xxxx), (0020,xxxx), (0040,xxxx)
    if (el.group == 0x0008 || el.group == 0x0010 || el.group == 0x0020 || el.group == 0x0040) {
      depths.push_back(el.depth);
      seq_paths.push_back(el.seq_path);
      tags.push_back(dicomtk::format_tag(el.group, el.element));
      keywords.push_back(el.keyword);
      vrs.push_back(el.vr);
      values.push_back(el.value_str);
    }
  }

  return Rcpp::DataFrame::create(
    Rcpp::_["depth"] = depths,
    Rcpp::_["sequence_path"] = seq_paths,
    Rcpp::_["tag"] = tags,
    Rcpp::_["keyword"] = keywords,
    Rcpp::_["vr"] = vrs,
    Rcpp::_["value"] = values,
    Rcpp::_["stringsAsFactors"] = false
  );
}

// [[Rcpp::export]]
bool cpp_create_dicom_sr(const std::string& out_path,
                         const std::string& title,
                         const std::string& text_content,
                         const std::string& patient_name = "ANONYMOUS",
                         const std::string& patient_id = "ANON001",
                         const std::string& study_uid = "") {
  dicomtk::DcmParsedFile dcm;
  dcm.valid_dicom = true;
  dcm.has_preamble = true;
  dcm.transfer_syntax = "1.2.840.10008.1.2.1";
  dcm.explicit_vr = true;
  dcm.big_endian = false;

  std::string sop_class = "1.2.840.10008.5.1.4.1.1.88.11"; // Basic Text SR Storage
  std::string sop_uid = dicomtk::generate_dicom_uid();
  std::string st_uid = study_uid.empty() ? dicomtk::generate_dicom_uid() : study_uid;
  std::string ser_uid = dicomtk::generate_dicom_uid();

  auto add_tag = [&](uint16_t g, uint16_t e, const std::string& vr, const std::string& val) {
    dicomtk::DcmElementRecord r;
    r.group = g;
    r.element = e;
    r.vr = vr;
    r.value_str = val;
    r.depth = 0;
    dcm.elements.push_back(std::move(r));
  };

  add_tag(0x0002, 0x0002, "UI", sop_class);
  add_tag(0x0002, 0x0003, "UI", sop_uid);
  add_tag(0x0002, 0x0010, "UI", dcm.transfer_syntax);
  add_tag(0x0002, 0x0012, "UI", "1.2.276.0.7230010.3.0.3.7.1");
  add_tag(0x0002, 0x0013, "SH", "DICOMTK_371");

  add_tag(0x0008, 0x0005, "CS", "ISO_IR 192");
  add_tag(0x0008, 0x0016, "UI", sop_class);
  add_tag(0x0008, 0x0018, "UI", sop_uid);
  add_tag(0x0008, 0x0060, "CS", "SR");
  add_tag(0x0008, 0x103E, "LO", title);

  add_tag(0x0010, 0x0010, "PN", patient_name);
  add_tag(0x0010, 0x0020, "LO", patient_id);

  add_tag(0x0020, 0x000D, "UI", st_uid);
  add_tag(0x0020, 0x000E, "UI", ser_uid);
  add_tag(0x0020, 0x0013, "IS", "1");

  add_tag(0x0040, 0xA040, "CS", "TEXT");          // ValueType
  add_tag(0x0040, 0xA491, "CS", "COMPLETE");      // CompletionFlag
  add_tag(0x0040, 0xA493, "CS", "UNVERIFIED");    // VerificationFlag
  add_tag(0x0040, 0xA160, "UT", text_content);    // TextValue

  return dicomtk::write_dicom_file(dcm, out_path);
}
