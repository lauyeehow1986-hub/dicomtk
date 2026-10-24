test_that("read_dicom_volume() reconstructs reversed and shuffled classic series across all orientations and modalities", {
  orientations <- c("axial", "coronal", "sagittal", "oblique")
  dims <- c(14L, 12L, 5L)
  sp <- c(0.8, 0.9, 2.5)
  orig <- c(-18.5, 12.0, -25.0)

  for (ori in orientations) {
    out_dir <- tempfile(paste0("read_vol_ori_", ori, "_"))
    on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

    phantom <- dicom_synthesize(
      out_dir = out_dir,
      modality = "CT",
      dims = dims,
      spacing = sp,
      origin = orig,
      orientation = ori,
      oblique_angles_deg = c(18, -12, 7),
      reverse_order = TRUE,
      phi = FALSE
    )

    vol <- read_dicom_volume(phantom$files)
    expect_true(is_dicom_volume(vol))
    expect_equal(vol$coord_system, "LPS")
    expect_equal(dim(vol), dims)
    expect_equal(vol$modality, "CT")
    expect_equal(vol$units, "HU")

    expect_lt(max(abs(vol$affine - phantom$truth_affine_lps)), 1e-5)
    expect_lt(max(abs(as.array(vol) - phantom$truth_voxels)), 1e-5)

    # Verify all 5 asymmetric corner fiducial intensities explicitly
    rows <- dims[1L]
    cols <- dims[2L]
    ns <- dims[3L]
    expect_equal(vol$voxels[1L, 1L, 1L], phantom$truth_voxels[1L, 1L, 1L], tolerance = 1e-5)
    expect_equal(vol$voxels[rows, 1L, 1L], phantom$truth_voxels[rows, 1L, 1L], tolerance = 1e-5)
    expect_equal(vol$voxels[1L, cols, 1L], phantom$truth_voxels[1L, cols, 1L], tolerance = 1e-5)
    expect_equal(vol$voxels[1L, 1L, ns], phantom$truth_voxels[1L, 1L, ns], tolerance = 1e-5)
    expect_equal(vol$voxels[1L, cols, ns], phantom$truth_voxels[1L, cols, ns], tolerance = 1e-5)
  }

  # Permuted input order + contradictory InstanceNumber must still sort strictly by IPP . normal
  perm_dir <- tempfile("read_vol_perm_")
  on.exit(unlink(perm_dir, recursive = TRUE), add = TRUE)
  p_perm <- dicom_synthesize(
    out_dir = perm_dir,
    modality = "CT",
    dims = c(10L, 12L, 5L),
    spacing = c(0.7, 0.8, 2.0),
    orientation = "oblique",
    reverse_order = FALSE,
    phi = FALSE
  )
  contradict_inst <- c("50", "10", "40", "20", "30")
  for (i in seq_along(p_perm$files)) {
    dicom_modify(p_perm$files[i], tags = list(InstanceNumber = contradict_inst[i]), out_path = p_perm$files[i])
  }
  shuffled_files <- p_perm$files[c(3L, 1L, 5L, 2L, 4L)]
  vol_perm <- read_dicom_volume(shuffled_files)
  expect_lt(max(abs(vol_perm$affine - p_perm$truth_affine_lps)), 1e-5)
  expect_lt(max(abs(as.array(vol_perm) - p_perm$truth_voxels)), 1e-5)

  # Classic modalities: CT, MR, PT, DX, MG, US
  classic_mods <- c("CT", "MR", "PT", "DX", "MG", "US")
  for (mod in classic_mods) {
    mod_dir <- tempfile(paste0("read_vol_mod_", mod, "_"))
    on.exit(unlink(mod_dir, recursive = TRUE), add = TRUE)
    ns <- if (mod %in% c("DX", "MG")) 1L else 4L
    pm <- dicom_synthesize(
      out_dir = mod_dir,
      modality = mod,
      dims = c(12L, 10L, ns),
      spacing = c(0.8, 0.8, 2.5),
      origin = c(-10, -8, 4),
      reverse_order = (ns > 1L),
      phi = FALSE
    )
    vm <- read_dicom_volume(pm$out_dir)
    expect_true(is_dicom_volume(vm))
    expect_equal(dim(vm), c(12L, 10L, ns))
    expect_lt(max(abs(vm$affine - pm$truth_affine_lps)), 1e-5)
    expect_lt(max(abs(as.array(vm) - pm$truth_voxels)), 1e-5)
  }
})

