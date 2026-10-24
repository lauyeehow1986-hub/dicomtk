# Helper: 3D right-handed cross product
cross3_test <- function(a, b) {
  c(
    a[2L] * b[3L] - a[3L] * b[2L],
    a[3L] * b[1L] - a[1L] * b[3L],
    a[1L] * b[2L] - a[2L] * b[1L]
  )
}

parse_ds_vec <- function(s) {
  as.numeric(strsplit(s, "\\\\", fixed = FALSE)[[1L]])
}

test_that("Classic 3D series synthesize across all classic modalities with asymmetric fiducials", {
  classic_mods <- c("CT", "MR", "PT", "DX", "MG", "US", "XA")

  for (mod in classic_mods) {
    out_dir <- tempfile(paste0("synth_", mod, "_"))
    on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

    nslices <- if (mod %in% c("DX", "MG")) 1L else 4L
    dims <- c(16L, 12L, nslices)
    sp <- c(0.8, 0.9, 2.5)
    orig <- c(-10.5, -12.0, 5.0)

    phantom <- dicom_synthesize(
      out_dir = out_dir,
      modality = mod,
      dims = dims,
      spacing = sp,
      origin = orig,
      orientation = "axial",
      phi = TRUE
    )

    expect_s3_class(phantom, "dicom_phantom")
    expect_output(print(phantom), mod)

    # Required S3 fields
    req_fields <- c(
      "files", "modality", "truth_affine_lps", "truth_voxels",
      "direction", "spacing", "slice_positions_lps", "planted_phi"
    )
    expect_true(all(req_fields %in% names(phantom)))
    expect_equal(phantom$modality, mod)
    expect_equal(length(phantom$files), nslices)
    expect_true(all(file.exists(phantom$files)))
    expect_true(all(is_dicom(phantom$files)))

    expect_true(is.matrix(phantom$truth_affine_lps))
    expect_equal(dim(phantom$truth_affine_lps), c(4L, 4L))
    expect_equal(dim(phantom$truth_voxels), dims)
    expect_equal(phantom$spacing, sp)
    expect_equal(dim(phantom$slice_positions_lps), c(nslices, 3L))
    expect_true(is.list(phantom$planted_phi) && length(phantom$planted_phi) >= 7L)

    # Asymmetric corner fiducial intensities must be distinct and match read-back
    rows <- dims[1L]
    cols <- dims[2L]
    c_111 <- phantom$truth_voxels[1L, 1L, 1L]
    c_r11 <- phantom$truth_voxels[rows, 1L, 1L]
    c_1c1 <- phantom$truth_voxels[1L, cols, 1L]

    if (nslices > 1L) {
      c_11s <- phantom$truth_voxels[1L, 1L, nslices]
      c_1cs <- phantom$truth_voxels[1L, cols, nslices]
      corners <- c(c_111, c_r11, c_1c1, c_11s, c_1cs)
      expect_equal(length(unique(corners)), 5L)
    } else {
      corners <- c(c_111, c_r11, c_1c1)
      expect_equal(length(unique(corners)), 3L)
    }

    # Read back first and last slice with rescale = TRUE and verify exact match
    px_first <- read_dicom_pixels(phantom$files[1L], rescale = TRUE)
    expect_equal(dim(px_first), c(rows, cols))
    expect_equal(as.numeric(px_first), as.numeric(phantom$truth_voxels[, , 1L]), tolerance = 1e-6)
    expect_equal(px_first[1L, 1L], c_111, tolerance = 1e-6)
    expect_equal(px_first[rows, 1L], c_r11, tolerance = 1e-6)
    expect_equal(px_first[1L, cols], c_1c1, tolerance = 1e-6)

    if (nslices > 1L) {
      px_last <- read_dicom_pixels(phantom$files[nslices], rescale = TRUE)
      expect_equal(as.numeric(px_last), as.numeric(phantom$truth_voxels[, , nslices]), tolerance = 1e-6)
      expect_equal(px_last[1L, 1L], phantom$truth_voxels[1L, 1L, nslices], tolerance = 1e-6)
    }
  }
})

