#ifndef RCPP_DCMTK_H
#define RCPP_DCMTK_H

#include <Rcpp.h>
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <cmath>
#include <string>
#include <vector>
#include <map>
#include <memory>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <algorithm>
#include <random>
#include <chrono>

#include "dcmtk_dict_builtin.h"

#ifdef DICOMTK_HAVE_DCMTK
#include "dcmtk/config/osconfig.h"
#include "dcmtk/dcmdata/dctk.h"
#include "dcmtk/dcmdata/dcistrmf.h"
#include "dcmtk/dcmdata/dcrledrg.h"
#include "dcmtk/dcmdata/dcrleerg.h"
#include "dcmtk/dcmimgle/dcmimage.h"
#include "dcmtk/dcmimage/diregist.h"
#include "dcmtk/dcmjpeg/djdecode.h"
#include "dcmtk/dcmjpeg/djencode.h"
#endif

namespace dicomtk {

struct DcmElementRecord {
  uint16_t group = 0;
  uint16_t element = 0;
  std::string vr;
  uint32_t length = 0;
  std::string name;
  std::string keyword;
  std::string vm;
  std::string value_str;
  std::vector<uint8_t> raw_bytes;
  int depth = 0;
  std::string seq_path;
};

struct DcmParsedFile {
  std::string filepath;
  bool valid_dicom = false;
  bool has_preamble = false;
  std::string transfer_syntax = "1.2.840.10008.1.2.1"; // Explicit VR Little Endian default
  bool explicit_vr = true;
  bool big_endian = false;
  bool deflated = false;
  bool encapsulated_pixels = false;
  std::vector<DcmElementRecord> elements;
  std::vector<uint8_t> pixel_data;
  std::vector<std::vector<uint8_t>> pixel_fragments;
};

// Dictionary lookup helpers
const DcmDictEntry* lookup_dict_tag(uint16_t group, uint16_t element);
const DcmDictEntry* lookup_dict_keyword(const std::string& keyword_or_tag);
bool parse_tag_string(const std::string& str, uint16_t& group, uint16_t& element);
std::string format_tag(uint16_t group, uint16_t element);

// Core parser & writer
bool check_is_dicom_file(const std::string& path);
DcmParsedFile parse_dicom_file(const std::string& path, bool stop_at_pixels = false, int max_depth = 8);
bool write_dicom_file(const DcmParsedFile& dcm, const std::string& out_path);

// RLE codec helpers
std::vector<uint8_t> decode_rle_segment(const uint8_t* data, std::size_t len, std::size_t expected_size);
std::vector<uint8_t> decode_rle_frame(const std::vector<uint8_t>& frag, std::size_t num_pixels, int bytes_per_sample, int samples_per_pixel);
std::vector<uint8_t> encode_rle_frame(const uint8_t* raw_pixels, std::size_t num_pixels, int bytes_per_sample, int samples_per_pixel);

// UID generator
std::string generate_dicom_uid(const std::string& prefix = "2.25");

} // namespace dicomtk

#endif // RCPP_DCMTK_H
