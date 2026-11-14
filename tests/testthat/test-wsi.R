testthat::test_that("read_dicom_wsi_pyramid, wsi_extract_tile, and wsi_stitch_region work for TILED_FULL and TILED_SPARSE", {
  wsi_full <- tempfile("wsi_full_")
  on.exit(unlink(wsi_full, recursive = TRUE, force = TRUE), add = TRUE)

  syn <- dicom_synthesize_wsi(
    out_dir = wsi_full,
    base_dims = c(32L, 32L),
    tile_dims = c(16L, 16L),
    levels = 2L,
    organization = "TILED_FULL"
  )
  pyr <- read_dicom_wsi_pyramid(wsi_full)
  testthat::expect_s3_class(pyr, "dicom_wsi_pyramid")
  testthat::expect_equal(nrow(pyr$levels), 2L)
  testthat::expect_equal(pyr$levels$total_cols[1L], 32L)
  testthat::expect_equal(pyr$levels$total_cols[2L], 16L)

  tile12 <- wsi_extract_tile(pyr, level = 1L, tile_row = 1L, tile_col = 2L)
  testthat::expect_equal(dim(tile12), c(16L, 16L))
  testthat::expect_equal(tile12, syn$level_arrays[[1L]][1:16, 17:32])

  # Stitch across all 4 tiles at Level 1
  stitched <- wsi_stitch_region(pyr, level = 1L, x = 9L, y = 9L, width = 16L, height = 16L)
  testthat::expect_equal(dim(stitched), c(16L, 16L))
  testthat::expect_equal(stitched, syn$level_arrays[[1L]][9:24, 9:24])

  # TILED_SPARSE
  wsi_sparse <- tempfile("wsi_sparse_")
  on.exit(unlink(wsi_sparse, recursive = TRUE, force = TRUE), add = TRUE)
  syn_sp <- dicom_synthesize_wsi(
    out_dir = wsi_sparse,
    base_dims = c(32L, 32L),
    tile_dims = c(16L, 16L),
    levels = 1L,
    organization = "TILED_SPARSE"
  )
  pyr_sp <- read_dicom_wsi_pyramid(wsi_sparse)
  stitched_sp <- wsi_stitch_region(pyr_sp, level = 1L, x = 1L, y = 1L, width = 32L, height = 32L)
  testthat::expect_equal(stitched_sp, syn_sp$level_arrays[[1L]])
})

testthat::test_that("dicom_wsi_annotations and wsi_annotations_to_mask rasterize Sup 222 ROIs", {
  rois <- list(
    list(
      label = "tumor_core",
      type = "POLYGON",
      coords = matrix(c(5, 5, 15, 5, 15, 15, 5, 15), ncol = 2L, byrow = TRUE)
    )
  )
  ann <- dicom_wsi_annotations(rois, coordinate_type = "2D", pixel_matrix_dims = c(32L, 32L))
  testthat::expect_s3_class(ann, "dicom_wsi_annotations")
  mask <- wsi_annotations_to_mask(ann)
  testthat::expect_equal(dim(mask), c(32L, 32L))
  testthat::expect_equal(mask[10L, 10L], 1L)
  testthat::expect_equal(mask[2L, 2L], 0L)
})