test_that("read_dicom_volume() handles Enhanced Multi-Frame IODs (ENHCT, ENHMR, DBT) and per-frame RescaleSlope", {
  for (mod in c("ENHCT", "ENHMR", "DBT")) {
    for (rev_flag in c(FALSE, TRUE)) {
      enh_dir <- tempfile(paste0("read_enh_", mod, "_", rev_flag, "_"))
      on.exit(unlink(enh_dir, recursive = TRUE), add = TRUE)

      dims <- c(12L, 10L, 4L)
      phantom <- dicom_synthesize(
        out_dir = enh_dir,
        modality = mod,
        dims = dims,
        spacing = c(0.6, 0.7, 1.8),
        origin = c(-15.0, 10.0, 5.0),
        orientation = "oblique",
        oblique_angles_deg = c(12, -8, 6),
        reverse_order = rev_flag,
        phi = FALSE
      )

      vol <- read_dicom_volume(phantom$files)
      expect_true(is_dicom_volume(vol))
      expect_equal(dim(vol), dims)
      expect_lt(max(abs(vol$affine - phantom$truth_affine_lps)), 1e-5)
      expect_lt(max(abs(as.array(vol) - phantom$truth_voxels)), 1e-5)
      expect_equal(nrow(vol$frame_meta), 4L)
    }
  }

  # Per-frame varying RescaleSlope & RescaleIntercept in PerFrameFunctionalGroupsSequence + reversed IPPs
  var_dcm <- tempfile(fileext = ".dcm")
  on.exit(unlink(var_dcm), add = TRUE)

  raw_px <- array(0.0, dim = c(4L, 5L, 3L))
  raw_px[, , 1L] <- 100.0 # disk frame 1: z = 6.0 (canonical slice 3), slope = 0.5, intercept = 10 -> 60
  raw_px[, , 2L] <- 200.0 # disk frame 2: z = 3.0 (canonical slice 2), slope = 2.0, intercept = -50 -> 350
  raw_px[, , 3L] <- 300.0 # disk frame 3: z = 0.0 (canonical slice 1), slope = 1.5, intercept = -1000 -> -550

  shared_fg <- list(
    list(
      PlaneOrientationSequence = list(list(ImageOrientationPatient = "1\\0\\0\\0\\1\\0")),
      PixelMeasuresSequence = list(list(PixelSpacing = "0.5\\0.8", SliceThickness = "3.0"))
    )
  )
  per_frame_fg <- list(
    list(
      PlanePositionSequence = list(list(ImagePositionPatient = "-10\\-20\\6")),
      PixelValueTransformationSequence = list(list(RescaleIntercept = "10", RescaleSlope = "0.5", RescaleType = "HU"))
    ),
    list(
      PlanePositionSequence = list(list(ImagePositionPatient = "-10\\-20\\3")),
      PixelValueTransformationSequence = list(list(RescaleIntercept = "-50", RescaleSlope = "2", RescaleType = "HU"))
    ),
    list(
      PlanePositionSequence = list(list(ImagePositionPatient = "-10\\-20\\0")),
      PixelValueTransformationSequence = list(list(RescaleIntercept = "-1000", RescaleSlope = "1.5", RescaleType = "HU"))
    )
  )

  ok <- dicomtk:::cpp_write_dicom_multiframe(
    pixels = as.double(raw_px),
    dims = c(4L, 5L, 3L),
    out_path = var_dcm,
    meta_tags = c("Modality", "SOPClassUID", "SeriesInstanceUID", "StudyInstanceUID"),
    meta_values = c("CT", "1.2.840.10008.5.1.4.1.1.2.1", "2.25.1001", "2.25.1000"),
    shared_fg = shared_fg,
    per_frame_fg = per_frame_fg
  )
  expect_true(ok)

  vol_var <- read_dicom_volume(var_dcm)
  expect_equal(dim(vol_var), c(4L, 5L, 3L))
  expect_equal(vol_var$units, "HU")
  expect_equal(vol_var$affine[1:3, 4L], c(-10, -20, 0), tolerance = 1e-6)
  expect_equal(vol_var$affine[1:3, 1L], c(0, 0.5, 0), tolerance = 1e-6)
  expect_equal(vol_var$affine[1:3, 2L], c(0.8, 0, 0), tolerance = 1e-6)
  expect_equal(vol_var$affine[1:3, 3L], c(0, 0, 3), tolerance = 1e-6)
  expect_true(all(vol_var$voxels[, , 1L] == -550.0))
  expect_true(all(vol_var$voxels[, , 2L] == 350.0))
  expect_true(all(vol_var$voxels[, , 3L] == 60.0))

  # rescale = FALSE preserves raw stored values in sorted spatial order
  vol_raw <- read_dicom_volume(var_dcm, rescale = FALSE)
  expect_true(is.na(vol_raw$units))
  expect_true(all(vol_raw$voxels[, , 1L] == 300.0))
  expect_true(all(vol_raw$voxels[, , 2L] == 200.0))
  expect_true(all(vol_raw$voxels[, , 3L] == 100.0))
})

