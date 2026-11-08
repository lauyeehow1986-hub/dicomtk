#include "rcpp_dcmtk.h"
#include <queue>
#include <vector>
#include <cmath>
#include <algorithm>
#include <string>
#include <tuple>
#include <limits>
#include <set>
#include <map>

namespace dicomtk {

// Telea (2004) Fast Marching Method Inpainting Engine
static void run_telea_inpaint_frame(std::vector<double>& img,
                                    const std::vector<uint8_t>& in_mask,
                                    int rows,
                                    int cols,
                                    int radius) {
  enum State : uint8_t { KNOWN = 0, BAND = 1, INSIDE = 2 };
  std::vector<State> state(rows * cols);
  std::vector<double> dist(rows * cols, 1e9);

  for (int i = 0; i < rows * cols; ++i) {
    if (in_mask[i]) {
      state[i] = INSIDE;
    } else {
      state[i] = KNOWN;
      dist[i] = 0.0;
    }
  }

  typedef std::pair<double, int> QueueElem;
  std::priority_queue<QueueElem, std::vector<QueueElem>, std::greater<QueueElem>> pq;

  // Initialize narrow band
  for (int r = 0; r < rows; ++r) {
    for (int c = 0; c < cols; ++c) {
      int idx = r * cols + c;
      if (state[idx] == INSIDE) {
        bool near_known = false;
        if (r > 0 && state[(r - 1) * cols + c] == KNOWN) near_known = true;
        if (r + 1 < rows && state[(r + 1) * cols + c] == KNOWN) near_known = true;
        if (c > 0 && state[r * cols + (c - 1)] == KNOWN) near_known = true;
        if (c + 1 < cols && state[r * cols + (c + 1)] == KNOWN) near_known = true;

        if (near_known) {
          state[idx] = BAND;
          dist[idx] = 1.0;
          pq.push({dist[idx], idx});
        }
      }
    }
  }

  while (!pq.empty()) {
    auto top = pq.top();
    pq.pop();
    double d = top.first;
    int idx = top.second;

    if (dist[idx] < d || state[idx] == KNOWN) continue;
    state[idx] = KNOWN;
    int r = idx / cols;
    int c = idx % cols;

    // Gradient of distance map at (r, c)
    double grad_T_r = 0.0, grad_T_c = 0.0;
    if (r > 0 && r + 1 < rows) {
      grad_T_r = (dist[(r + 1) * cols + c] - dist[(r - 1) * cols + c]) * 0.5;
    } else if (r > 0) {
      grad_T_r = dist[idx] - dist[(r - 1) * cols + c];
    } else if (r + 1 < rows) {
      grad_T_r = dist[(r + 1) * cols + c] - dist[idx];
    }

    if (c > 0 && c + 1 < cols) {
      grad_T_c = (dist[r * cols + (c + 1)] - dist[r * cols + (c - 1)]) * 0.5;
    } else if (c > 0) {
      grad_T_c = dist[idx] - dist[r * cols + (c - 1)];
    } else if (c + 1 < cols) {
      grad_T_c = dist[r * cols + (c + 1)] - dist[idx];
    }

    double grad_norm = std::sqrt(grad_T_r * grad_T_r + grad_T_c * grad_T_c);

    double sum_val = 0.0;
    double sum_w = 0.0;

    int r_min = std::max(0, r - radius);
    int r_max = std::min(rows - 1, r + radius);
    int c_min = std::max(0, c - radius);
    int c_max = std::min(cols - 1, c + radius);

    for (int nr = r_min; nr <= r_max; ++nr) {
      for (int nc = c_min; nc <= c_max; ++nc) {
        int n_idx = nr * cols + nc;
        if (state[n_idx] != KNOWN) continue;

        double dr = nr - r;
        double dc = nc - c;
        double d2 = dr * dr + dc * dc;
        if (d2 > radius * radius || d2 == 0) continue;
        double d_geom = std::sqrt(d2);

        double dir = 1.0;
        if (grad_norm > 1e-6) {
          double dot = (dr * grad_T_r + dc * grad_T_c) / (d_geom * grad_norm);
          dir = std::abs(dot);
          if (dir < 1e-4) dir = 1e-4;
        }

        double dst = 1.0 / (d_geom * d_geom);
        double lev = 1.0 / (1.0 + std::abs(dist[idx] - dist[n_idx]));
        double w = dir * dst * lev;

        sum_val += w * img[n_idx];
        sum_w += w;
      }
    }

    if (sum_w > 0.0) {
      img[idx] = sum_val / sum_w;
    }

    // Propagate to 4-neighbors
    const int dr4[4] = {-1, 1, 0, 0};
    const int dc4[4] = {0, 0, -1, 1};

    for (int k = 0; k < 4; ++k) {
      int nr = r + dr4[k];
      int nc = c + dc4[k];
      if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
      int n_idx = nr * cols + nc;

      if (state[n_idx] != KNOWN) {
        double t_min_r = 1e9, t_min_c = 1e9;
        if (nr > 0 && state[(nr - 1) * cols + nc] == KNOWN) t_min_r = std::min(t_min_r, dist[(nr - 1) * cols + nc]);
        if (nr + 1 < rows && state[(nr + 1) * cols + nc] == KNOWN) t_min_r = std::min(t_min_r, dist[(nr + 1) * cols + nc]);
        if (nc > 0 && state[nr * cols + (nc - 1)] == KNOWN) t_min_c = std::min(t_min_c, dist[nr * cols + (nc - 1)]);
        if (nc + 1 < cols && state[nr * cols + (nc + 1)] == KNOWN) t_min_c = std::min(t_min_c, dist[nr * cols + (nc + 1)]);

        double new_dist = 1e9;
        if (t_min_r < 1e8 && t_min_c < 1e8) {
          double d_diff = std::abs(t_min_r - t_min_c);
          if (d_diff <= 1.0) {
            new_dist = (t_min_r + t_min_c + std::sqrt(2.0 - (t_min_r - t_min_c) * (t_min_r - t_min_c))) * 0.5;
          } else {
            new_dist = std::min(t_min_r, t_min_c) + 1.0;
          }
        } else if (t_min_r < 1e8) {
          new_dist = t_min_r + 1.0;
        } else if (t_min_c < 1e8) {
          new_dist = t_min_c + 1.0;
        }

        if (state[n_idx] == INSIDE) {
          state[n_idx] = BAND;
          dist[n_idx] = new_dist;
          pq.push({dist[n_idx], n_idx});
        } else if (state[n_idx] == BAND && new_dist < dist[n_idx]) {
          dist[n_idx] = new_dist;
          pq.push({dist[n_idx], n_idx});
        }
      }
    }
  }
}

} // namespace dicomtk