test_that("Axial, coronal, sagittal, and oblique orientations produce exact right-handed LPS affines", {
  orientations <- c("axial", "coronal", "sagittal", "oblique")
  sp <- c(0.75, 0.85, 2.5)
  orig <- c(-20.0, 15.0, -30.0)
  dims <- c(12L, 14L, 5L)

  expected_basis <- list(
    axial = list(d_row = c(1, 0, 0), d_col = c(0, 1, 0), normal = c(0, 0, 1)),
    coronal = list(d_row = c(1, 0, 0), d_col = c(0, 0, -1), normal = c(0, 1, 0)),
    sagittal = list(d_row = c(0, 1, 0), d_col = c(0, 0, -1), normal = c(-1, 0, 0))
  )

  for (ori in orientations) {
    out_dir <- tempfile(paste0("synth_ori_", ori, "_"))
    on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

    phantom <- dicom_synthesize(
      out_dir = out_dir,
      modality = "CT",
      dims = dims,
      spacing = sp,
      origin = orig,
      orientation = ori,
      oblique_angles_deg = c(15, -10, 5),
      phi = FALSE
    )

    d_row <- phantom$direction$d_row
    d_col <- phantom$direction$d_col
    normal <- phantom$direction$normal

    # Orthonormality & right-handedness
    expect_equal(sqrt(sum(d_row^2)), 1.0, tolerance = 1e-12)
    expect_equal(sqrt(sum(d_col^2)), 1.0, tolerance = 1e-12)
    expect_equal(sum(d_row * d_col), 0.0, tolerance = 1e-12)
    expect_equal(normal, cross3_test(d_row, d_col), tolerance = 1e-12)
    expect_equal(det(cbind(d_row, d_col, normal)), 1.0, tolerance = 1e-12)

    if (ori %in% names(expected_basis)) {
      expect_equal(d_row, expected_basis[[ori]]$d_row, tolerance = 1e-12)
      expect_equal(d_col, expected_basis[[ori]]$d_col, tolerance = 1e-12)
      expect_equal(normal, expected_basis[[ori]]$normal, tolerance = 1e-12)
    } else {
      # Oblique must genuinely differ from axial
      expect_gt(max(abs(d_row - c(1, 0, 0))), 0.05)
      expect_gt(max(abs(normal - c(0, 0, 1))), 0.05)
    }

    # Reconstruct 4x4 LPS affine strictly from written DICOM tags and verify < 1e-6
    tags_first <- dicom_tag_value(
      phantom$files[1L],
      c("ImageOrientationPatient", "ImagePositionPatient", "PixelSpacing")
    )
    tags_last <- dicom_tag_value(phantom$files[dims[3L]], "ImagePositionPatient")

    iop_file <- parse_ds_vec(tags_first[["ImageOrientationPatient"]])
    ipp_first_file <- parse_ds_vec(tags_first[["ImagePositionPatient"]])
    ipp_last_file <- parse_ds_vec(tags_last[["ImagePositionPatient"]])
    ps_file <- parse_ds_vec(tags_first[["PixelSpacing"]])

    expect_equal(ps_file, sp[1:2], tolerance = 1e-8)
    expect_equal(iop_file[1:3], d_row, tolerance = 1e-7)
    expect_equal(iop_file[4:6], d_col, tolerance = 1e-7)
    expect_equal(ipp_first_file, orig, tolerance = 1e-7)

    reconstructed_affine <- diag(4L)
    reconstructed_affine[1:3, 1L] <- iop_file[4:6] * ps_file[1L]
    reconstructed_affine[1:3, 2L] <- iop_file[1:3] * ps_file[2L]
    reconstructed_affine[1:3, 3L] <- (ipp_last_file - ipp_first_file) / (dims[3L] - 1L)
    reconstructed_affine[1:3, 4L] <- ipp_first_file

    expect_lt(max(abs(reconstructed_affine - phantom$truth_affine_lps)), 1e-6)
  }

  # Also check single-slice (nslices == 1) column 3 == dz * normal
  out_single <- tempfile("synth_single_slice_")
  on.exit(unlink(out_single, recursive = TRUE), add = TRUE)
  p1 <- dicom_synthesize(
    out_dir = out_single,
    modality = "CT",
    dims = c(8L, 10L, 1L),
    spacing = c(0.5, 0.6, 3.0),
    origin = c(1.0, 2.0, 3.0),
    orientation = "coronal",
    phi = FALSE
  )
  expect_equal(p1$truth_affine_lps[1:3, 3L], 3.0 * p1$direction$normal, tolerance = 1e-12)
})

