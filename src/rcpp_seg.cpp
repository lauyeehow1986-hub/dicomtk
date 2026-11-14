#include <Rcpp.h>
#include <vector>
#include <cstdint>
#include <cmath>
#include <string>

namespace dicomtk {

// Pack 2D integer/logical matrix into DICOM-SEG 1-bit packed byte vector (PS3.5 section 8.1.2)
// Bit 0 of byte 0 corresponds to first pixel (row 0, col 0)
std::vector<uint8_t> pack_binary_frame(const int* data, int width, int height) {
  size_t total_pixels = static_cast<size_t>(width) * height;
  size_t total_bytes = (total_pixels + 7) / 8;
  // DICOM requires even number of bytes for elements
  if (total_bytes % 2 != 0) {
    total_bytes += 1;
  }
  std::vector<uint8_t> out(total_bytes, 0);

  for (size_t i = 0; i < total_pixels; ++i) {
    if (data[i] != 0) {
      size_t byte_idx = i / 8;
      int bit_idx = static_cast<int>(i % 8);
      out[byte_idx] |= static_cast<uint8_t>(1 << bit_idx);
    }
  }
  return out;
}

// Unpack DICOM-SEG 1-bit packed byte vector back to 2D integer buffer
std::vector<int> unpack_binary_frame(const uint8_t* bytes, size_t n_bytes, int width, int height) {
  size_t total_pixels = static_cast<size_t>(width) * height;
  std::vector<int> out(total_pixels, 0);

  for (size_t i = 0; i < total_pixels; ++i) {
    size_t byte_idx = i / 8;
    if (byte_idx < n_bytes) {
      int bit_idx = static_cast<int>(i % 8);
      if ((bytes[byte_idx] & (1 << bit_idx)) != 0) {
        out[i] = 1;
      }
    }
  }
  return out;
}

} // namespace dicomtk

// [[Rcpp::export]]
Rcpp::RawVector cpp_pack_binary_frame(Rcpp::IntegerMatrix frame) {
  int height = frame.nrow();
  int width = frame.ncol();

  // R IntegerMatrix is column-major: frame(r, c)
  // DICOM frame order is row-major: pixel(r, c) = r * width + c
  std::vector<int> row_major_data(static_cast<size_t>(width) * height);
  for (int r = 0; r < height; ++r) {
    for (int c = 0; c < width; ++c) {
      row_major_data[static_cast<size_t>(r) * width + c] = frame(r, c);
    }
  }

  auto packed = dicomtk::pack_binary_frame(row_major_data.data(), width, height);

  Rcpp::RawVector out(packed.size());
  std::memcpy(out.begin(), packed.data(), packed.size());
  return out;
}

// [[Rcpp::export]]
Rcpp::IntegerMatrix cpp_unpack_binary_frame(Rcpp::RawVector bytes, int width, int height) {
  size_t n_bytes = bytes.size();
  const uint8_t* raw_ptr = reinterpret_cast<const uint8_t*>(bytes.begin());

  auto unpacked = dicomtk::unpack_binary_frame(raw_ptr, n_bytes, width, height);

  // Convert row-major buffer into R column-major IntegerMatrix
  Rcpp::IntegerMatrix out(height, width);
  for (int r = 0; r < height; ++r) {
    for (int c = 0; c < width; ++c) {
      out(r, c) = unpacked[static_cast<size_t>(r) * width + c];
    }
  }
  return out;
}
#include "rcpp_dcmtk.h"
#include <Rcpp.h>

// [[Rcpp::export]]
bool cpp_write_dicom_raw_pixels(
    std::string in_dcm_path,
    std::string out_dcm_path,
    Rcpp::RawVector raw_pixel_bytes,
    int bits_allocated = 1,
    int bits_stored = 1,
    int high_bit = 0,
    int pixel_representation = 0,
    int samples_per_pixel = 1,
    int number_of_frames = 1) {

  dicomtk::DcmParsedFile dcm = dicomtk::parse_dicom_file(in_dcm_path, true);

  // Set DICOM-SEG pixel attributes
  dicomtk::upsert_tag(dcm, 0x0008, 0x0016, "1.2.840.10008.5.1.4.1.1.66.4"); // Segmentation Storage
  dicomtk::upsert_tag(dcm, 0x0008, 0x0060, "SEG");
  dicomtk::upsert_tag(dcm, 0x0028, 0x0002, std::to_string(samples_per_pixel));
  dicomtk::upsert_tag(dcm, 0x0028, 0x0004, "MONOCHROME2");
  dicomtk::upsert_tag(dcm, 0x0028, 0x0008, std::to_string(number_of_frames));
  dicomtk::upsert_tag(dcm, 0x0028, 0x0100, std::to_string(bits_allocated));
  dicomtk::upsert_tag(dcm, 0x0028, 0x0101, std::to_string(bits_stored));
  dicomtk::upsert_tag(dcm, 0x0028, 0x0102, std::to_string(high_bit));
  dicomtk::upsert_tag(dcm, 0x0028, 0x0103, std::to_string(pixel_representation));
  dicomtk::upsert_tag(dcm, 0x0062, 0x0001, "BINARY");

  // Replace pixel payload
  dcm.pixel_data.resize(raw_pixel_bytes.size());
  std::memcpy(dcm.pixel_data.data(), raw_pixel_bytes.begin(), raw_pixel_bytes.size());

  // Even byte length padding for OW/OB element
  if (dcm.pixel_data.size() % 2 != 0) {
    dcm.pixel_data.push_back(0);
  }

  return dicomtk::write_dicom_file(dcm, out_dcm_path);
}
// [[Rcpp::export]]
Rcpp::RawVector cpp_read_dicom_raw_pixels(std::string path) {
  dicomtk::DcmParsedFile dcm = dicomtk::parse_dicom_file(path, false);
  Rcpp::RawVector out(dcm.pixel_data.size());
  if (!dcm.pixel_data.empty()) {
    std::memcpy(out.begin(), dcm.pixel_data.data(), dcm.pixel_data.size());
  }
  return out;
}
