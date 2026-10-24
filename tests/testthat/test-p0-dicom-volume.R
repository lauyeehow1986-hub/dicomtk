cross3_vol_test <- function(a, b) {
  c(
    a[2L] * b[3L] - a[3L] * b[2L],
    a[3L] * b[1L] - a[1L] * b[3L],
    a[1L] * b[2L] - a[2L] * b[1L]
  )
}

make_test_oblique_volume <- function(dims = c(12L, 14L, 6L),
                                     spacing = c(0.8, 0.9, 2.5),
                                     origin = c(-20.0, 15.0, -10.0),
                                     gantry_tilt_deg = 0) {
  out_dir <- tempfile("vol_test_synth_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  phantom <- dicom_synthesize(
    out_dir = out_dir,
    modality = "CT",
    dims = dims,
    spacing = spacing,
    origin = origin,
    orientation = "oblique",
    oblique_angles_deg = c(20, -15, 8),
    gantry_tilt_deg = gantry_tilt_deg,
    phi = FALSE
  )

  fmeta <- tibble::tibble(
    slice_id = seq_len(dims[3L]),
    z_pos = phantom$slice_positions_lps[, 3L],
    file = phantom$files
  )

  list(
    phantom = phantom,
    vol = new_dicom_volume(
      voxels = phantom$truth_voxels,
      affine = phantom$truth_affine_lps,
      coord_system = "LPS",
      frame_meta = fmeta,
      uids = phantom$uids,
      modality = "CT",
      units = "HU"
    )
  )
}

test_that("new_dicom_volume() constructs 2D/3D/4D volumes and auto-derives spacing and direction", {
  fixture <- make_test_oblique_volume(gantry_tilt_deg = 12)
  phantom <- fixture$phantom
  vol <- fixture$vol

  expect_true(is_dicom_volume(vol))
  expect_s3_class(vol, "dicom_volume")
  expect_false(is_dicom_volume(list()))
  expect_false(is_dicom_volume(phantom$truth_voxels))

  expected_fields <- c(
    "voxels", "affine", "coord_system", "spacing", "direction",
    "frame_meta", "uids", "modality", "units", "diagnostics", "provenance"
  )
  expect_true(all(expected_fields %in% names(vol)))

  expect_equal(dim(vol), c(12L, 14L, 6L))
  expect_equal(vol$coord_system, "LPS")
  expect_equal(vol$modality, "CT")
  expect_equal(vol$units, "HU")
  expect_s3_class(vol$frame_meta, "tbl_df")
  expect_true(is.list(vol$uids))
  expect_true(is.list(vol$diagnostics))
  expect_true(is.list(vol$provenance))

  # Auto-derived spacing & direction must match ground truth even with oblique + gantry tilt
  expect_equal(vol$spacing, phantom$spacing, tolerance = 1e-12)
  expect_equal(vol$direction$d_row, phantom$direction$d_row, tolerance = 1e-12)
  expect_equal(vol$direction$d_col, phantom$direction$d_col, tolerance = 1e-12)
  expect_equal(vol$direction$normal, phantom$direction$normal, tolerance = 1e-12)

  # 2D matrix auto-promotes to [rows, cols, 1L]
  mat2d <- matrix(seq_len(20), nrow = 4L, ncol = 5L, dimnames = list(paste0("r", 1:4), paste0("c", 1:5)))
  vol2d <- new_dicom_volume(mat2d)
  expect_true(is_dicom_volume(vol2d))
  expect_equal(dim(vol2d), c(4L, 5L, 1L))
  expect_equal(as.numeric(as.array(vol2d)), as.numeric(mat2d))

  # 4D array [rows, cols, slices, frames] is accepted
  arr4d <- array(seq_len(4 * 5 * 3 * 2), dim = c(4L, 5L, 3L, 2L))
  vol4d <- new_dicom_volume(arr4d, affine = phantom$truth_affine_lps, modality = "MR")
  expect_true(is_dicom_volume(vol4d))
  expect_equal(dim(vol4d), c(4L, 5L, 3L, 2L))
})