test_that("Enhanced multi-frame IODs (ENHCT, ENHMR, DBT) write single file with functional group SQs", {
  enh_specs <- list(
    ENHCT = "1.2.840.10008.5.1.4.1.1.2.1",
    ENHMR = "1.2.840.10008.5.1.4.1.1.4.1",
    DBT   = "1.2.840.10008.5.1.4.1.1.13.1.3"
  )

  for (mod in names(enh_specs)) {
    out_dir <- tempfile(paste0("synth_", mod, "_"))
    on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

    dims <- c(12L, 10L, 4L)
    sp <- c(0.6, 0.7, 1.5)
    phantom <- dicom_synthesize(
      out_dir = out_dir,
      modality = mod,
      dims = dims,
      spacing = sp,
      orientation = "oblique",
      oblique_angles_deg = c(10, -5, 8),
      phi = FALSE
    )

    expect_equal(length(phantom$files), 1L)
    dcm_path <- phantom$files[1L]
    expect_true(is_dicom(dcm_path))
    expect_equal(unname(dicom_tag_value(dcm_path, "NumberOfFrames")), "4")
    expect_equal(unname(dicom_tag_value(dcm_path, "SOPClassUID")), enh_specs[[mod]])

    hdr <- read_dicom(dcm_path, include_sequences = TRUE)
    expect_true("(5200,9229)" %in% hdr$tag)
    expect_true("(5200,9230)" %in% hdr$tag)

    # SharedFunctionalGroupsSequence: PlaneOrientationSequence & PixelMeasuresSequence
    iop_rows <- hdr[hdr$keyword == "ImageOrientationPatient" & grepl("5200,9229", hdr$sequence_path, fixed = TRUE), , drop = FALSE]
    expect_equal(nrow(iop_rows), 1L)
    expect_equal(
      parse_ds_vec(iop_rows$value[1L]),
      c(phantom$direction$d_row, phantom$direction$d_col),
      tolerance = 1e-7
    )

    ps_rows <- hdr[hdr$keyword == "PixelSpacing" & grepl("5200,9229", hdr$sequence_path, fixed = TRUE), , drop = FALSE]
    expect_equal(nrow(ps_rows), 1L)
    expect_equal(parse_ds_vec(ps_rows$value[1L]), sp[1:2], tolerance = 1e-8)

    # PerFrameFunctionalGroupsSequence: PlanePositionSequence & PixelValueTransformationSequence per frame
    ipp_rows <- hdr[hdr$keyword == "ImagePositionPatient" & grepl("5200,9230", hdr$sequence_path, fixed = TRUE), , drop = FALSE]
    expect_equal(nrow(ipp_rows), 4L)
    for (f in seq_len(4L)) {
      expect_equal(parse_ds_vec(ipp_rows$value[f]), phantom$slice_positions_lps[f, ], tolerance = 1e-6)
    }

    slope_rows <- hdr[hdr$keyword == "RescaleSlope" & grepl("5200,9230", hdr$sequence_path, fixed = TRUE), , drop = FALSE]
    inter_rows <- hdr[hdr$keyword == "RescaleIntercept" & grepl("5200,9230", hdr$sequence_path, fixed = TRUE), , drop = FALSE]
    expect_equal(nrow(slope_rows), 4L)
    expect_equal(nrow(inter_rows), 4L)

    # Verify per-frame rescaled pixels match truth_voxels
    raw_px <- read_dicom_pixels(dcm_path, frame = 0L, rescale = FALSE)
    expect_equal(dim(raw_px), dims)
    rescaled_px <- array(0.0, dim = dims)
    for (f in seq_len(4L)) {
      s_val <- as.numeric(slope_rows$value[f])
      i_val <- as.numeric(inter_rows$value[f])
      rescaled_px[, , f] <- raw_px[, , f] * s_val + i_val
    }
    expect_equal(as.numeric(rescaled_px), as.numeric(phantom$truth_voxels), tolerance = 1e-6)
  }
})