test_that("read_dicom_volume() preserves all frames of Cine Multi-Frame (XA_CINE, US_CINE) as 4D volumes", {
  for (mod in c("XA_CINE", "US_CINE")) {
    cine_dir <- tempfile(paste0("read_cine_", mod, "_"))
    on.exit(unlink(cine_dir, recursive = TRUE), add = TRUE)

    dims <- c(14L, 12L, 6L)
    phantom <- dicom_synthesize(
      out_dir = cine_dir,
      modality = mod,
      dims = dims,
      spacing = c(0.4, 0.5, 1.5),
      origin = c(-8.0, -6.0, 2.0),
      phi = FALSE
    )

    vol <- read_dicom_volume(phantom$files)
    expect_true(is_dicom_volume(vol))
    expect_equal(dim(vol), c(14L, 12L, 1L, 6L))
    expect_lt(max(abs(as.numeric(as.array(vol)) - as.numeric(phantom$truth_voxels))), 1e-5)
    expect_lt(max(abs(vol$affine - phantom$truth_affine_lps)), 1e-5)
    expect_gt(abs(det(vol$affine[1:3, 1:3])), 1e-6)
    expect_equal(nrow(vol$frame_meta), 6L)
    expect_true("FrameTime" %in% names(vol$frame_meta))
    expect_equal(as.numeric(vol$frame_meta$FrameTime[1L]), 33.3333, tolerance = 1e-3)
  }
})

