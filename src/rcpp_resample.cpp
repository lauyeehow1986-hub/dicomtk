#include <Rcpp.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <vector>

// [[Rcpp::export]]
Rcpp::NumericVector cpp_resample_volume_3d(const Rcpp::NumericVector& vox,
                                           const Rcpp::IntegerVector& old_dims,
                                           const Rcpp::DoubleVector& old_spacing,
                                           const Rcpp::IntegerVector& new_dims,
                                           const Rcpp::DoubleVector& new_spacing,
                                           const std::string& method = "trilinear") {
  if (old_dims.size() < 3 || new_dims.size() < 3) {
    Rcpp::stop("`old_dims` and `new_dims` must have length 3.");
  }
  if (old_spacing.size() < 3 || new_spacing.size() < 3) {
    Rcpp::stop("`old_spacing` and `new_spacing` must have length 3.");
  }

  const int nr_in = old_dims[0];
  const int nc_in = old_dims[1];
  const int ns_in = old_dims[2];

  const int nr_out = new_dims[0];
  const int nc_out = new_dims[1];
  const int ns_out = new_dims[2];

  if (nr_in <= 0 || nc_in <= 0 || ns_in <= 0 ||
      nr_out <= 0 || nc_out <= 0 || ns_out <= 0) {
    Rcpp::stop("All volume dimensions must be strictly positive.");
  }

  const double dr_in = old_spacing[0] > 0.0 ? old_spacing[0] : 1.0;
  const double dc_in = old_spacing[1] > 0.0 ? old_spacing[1] : 1.0;
  const double ds_in = old_spacing[2] > 0.0 ? old_spacing[2] : 1.0;

  const double scale_r = new_spacing[0] / dr_in;
  const double scale_c = new_spacing[1] / dc_in;
  const double scale_s = new_spacing[2] / ds_in;

  const std::size_t n_in = static_cast<std::size_t>(nr_in) * nc_in * ns_in;
  if (static_cast<std::size_t>(vox.size()) < n_in) {
    Rcpp::stop("`vox` length is smaller than `prod(old_dims)`.");
  }
  const std::size_t n_out = static_cast<std::size_t>(nr_out) * nc_out * ns_out;
  Rcpp::NumericVector out(n_out);
  out.attr("dim") = Rcpp::IntegerVector::create(nr_out, nc_out, ns_out);

  const double* in_ptr = vox.begin();
  double* out_ptr = out.begin();

  auto idx_in = [&](int r, int c, int s) -> double {
    return in_ptr[static_cast<std::size_t>(r) +
                  static_cast<std::size_t>(c) * nr_in +
                  static_cast<std::size_t>(s) * nr_in * nc_in];
  };

  const bool is_nearest = (method == "nearest");

  for (int s_out = 0; s_out < ns_out; ++s_out) {
    double s_src = s_out * scale_s;
    for (int c_out = 0; c_out < nc_out; ++c_out) {
      double c_src = c_out * scale_c;
      for (int r_out = 0; r_out < nr_out; ++r_out) {
        double r_src = r_out * scale_r;
        std::size_t out_idx = static_cast<std::size_t>(r_out) +
                              static_cast<std::size_t>(c_out) * nr_out +
                              static_cast<std::size_t>(s_out) * nr_out * nc_out;

        if (is_nearest) {
          int r_nn = std::min(nr_in - 1, std::max(0, static_cast<int>(std::round(r_src))));
          int c_nn = std::min(nc_in - 1, std::max(0, static_cast<int>(std::round(c_src))));
          int s_nn = std::min(ns_in - 1, std::max(0, static_cast<int>(std::round(s_src))));
          out_ptr[out_idx] = idx_in(r_nn, c_nn, s_nn);
        } else {
          // Trilinear interpolation clamped to boundary
          double rf = std::min(static_cast<double>(nr_in - 1), std::max(0.0, r_src));
          double cf = std::min(static_cast<double>(nc_in - 1), std::max(0.0, c_src));
          double sf = std::min(static_cast<double>(ns_in - 1), std::max(0.0, s_src));

          int r0 = static_cast<int>(std::floor(rf));
          int c0 = static_cast<int>(std::floor(cf));
          int s0 = static_cast<int>(std::floor(sf));

          int r1 = std::min(nr_in - 1, r0 + 1);
          int c1 = std::min(nc_in - 1, c0 + 1);
          int s1 = std::min(ns_in - 1, s0 + 1);

          double dr = rf - r0;
          double dc = cf - c0;
          double ds = sf - s0;

          double c00 = idx_in(r0, c0, s0) * (1.0 - dr) + idx_in(r1, c0, s0) * dr;
          double c01 = idx_in(r0, c0, s1) * (1.0 - dr) + idx_in(r1, c0, s1) * dr;
          double c10 = idx_in(r0, c1, s0) * (1.0 - dr) + idx_in(r1, c1, s0) * dr;
          double c11 = idx_in(r0, c1, s1) * (1.0 - dr) + idx_in(r1, c1, s1) * dr;

          double c0_val = c00 * (1.0 - dc) + c10 * dc;
          double c1_val = c01 * (1.0 - dc) + c11 * dc;

          out_ptr[out_idx] = c0_val * (1.0 - ds) + c1_val * ds;
        }
      }
    }
  }

  return out;
}