test_that("Cine multi-frame (XA_CINE, US_CINE) write single file with FrameTime and FrameIncrementPointer", {
  for (mod in c("XA_CINE", "US_CINE")) {
    out_dir <- tempfile(paste0("synth_", mod, "_"))
    on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

    dims <- c(16L, 14L, 6L)
    phantom <- dicom_synthesize(
      out_dir = out_dir,
      modality = mod,
      dims = dims,
      phi = TRUE
    )

    expect_equal(length(phantom$files), 1L)
    dcm_path <- phantom$files[1L]
    expect_true(is_dicom(dcm_path))

    tv <- dicom_tag_value(dcm_path, c("NumberOfFrames", "FrameTime", "FrameIncrementPointer"))
    expect_equal(tv[["NumberOfFrames"]], "6")
    expect_false(is.na(tv[["FrameTime"]]))
    expect_gt(as.numeric(tv[["FrameTime"]]), 0)
    expect_equal(tv[["FrameIncrementPointer"]], "(0018,1063)")

    px <- read_dicom_pixels(dcm_path, frame = 0L, rescale = TRUE)
    expect_equal(dim(px), dims)
    expect_equal(as.numeric(px), as.numeric(phantom$truth_voxels), tolerance = 1e-6)
  }
})

test_that("Modality-specific tags for PT, MG/DX, and US/US_CINE are configurable and accurate", {
  # 1. PET (PT) quantitative SUV tags & RadiopharmaceuticalInformationSequence
  pt_dir <- tempfile("synth_pt_suv_")
  on.exit(unlink(pt_dir, recursive = TRUE), add = TRUE)
  pt_phantom <- dicom_synthesize(
    out_dir = pt_dir,
    modality = "PT",
    dims = c(12L, 12L, 3L),
    pet_params = list(
      patient_weight = 75,
      patient_size = 1.80,
      patient_sex = "F",
      series_time = "103000.000000",
      acquisition_time = "103000.000000",
      total_dose = 400e6,
      half_life = 6586.2,
      start_time = "090000.000000",
      activity_bqml = 12500
    ),
    phi = FALSE
  )

  f_pt <- pt_phantom$files[1L]
  pt_tv <- dicom_tag_value(
    f_pt,
    c("PatientWeight", "PatientSize", "PatientSex", "SeriesTime",
      "AcquisitionTime", "Units", "CorrectedImage", "DecayCorrection")
  )
  expect_equal(as.numeric(pt_tv[["PatientWeight"]]), 75)
  expect_equal(as.numeric(pt_tv[["PatientSize"]]), 1.80)
  expect_equal(pt_tv[["PatientSex"]], "F")
  expect_equal(pt_tv[["SeriesTime"]], "103000.000000")
  expect_equal(pt_tv[["AcquisitionTime"]], "103000.000000")
  expect_equal(pt_tv[["Units"]], "BQML")
  expect_equal(pt_tv[["CorrectedImage"]], "DECY\\ATTN")
  expect_equal(pt_tv[["DecayCorrection"]], "START")

  pt_hdr <- read_dicom(f_pt, include_sequences = TRUE)
  expect_true("(0054,0016)" %in% pt_hdr$tag)
  expect_equal(
    as.numeric(pt_hdr$value[pt_hdr$keyword == "RadionuclideTotalDose"]),
    400e6
  )
  expect_equal(
    as.numeric(pt_hdr$value[pt_hdr$keyword == "RadionuclideHalfLife"]),
    6586.2
  )
  expect_equal(
    pt_hdr$value[pt_hdr$keyword == "RadiopharmaceuticalStartTime"],
    "090000.000000"
  )
  expect_true(any(pt_phantom$truth_voxels == 12500))

  # 2. MG and DX VOI LUT & PresentationIntentType tags
  mg_dir <- tempfile("synth_mg_voi_")
  on.exit(unlink(mg_dir, recursive = TRUE), add = TRUE)
  mg_phantom <- dicom_synthesize(
    out_dir = mg_dir,
    modality = "MG",
    dims = c(16L, 16L, 1L),
    voi_params = list(
      presentation_intent = "FOR PROCESSING",
      photometric = "MONOCHROME1",
      voi_lut_function = "SIGMOID",
      window_center = 2048,
      window_width = 4096
    ),
    phi = FALSE
  )
  mg_tv <- dicom_tag_value(
    mg_phantom$files[1L],
    c("PresentationIntentType", "PhotometricInterpretation", "VOILUTFunction",
      "WindowCenter", "WindowWidth")
  )
  expect_equal(mg_tv[["PresentationIntentType"]], "FOR PROCESSING")
  expect_equal(mg_tv[["PhotometricInterpretation"]], "MONOCHROME1")
  expect_equal(mg_tv[["VOILUTFunction"]], "SIGMOID")
  expect_equal(as.numeric(mg_tv[["WindowCenter"]]), 2048)
  expect_equal(as.numeric(mg_tv[["WindowWidth"]]), 4096)

  dx_dir <- tempfile("synth_dx_voi_")
  on.exit(unlink(dx_dir, recursive = TRUE), add = TRUE)
  dx_phantom <- dicom_synthesize(
    out_dir = dx_dir,
    modality = "DX",
    dims = c(16L, 16L, 1L),
    voi_params = list(
      presentation_intent = "FOR PRESENTATION",
      photometric = "MONOCHROME2",
      voi_lut_function = "LINEAR",
      window_center = 1000,
      window_width = 2000
    ),
    phi = FALSE
  )
  dx_tv <- dicom_tag_value(
    dx_phantom$files[1L],
    c("PresentationIntentType", "PhotometricInterpretation", "VOILUTFunction",
      "WindowCenter", "WindowWidth")
  )
  expect_equal(dx_tv[["PresentationIntentType"]], "FOR PRESENTATION")
  expect_equal(dx_tv[["PhotometricInterpretation"]], "MONOCHROME2")
  expect_equal(dx_tv[["VOILUTFunction"]], "LINEAR")
  expect_equal(as.numeric(dx_tv[["WindowCenter"]]), 1000)
  expect_equal(as.numeric(dx_tv[["WindowWidth"]]), 2000)

  # 3. US & US_CINE BurnedInAnnotation and bright top row strip
  for (us_mod in c("US", "US_CINE")) {
    us_phi_dir <- tempfile(paste0("synth_", us_mod, "_phi_"))
    us_clean_dir <- tempfile(paste0("synth_", us_mod, "_clean_"))
    on.exit(unlink(c(us_phi_dir, us_clean_dir), recursive = TRUE), add = TRUE)

    p_yes <- dicom_synthesize(out_dir = us_phi_dir, modality = us_mod, dims = c(16L, 16L, 2L), phi = TRUE)
    p_no  <- dicom_synthesize(out_dir = us_clean_dir, modality = us_mod, dims = c(16L, 16L, 2L), phi = FALSE)

    expect_equal(unname(dicom_tag_value(p_yes$files[1L], "BurnedInAnnotation")), "YES")
    expect_equal(unname(dicom_tag_value(p_no$files[1L], "BurnedInAnnotation")), "NO")

    # Interior of row 1 (columns 2..15) is burned bright when phi = TRUE vs background when phi = FALSE
    expect_gt(mean(p_yes$truth_voxels[1L, 2:15, 1L]), mean(p_yes$truth_voxels[2L, 2:15, 1L]) * 5)
    expect_equal(p_no$truth_voxels[1L, 2:15, 1L], p_no$truth_voxels[2L, 2:15, 1L])
  }
})