test_that("Multi-echo MR splits cleanly in dicom_split_series() while repeated temporal IPPs form 4D dynamic volumes", {
  # 1. Multi-echo MR (EchoNumbers 1 and 2 sharing SeriesInstanceUID) -> splits into 2 sub-series
  me_dir <- tempfile("read_multiecho_")
  dir.create(me_dir)
  on.exit(unlink(me_dir, recursive = TRUE), add = TRUE)

  e1_dir <- tempfile("me_e1_")
  on.exit(unlink(e1_dir, recursive = TRUE), add = TRUE)
  p_e1 <- dicom_synthesize(
    out_dir = e1_dir,
    modality = "MR",
    dims = c(10L, 10L, 4L),
    spacing = c(1.0, 1.0, 3.0),
    origin = c(-5, -5, 0),
    phi = FALSE
  )

  for (i in seq_len(4L)) {
    f1 <- file.path(me_dir, sprintf("echo1_slice_%02d.dcm", i))
    file.copy(p_e1$files[i], f1)

    f2 <- file.path(me_dir, sprintf("echo2_slice_%02d.dcm", i))
    px_e2 <- read_dicom_pixels(p_e1$files[i], rescale = FALSE) * 2.0
    hdr_i <- dicom_tag_value(
      p_e1$files[i],
      c("StudyInstanceUID", "SeriesInstanceUID", "FrameOfReferenceUID",
        "ImagePositionPatient", "ImageOrientationPatient", "PixelSpacing", "SliceThickness")
    )
    dicomtk:::cpp_write_dicom_multiframe(
      pixels = as.double(px_e2),
      dims = c(10L, 10L, 1L),
      out_path = f2,
      meta_tags = c(
        "Modality", "SOPClassUID", "SOPInstanceUID", "StudyInstanceUID",
        "SeriesInstanceUID", "FrameOfReferenceUID", "InstanceNumber",
        "EchoNumbers", "EchoTime", "ImagePositionPatient",
        "ImageOrientationPatient", "PixelSpacing", "SliceThickness"
      ),
      meta_values = c(
        "MR", "1.2.840.10008.5.1.4.1.1.4", paste0("2.25.8800", i),
        hdr_i[["StudyInstanceUID"]], hdr_i[["SeriesInstanceUID"]],
        hdr_i[["FrameOfReferenceUID"]], as.character(4L + i),
        "2", "80", hdr_i[["ImagePositionPatient"]],
        hdr_i[["ImageOrientationPatient"]], hdr_i[["PixelSpacing"]], hdr_i[["SliceThickness"]]
      )
    )
  }

  sp_me <- dicom_split_series(me_dir)
  expect_s3_class(sp_me, "tbl_df")
  expect_equal(nrow(sp_me), 2L)
  expect_equal(sp_me$n_files, c(4L, 4L))

  me_vols <- read_dicom_volume(me_dir, split = TRUE)
  expect_type(me_vols, "list")
  expect_equal(length(me_vols), 2L)
  expect_equal(dim(me_vols[[1L]]), c(10L, 10L, 4L))
  expect_equal(dim(me_vols[[2L]]), c(10L, 10L, 4L))
  expect_lt(max(abs(me_vols[[1L]]$affine - p_e1$truth_affine_lps)), 1e-5)
  expect_lt(max(abs(me_vols[[2L]]$affine - p_e1$truth_affine_lps)), 1e-5)
  expect_lt(max(abs(as.array(me_vols[[1L]]) - p_e1$truth_voxels)), 1e-5)
  expect_lt(max(abs(as.array(me_vols[[2L]]) - 2.0 * p_e1$truth_voxels)), 1e-5)

  # 2. 4D dynamic stack (same EchoNumbers & SeriesInstanceUID, 2 TemporalPositionIdentifiers across 4 slices)
  dyn_dir <- tempfile("read_dyn4d_")
  dir.create(dyn_dir)
  on.exit(unlink(dyn_dir, recursive = TRUE), add = TRUE)

  for (i in seq_len(4L)) {
    hdr_i <- dicom_tag_value(
      p_e1$files[i],
      c("StudyInstanceUID", "SeriesInstanceUID", "FrameOfReferenceUID",
        "ImagePositionPatient", "ImageOrientationPatient", "PixelSpacing", "SliceThickness")
    )
    px_base <- read_dicom_pixels(p_e1$files[i], rescale = FALSE)

    for (tp in c(2L, 1L)) {
      # Write timepoint 2 with lower filename prefix to verify temporal sorting works regardless of filename
      f_tp <- file.path(dyn_dir, sprintf("img_tp%d_s%02d.dcm", if (tp == 2L) 1L else 2L, 5L - i))
      dicomtk:::cpp_write_dicom_multiframe(
        pixels = as.double(px_base + (tp - 1L) * 500.0),
        dims = c(10L, 10L, 1L),
        out_path = f_tp,
        meta_tags = c(
          "Modality", "SOPClassUID", "SOPInstanceUID", "StudyInstanceUID",
          "SeriesInstanceUID", "FrameOfReferenceUID", "InstanceNumber",
          "EchoNumbers", "TemporalPositionIdentifier", "TriggerTime",
          "ImagePositionPatient", "ImageOrientationPatient", "PixelSpacing", "SliceThickness"
        ),
        meta_values = c(
          "MR", "1.2.840.10008.5.1.4.1.1.4", sprintf("2.25.990%d%d", tp, i),
          hdr_i[["StudyInstanceUID"]], hdr_i[["SeriesInstanceUID"]],
          hdr_i[["FrameOfReferenceUID"]], as.character((tp - 1L) * 4L + i),
          "1", as.character(tp), as.character((tp - 1L) * 1500),
          hdr_i[["ImagePositionPatient"]], hdr_i[["ImageOrientationPatient"]],
          hdr_i[["PixelSpacing"]], hdr_i[["SliceThickness"]]
        )
      )
    }
  }

  sp_dyn <- dicom_split_series(dyn_dir)
  expect_equal(nrow(sp_dyn), 1L)
  expect_equal(sp_dyn$n_files, 8L)

  expect_no_warning(vol_dyn <- read_dicom_volume(dyn_dir))
  expect_true(is_dicom_volume(vol_dyn))
  expect_equal(dim(vol_dyn), c(10L, 10L, 4L, 2L))
  expect_false(isTRUE(vol_dyn$diagnostics$duplicate_positions))
  expect_lt(max(abs(vol_dyn$affine - p_e1$truth_affine_lps)), 1e-5)
  expect_lt(max(abs(vol_dyn$voxels[, , , 1L] - p_e1$truth_voxels)), 1e-5)
  expect_lt(max(abs(vol_dyn$voxels[, , , 2L] - (p_e1$truth_voxels + 500.0))), 1e-5)
  expect_equal(nrow(vol_dyn$frame_meta), 8L)
})