test_that("new_dicom_volume() rejects invalid inputs via cli_abort()", {
  good_vox <- array(1.0, dim = c(4L, 4L, 2L))
  good_aff <- diag(4L)

  # Invalid voxels
  expect_error(new_dicom_volume("not_numeric", good_aff), "voxels")
  expect_error(new_dicom_volume(numeric(0), good_aff), "voxels")
  expect_error(new_dicom_volume(1:8, good_aff), "voxels|dimensions")
  expect_error(new_dicom_volume(array(numeric(0), dim = c(0L, 4L, 2L)), good_aff), "voxels|positive")
  expect_error(new_dicom_volume(array(1.0, dim = c(2L, 2L, 2L, 2L, 2L)), good_aff), "voxels|dimensions")

  # Invalid affine
  expect_error(new_dicom_volume(good_vox, diag(3L)), "affine|4x4")
  expect_error(new_dicom_volume(good_vox, matrix("a", 4L, 4L)), "affine")
  na_aff <- good_aff
  na_aff[1L, 4L] <- NA_real_
  expect_error(new_dicom_volume(good_vox, na_aff), "affine|finite")
  inf_aff <- good_aff
  inf_aff[2L, 2L] <- Inf
  expect_error(new_dicom_volume(good_vox, inf_aff), "affine|finite")
  bad_bottom <- good_aff
  bad_bottom[4L, ] <- c(0, 0, 0, 2)
  expect_error(new_dicom_volume(good_vox, bad_bottom), "affine|Bottom row")
  bad_bottom2 <- good_aff
  bad_bottom2[4L, 1L] <- 0.5
  expect_error(new_dicom_volume(good_vox, bad_bottom2), "affine|Bottom row")

  # Invalid metadata fields
  expect_error(new_dicom_volume(good_vox, good_aff, coord_system = "MNI"), "coord_system")
  expect_error(new_dicom_volume(good_vox, good_aff, spacing = c(1, -1, 2)), "spacing")
  expect_error(new_dicom_volume(good_vox, good_aff, spacing = c(1, 1)), "spacing")
  expect_error(new_dicom_volume(good_vox, good_aff, direction = list(d_row = c(1, 0, 0))), "direction")
  expect_error(new_dicom_volume(good_vox, good_aff, frame_meta = "not_a_tibble"), "frame_meta")
  expect_error(new_dicom_volume(good_vox, good_aff, uids = "not_a_list"), "uids")
  expect_error(new_dicom_volume(good_vox, good_aff, diagnostics = "not_a_list"), "diagnostics")
  expect_error(new_dicom_volume(good_vox, good_aff, provenance = "not_a_list"), "provenance")
  expect_error(new_dicom_volume(good_vox, good_aff, modality = c("CT", "MR")), "modality")
  expect_error(new_dicom_volume(good_vox, good_aff, units = 123), "units")
})

test_that("S3 methods dim(), as.array(), and print() work cleanly on dicom_volume", {
  fixture <- make_test_oblique_volume(dims = c(8L, 10L, 4L))
  vol <- fixture$vol

  expect_equal(dim(vol), c(8L, 10L, 4L))
  arr <- as.array(vol)
  expect_true(is.array(arr))
  expect_false(is_dicom_volume(arr))
  expect_equal(arr, fixture$phantom$truth_voxels)

  expect_output(ret <- print(vol), "dicom_volume")
  expect_output(print(vol), "LPS")
  expect_identical(ret, vol)
})

