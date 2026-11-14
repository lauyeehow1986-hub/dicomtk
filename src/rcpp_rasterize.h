#ifndef DICOMTK_RCPP_RASTERIZE_H
#define DICOMTK_RCPP_RASTERIZE_H

#include <vector>
#include <cstdint>
#include <string>

namespace dicomtk {

struct Point2D {
  double x;
  double y;
};

// Rasterize single 2D polygon onto a width x height binary mask
std::vector<uint8_t> rasterize_polygon_scanline(
    const std::vector<Point2D>& vertices,
    int width,
    int height);

// Rasterize multiple 2D polygons using either "evenodd" or "nonzero" fill rule
std::vector<uint8_t> rasterize_polygons_scanline(
    const std::vector<std::vector<Point2D>>& polygons,
    int width,
    int height,
    const std::string& rule = "evenodd");

// Extract closed contour loops from a width x height binary mask using marching squares
std::vector<std::vector<Point2D>> trace_contours_marching_squares(
    const uint8_t* mask,
    int width,
    int height);

} // namespace dicomtk

#endif // DICOMTK_RCPP_RASTERIZE_H