test_that("dicom_split_series() and read_dicom_volume() handle mixed_series = TRUE and subseries selection", {
  mix_dir <- tempfile("read_mixed_")
  on.exit(unlink(mix_dir, recursive = TRUE), add = TRUE)

  phantom <- dicom_synthesize(
    out_dir = mix_dir,
    modality = "CT",
    dims = c(16L, 14L, 5L),
    spacing = c(0.8, 0.8, 2.5),
    mixed_series = TRUE,
    phi = FALSE
  )

  sp <- dicom_split_series(mix_dir)
  expect_s3_class(sp, "tbl_df")
  req_cols <- c(
    "series_uid", "subseries_id", "modality", "rows", "cols",
    "n_files", "n_frames", "orientation_key", "files"
  )
  expect_true(all(req_cols %in% names(sp)))
  expect_equal(nrow(sp), 2L)
  expect_equal(sp$subseries_id, c(1L, 2L))
  # Main 3D stack first, localizer scout second
  expect_equal(sp$n_files, c(5L, 1L))
  expect_equal(sp$rows, c(16L, 24L))
  expect_equal(sp$cols, c(14L, 22L))

  # Default read_dicom_volume(dir) warns about multiple sub-series and returns main 3D stack
  expect_warning(
    vol_main <- read_dicom_volume(mix_dir),
    "sub-series|multiple",
    ignore.case = TRUE
  )
  expect_equal(dim(vol_main), c(16L, 14L, 5L))
  expect_lt(max(abs(vol_main$affine - phantom$truth_affine_lps)), 1e-5)
  expect_lt(max(abs(as.array(vol_main) - phantom$truth_voxels)), 1e-5)

  # Explicit subseries = 2L returns scout without mixed-series warning
  expect_no_warning(vol_scout <- read_dicom_volume(mix_dir, subseries = 2L))
  expect_true(is_dicom_volume(vol_scout))
  expect_equal(dim(vol_scout), c(24L, 22L, 1L))

  # split = TRUE returns length-2 list of dicom_volume objects without warning
  expect_no_warning(vol_list <- read_dicom_volume(mix_dir, split = TRUE))
  expect_type(vol_list, "list")
  expect_equal(length(vol_list), 2L)
  expect_true(all(vapply(vol_list, is_dicom_volume, logical(1L))))
  expect_equal(dim(vol_list[[1L]]), c(16L, 14L, 5L))
  expect_equal(dim(vol_list[[2L]]), c(24L, 22L, 1L))

  # Out-of-bounds subseries aborts cleanly
  expect_error(read_dicom_volume(mix_dir, subseries = 99L), "subseries")
  expect_no_warning(expect_error(read_dicom_volume(mix_dir, subseries = 3e9), "subseries"))

  # series_uid filtering + ignoring non-image SR files in the same directory
  s2_dir <- file.path(mix_dir, "second_series")
  p2 <- dicom_synthesize(
    out_dir = s2_dir,
    modality = "MR",
    dims = c(8L, 8L, 3L),
    phi = FALSE
  )
  sr_path <- file.path(mix_dir, "report.dcm")
  create_dicom_sr(sr_path, title = "Note", text = "Test SR alongside images")

  sp_all <- dicom_split_series(mix_dir)
  expect_equal(nrow(sp_all), 3L)

  expect_no_warning(vol_s2 <- read_dicom_volume(mix_dir, series_uid = p2$uids$series_uid))
  expect_equal(vol_s2$modality, "MR")
  expect_equal(dim(vol_s2), c(8L, 8L, 3L))
  expect_error(read_dicom_volume(mix_dir, series_uid = "2.25.999999999"), "series_uid")

  # Missing IPP/IOP fallback orders by InstanceNumber and flags missing_geometry = TRUE
  no_ipp_1 <- tempfile(fileext = ".dcm")
  no_ipp_2 <- tempfile(fileext = ".dcm")
  on.exit(unlink(c(no_ipp_1, no_ipp_2)), add = TRUE)
  write_dicom(matrix(20, 8L, 8L), no_ipp_1, metadata = list(Modality = "OT", SeriesInstanceUID = "2.25.77", InstanceNumber = "2"))
  write_dicom(matrix(10, 8L, 8L), no_ipp_2, metadata = list(Modality = "OT", SeriesInstanceUID = "2.25.77", InstanceNumber = "1"))
  vol_no_ipp <- read_dicom_volume(c(no_ipp_1, no_ipp_2))
  expect_true(isTRUE(vol_no_ipp$diagnostics$missing_geometry))
  expect_true(all(vol_no_ipp$voxels[, , 1L] == 10))
  expect_true(all(vol_no_ipp$voxels[, , 2L] == 20))
})

