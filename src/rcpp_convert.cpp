#include "rcpp_dcmtk.h"

namespace dicomtk {

static std::string xml_escape(const std::string& s) {
  std::string out;
  out.reserve(s.size());
  for (char c : s) {
    switch (c) {
      case '&': out += "&amp;"; break;
      case '<': out += "&lt;"; break;
      case '>': out += "&gt;"; break;
      case '"': out += "&quot;"; break;
      case '\'': out += "&apos;"; break;
      default:
        if (static_cast<unsigned char>(c) >= 32 || c == '\t' || c == '\n') {
          out.push_back(c);
        }
        break;
    }
  }
  return out;
}

static std::string json_escape(const std::string& s) {
  std::string out;
  out.reserve(s.size());
  for (char c : s) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (static_cast<unsigned char>(c) >= 32) {
          out.push_back(c);
        }
        break;
    }
  }
  return out;
}

} // namespace dicomtk

// [[Rcpp::export]]
std::string cpp_dcm_to_xml(const std::string& path) {
  dicomtk::DcmParsedFile dcm = dicomtk::parse_dicom_file(path, true, 4);
  std::ostringstream oss;
  oss << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  oss << "<NativeDicomModel xml:space=\"preserve\">\n";

  for (const auto& el : dcm.elements) {
    if (el.depth > 0) continue;
    if (el.group == 0x7FE0 && el.element == 0x0010) continue;
    char tag_hex[12];
    std::snprintf(tag_hex, sizeof(tag_hex), "%04X%04X", el.group, el.element);
    oss << "  <DicomAttribute tag=\"" << tag_hex
        << "\" vr=\"" << dicomtk::xml_escape(el.vr)
        << "\" keyword=\"" << dicomtk::xml_escape(el.keyword) << "\">\n";
    if (!el.value_str.empty() && el.vr != "SQ") {
      std::stringstream ss(el.value_str);
      std::string item;
      int idx = 1;
      while (std::getline(ss, item, '\\')) {
        oss << "    <Value number=\"" << idx++ << "\">"
            << dicomtk::xml_escape(item) << "</Value>\n";
      }
    }
    oss << "  </DicomAttribute>\n";
  }

  oss << "</NativeDicomModel>\n";
  return oss.str();
}

// [[Rcpp::export]]
std::string cpp_dcm_to_json(const std::string& path) {
  dicomtk::DcmParsedFile dcm = dicomtk::parse_dicom_file(path, true, 4);
  std::ostringstream oss;
  oss << "{\n";
  bool first = true;

  for (const auto& el : dcm.elements) {
    if (el.depth > 0) continue;
    if (el.group == 0x7FE0 && el.element == 0x0010) continue;
    if (el.element == 0x0000) continue;

    if (!first) oss << ",\n";
    first = false;

    char tag_hex[12];
    std::snprintf(tag_hex, sizeof(tag_hex), "%04X%04X", el.group, el.element);
    oss << "  \"" << tag_hex << "\": {\n";
    oss << "    \"vr\": \"" << dicomtk::json_escape(el.vr) << "\"";

    if (!el.value_str.empty() && el.vr != "SQ") {
      oss << ",\n    \"Value\": [";
      std::stringstream ss(el.value_str);
      std::string item;
      bool first_val = true;
      bool is_num = (el.vr == "US" || el.vr == "SS" || el.vr == "UL" ||
                     el.vr == "SL" || el.vr == "FL" || el.vr == "FD");
      while (std::getline(ss, item, '\\')) {
        if (!first_val) oss << ", ";
        first_val = false;
        if (is_num) {
          try {
            double d = std::stod(item);
            oss << d;
          } catch (...) {
            oss << "\"" << dicomtk::json_escape(item) << "\"";
          }
        } else {
          oss << "\"" << dicomtk::json_escape(item) << "\"";
        }
      }
      oss << "]\n";
    } else {
      oss << "\n";
    }
    oss << "  }";
  }
  oss << "\n}\n";
  return oss.str();
}