test_that("Edge-case flags (reverse_order, irregular_z, gantry_tilt_deg, mixed_series, phi) behave accurately", {
  # 1. reverse_order = TRUE vs FALSE
  dir_fwd <- tempfile("synth_fwd_")
  dir_rev <- tempfile("synth_rev_")
  on.exit(unlink(c(dir_fwd, dir_rev), recursive = TRUE), add = TRUE)

  p_fwd <- dicom_synthesize(
    out_dir = dir_fwd, modality = "CT", dims = c(12L, 10L, 5L),
    spacing = c(0.8, 0.8, 2.0), origin = c(-5, -5, 0),
    reverse_order = FALSE, phi = FALSE
  )
  p_rev <- dicom_synthesize(
    out_dir = dir_rev, modality = "CT", dims = c(12L, 10L, 5L),
    spacing = c(0.8, 0.8, 2.0), origin = c(-5, -5, 0),
    reverse_order = TRUE, phi = FALSE
  )

  # Ground-truth affine and voxels remain in canonical ascending IPP . normal order!
  expect_equal(p_rev$truth_affine_lps, p_fwd$truth_affine_lps, tolerance = 1e-12)
  expect_equal(p_rev$truth_voxels, p_fwd$truth_voxels, tolerance = 1e-12)
  expect_equal(p_rev$slice_positions_lps, p_fwd$slice_positions_lps, tolerance = 1e-12)

  # On disk, file 1 of reversed series has the last canonical IPP and last slice pixels (while InstanceNumber == "1")
  expect_equal(unname(dicom_tag_value(p_rev$files[1L], "InstanceNumber")), "1")
  ipp_rev_1 <- parse_ds_vec(dicom_tag_value(p_rev$files[1L], "ImagePositionPatient"))
  ipp_rev_5 <- parse_ds_vec(dicom_tag_value(p_rev$files[5L], "ImagePositionPatient"))
  expect_equal(ipp_rev_1, p_fwd$slice_positions_lps[5L, ], tolerance = 1e-7)
  expect_equal(ipp_rev_5, p_fwd$slice_positions_lps[1L, ], tolerance = 1e-7)
  expect_equal(
    as.numeric(read_dicom_pixels(p_rev$files[1L], rescale = TRUE)),
    as.numeric(p_rev$truth_voxels[, , 5L]),
    tolerance = 1e-6
  )

  # 2. irregular_z = TRUE (2 * dz jump after floor(slices / 2))
  dir_irreg <- tempfile("synth_irreg_")
  on.exit(unlink(dir_irreg, recursive = TRUE), add = TRUE)
  p_irreg <- dicom_synthesize(
    out_dir = dir_irreg, modality = "CT", dims = c(10L, 10L, 6L),
    spacing = c(1.0, 1.0, 2.5), origin = c(0, 0, 0),
    irregular_z = TRUE, phi = FALSE
  )
  z_pos <- p_irreg$slice_positions_lps[, 3L]
  dz_steps <- diff(z_pos)
  expect_equal(dz_steps, c(2.5, 2.5, 5.0, 2.5, 2.5), tolerance = 1e-8)
  for (i in seq_len(6L)) {
    ipp_i <- parse_ds_vec(dicom_tag_value(p_irreg$files[i], "ImagePositionPatient"))
    expect_equal(ipp_i, p_irreg$slice_positions_lps[i, ], tolerance = 1e-7)
  }

  # 3. gantry_tilt_deg = 15
  dir_tilt <- tempfile("synth_tilt_")
  on.exit(unlink(dir_tilt, recursive = TRUE), add = TRUE)
  p_tilt <- dicom_synthesize(
    out_dir = dir_tilt, modality = "CT", dims = c(10L, 10L, 4L),
    spacing = c(1.0, 1.0, 3.0), origin = c(-10, -10, 0),
    orientation = "axial", gantry_tilt_deg = 15, phi = FALSE
  )
  theta <- 15 * pi / 180
  expected_s_vec <- 3.0 * (cos(theta) * p_tilt$direction$normal + sin(theta) * p_tilt$direction$d_col)
  expect_equal(p_tilt$truth_affine_lps[1:3, 3L], expected_s_vec, tolerance = 1e-7)
  expect_equal(as.numeric(dicom_tag_value(p_tilt$files[1L], "GantryDetectorTilt")), 15)
  ipp_tilt_2 <- parse_ds_vec(dicom_tag_value(p_tilt$files[2L], "ImagePositionPatient"))
  expect_equal(ipp_tilt_2, c(-10, -10, 0) + expected_s_vec, tolerance = 1e-6)

  # 4. mixed_series = TRUE
  dir_mixed <- tempfile("synth_mixed_")
  on.exit(unlink(dir_mixed, recursive = TRUE), add = TRUE)
  p_mixed <- dicom_synthesize(
    out_dir = dir_mixed, modality = "CT", dims = c(12L, 12L, 3L),
    mixed_series = TRUE, phi = FALSE
  )
  expect_equal(length(p_mixed$files), 3L)
  expect_equal(length(p_mixed$extra_files), 1L)
  expect_true(file.exists(p_mixed$extra_files[1L]))
  expect_true(is_dicom(p_mixed$extra_files[1L]))
  all_dcms <- list.files(dir_mixed, full.names = TRUE)
  expect_equal(length(all_dcms), 4L)
  # Localizer shares SeriesInstanceUID with primary series but differs in IOP and Rows/Cols
  expect_equal(
    unname(dicom_tag_value(p_mixed$extra_files[1L], "SeriesInstanceUID")),
    unname(dicom_tag_value(p_mixed$files[1L], "SeriesInstanceUID"))
  )
  expect_false(identical(
    unname(dicom_tag_value(p_mixed$extra_files[1L], "ImageOrientationPatient")),
    unname(dicom_tag_value(p_mixed$files[1L], "ImageOrientationPatient"))
  ))

  # 5. phi = TRUE vs phi = FALSE
  dir_phi <- tempfile("synth_phi_true_")
  dir_anon <- tempfile("synth_phi_false_")
  on.exit(unlink(c(dir_phi, dir_anon), recursive = TRUE), add = TRUE)

  p_phi <- dicom_synthesize(out_dir = dir_phi, modality = "MR", dims = c(8L, 8L, 2L), phi = TRUE)
  p_anon <- dicom_synthesize(out_dir = dir_anon, modality = "MR", dims = c(8L, 8L, 2L), phi = FALSE)

  phi_tags <- c(
    "PatientName", "PatientID", "PatientBirthDate", "InstitutionName",
    "ReferringPhysicianName", "AccessionNumber", "DeviceSerialNumber"
  )
  expect_true(all(phi_tags %in% names(p_phi$planted_phi)))
  tv_phi <- dicom_tag_value(p_phi$files[1L], phi_tags)
  for (tg in phi_tags) {
    expect_equal(tv_phi[[tg]], p_phi$planted_phi[[tg]])
    expect_true(nzchar(tv_phi[[tg]]))
  }

  expect_equal(p_anon$planted_phi, list())
  tv_anon <- dicom_tag_value(p_anon$files[1L], c(phi_tags, "PatientIdentityRemoved"))
  expect_equal(tv_anon[["PatientName"]], "ANONYMOUS")
  expect_equal(tv_anon[["PatientID"]], "ANON001")
  expect_equal(tv_anon[["PatientIdentityRemoved"]], "YES")
  for (tg in setdiff(phi_tags, c("PatientName", "PatientID"))) {
    expect_true(is.na(tv_anon[[tg]]) || !nzchar(tv_anon[[tg]]))
  }
})

