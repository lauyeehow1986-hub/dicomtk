#include "rcpp_rasterize.h"
#include <Rcpp.h>
#include <algorithm>
#include <cmath>
#include <map>
#include <set>

namespace dicomtk {

struct Edge {
  double y_min;
  double y_max;
  double x_val;  // x coordinate at y_min
  double inv_m;  // 1 / slope (dx / dy)
  int direction; // +1 if edge goes up, -1 if edge goes down
};

std::vector<uint8_t> rasterize_polygon_scanline(
    const std::vector<Point2D>& vertices,
    int width,
    int height) {
  std::vector<std::vector<Point2D>> poly_list = { vertices };
  return rasterize_polygons_scanline(poly_list, width, height, "evenodd");
}

std::vector<uint8_t> rasterize_polygons_scanline(
    const std::vector<std::vector<Point2D>>& polygons,
    int width,
    int height,
    const std::string& rule) {
  std::vector<uint8_t> mask(static_cast<size_t>(width) * height, 0);
  if (width <= 0 || height <= 0 || polygons.empty()) {
    return mask;
  }

  // Build global edge table (GET)
  std::vector<Edge> edges;
  for (const auto& poly : polygons) {
    size_t n = poly.size();
    if (n < 3) continue;

    for (size_t i = 0; i < n; ++i) {
      const Point2D& p1 = poly[i];
      const Point2D& p2 = poly[(i + 1) % n];

      if (std::abs(p1.y - p2.y) < 1e-9) {
        // Ignore perfectly horizontal edges for scanline intersection
        continue;
      }

      Edge e;
      if (p1.y < p2.y) {
        e.y_min = p1.y;
        e.y_max = p2.y;
        e.x_val = p1.x;
        e.inv_m = (p2.x - p1.x) / (p2.y - p1.y);
        e.direction = 1;
      } else {
        e.y_min = p2.y;
        e.y_max = p1.y;
        e.x_val = p2.x;
        e.inv_m = (p1.x - p2.x) / (p1.y - p2.y);
        e.direction = -1;
      }
      edges.push_back(e);
    }
  }

  if (edges.empty()) {
    return mask;
  }

  // Scan each column y in 1..width, intersecting edges to fill rows x in 1..height
  // Coordinates are 1-based R matrix coordinates: Point2D.x = row (1..height), Point2D.y = col (1..width)
  for (int y = 1; y <= width; ++y) {
    double scan_y = static_cast<double>(y);

    // Collect intersections with active edges
    struct Intersection {
      double x;
      int direction;
    };
    std::vector<Intersection> x_inters;

    for (const auto& e : edges) {
      if (scan_y >= e.y_min && scan_y < e.y_max) {
        double ix = e.x_val + (scan_y - e.y_min) * e.inv_m;
        x_inters.push_back({ ix, e.direction });
      }
    }

    if (x_inters.empty()) continue;

    std::sort(x_inters.begin(), x_inters.end(), [](const Intersection& a, const Intersection& b) {
      return a.x < b.x;
    });

    if (rule == "nonzero") {
      int winding = 0;
      for (size_t i = 0; i + 1 < x_inters.size(); ++i) {
        winding += x_inters[i].direction;
        if (winding != 0) {
          int r_start = std::max(1, static_cast<int>(std::round(x_inters[i].x)));
          int r_end = std::min(height, static_cast<int>(std::round(x_inters[i + 1].x)));
          for (int r = r_start; r <= r_end; ++r) {
            // R column-major order: index = (col - 1) * height + (row - 1)
            mask[static_cast<size_t>(y - 1) * height + (r - 1)] = 1;
          }
        }
      }
    } else { // "evenodd"
      for (size_t i = 0; i + 1 < x_inters.size(); i += 2) {
        int r_start = std::max(1, static_cast<int>(std::round(x_inters[i].x)));
        int r_end = std::min(height, static_cast<int>(std::round(x_inters[i + 1].x)));
        for (int r = r_start; r <= r_end; ++r) {
          mask[static_cast<size_t>(y - 1) * height + (r - 1)] = 1;
        }
      }
    }
  }

  return mask;
}

// Simple boundary tracing / marching squares to extract closed polygons in (row, col) coordinates
std::vector<std::vector<Point2D>> trace_contours_marching_squares(
    const uint8_t* mask,
    int width,
    int height) {
  std::vector<std::vector<Point2D>> contours;
  if (width <= 0 || height <= 0 || mask == nullptr) {
    return contours;
  }

  // Directed segment representation
  struct Segment {
    Point2D p1;
    Point2D p2;
    bool used = false;
  };
  std::vector<Segment> segments;

  auto get_val = [&](int r, int c) -> int {
    if (r < 1 || r > height || c < 1 || c > width) return 0;
    return mask[static_cast<size_t>(c - 1) * height + (r - 1)] ? 1 : 0;
  };

  // Evaluate cells on grid corners [0..height] x [0..width]
  for (int r = 0; r <= height; ++r) {
    for (int c = 0; c <= width; ++c) {
      // Four corners around grid cell:
      // (r, c)       top-left
      // (r, c+1)     top-right
      // (r+1, c+1)   bottom-right
      // (r+1, c)     bottom-left
      int tl = get_val(r, c);
      int tr = get_val(r, c + 1);
      int br = get_val(r + 1, c + 1);
      int bl = get_val(r + 1, c);

      int cell_case = (tl << 3) | (tr << 2) | (br << 1) | bl;
      if (cell_case == 0 || cell_case == 15) continue;

      Point2D top_mid    = { static_cast<double>(r),       static_cast<double>(c) + 0.5 };
      Point2D right_mid  = { static_cast<double>(r) + 0.5, static_cast<double>(c + 1) };
      Point2D bottom_mid = { static_cast<double>(r + 1),   static_cast<double>(c) + 0.5 };
      Point2D left_mid   = { static_cast<double>(r) + 0.5, static_cast<double>(c) };

      switch (cell_case) {
        case 1:  segments.push_back({ left_mid, bottom_mid }); break;
        case 2:  segments.push_back({ bottom_mid, right_mid }); break;
        case 3:  segments.push_back({ left_mid, right_mid }); break;
        case 4:  segments.push_back({ right_mid, top_mid }); break;
        case 5:
          segments.push_back({ left_mid, top_mid });
          segments.push_back({ bottom_mid, right_mid });
          break;
        case 6:  segments.push_back({ bottom_mid, top_mid }); break;
        case 7:  segments.push_back({ left_mid, top_mid }); break;
        case 8:  segments.push_back({ top_mid, left_mid }); break;
        case 9:  segments.push_back({ top_mid, bottom_mid }); break;
        case 10:
          segments.push_back({ top_mid, right_mid });
          segments.push_back({ left_mid, bottom_mid });
          break;
        case 11: segments.push_back({ top_mid, right_mid }); break;
        case 12: segments.push_back({ right_mid, left_mid }); break;
        case 13: segments.push_back({ right_mid, bottom_mid }); break;
        case 14: segments.push_back({ bottom_mid, left_mid }); break;
      }
    }
  }

  // Connect segments into closed contour chains
  for (size_t i = 0; i < segments.size(); ++i) {
    if (segments[i].used) continue;

    std::vector<Point2D> contour;
    contour.push_back(segments[i].p1);
    contour.push_back(segments[i].p2);
    segments[i].used = true;

    Point2D curr_end = segments[i].p2;
    bool extended = true;

    while (extended) {
      extended = false;
      for (size_t j = 0; j < segments.size(); ++j) {
        if (segments[j].used) continue;

        double d_fwd = std::hypot(curr_end.x - segments[j].p1.x, curr_end.y - segments[j].p1.y);
        if (d_fwd < 1e-4) {
          contour.push_back(segments[j].p2);
          curr_end = segments[j].p2;
          segments[j].used = true;
          extended = true;
          break;
        }

        double d_rev = std::hypot(curr_end.x - segments[j].p2.x, curr_end.y - segments[j].p2.y);
        if (d_rev < 1e-4) {
          contour.push_back(segments[j].p1);
          curr_end = segments[j].p1;
          segments[j].used = true;
          extended = true;
          break;
        }
      }

      // Check if loop is closed
      if (contour.size() > 2) {
        double d_close = std::hypot(contour.front().x - curr_end.x, contour.front().y - curr_end.y);
        if (d_close < 1e-4) {
          break;
        }
      }
    }

    if (contour.size() >= 3) {
      contours.push_back(contour);
    }
  }

  return contours;
}

} // namespace dicomtk

