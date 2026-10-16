#include "rcpp_dcmtk.h"

namespace dicomtk {

std::vector<uint8_t> decode_rle_segment(const uint8_t* data, std::size_t len, std::size_t expected_size) {
  std::vector<uint8_t> out;
  out.reserve(expected_size);
  std::size_t i = 0;
  while (i < len && out.size() < expected_size) {
    int8_t n = static_cast<int8_t>(data[i++]);
    if (n >= 0) {
      std::size_t count = static_cast<std::size_t>(n) + 1;
      for (std::size_t k = 0; k < count && i < len && out.size() < expected_size; ++k) {
        out.push_back(data[i++]);
      }
    } else if (n >= -127) {
      if (i >= len) break;
      uint8_t val = data[i++];
      std::size_t count = static_cast<std::size_t>(-static_cast<int>(n)) + 1;
      for (std::size_t k = 0; k < count && out.size() < expected_size; ++k) {
        out.push_back(val);
      }
    }
    // n == -128 is noop per DICOM PS3.5 Annex G
  }
  if (out.size() < expected_size) {
    out.resize(expected_size, 0);
  }
  return out;
}

std::vector<uint8_t> decode_rle_frame(const std::vector<uint8_t>& frag,
                                      std::size_t num_pixels,
                                      int bytes_per_sample,
                                      int samples_per_pixel) {
  if (frag.size() < 64) {
    Rcpp::stop("Invalid DICOM RLE fragment: header shorter than 64 bytes");
  }
  uint32_t num_segments = static_cast<uint32_t>(frag[0]) |
                          (static_cast<uint32_t>(frag[1]) << 8) |
                          (static_cast<uint32_t>(frag[2]) << 16) |
                          (static_cast<uint32_t>(frag[3]) << 24);
  uint32_t offsets[15];
  for (int s = 0; s < 15; ++s) {
    const uint8_t* p = &frag[4 + s * 4];
    offsets[s] = static_cast<uint32_t>(p[0]) |
                 (static_cast<uint32_t>(p[1]) << 8) |
                 (static_cast<uint32_t>(p[2]) << 16) |
                 (static_cast<uint32_t>(p[3]) << 24);
  }

  int expected_segments = bytes_per_sample * samples_per_pixel;
  if (static_cast<int>(num_segments) < expected_segments || num_segments > 15) {
    Rcpp::stop("Unexpected number of RLE segments in DICOM frame");
  }

  std::vector<uint8_t> frame_bytes(num_pixels * expected_segments, 0);

  for (uint32_t s = 0; s < num_segments; ++s) {
    std::size_t start = offsets[s];
    std::size_t end = (s + 1 < num_segments) ? offsets[s + 1] : frag.size();
    if (start >= frag.size() || end > frag.size() || start >= end) continue;

    std::vector<uint8_t> seg = decode_rle_segment(&frag[start], end - start, num_pixels);
    int sample_idx = s / bytes_per_sample;
    int byte_in_sample = s % bytes_per_sample; // 0 = MSB, bytes_per_sample - 1 = LSB
    int target_byte_offset = (bytes_per_sample - 1 - byte_in_sample); // Little endian storage

    for (std::size_t px = 0; px < num_pixels; ++px) {
      std::size_t dst_idx = (px * samples_per_pixel + sample_idx) * bytes_per_sample + target_byte_offset;
      if (dst_idx < frame_bytes.size()) {
        frame_bytes[dst_idx] = seg[px];
      }
    }
  }
  return frame_bytes;
}

static std::vector<uint8_t> encode_rle_byte_stream(const std::vector<uint8_t>& in) {
  std::vector<uint8_t> out;
  out.reserve(in.size());
  std::size_t n = in.size();
  std::size_t i = 0;
  while (i < n) {
    // Check run of identical bytes
    std::size_t run = 1;
    while (i + run < n && run < 128 && in[i + run] == in[i]) {
      ++run;
    }
    if (run >= 3) {
      out.push_back(static_cast<uint8_t>(static_cast<int8_t>(1 - static_cast<int>(run))));
      out.push_back(in[i]);
      i += run;
    } else {
      // Literal run
      std::size_t lit_start = i;
      std::size_t lit_len = 0;
      while (i < n && lit_len < 128) {
        std::size_t r = 1;
        while (i + r < n && r < 3 && in[i + r] == in[i]) ++r;
        if (r >= 3 && lit_len > 0) break;
        ++i;
        ++lit_len;
      }
      out.push_back(static_cast<uint8_t>(lit_len - 1));
      out.insert(out.end(), in.begin() + lit_start, in.begin() + lit_start + lit_len);
    }
  }
  if (out.size() % 2 == 1) {
    out.push_back(0);
  }
  return out;
}

std::vector<uint8_t> encode_rle_frame(const uint8_t* raw_pixels,
                                      std::size_t num_pixels,
                                      int bytes_per_sample,
                                      int samples_per_pixel) {
  int num_segments = bytes_per_sample * samples_per_pixel;
  std::vector<std::vector<uint8_t>> encoded_segs(num_segments);

  for (int s = 0; s < num_segments; ++s) {
    int sample_idx = s / bytes_per_sample;
    int byte_in_sample = s % bytes_per_sample; // 0 = MSB
    int src_byte_offset = (bytes_per_sample - 1 - byte_in_sample);

    std::vector<uint8_t> plane(num_pixels);
    for (std::size_t px = 0; px < num_pixels; ++px) {
      plane[px] = raw_pixels[(px * samples_per_pixel + sample_idx) * bytes_per_sample + src_byte_offset];
    }
    encoded_segs[s] = encode_rle_byte_stream(plane);
  }

  std::vector<uint8_t> out(64, 0);
  uint32_t nseg = static_cast<uint32_t>(num_segments);
  out[0] = static_cast<uint8_t>(nseg & 0xFF);
  out[1] = static_cast<uint8_t>((nseg >> 8) & 0xFF);
  out[2] = static_cast<uint8_t>((nseg >> 16) & 0xFF);
  out[3] = static_cast<uint8_t>((nseg >> 24) & 0xFF);

  uint32_t cur_offset = 64;
  for (int s = 0; s < num_segments; ++s) {
    uint8_t* p = &out[4 + s * 4];
    p[0] = static_cast<uint8_t>(cur_offset & 0xFF);
    p[1] = static_cast<uint8_t>((cur_offset >> 8) & 0xFF);
    p[2] = static_cast<uint8_t>((cur_offset >> 16) & 0xFF);
    p[3] = static_cast<uint8_t>((cur_offset >> 24) & 0xFF);
    out.insert(out.end(), encoded_segs[s].begin(), encoded_segs[s].end());
    cur_offset += static_cast<uint32_t>(encoded_segs[s].size());
  }
  return out;
}

static std::string find_tag_str(const DcmParsedFile& dcm, uint16_t g, uint16_t e, const std::string& def = "") {
  for (const auto& el : dcm.elements) {
    if (el.depth == 0 && el.group == g && el.element == e) {
      return el.value_str;
    }
  }
  return def;
}

static int find_tag_int(const DcmParsedFile& dcm, uint16_t g, uint16_t e, int def) {
  std::string s = find_tag_str(dcm, g, e, "");
  if (s.empty()) return def;
  try {
    return std::stoi(s);
  } catch (...) {
    return def;
  }
}

static double find_tag_double(const DcmParsedFile& dcm, uint16_t g, uint16_t e, double def) {
  std::string s = find_tag_str(dcm, g, e, "");
  if (s.empty()) return def;
  try {
    std::size_t sep = s.find('\\');
    if (sep != std::string::npos) s = s.substr(0, sep);
    return std::stod(s);
  } catch (...) {
    return def;
  }
}

static std::vector<double> find_tag_double_vec(const DcmParsedFile& dcm, uint16_t g, uint16_t e) {
  std::vector<double> res;
  std::string s = find_tag_str(dcm, g, e, "");
  if (s.empty()) return res;
  std::stringstream ss(s);
  std::string item;
  while (std::getline(ss, item, '\\')) {
    try {
      res.push_back(std::stod(item));
    } catch (...) {}
  }
  return res;
}

} // namespace dicomtk