// [[Rcpp::export]]
Rcpp::DataFrame cpp_detect_burned_boxes(const Rcpp::NumericVector& pixels,
                                       const Rcpp::IntegerVector& dims,
                                       double margin_frac = 0.18) {
  int rows = dims[0];
  int cols = dims[1];
  int frames = (dims.size() >= 3) ? dims[2] : 1;

  std::vector<int> out_ymin;
  std::vector<int> out_xmin;
  std::vector<int> out_ymax;
  std::vector<int> out_xmax;
  std::vector<std::string> out_type;
  std::vector<double> out_score;

  if (rows <= 0 || cols <= 0 || frames <= 0) {
    return Rcpp::DataFrame::create(
      Rcpp::Named("ymin") = out_ymin,
      Rcpp::Named("xmin") = out_xmin,
      Rcpp::Named("ymax") = out_ymax,
      Rcpp::Named("xmax") = out_xmax,
      Rcpp::Named("region_type") = out_type,
      Rcpp::Named("score") = out_score
    );
  }

  // 1. Cine Static-Overlay Detector (frames >= 3)
  if (frames >= 3) {
    std::vector<uint8_t> is_static(rows * cols, 0);

    for (int r = 0; r < rows; ++r) {
      for (int c = 0; c < cols; ++c) {
        double sum = 0.0;
        double v_min = 1e9, v_max = -1e9;
        for (int f = 0; f < frames; ++f) {
          std::size_t idx = static_cast<std::size_t>(r) +
                            static_cast<std::size_t>(c) * rows +
                            static_cast<std::size_t>(f) * (rows * cols);
          double v = pixels[idx];
          sum += v;
          if (v < v_min) v_min = v;
          if (v > v_max) v_max = v;
        }
        double mean_v = sum / frames;
        double diff = v_max - v_min;

        if (diff < 1e-3 && mean_v > 30.0) {
          is_static[r * cols + c] = 1;
        }
      }
    }

    std::vector<uint8_t> visited(rows * cols, 0);
    for (int r = 0; r < rows; ++r) {
      for (int c = 0; c < cols; ++c) {
        if (is_static[r * cols + c] && !visited[r * cols + c]) {
          int min_r = r, max_r = r, min_c = c, max_c = c;
          int count = 0;
          std::queue<std::pair<int, int>> q;
          q.push({r, c});
          visited[r * cols + c] = 1;

          while (!q.empty()) {
            auto top_p = q.front();
            q.pop();
            int cr = top_p.first;
            int cc = top_p.second;
            count++;
            if (cr < min_r) min_r = cr;
            if (cr > max_r) max_r = cr;
            if (cc < min_c) min_c = cc;
            if (cc > max_c) max_c = cc;

            const int dr[4] = {-1, 1, 0, 0};
            const int dc[4] = {0, 0, -1, 1};
            for (int k = 0; k < 4; ++k) {
              int nr = cr + dr[k];
              int nc = cc + dc[k];
              if (nr >= 0 && nr < rows && nc >= 0 && nc < cols) {
                if (is_static[nr * cols + nc] && !visited[nr * cols + nc]) {
                  visited[nr * cols + nc] = 1;
                  q.push({nr, nc});
                }
              }
            }
          }

          if (count >= 8) {
            out_ymin.push_back(min_r + 1);
            out_xmin.push_back(min_c + 1);
            out_ymax.push_back(max_r + 1);
            out_xmax.push_back(max_c + 1);
            out_type.push_back("cine_static");
            out_score.push_back(1.0);
          }
        }
      }
    }
  }

  // 2. Border Stroke Detector
  int margin_rows = std::max(2, static_cast<int>(std::round(rows * margin_frac)));

  int top_min_r = rows, top_max_r = -1, top_min_c = cols, top_max_c = -1;
  int top_count = 0;
  for (int r = 0; r < margin_rows; ++r) {
    for (int c = 0; c < cols; ++c) {
      double v = pixels[r + c * rows]; // frame 0
      if (v >= 200.0) {
        if (r < top_min_r) top_min_r = r;
        if (r > top_max_r) top_max_r = r;
        if (c < top_min_c) top_min_c = c;
        if (c > top_max_c) top_max_c = c;
        top_count++;
      }
    }
  }

  if (top_count >= 8 && top_max_r >= 0) {
    bool already = false;
    for (std::size_t i = 0; i < out_ymin.size(); ++i) {
      if (out_ymin[i] == 1 && out_ymax[i] >= top_max_r + 1) already = true;
    }
    if (!already) {
      out_ymin.push_back(1);
      out_xmin.push_back(1);
      out_ymax.push_back(top_max_r + 1);
      out_xmax.push_back(cols);
      out_type.push_back("border_stroke");
      out_score.push_back(0.95);
    }
  }

  return Rcpp::DataFrame::create(
    Rcpp::Named("ymin") = out_ymin,
    Rcpp::Named("xmin") = out_xmin,
    Rcpp::Named("ymax") = out_ymax,
    Rcpp::Named("xmax") = out_xmax,
    Rcpp::Named("region_type") = out_type,
    Rcpp::Named("score") = out_score
  );
}