test_that("Geometry diagnostics and warnings cover irregular_z, gantry_tilt_deg, and duplicate positions", {
  # 1. irregular_z = TRUE
  irr_dir <- tempfile("read_irreg_")
  on.exit(unlink(irr_dir, recursive = TRUE), add = TRUE)
  p_irr <- dicom_synthesize(
    out_dir = irr_dir,
    modality = "CT",
    dims = c(10L, 10L, 6L),
    spacing = c(1.0, 1.0, 2.5),
    irregular_z = TRUE,
    phi = FALSE
  )

  expect_warning(
    vol_irr <- read_dicom_volume(p_irr$files),
    "irregular|spacing|gap",
    ignore.case = TRUE
  )
  expect_no_warning(read_dicom_volume(p_irr$files, warn = FALSE))
  expect_true(isTRUE(vol_irr$diagnostics$irregular_spacing))
  expect_gt(vol_irr$diagnostics$max_spacing_dev_mm, 2.0)

  # 2. gantry_tilt_deg = 15
  tilt_dir <- tempfile("read_tilt_")
  on.exit(unlink(tilt_dir, recursive = TRUE), add = TRUE)
  p_tilt <- dicom_synthesize(
    out_dir = tilt_dir,
    modality = "CT",
    dims = c(10L, 12L, 5L),
    spacing = c(0.8, 0.9, 3.0),
    origin = c(-10, -12, 0),
    orientation = "axial",
    gantry_tilt_deg = 15,
    phi = FALSE
  )

  expect_warning(
    vol_tilt <- read_dicom_volume(p_tilt$files),
    "gantry|tilt|shear",
    ignore.case = TRUE
  )
  expect_true(isTRUE(vol_tilt$diagnostics$has_gantry_tilt))
  expect_lt(abs(vol_tilt$diagnostics$gantry_tilt_deg - 15.0), 0.05)
  expect_lt(max(abs(vol_tilt$affine - p_tilt$truth_affine_lps)), 1e-5)
  expect_lt(max(abs(vol_tilt$affine[, 3L] - p_tilt$truth_affine_lps[, 3L])), 1e-5)

  # 3. Duplicate slice positions without temporal identifiers
  expect_warning(
    vol_dup <- read_dicom_volume(c(p_irr$files[1L], p_irr$files[1L])),
    "duplicate",
    ignore.case = TRUE
  )
  expect_true(isTRUE(vol_dup$diagnostics$duplicate_positions))
  expect_equal(dim(vol_dup), c(10L, 10L, 2L))
  expect_gt(abs(det(vol_dup$affine[1:3, 1:3])), 1e-6)
})