test_that("to_ras() and to_lps() transform affine/direction accurately, preserve handedness, and are idempotent", {
  fixture <- make_test_oblique_volume(gantry_tilt_deg = 10)
  vol_lps <- fixture$vol

  # Already LPS -> to_lps is idempotent without adding provenance
  vol_lps_noop <- to_lps(vol_lps)
  expect_identical(vol_lps_noop$affine, vol_lps$affine)
  expect_identical(vol_lps_noop$provenance, vol_lps$provenance)

  # LPS -> RAS
  vol_ras <- to_ras(vol_lps)
  expect_true(is_dicom_volume(vol_ras))
  expect_equal(vol_ras$coord_system, "RAS")
  expect_equal(length(vol_ras$provenance), length(vol_lps$provenance) + 1L)

  expected_ras_aff <- diag(c(-1, -1, 1, 1)) %*% vol_lps$affine
  expect_equal(vol_ras$affine, expected_ras_aff, tolerance = 1e-12)

  # Components 1 & 2 of d_row, d_col, normal negated; component 3 preserved
  expect_equal(vol_ras$direction$d_row, vol_lps$direction$d_row * c(-1, -1, 1), tolerance = 1e-12)
  expect_equal(vol_ras$direction$d_col, vol_lps$direction$d_col * c(-1, -1, 1), tolerance = 1e-12)
  expect_equal(vol_ras$direction$normal, vol_lps$direction$normal * c(-1, -1, 1), tolerance = 1e-12)

  # Right-handedness preserved: cross(d_row, d_col) == normal and det == +1
  expect_equal(
    cross3_vol_test(vol_ras$direction$d_row, vol_ras$direction$d_col),
    vol_ras$direction$normal,
    tolerance = 1e-12
  )
  basis_ras <- cbind(vol_ras$direction$d_row, vol_ras$direction$d_col, vol_ras$direction$normal)
  expect_equal(det(basis_ras), 1.0, tolerance = 1e-12)

  # Idempotent when already RAS (no duplicate no-op provenance)
  vol_ras_noop <- to_ras(vol_ras)
  expect_identical(vol_ras_noop$affine, vol_ras$affine)
  expect_identical(vol_ras_noop$provenance, vol_ras$provenance)

  # RAS -> LPS round-trip recovers truth_affine_lps within 1e-12
  vol_back <- to_lps(vol_ras)
  expect_equal(vol_back$coord_system, "LPS")
  expect_equal(vol_back$affine, vol_lps$affine, tolerance = 1e-12)
  expect_equal(vol_back$direction$d_row, vol_lps$direction$d_row, tolerance = 1e-12)
  expect_equal(vol_back$direction$d_col, vol_lps$direction$d_col, tolerance = 1e-12)
  expect_equal(vol_back$direction$normal, vol_lps$direction$normal, tolerance = 1e-12)
  expect_equal(length(vol_back$provenance), length(vol_lps$provenance) + 2L)
})

test_that("voxel_to_world() and world_to_voxel() support 0/1-based vectors and Nx3 matrices and reject singular affines", {
  fixture <- make_test_oblique_volume(dims = c(16L, 16L, 8L), gantry_tilt_deg = 15)
  vol <- fixture$vol

  # Origin tests for index_base = 1L and index_base = 0L
  w1 <- voxel_to_world(vol, c(1, 1, 1), index_base = 1L)
  expect_true(is.numeric(w1) && !is.matrix(w1) && length(w1) == 3L)
  expect_false(is.null(names(w1)))
  expect_equal(unname(w1), vol$affine[1:3, 4L], tolerance = 1e-12)

  w0 <- voxel_to_world(vol, c(0, 0, 0), index_base = 0L)
  expect_true(is.numeric(w0) && !is.matrix(w0) && length(w0) == 3L)
  expect_false(is.null(names(w0)))
  expect_equal(unname(w0), vol$affine[1:3, 4L], tolerance = 1e-12)

  # Single vector round-trip (sub-voxel oblique + tilted)
  pt_vec <- c(3.25, 7.5, 4.125)
  world_vec <- voxel_to_world(vol, pt_vec, index_base = 1L)
  vox_vec <- world_to_voxel(vol, world_vec, index_base = 1L)
  expect_true(is.numeric(vox_vec) && !is.matrix(vox_vec) && length(vox_vec) == 3L)
  expect_false(is.null(names(vox_vec)))
  expect_equal(unname(vox_vec), pt_vec, tolerance = 1e-10)

  # N x 3 matrix round-trip for both index_base = 1L and index_base = 0L
  pts <- rbind(
    c(1.0, 1.0, 1.0),
    c(16.0, 1.0, 1.0),
    c(1.0, 16.0, 8.0),
    c(5.4, 9.2, 3.7)
  )
  world_mat <- voxel_to_world(vol, pts, index_base = 1L)
  expect_true(is.matrix(world_mat) && is.numeric(world_mat))
  expect_equal(dim(world_mat), c(4L, 3L))
  expect_equal(world_to_voxel(vol, world_mat, index_base = 1L), pts, tolerance = 1e-10)

  pts0 <- pts - 1.0
  world_mat0 <- voxel_to_world(vol, pts0, index_base = 0L)
  expect_equal(world_mat0, world_mat, tolerance = 1e-12)
  expect_equal(world_to_voxel(vol, world_mat0, index_base = 0L), pts0, tolerance = 1e-10)

  # Singular affine aborts informatively in world_to_voxel()
  sing_aff <- vol$affine
  sing_aff[1:3, 3L] <- 0.0
  vol_sing <- new_dicom_volume(vol$voxels, affine = sing_aff)
  expect_error(world_to_voxel(vol_sing, c(0, 0, 0)), "singular|invert", ignore.case = TRUE)
})

