test_that("C++17 rasterizer fills convex and concave 2D polygons accurately", {
  # 1. Simple square: [10, 10] to [20, 20] in a 32x32 grid (0-indexed or 1-indexed)
  # In R 1-indexing: rows 10..20, cols 10..20
  coords <- matrix(c(
    10, 10,
    20, 10,
    20, 20,
    10, 20
  ), ncol = 2, byrow = TRUE)

  mask <- rasterize_polygon_2d(coords, width = 32L, height = 32L)
  expect_true(is.matrix(mask))
  expect_equal(dim(mask), c(32L, 32L))
  expect_equal(typeof(mask), "logical")

  # Interior point should be TRUE
  expect_true(mask[15, 15])
  expect_false(mask[5, 5])
  expect_false(mask[25, 25])

  # Expected area should be approximately (20 - 10) * (20 - 10) = 100 pixels
  filled_count <- sum(mask)
  expect_gte(filled_count, 90L)
  expect_lte(filled_count, 121L)
})

test_that("C++17 rasterizer handles concave / L-shaped polygons and multiple contours with holes", {
  # L-shaped polygon
  l_coords <- matrix(c(
    5, 5,
    25, 5,
    25, 15,
    15, 15,
    15, 25,
    5, 25
  ), ncol = 2, byrow = TRUE)

  mask <- rasterize_polygon_2d(l_coords, width = 32L, height = 32L)
  # Inside the L
  expect_true(mask[10, 10])
  expect_true(mask[20, 10])
  expect_true(mask[10, 20])
  # Cutout region of the L
  expect_false(mask[20, 20])
  expect_false(mask[2, 2])

  # Donut / polygon with hole using even-odd fill rule
  # Outer box: 5..25, Inner hole: 10..20
  donut_list <- list(
    matrix(c(5, 5, 25, 5, 25, 25, 5, 25), ncol = 2, byrow = TRUE),
    matrix(c(10, 10, 20, 10, 20, 20, 10, 20), ncol = 2, byrow = TRUE)
  )
  donut_mask <- rasterize_polygons_2d(donut_list, width = 32L, height = 32L, rule = "evenodd")
  expect_true(donut_mask[7, 7])
  expect_false(donut_mask[15, 15]) # Inside hole should be FALSE
})

test_that("C++17 contour tracer extracts closed polygon vertices from binary masks", {
  # Create a known 32x32 binary mask with a 10x10 square in the center
  m <- matrix(FALSE, nrow = 32L, ncol = 32L)
  m[10:19, 10:19] <- TRUE

  contours <- trace_contours_2d(m)
  expect_true(is.list(contours))
  expect_gte(length(contours), 1L)

  poly <- contours[[1L]]
  expect_true(is.matrix(poly))
  expect_equal(ncol(poly), 2L)
  # Check bounding box of traced polygon matches [10..19]
  expect_gte(min(poly[, 1]), 9.0)
  expect_lte(max(poly[, 1]), 20.0)
  expect_gte(min(poly[, 2]), 9.0)
  expect_lte(max(poly[, 2]), 20.0)

  # Round-trip check: rasterizing the traced polygon should closely match original mask
  re_mask <- rasterize_polygon_2d(poly, width = 32L, height = 32L)
  dice <- 2 * sum(m & re_mask) / (sum(m) + sum(re_mask))
  expect_gt(dice, 0.90)
})