test_that("Modality units and header/file metadata are preserved for downstream quantitative & NIfTI tasks", {
  # PET (PT) -> BQML units + file paths with RadiopharmaceuticalInformationSequence
  pt_dir <- tempfile("read_pt_meta_")
  on.exit(unlink(pt_dir, recursive = TRUE), add = TRUE)
  p_pt <- dicom_synthesize(
    out_dir = pt_dir,
    modality = "PT",
    dims = c(10L, 10L, 3L),
    phi = FALSE
  )
  vol_pt <- read_dicom_volume(p_pt$files)
  expect_equal(vol_pt$modality, "PT")
  expect_equal(vol_pt$units, "BQML")
  expect_true("file" %in% names(vol_pt$frame_meta))
  expect_true(all(file.exists(vol_pt$frame_meta$file)))
  expect_equal(vol_pt$uids$series_uid, p_pt$uids$series_uid)
  expect_equal(vol_pt$uids$study_uid, p_pt$uids$study_uid)
  expect_equal(vol_pt$uids$frame_of_reference_uid, p_pt$uids$frame_of_reference_uid)

  pt_sq_hdr <- read_dicom(vol_pt$frame_meta$file[1L], include_sequences = TRUE)
  expect_true("RadionuclideTotalDose" %in% pt_sq_hdr$keyword)

  # MR with Philips private tags -> source files retained in frame_meta
  mr_dir <- tempfile("read_mr_priv_")
  on.exit(unlink(mr_dir, recursive = TRUE), add = TRUE)
  p_mr <- dicom_synthesize(
    out_dir = mr_dir,
    modality = "MR",
    dims = c(8L, 8L, 2L),
    extra_tags = list("(2005,100D)" = "0", "(2005,100E)" = "2.5"),
    phi = FALSE
  )
  vol_mr <- read_dicom_volume(p_mr$files)
  expect_equal(vol_mr$modality, "MR")
  expect_equal(unname(dicom_tag_value(vol_mr$frame_meta$file[1L], "(2005,100E)")), "2.5")
})

test_that("Backward-compatible read_dicom_series() and render_volume() support geometry, deprecation, and dicom_volume", {
  rev_dir <- tempfile("series_compat_rev_")
  on.exit(unlink(rev_dir, recursive = TRUE), add = TRUE)
  phantom <- dicom_synthesize(
    out_dir = rev_dir,
    modality = "CT",
    dims = c(12L, 10L, 4L),
    spacing = c(0.5, 1.0, 3.0),
    orientation = "oblique",
    reverse_order = TRUE,
    phi = FALSE
  )

  # Emits lifecycle deprecation warning when lifecycle_verbosity = "warning"
  expect_warning(
    withr::with_options(
      list(lifecycle_verbosity = "warning"),
      read_dicom_series(phantom$files)
    ),
    class = "lifecycle_warning_deprecated"
  )

  withr::local_options(lifecycle_verbosity = "quiet")
  series <- read_dicom_series(phantom$files)
  expect_s3_class(series, "dicom_series")
  expect_true(all(c("volume", "metadata", "files", "dims", "affine") %in% names(series)))
  expect_equal(series$dims, c(rows = 12L, cols = 10L, slices = 4L))
  expect_equal(dim(series$affine), c(4L, 4L))
  expect_lt(max(abs(series$affine - phantom$truth_affine_lps)), 1e-5)
  expect_lt(max(abs(series$volume - phantom$truth_voxels)), 1e-5)

  # Legacy duplicate single-file call read_dicom_series(c(dcm_file, dcm_file))
  dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
  s_dup <- read_dicom_series(c(dcm_file, dcm_file))
  expect_s3_class(s_dup, "dicom_series")
  expect_equal(dim(s_dup$volume)[3L], 2L)
  expect_equal(dim(s_dup$affine), c(4L, 4L))
  expect_gt(abs(det(s_dup$affine[1:3, 1:3])), 1e-6)

  # render_volume() accepts dicom_volume directly and scales tile aspect ratios by physical spacing
  vol <- read_dicom_volume(phantom$files)
  p_mpr <- render_volume(vol, method = "mpr")
  expect_s3_class(p_mpr, "ggplot")
  p_mip <- render_volume(vol, method = "mip")
  expect_s3_class(p_mip, "ggplot")
  p_path <- render_volume(phantom$files, method = "mpr")
  expect_s3_class(p_path, "ggplot")

  # Verify physical spacing (dr=0.5, dc=1.0, dz=3.0) produces distinct tile width vs height in Axial plane
  ax_df <- p_mpr$data[p_mpr$data$plane == "Axial", , drop = FALSE]
  expect_gt(ax_df$w[1L], ax_df$h[1L] * 1.5)
})