// [[Rcpp::export]]
Rcpp::List cpp_apply_pixel_mask(Rcpp::RawVector raw_pixel_data,
                                int rows,
                                int cols,
                                int frames,
                                int bits_allocated,
                                int pixel_representation,
                                int samples_per_pixel,
                                Rcpp::IntegerMatrix boxes,
                                std::string method = "blackout",
                                int radius = 5) {
  if (rows <= 0 || cols <= 0 || frames <= 0) {
    Rcpp::stop("Invalid image dimensions in cpp_apply_pixel_mask.");
  }

  int bytes_per_sample = (bits_allocated <= 8) ? 1 : 2;
  std::size_t expected_size = static_cast<std::size_t>(rows) * cols * frames * samples_per_pixel * bytes_per_sample;
  if (static_cast<std::size_t>(raw_pixel_data.size()) < expected_size) {
    Rcpp::stop("raw_pixel_data buffer size is smaller than expected dimensions.");
  }

  Rcpp::RawVector out_raw = Rcpp::clone(raw_pixel_data);
  uint8_t* p = out_raw.begin();

  std::vector<uint8_t> in_mask(rows * cols, 0);

  int nboxes = boxes.nrow();
  for (int i = 0; i < nboxes; ++i) {
    int ymin = boxes(i, 0);
    int xmin = boxes(i, 1);
    int ymax = boxes(i, 2);
    int xmax = boxes(i, 3);

    int r0 = std::max(0, std::min(ymin - 1, rows - 1));
    int c0 = std::max(0, std::min(xmin - 1, cols - 1));
    int r1 = std::max(0, std::min(ymax - 1, rows - 1));
    int c1 = std::max(0, std::min(xmax - 1, cols - 1));
    if (r0 > r1) std::swap(r0, r1);
    if (c0 > c1) std::swap(c0, c1);

    for (int r = r0; r <= r1; ++r) {
      for (int c = c0; c <= c1; ++c) {
        in_mask[r * cols + c] = 1;
      }
    }
  }

  Rcpp::LogicalVector r_mask(rows * cols);
  for (int r = 0; r < rows; ++r) {
    for (int c = 0; c < cols; ++c) {
      r_mask[r + c * rows] = (in_mask[r * cols + c] != 0);
    }
  }

  if (method == "blackout") {
    for (int f = 0; f < frames; ++f) {
      std::size_t frame_byte_offset = static_cast<std::size_t>(f) * rows * cols * samples_per_pixel * bytes_per_sample;
      for (int r = 0; r < rows; ++r) {
        for (int c = 0; c < cols; ++c) {
          if (in_mask[r * cols + c]) {
            std::size_t px_offset = frame_byte_offset + (static_cast<std::size_t>(r) * cols + c) * samples_per_pixel * bytes_per_sample;
            for (int s = 0; s < samples_per_pixel; ++s) {
              std::size_t b_idx = px_offset + s * bytes_per_sample;
              if (bytes_per_sample == 1) {
                p[b_idx] = 0;
              } else {
                if (pixel_representation == 1) {
                  int16_t bg = -1024;
                  uint16_t u = static_cast<uint16_t>(bg);
                  p[b_idx] = static_cast<uint8_t>(u & 0xFF);
                  p[b_idx + 1] = static_cast<uint8_t>((u >> 8) & 0xFF);
                } else {
                  p[b_idx] = 0;
                  p[b_idx + 1] = 0;
                }
              }
            }
          }
        }
      }
    }
  } else if (method == "inpaint") {
    for (int f = 0; f < frames; ++f) {
      std::size_t frame_byte_offset = static_cast<std::size_t>(f) * rows * cols * samples_per_pixel * bytes_per_sample;
      for (int s = 0; s < samples_per_pixel; ++s) {
        std::vector<double> img(rows * cols);
        for (int r = 0; r < rows; ++r) {
          for (int c = 0; c < cols; ++c) {
            std::size_t b_idx = frame_byte_offset + ((static_cast<std::size_t>(r) * cols + c) * samples_per_pixel + s) * bytes_per_sample;
            if (bytes_per_sample == 1) {
              img[r * cols + c] = static_cast<double>(p[b_idx]);
            } else {
              uint16_t u = static_cast<uint16_t>(p[b_idx]) | (static_cast<uint16_t>(p[b_idx + 1]) << 8);
              if (pixel_representation == 1) {
                img[r * cols + c] = static_cast<double>(static_cast<int16_t>(u));
              } else {
                img[r * cols + c] = static_cast<double>(u);
              }
            }
          }
        }

        dicomtk::run_telea_inpaint_frame(img, in_mask, rows, cols, radius);

        for (int r = 0; r < rows; ++r) {
          for (int c = 0; c < cols; ++c) {
            if (in_mask[r * cols + c]) {
              std::size_t b_idx = frame_byte_offset + ((static_cast<std::size_t>(r) * cols + c) * samples_per_pixel + s) * bytes_per_sample;
              double v = std::round(img[r * cols + c]);
              if (bytes_per_sample == 1) {
                uint8_t u8 = static_cast<uint8_t>(std::max(0.0, std::min(255.0, v)));
                p[b_idx] = u8;
              } else {
                if (pixel_representation == 1) {
                  int16_t s16 = static_cast<int16_t>(std::max(-32768.0, std::min(32767.0, v)));
                  uint16_t u = static_cast<uint16_t>(s16);
                  p[b_idx] = static_cast<uint8_t>(u & 0xFF);
                  p[b_idx + 1] = static_cast<uint8_t>((u >> 8) & 0xFF);
                } else {
                  uint16_t u16 = static_cast<uint16_t>(std::max(0.0, std::min(65535.0, v)));
                  p[b_idx] = static_cast<uint8_t>(u16 & 0xFF);
                  p[b_idx + 1] = static_cast<uint8_t>((u16 >> 8) & 0xFF);
                }
              }
            }
          }
        }
      }
    }
  } else {
    Rcpp::stop("Unknown pixel cleaning method: " + method);
  }

  return Rcpp::List::create(
    Rcpp::Named("pixels") = out_raw,
    Rcpp::Named("mask") = r_mask
  );
}

