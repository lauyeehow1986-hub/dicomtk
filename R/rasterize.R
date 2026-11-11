#' 2D Polygon Rasterization
#'
#' Rasterizes a 2D planar polygon into a binary mask of dimensions `height x width`.
#'
#' @param coords A 2-column numeric matrix of (x, y) vertex coordinates.
#' @param width Grid width (number of columns).
#' @param height Grid height (number of rows).
#'
#' @return A logical matrix of dimension `height x width`.
#' @export
#' @examples
#' poly <- matrix(c(5, 5, 15, 5, 15, 15, 5, 15), ncol = 2, byrow = TRUE)
#' m <- rasterize_polygon_2d(poly, 20L, 20L)
#' sum(m)
rasterize_polygon_2d <- function(coords, width, height) {
  if (!is.matrix(coords) || ncol(coords) != 2L) {
    rlang::abort("`coords` must be a 2-column numeric matrix.")
  }
  width <- as.integer(width)
  height <- as.integer(height)
  if (width <= 0L || height <= 0L) {
    rlang::abort("`width` and `height` must be positive integers.")
  }
  cpp_rasterize_polygon_2d(coords, width, height)
}

#' Rasterize Multiple 2D Polygons
#'
#' Rasterizes multiple 2D planar polygons (e.g. outer contour and inner holes)
#' using either `"evenodd"` or `"nonzero"` winding fill rules.
#'
#' @param polygons A list of 2-column numeric matrices.
#' @param width Grid width.
#' @param height Grid height.
#' @param rule Fill rule: `"evenodd"` (default) or `"nonzero"`.
#'
#' @return A logical matrix of dimension `height x width`.
#' @export
#' @examples
#' p1 <- matrix(c(2, 2, 18, 2, 18, 18, 2, 18), ncol = 2, byrow = TRUE)
#' p2 <- matrix(c(6, 6, 14, 6, 14, 14, 6, 14), ncol = 2, byrow = TRUE)
#' m <- rasterize_polygons_2d(list(p1, p2), 20L, 20L, rule = "evenodd")
#' sum(m)
rasterize_polygons_2d <- function(polygons, width, height, rule = c("evenodd", "nonzero")) {
  if (!is.list(polygons)) {
    rlang::abort("`polygons` must be a list of 2-column numeric matrices.")
  }
  rule <- match.arg(rule)
  width <- as.integer(width)
  height <- as.integer(height)
  cpp_rasterize_polygons_2d(polygons, width, height, rule)
}

#' Trace Contours from 2D Binary Mask
#'
#' Extracts ordered planar polygon vertices from a 2D binary mask using marching squares.
#'
#' @param mask A 2D logical matrix.
#'
#' @return A list of 2-column numeric matrices representing closed contour loops.
#' @export
#' @examples
#' m <- matrix(FALSE, 20L, 20L)
#' m[5:15, 5:15] <- TRUE
#' polys <- trace_contours_2d(m)
#' length(polys)
trace_contours_2d <- function(mask) {
  if (!is.matrix(mask) || !is.logical(mask)) {
    rlang::abort("`mask` must be a 2D logical matrix.")
  }
  cpp_trace_contours_2d(mask)
}