test_that("Input validation, extra_tags private tags, ENHCT reverse_order, and RNG state preservation work", {
  expect_error(dicom_synthesize(modality = "NOT_A_MODALITY"))
  expect_error(dicom_synthesize(dims = c(0L, 8L, 2L)), "dims")
  expect_error(dicom_synthesize(spacing = c(1.0, -0.5, 2.0)), "spacing")
  expect_error(dicom_synthesize(gantry_tilt_deg = 90), "gantry_tilt_deg")
  expect_error(dicom_synthesize(orientation = "oblique", oblique_angles_deg = c(10, 20)), "oblique_angles_deg")

  # Caller .Random.seed is preserved across dicom_synthesize(seed = ...)
  set.seed(2026L)
  seed_before <- .Random.seed
  tmp_dir <- tempfile("synth_seed_check_")
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
  p_mr <- dicom_synthesize(
    out_dir = tmp_dir,
    modality = "MR",
    dims = c(8L, 8L, 2L),
    extra_tags = list("(2005,100D)" = "0", "(2005,100E)" = "2.5"),
    phi = FALSE,
    seed = 99L
  )
  expect_identical(.Random.seed, seed_before)

  # Philips private scaling tags survive round-trip for Task 5
  priv_tv <- dicom_tag_value(p_mr$files[1L], c("(2005,100D)", "(2005,100E)"))
  expect_equal(priv_tv[["(2005,100D)"]], "0")
  expect_equal(priv_tv[["(2005,100E)"]], "2.5")

  # Enhanced multi-frame reverse_order writes reversed per-frame IPPs while keeping canonical truth
  enh_rev_dir <- tempfile("synth_enh_rev_")
  on.exit(unlink(enh_rev_dir, recursive = TRUE), add = TRUE)
  p_enh_rev <- dicom_synthesize(
    out_dir = enh_rev_dir,
    modality = "ENHCT",
    dims = c(8L, 8L, 3L),
    spacing = c(1.0, 1.0, 2.0),
    origin = c(0, 0, 0),
    reverse_order = TRUE,
    phi = FALSE
  )
  hdr_enh <- read_dicom(p_enh_rev$files[1L], include_sequences = TRUE)
  ipp_enh <- hdr_enh$value[hdr_enh$keyword == "ImagePositionPatient"]
  expect_equal(parse_ds_vec(ipp_enh[1L]), c(0, 0, 4), tolerance = 1e-7)
  expect_equal(parse_ds_vec(ipp_enh[3L]), c(0, 0, 0), tolerance = 1e-7)
  expect_equal(p_enh_rev$truth_affine_lps[1:3, 4L], c(0, 0, 0), tolerance = 1e-12)
})