// [[Rcpp::export]]
Rcpp::List cpp_clean_pixels_file(const std::string& in_path,
                                 const std::string& out_path,
                                 const Rcpp::IntegerMatrix& boxes,
                                 const std::string& method = "blackout",
                                 int radius = 5) {
  dicomtk::DcmParsedFile dcm = dicomtk::parse_dicom_file(in_path, false, 64);
  if (!dcm.valid_dicom) {
    Rcpp::stop("Failed to parse valid DICOM file for pixel cleaning: " + in_path);
  }

  int rows = 0;
  int cols = 0;
  int nframes = 1;
  int bits_allocated = 16;
  int pixel_representation = 0;
  int samples_per_pixel = 1;
  std::string orig_sop_uid;
  std::string orig_image_type;
  std::string orig_deid_method;

  for (const auto& el : dcm.elements) {
    if (el.depth == 0) {
      if (el.group == 0x0028 && el.element == 0x0010) rows = std::atoi(el.value_str.c_str());
      else if (el.group == 0x0028 && el.element == 0x0011) cols = std::atoi(el.value_str.c_str());
      else if (el.group == 0x0028 && el.element == 0x0008) nframes = std::max(1, std::atoi(el.value_str.c_str()));
      else if (el.group == 0x0028 && el.element == 0x0100) bits_allocated = std::atoi(el.value_str.c_str());
      else if (el.group == 0x0028 && el.element == 0x0103) pixel_representation = std::atoi(el.value_str.c_str());
      else if (el.group == 0x0028 && el.element == 0x0002) samples_per_pixel = std::max(1, std::atoi(el.value_str.c_str()));
      else if (el.group == 0x0008 && el.element == 0x0018) orig_sop_uid = el.value_str;
      else if (el.group == 0x0008 && el.element == 0x0008) orig_image_type = el.value_str;
      else if (el.group == 0x0012 && el.element == 0x0063) orig_deid_method = el.value_str;
    }
  }

  if (dcm.pixel_data.empty()) {
    Rcpp::stop("No uncompressed pixel data found in DICOM file: " + in_path);
  }

  Rcpp::RawVector raw_vec(dcm.pixel_data.size());
  std::memcpy(raw_vec.begin(), dcm.pixel_data.data(), dcm.pixel_data.size());

  Rcpp::List applied = cpp_apply_pixel_mask(
    raw_vec, rows, cols, nframes, bits_allocated, pixel_representation, samples_per_pixel,
    boxes, method, radius
  );

  Rcpp::RawVector mod_raw = applied["pixels"];
  Rcpp::LogicalVector mask_vec = applied["mask"];
  std::memcpy(dcm.pixel_data.data(), mod_raw.begin(), mod_raw.size());

  // Set BurnedInAnnotation (0028,0301) = "NO"
  dicomtk::upsert_tag(dcm, 0x0028, 0x0301, "NO");

  std::string new_sop = orig_sop_uid;

  if (method == "inpaint") {
    // Guardrail 1: ImageType (0008,0008) starts with "DERIVED\SECONDARY"
    std::string new_img_type = "DERIVED\\SECONDARY";
    if (!orig_image_type.empty()) {
      std::size_t p1 = orig_image_type.find('\\');
      if (p1 != std::string::npos) {
        std::size_t p2 = orig_image_type.find('\\', p1 + 1);
        if (p2 != std::string::npos) {
          new_img_type += orig_image_type.substr(p2);
        }
      }
    }
    dicomtk::upsert_tag(dcm, 0x0008, 0x0008, new_img_type);

    // Guardrail 2: Generate new SOPInstanceUID
    new_sop = dicomtk::generate_dicom_uid("2.25");
    dicomtk::upsert_tag(dcm, 0x0008, 0x0018, new_sop);
    dicomtk::upsert_tag(dcm, 0x0002, 0x0003, new_sop);

    // Guardrail 3: DeidentificationMethodCodeSequence (0012,0064) records "113101"
    // and "INPAINT_TELEA" in (0012,0063)
    std::string new_method_str = orig_deid_method;
    if (new_method_str.empty()) {
      new_method_str = "INPAINT_TELEA";
    } else if (new_method_str.find("INPAINT_TELEA") == std::string::npos) {
      new_method_str += "\\INPAINT_TELEA";
    }
    dicomtk::upsert_tag(dcm, 0x0012, 0x0063, new_method_str);

    std::vector<dicomtk::DcmElementRecord> item_elems;
    dicomtk::DcmElementRecord r_code;
    r_code.group = 0x0008; r_code.element = 0x0100; r_code.vr = "SH";
    r_code.name = "Code Value"; r_code.keyword = "CodeValue"; r_code.vm = "1";
    r_code.value_str = "113101"; r_code.depth = 1;
    item_elems.push_back(std::move(r_code));

    dicomtk::DcmElementRecord r_sch;
    r_sch.group = 0x0008; r_sch.element = 0x0102; r_sch.vr = "SH";
    r_sch.name = "Coding Scheme Designator"; r_sch.keyword = "CodingSchemeDesignator"; r_sch.vm = "1";
    r_sch.value_str = "DCM"; r_sch.depth = 1;
    item_elems.push_back(std::move(r_sch));

    dicomtk::DcmElementRecord r_mean;
    r_mean.group = 0x0008; r_mean.element = 0x0104; r_mean.vr = "LO";
    r_mean.name = "Code Meaning"; r_mean.keyword = "CodeMeaning"; r_mean.vm = "1";
    r_mean.value_str = "Clean Pixel Data Option"; r_mean.depth = 1;
    item_elems.push_back(std::move(r_mean));

    std::vector<std::vector<dicomtk::DcmElementRecord>> code_items;
    code_items.push_back(std::move(item_elems));
    dicomtk::upsert_sq_tag(dcm, 0x0012, 0x0064, std::move(code_items));
  } else if (method == "blackout") {
    std::string new_method_str = orig_deid_method;
    if (new_method_str.empty()) {
      new_method_str = "PIXEL_BLACKOUT";
    } else if (new_method_str.find("PIXEL_BLACKOUT") == std::string::npos) {
      new_method_str += "\\PIXEL_BLACKOUT";
    }
    dicomtk::upsert_tag(dcm, 0x0012, 0x0063, new_method_str);

    std::vector<dicomtk::DcmElementRecord> item_elems;
    dicomtk::DcmElementRecord r_code;
    r_code.group = 0x0008; r_code.element = 0x0100; r_code.vr = "SH";
    r_code.name = "Code Value"; r_code.keyword = "CodeValue"; r_code.vm = "1";
    r_code.value_str = "113101"; r_code.depth = 1;
    item_elems.push_back(std::move(r_code));

    dicomtk::DcmElementRecord r_sch;
    r_sch.group = 0x0008; r_sch.element = 0x0102; r_sch.vr = "SH";
    r_sch.name = "Coding Scheme Designator"; r_sch.keyword = "CodingSchemeDesignator"; r_sch.vm = "1";
    r_sch.value_str = "DCM"; r_sch.depth = 1;
    item_elems.push_back(std::move(r_sch));

    dicomtk::DcmElementRecord r_mean;
    r_mean.group = 0x0008; r_mean.element = 0x0104; r_mean.vr = "LO";
    r_mean.name = "Code Meaning"; r_mean.keyword = "CodeMeaning"; r_mean.vm = "1";
    r_mean.value_str = "Clean Pixel Data Option"; r_mean.depth = 1;
    item_elems.push_back(std::move(r_mean));

    std::vector<std::vector<dicomtk::DcmElementRecord>> code_items;
    code_items.push_back(std::move(item_elems));
    dicomtk::upsert_sq_tag(dcm, 0x0012, 0x0064, std::move(code_items));
  }

  bool ok = dicomtk::write_dicom_file(dcm, out_path);
  if (!ok) {
    Rcpp::stop("Failed to write cleaned DICOM file to: " + out_path);
  }

  return Rcpp::List::create(
    Rcpp::Named("status") = "ok",
    Rcpp::Named("out_path") = out_path,
    Rcpp::Named("rows") = rows,
    Rcpp::Named("cols") = cols,
    Rcpp::Named("frames") = nframes,
    Rcpp::Named("mask") = mask_vec,
    Rcpp::Named("sop_instance_uid") = new_sop
  );
}