// [[Rcpp::export]]
Rcpp::NumericVector cpp_read_dicom_pixels(const std::string& path,
                                          int frame = 0,
                                          bool rescale = true) {
  dicomtk::DcmParsedFile dcm = dicomtk::parse_dicom_file(path, false, 1);

  int rows = dicomtk::find_tag_int(dcm, 0x0028, 0x0010, 0);
  int cols = dicomtk::find_tag_int(dcm, 0x0028, 0x0011, 0);
  int nframes = std::max(1, dicomtk::find_tag_int(dcm, 0x0028, 0x0008, 1));
  int samples = std::max(1, dicomtk::find_tag_int(dcm, 0x0028, 0x0002, 1));
  int bits_alloc = dicomtk::find_tag_int(dcm, 0x0028, 0x0100, 16);
  int bits_stored = dicomtk::find_tag_int(dcm, 0x0028, 0x0101, bits_alloc);
  int high_bit = dicomtk::find_tag_int(dcm, 0x0028, 0x0102, bits_stored - 1);
  int pixel_rep = dicomtk::find_tag_int(dcm, 0x0028, 0x0103, 0);
  int planar_cfg = dicomtk::find_tag_int(dcm, 0x0028, 0x0006, 0);
  std::string photometric = dicomtk::find_tag_str(dcm, 0x0028, 0x0004, "MONOCHROME2");
  std::string modality = dicomtk::find_tag_str(dcm, 0x0008, 0x0060, "OT");
  double intercept = dicomtk::find_tag_double(dcm, 0x0028, 0x1052, 0.0);
  double slope = dicomtk::find_tag_double(dcm, 0x0028, 0x1053, 1.0);
  double win_center = dicomtk::find_tag_double(dcm, 0x0028, 0x1050, NA_REAL);
  double win_width = dicomtk::find_tag_double(dcm, 0x0028, 0x1051, NA_REAL);
  double slice_thickness = dicomtk::find_tag_double(dcm, 0x0018, 0x0050, NA_REAL);
  int instance_num = dicomtk::find_tag_int(dcm, 0x0020, 0x0013, NA_INTEGER);
  std::vector<double> pixel_spacing = dicomtk::find_tag_double_vec(dcm, 0x0028, 0x0030);
  std::vector<double> img_pos = dicomtk::find_tag_double_vec(dcm, 0x0020, 0x0032);

  if (rows <= 0 || cols <= 0) {
    Rcpp::stop("DICOM file does not contain valid image dimensions (Rows/Columns): " + path);
  }

  int bytes_per_sample = std::max(1, (bits_alloc + 7) / 8);
  std::size_t pixels_per_frame = static_cast<std::size_t>(rows) * static_cast<std::size_t>(cols);
  std::size_t frame_byte_size = pixels_per_frame * samples * bytes_per_sample;

  std::vector<uint8_t> raw_buffer;
  if (dcm.encapsulated_pixels) {
    if (dcm.transfer_syntax == "1.2.840.10008.1.2.5") {
      // RLE Lossless
      raw_buffer.reserve(frame_byte_size * nframes);
      for (std::size_t f = 0; f < dcm.pixel_fragments.size(); ++f) {
        std::vector<uint8_t> dec = dicomtk::decode_rle_frame(
            dcm.pixel_fragments[f], pixels_per_frame, bytes_per_sample, samples);
        raw_buffer.insert(raw_buffer.end(), dec.begin(), dec.end());
      }
    } else {
      Rcpp::stop("Encapsulated transfer syntax (" + dcm.transfer_syntax +
                 ") requires decompressing first with dicom_decompress().");
    }
  } else {
    raw_buffer = std::move(dcm.pixel_data);
  }

  if (raw_buffer.empty()) {
    Rcpp::stop("No pixel data (7FE0,0010) found in DICOM file: " + path);
  }

  // Determine which frames to extract (frame == 0 means all frames; frame >= 1 is 1-based frame index)
  int start_f = 0;
  int end_f = nframes;
  if (frame >= 1) {
    if (frame > nframes) {
      Rcpp::stop("Requested frame " + std::to_string(frame) +
                 " exceeds NumberOfFrames (" + std::to_string(nframes) + ")");
    }
    start_f = frame - 1;
    end_f = frame;
  }
  int out_frames = end_f - start_f;

  std::size_t total_vals = pixels_per_frame * samples * out_frames;
  Rcpp::NumericVector out(total_vals);

  uint16_t bit_mask = (bits_stored >= 16) ? 0xFFFFU : static_cast<uint16_t>((1U << bits_stored) - 1U);
  uint16_t sign_bit = (bits_stored >= 1) ? static_cast<uint16_t>(1U << (bits_stored - 1)) : 0;
  int shift_right = std::max(0, (high_bit + 1) - bits_stored);

  for (int f = 0; f < out_frames; ++f) {
    std::size_t src_frame_offset = static_cast<std::size_t>(start_f + f) * frame_byte_size;
    for (int r = 0; r < rows; ++r) {
      for (int c = 0; c < cols; ++c) {
        std::size_t px_idx = static_cast<std::size_t>(r) * cols + c;
        for (int s = 0; s < samples; ++s) {
          std::size_t sample_idx = (planar_cfg == 1)
                                     ? (static_cast<std::size_t>(s) * pixels_per_frame + px_idx)
                                     : (px_idx * samples + s);
          std::size_t byte_pos = src_frame_offset + sample_idx * bytes_per_sample;
          double val = 0.0;
          if (byte_pos + bytes_per_sample <= raw_buffer.size()) {
            const uint8_t* p = &raw_buffer[byte_pos];
            if (bytes_per_sample == 1) {
              if (pixel_rep == 1) {
                val = static_cast<double>(static_cast<int8_t>(p[0]));
              } else {
                val = static_cast<double>(p[0]);
              }
            } else if (bytes_per_sample == 2) {
              uint16_t u = dcm.big_endian
                             ? ((static_cast<uint16_t>(p[0]) << 8) | p[1])
                             : (static_cast<uint16_t>(p[0]) | (static_cast<uint16_t>(p[1]) << 8));
              if (pixel_rep == 1) {
                if (bits_stored == 16) {
                  val = static_cast<double>(static_cast<int16_t>(u));
                } else {
                  uint16_t m = (u >> shift_right) & bit_mask;
                  if (m & sign_bit) {
                    int16_t sv = static_cast<int16_t>(m | (~bit_mask));
                    val = static_cast<double>(sv);
                  } else {
                    val = static_cast<double>(m);
                  }
                }
              } else {
                uint16_t m = (u >> shift_right) & bit_mask;
                val = static_cast<double>(m);
              }
            } else if (bytes_per_sample == 4) {
              uint32_t u = static_cast<uint32_t>(p[0]) |
                           (static_cast<uint32_t>(p[1]) << 8) |
                           (static_cast<uint32_t>(p[2]) << 16) |
                           (static_cast<uint32_t>(p[3]) << 24);
              if (pixel_rep == 1) {
                val = static_cast<double>(static_cast<int32_t>(u));
              } else {
                val = static_cast<double>(u);
              }
            }
          }

          if (rescale && samples == 1) {
            val = val * slope + intercept;
          }

          // R stores matrices column-major: [r, c, (s/f)]
          std::size_t r_idx = static_cast<std::size_t>(r) +
                              static_cast<std::size_t>(c) * rows +
                              static_cast<std::size_t>(s + f * samples) * pixels_per_frame;
          out[r_idx] = val;
        }
      }
    }
  }

  if (out_frames == 1 && samples == 1) {
    out.attr("dim") = Rcpp::IntegerVector::create(rows, cols);
  } else if (out_frames == 1 && samples > 1) {
    out.attr("dim") = Rcpp::IntegerVector::create(rows, cols, samples);
  } else if (out_frames > 1 && samples == 1) {
    out.attr("dim") = Rcpp::IntegerVector::create(rows, cols, out_frames);
  } else {
    out.attr("dim") = Rcpp::IntegerVector::create(rows, cols, samples, out_frames);
  }

  out.attr("rows") = rows;
  out.attr("columns") = cols;
  out.attr("frames") = out_frames;
  out.attr("samples_per_pixel") = samples;
  out.attr("photometric") = photometric;
  out.attr("modality") = modality;
  out.attr("bits_allocated") = bits_alloc;
  out.attr("bits_stored") = bits_stored;
  out.attr("pixel_representation") = pixel_rep;
  out.attr("rescale_slope") = slope;
  out.attr("rescale_intercept") = intercept;
  out.attr("window_center") = win_center;
  out.attr("window_width") = win_width;
  out.attr("pixel_spacing") = pixel_spacing;
  out.attr("slice_thickness") = slice_thickness;
  out.attr("image_position") = img_pos;
  out.attr("instance_number") = instance_num;

  return out;
}