test_that("Subsetting [.dicom_volume updates origin, strides, frame_meta, 4D frames, irregular spacing, and drop", {
  fixture <- make_test_oblique_volume(dims = c(12L, 14L, 6L), gantry_tilt_deg = 8)
  vol <- fixture$vol

  # 1. Contiguous 3D subset
  sub <- vol[2:10, 3:12, 2:5]
  expect_true(is_dicom_volume(sub))
  expect_equal(dim(sub), c(9L, 10L, 4L))
  expect_identical(as.array(sub), as.array(vol)[2:10, 3:12, 2:5])
  expect_equal(
    sub$affine[1:3, 4L],
    unname(voxel_to_world(vol, c(2, 3, 2), index_base = 1L)),
    tolerance = 1e-12
  )
  expect_equal(nrow(sub$frame_meta), 4L)
  expect_equal(sub$frame_meta$slice_id, 2:5)
  # Check interior voxel world coordinate invariance
  expect_equal(
    voxel_to_world(sub, c(4, 5, 3), index_base = 1L),
    voxel_to_world(vol, c(5, 7, 4), index_base = 1L),
    tolerance = 1e-11
  )

  # 2. Strided and reversed subset: vol[seq(2, 10, by = 2), , 5:2]
  sub_sr <- vol[seq(2, 10, by = 2), , 5:2]
  expect_true(is_dicom_volume(sub_sr))
  expect_equal(dim(sub_sr), c(5L, 14L, 4L))
  expect_identical(as.array(sub_sr), as.array(vol)[seq(2, 10, by = 2), , 5:2])
  expect_equal(sub_sr$spacing, c(vol$spacing[1L] * 2, vol$spacing[2L], vol$spacing[3L]), tolerance = 1e-12)
  expect_equal(sub_sr$affine[1:3, 1L], vol$affine[1:3, 1L] * 2, tolerance = 1e-12)
  expect_equal(sub_sr$affine[1:3, 3L], -vol$affine[1:3, 3L], tolerance = 1e-12)
  expect_equal(sub_sr$frame_meta$slice_id, 5:2)
  expect_equal(
    voxel_to_world(sub_sr, c(3, 6, 4), index_base = 1L),
    voxel_to_world(vol, c(6, 6, 2), index_base = 1L),
    tolerance = 1e-11
  )

  # Reversed in-plane row/col indices update direction signs & preserve right-handed normal
  sub_flip_rc <- vol[10:2, 12:3, 2:5]
  expect_equal(sub_flip_rc$direction$d_col, -vol$direction$d_col, tolerance = 1e-12)
  expect_equal(sub_flip_rc$direction$d_row, -vol$direction$d_row, tolerance = 1e-12)
  expect_equal(
    sub_flip_rc$direction$normal,
    cross3_vol_test(sub_flip_rc$direction$d_row, sub_flip_rc$direction$d_col),
    tolerance = 1e-12
  )

  # 3. Non-uniform indices warn and flag diagnostics$irregular_spacing = TRUE
  expect_warning(
    sub_irreg <- vol[, , c(1L, 2L, 5L)],
    "irregular|non-uniform|spacing",
    ignore.case = TRUE
  )
  expect_true(is_dicom_volume(sub_irreg))
  expect_true(isTRUE(sub_irreg$diagnostics$irregular_spacing))
  expect_equal(sub_irreg$frame_meta$slice_id, c(1L, 2L, 5L))

  # 4. Missing and logical indices
  sub_miss <- vol[, , 2:4]
  sub_log <- vol[, , c(FALSE, TRUE, TRUE, TRUE, FALSE, FALSE)]
  expect_equal(as.array(sub_miss), as.array(sub_log))
  expect_equal(sub_miss$affine, sub_log$affine, tolerance = 1e-12)

  # 5. 4D subsetting
  arr4 <- array(seq_len(6 * 8 * 4 * 3), dim = c(6L, 8L, 4L, 3L))
  vol4 <- new_dicom_volume(arr4, affine = vol$affine, modality = "MR")
  sub4_frame <- vol4[, , , 2]
  expect_true(is_dicom_volume(sub4_frame))
  expect_equal(dim(sub4_frame), c(6L, 8L, 4L))
  expect_identical(as.array(sub4_frame), arr4[, , , 2])

  sub4_keep <- vol4[, , , 2, drop = FALSE]
  expect_true(is_dicom_volume(sub4_keep))
  expect_equal(dim(sub4_keep), c(6L, 8L, 4L, 1L))

  sub4_multi <- vol4[2:5, , 2:4, 2:3]
  expect_true(is_dicom_volume(sub4_multi))
  expect_equal(dim(sub4_multi), c(4L, 8L, 3L, 2L))

  # 6. drop = TRUE reduces dimensions < 3 -> returns base matrix/vector
  dropped_slice <- vol[, , 2]
  expect_false(is_dicom_volume(dropped_slice))
  expect_true(is.matrix(dropped_slice))
  expect_equal(dim(dropped_slice), c(12L, 14L))

  kept_slice <- vol[, , 2, drop = FALSE]
  expect_true(is_dicom_volume(kept_slice))
  expect_equal(dim(kept_slice), c(12L, 14L, 1L))
  expect_equal(kept_slice$frame_meta$slice_id, 2L)
})