// [[Rcpp::export]]
bool cpp_dcm_extract_pdf(const std::string& path, const std::string& out_path) {
  dicomtk::DcmParsedFile dcm = dicomtk::parse_dicom_file(path, true, 1);
  for (const auto& el : dcm.elements) {
    if (el.group == 0x0042 && el.element == 0x0011 && !el.raw_bytes.empty()) {
      std::size_t len = el.raw_bytes.size();
      while (len > 0 && el.raw_bytes[len - 1] == 0) {
        --len;
      }
      std::ofstream ofs(out_path, std::ios::binary | std::ios::trunc);
      if (!ofs.good()) {
        Rcpp::stop("Cannot open output PDF file for writing: " + out_path);
      }
      ofs.write(reinterpret_cast<const char*>(el.raw_bytes.data()), static_cast<std::streamsize>(len));
      return ofs.good();
    }
  }
  Rcpp::stop("No Encapsulated Document (0042,0011) found in DICOM file: " + path);
  return false;
}

// [[Rcpp::export]]
bool cpp_dcm_transcode_rle(const std::string& in_path,
                           const std::string& out_path,
                           bool compress = true) {
  dicomtk::DcmParsedFile dcm = dicomtk::parse_dicom_file(in_path, false, 0);

  int rows = 0, cols = 0, nframes = 1, samples = 1, bits_alloc = 16;
  for (const auto& el : dcm.elements) {
    if (el.depth > 0) continue;
    if (el.group == 0x0028 && el.element == 0x0010) rows = std::stoi(el.value_str);
    if (el.group == 0x0028 && el.element == 0x0011) cols = std::stoi(el.value_str);
    if (el.group == 0x0028 && el.element == 0x0008) nframes = std::max(1, std::stoi(el.value_str));
    if (el.group == 0x0028 && el.element == 0x0002) samples = std::max(1, std::stoi(el.value_str));
    if (el.group == 0x0028 && el.element == 0x0100) bits_alloc = std::stoi(el.value_str);
  }
  int bytes_per_sample = std::max(1, (bits_alloc + 7) / 8);
  std::size_t pixels_per_frame = static_cast<std::size_t>(rows) * static_cast<std::size_t>(cols);
  std::size_t frame_bytes = pixels_per_frame * samples * bytes_per_sample;

  if (compress) {
    if (dcm.encapsulated_pixels && dcm.transfer_syntax == "1.2.840.10008.1.2.5") {
      // Already RLE compressed
      return dicomtk::write_dicom_file(dcm, out_path);
    }
    if (dcm.pixel_data.empty() || rows <= 0 || cols <= 0) {
      Rcpp::stop("Cannot RLE-compress DICOM without uncompressed pixel data: " + in_path);
    }
    dcm.pixel_fragments.clear();
    for (int f = 0; f < nframes; ++f) {
      std::size_t offset = static_cast<std::size_t>(f) * frame_bytes;
      if (offset + frame_bytes > dcm.pixel_data.size()) break;
      dcm.pixel_fragments.push_back(
          dicomtk::encode_rle_frame(&dcm.pixel_data[offset], pixels_per_frame, bytes_per_sample, samples));
    }
    dcm.pixel_data.clear();
    dcm.encapsulated_pixels = true;
    dcm.transfer_syntax = "1.2.840.10008.1.2.5";
    dcm.explicit_vr = true;
    dcm.big_endian = false;
    return dicomtk::write_dicom_file(dcm, out_path);
  } else {
    // Decompress to Explicit VR Little Endian
    if (dcm.encapsulated_pixels) {
      if (dcm.transfer_syntax == "1.2.840.10008.1.2.5") {
        dcm.pixel_data.clear();
        dcm.pixel_data.reserve(frame_bytes * dcm.pixel_fragments.size());
        for (const auto& frag : dcm.pixel_fragments) {
          std::vector<uint8_t> dec = dicomtk::decode_rle_frame(
              frag, pixels_per_frame, bytes_per_sample, samples);
          dcm.pixel_data.insert(dcm.pixel_data.end(), dec.begin(), dec.end());
        }
        dcm.pixel_fragments.clear();
        dcm.encapsulated_pixels = false;
      } else {
        Rcpp::stop("Unsupported compressed transfer syntax for native decompression: " + dcm.transfer_syntax);
      }
    }
    dcm.transfer_syntax = "1.2.840.10008.1.2.1";
    dcm.explicit_vr = true;
    dcm.big_endian = false;
    return dicomtk::write_dicom_file(dcm, out_path);
  }
}