// [[Rcpp::export]]
Rcpp::LogicalMatrix cpp_rasterize_polygon_2d(
    Rcpp::NumericMatrix coords,
    int width,
    int height) {
  int n = coords.nrow();
  std::vector<dicomtk::Point2D> pts(n);
  for (int i = 0; i < n; ++i) {
    pts[i] = { coords(i, 0), coords(i, 1) };
  }

  auto raw_mask = dicomtk::rasterize_polygon_scanline(pts, width, height);

  Rcpp::LogicalMatrix out(height, width);
  for (size_t i = 0; i < raw_mask.size(); ++i) {
    out[i] = raw_mask[i] ? true : false;
  }
  return out;
}

// [[Rcpp::export]]
Rcpp::LogicalMatrix cpp_rasterize_polygons_2d(
    Rcpp::List poly_list,
    int width,
    int height,
    std::string rule = "evenodd") {
  std::vector<std::vector<dicomtk::Point2D>> polys;
  for (int k = 0; k < poly_list.size(); ++k) {
    Rcpp::NumericMatrix coords = poly_list[k];
    int n = coords.nrow();
    std::vector<dicomtk::Point2D> pts(n);
    for (int i = 0; i < n; ++i) {
      pts[i] = { coords(i, 0), coords(i, 1) };
    }
    polys.push_back(pts);
  }

  auto raw_mask = dicomtk::rasterize_polygons_scanline(polys, width, height, rule);

  Rcpp::LogicalMatrix out(height, width);
  for (size_t i = 0; i < raw_mask.size(); ++i) {
    out[i] = raw_mask[i] ? true : false;
  }
  return out;
}

// [[Rcpp::export]]
Rcpp::List cpp_trace_contours_2d(Rcpp::LogicalMatrix mask) {
  int height = mask.nrow();
  int width = mask.ncol();

  std::vector<uint8_t> raw_mask(static_cast<size_t>(width) * height);
  for (int i = 0; i < height * width; ++i) {
    raw_mask[i] = mask[i] ? 1 : 0;
  }

  auto contours = dicomtk::trace_contours_marching_squares(raw_mask.data(), width, height);

  Rcpp::List out(contours.size());
  for (size_t i = 0; i < contours.size(); ++i) {
    int n = static_cast<int>(contours[i].size());
    Rcpp::NumericMatrix mat(n, 2);
    for (int j = 0; j < n; ++j) {
      mat(j, 0) = contours[i][j].x;
      mat(j, 1) = contours[i][j].y;
    }
    out[i] = mat;
  }
  return out;
}