test_that("plot.dicom_volume() returns ggplot objects for 3D MPR/MIP and single-slice views", {
  fixture <- make_test_oblique_volume(dims = c(12L, 14L, 4L))
  vol <- fixture$vol

  p_mpr <- plot(vol, method = "mpr")
  expect_s3_class(p_mpr, "ggplot")

  p_mip <- plot(vol, method = "mip")
  expect_s3_class(p_mip, "ggplot")

  p_slice <- plot(vol, slice = 2L)
  expect_s3_class(p_slice, "ggplot")

  vol_1slice <- vol[, , 2L, drop = FALSE]
  p_single <- plot(vol_1slice)
  expect_s3_class(p_single, "ggplot")

  expect_error(plot(vol, slice = 99L), "slice")
})

test_that("Internal provenance helpers and subscript/transform validation guard edge cases", {
  fixture <- make_test_oblique_volume(dims = c(8L, 8L, 4L))
  vol <- fixture$vol

  entry <- dicomtk:::make_provenance_entry("custom_step", list(alpha = 0.5))
  expect_true(is.list(entry))
  expect_equal(entry$action, "custom_step")
  expect_equal(entry$params, list(alpha = 0.5))
  expect_true(nzchar(entry$timestamp))
  expect_true(nzchar(entry$package_version))

  vol2 <- dicomtk:::append_provenance(vol, "step_one", list(k = 1L))
  expect_true(is_dicom_volume(vol2))
  expect_equal(length(vol2$provenance), 1L)
  expect_equal(vol2$provenance[[1L]]$action, "step_one")

  prov_list <- dicomtk:::append_provenance(vol2$provenance, entry)
  expect_equal(length(prov_list), 2L)
  expect_equal(prov_list[[2L]]$action, "custom_step")

  expect_error(dicomtk:::make_provenance_entry(""), "action")
  expect_error(to_ras(list()), "dicom_volume")
  expect_error(to_lps(list()), "dicom_volume")
  expect_error(voxel_to_world(vol, c(1, 2)), "length 3")
  expect_error(voxel_to_world(vol, c(1, 2, 3), index_base = 2L), "index_base")
  expect_error(world_to_voxel(vol, matrix(1:4, nrow = 2L, ncol = 2L)), "3 columns")
  expect_error(vol[, , 99L], "out of bounds")
  expect_error(vol[, , c(-1L, 2L)], "positive and negative")
})
