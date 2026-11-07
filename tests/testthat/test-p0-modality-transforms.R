test_that("dicom_pet_suv calculates SUVbw, SUVlbm, and SUVbsa correctly", {
  # Synthesize a known PT volume:
  # 10,000 Bq/mL in phantom
  # PatientWeight = 70 kg (70,000 g), PatientSize = 1.75 m, PatientSex = "M"
  # RadionuclideTotalDose = 350e6 Bq, RadionuclideHalfLife = 6586.2 s
  # SeriesTime = 12:00:00, RadiopharmaceuticalStartTime = 10:10:13.8 (exact 6586.2s prior)
  # Decayed dose at scan time = 350e6 * 0.5 = 175e6 Bq
  # SUVbw = (10000) / (175e6 / 70000) = 4.0 g/mL
  out_dir <- tempfile("pet_suv_test_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  p <- dicom_synthesize(
    out_dir = out_dir,
    modality = "PT",
    dims = c(16L, 16L, 4L),
    pet_params = list(
      activity_bqml = 10000,
      weight_kg = 70,
      height_m = 1.75,
      patient_sex = "M",
      injected_dose_bq = 350e6,
      halflife_sec = 6586.2,
      start_time = "101013.800000",
      scan_time = "120000.000000"
    )
  )

  vol <- read_dicom_volume(out_dir)
  expect_equal(vol$units, "BQML")

  # SUVbw
  suv_bw <- dicom_pet_suv(vol, method = "bw")
  expect_s3_class(suv_bw, "dicom_volume")
  expect_equal(suv_bw$units, "g/ml")
  # Check central voxel value where sphere activity is 10000
  expect_equal(as.numeric(suv_bw$voxels[8, 8, 2]), 4.0, tolerance = 1e-4)

  # SUVlbm (Male: (9270 * 70) / (6680 + 216 * (70 / 1.75^2)) = 648900 / (6680 + 216 * 22.85714)
  # BMI = 22.85714; denominator = 6680 + 4937.143 = 11617.143; LBM = 55.85714 kg (55857.14 g)
  # SUVlbm = 10000 / (175e6 / 55857.14) = 10000 / 3133 = 3.1918 g/mL
  suv_lbm <- dicom_pet_suv(vol, method = "lbm")
  expect_equal(suv_lbm$units, "g/ml")
  expect_equal(as.numeric(suv_lbm$voxels[8, 8, 2]), 3.1918, tolerance = 1e-3)

  # SUVbsa: BSA = 0.007184 * (70^0.425) * (175^0.725) = 1.848148 m^2 = 18481.48 cm^2
  # SUVbsa = 10000 / (175e6 / 18481.48) = 1.056085 cm2/ml
  bsa_expected <- 0.007184 * (70^0.425) * (175^0.725) * 10000 / 175e6 * 10000
  suv_bsa <- dicom_pet_suv(vol, method = "bsa")
  expect_equal(suv_bsa$units, "cm2/ml")
  expect_equal(as.numeric(suv_bsa$voxels[8, 8, 2]), bsa_expected, tolerance = 1e-4)

  # Works directly on character file path or directory
  suv_direct <- dicom_pet_suv(out_dir, method = "bw")
  expect_s3_class(suv_direct, "dicom_volume")
  expect_equal(as.numeric(suv_direct$voxels[8, 8, 2]), 4.0, tolerance = 1e-4)
})

test_that("dicom_pet_suv error handling and decay options", {
  out_dir <- tempfile("pet_suv_err_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  # Missing pet_params -> weight or radiopharm seq missing
  p <- dicom_synthesize(out_dir = out_dir, modality = "CT")
  vol_ct <- read_dicom_volume(out_dir)
  expect_error(dicom_pet_suv(vol_ct), "BQML|RadiopharmaceuticalInformationSequence")

  # Synthesize PT without weight
  out_dir_pt <- tempfile("pet_no_wt_")
  on.exit(unlink(out_dir_pt, recursive = TRUE), add = TRUE)
  dicom_synthesize(out_dir = out_dir_pt, modality = "PT", extra_tags = list(PatientWeight = ""))
  vol_pt <- read_dicom_volume(out_dir_pt)
  expect_error(dicom_pet_suv(vol_pt), "PatientWeight")

  # Non-BQML Units must abort
  out_dir_cnts <- tempfile("pet_cnts_")
  on.exit(unlink(out_dir_cnts, recursive = TRUE), add = TRUE)
  dicom_synthesize(out_dir = out_dir_cnts, modality = "PT", pet_params = list(units = "CNTS"))
  expect_error(dicom_pet_suv(out_dir_cnts), "BQML")

  # Invalid PatientSize for lbm/bsa must abort
  out_dir_bad_sz <- tempfile("pet_badsz_")
  on.exit(unlink(out_dir_bad_sz, recursive = TRUE), add = TRUE)
  dicom_synthesize(out_dir = out_dir_bad_sz, modality = "PT", extra_tags = list(PatientSize = "0"))
  expect_error(dicom_pet_suv(out_dir_bad_sz, method = "lbm"), "PatientSize")

  # DecayCorrection = "ADMIN": auto does NOT re-decay (SUVbw = 2.0), force DOES decay (SUVbw = 4.0)
  out_dir_admin <- tempfile("pet_admin_")
  on.exit(unlink(out_dir_admin, recursive = TRUE), add = TRUE)
  dicom_synthesize(
    out_dir = out_dir_admin,
    modality = "PT",
    dims = c(16L, 16L, 2L),
    pet_params = list(
      activity_bqml = 10000,
      weight_kg = 70,
      injected_dose_bq = 350e6,
      halflife_sec = 6586.2,
      start_time = "101013.800000",
      scan_time = "120000.000000",
      decay_correction = "ADMIN"
    )
  )
  suv_auto_admin <- dicom_pet_suv(out_dir_admin, method = "bw", decay_correct = "auto")
  suv_force_admin <- dicom_pet_suv(out_dir_admin, method = "bw", decay_correct = "force")
  expect_equal(as.numeric(suv_auto_admin$voxels[8, 8, 1]), 2.0, tolerance = 1e-4)
  expect_equal(as.numeric(suv_force_admin$voxels[8, 8, 1]), 4.0, tolerance = 1e-4)
})

test_that("dicom_apply_voi_lut applies PS3.3 LINEAR, LINEAR_EXACT, SIGMOID, MONOCHROME1 inversion, and multi-window index", {
  # Synthesize MG FOR PROCESSING (PhotometricInterpretation = MONOCHROME1)
  out_dir <- tempfile("mg_voi_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  dicom_synthesize(
    out_dir = out_dir,
    modality = "MG",
    dims = c(16L, 16L, 1L),
    voi_params = list(
      presentation_intent = "FOR PROCESSING",
      window_center = 1000,
      window_width = 1000,
      voi_lut_function = "LINEAR_EXACT"
    )
  )
  vol_mg <- read_dicom_volume(out_dir)
  expect_equal(vol_mg$frame_meta$PhotometricInterpretation[1L], "MONOCHROME1")

  voi_m1 <- dicom_apply_voi_lut(vol_mg)
  voi_no_inv <- dicom_apply_voi_lut(vol_mg, invert_monochrome1 = FALSE)
  expect_s3_class(voi_m1, "dicom_volume")
  expect_equal(voi_m1$units, "normalized")
  expect_equal(voi_m1$voxels, 1.0 - voi_no_inv$voxels, tolerance = 1e-12)
  # Corner [1,1,1] has raw value 1000 == wc -> midpoint 0.5
  expect_equal(as.numeric(voi_m1$voxels[1, 1, 1]), 0.5, tolerance = 1e-12)
  # Background (20) < wc (1000): under MONOCHROME1 inversion, lower raw exposure -> brighter (> 0.5)
  expect_gt(as.numeric(voi_m1$voxels[8, 2, 1]), 0.9)

  # Exact analytical equations on MONOCHROME2 volume + multi-window index
  vox_test <- array(c(0, 500, 1000, 1500), dim = c(2L, 2L, 1L))
  meta_m2 <- tibble::tibble(
    PhotometricInterpretation = "MONOCHROME2",
    WindowCenter = "200\\500",
    WindowWidth = "100\\1000",
    VOILUTFunction = "LINEAR"
  )
  vol_m2 <- new_dicom_volume(vox_test, frame_meta = meta_m2, modality = "DX")

  # PS3.3 C.11.2.1.2.1 LINEAR with index = 2 (c = 500, w = 1000): y = clamp((x - 499.5)/999 + 0.5, 0, 1)
  res_lin <- dicom_apply_voi_lut(vol_m2, function_type = "LINEAR", index = 2L)
  expect_equal(as.numeric(res_lin$voxels[2, 1, 1]), (500 - 499.5) / 999 + 0.5, tolerance = 1e-12)

  # PS3.3 C.11.2.1.3.2 LINEAR_EXACT with index = 2 (c = 500, w = 1000): y = clamp((x - 500)/1000 + 0.5, 0, 1)
  res_lex <- dicom_apply_voi_lut(vol_m2, function_type = "LINEAR_EXACT", index = 2L)
  expect_equal(as.numeric(res_lex$voxels), c(0.0, 0.5, 1.0, 1.0), tolerance = 1e-12)

  # PS3.3 C.11.2.1.3.1 SIGMOID with index = 2 (c = 500, w = 1000): y = 1 / (1 + exp(-4*(x - c)/w))
  res_sig <- dicom_apply_voi_lut(vol_m2, function_type = "SIGMOID", index = 2L)
  expect_equal(
    as.numeric(res_sig$voxels),
    1.0 / (1.0 + exp(-4.0 * (c(0, 500, 1000, 1500) - 500) / 1000)),
    tolerance = 1e-12
  )
})

test_that("dicom_mr_rescale implements Chenevert/Philips quantitative FP and display DV scaling without double-rescaling", {
  # Case 1: Philips MR with both public RS/RI and private SS/SI tags
  out_dir <- tempfile("mr_philips_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  dicom_synthesize(
    out_dir = out_dir,
    modality = "MR",
    dims = c(16L, 16L, 2L),
    extra_tags = list(
      RescaleIntercept = "-10.0",
      RescaleSlope = "2.0",
      "(2005,100D)" = "-10.0",
      "(2005,100E)" = "5.0"
    )
  )
  vol_rescaled <- read_dicom_volume(out_dir, rescale = TRUE)
  vol_raw <- read_dicom_volume(out_dir, rescale = FALSE)
  pv <- vol_raw$voxels
  dv_expected <- pv * 2.0 - 10.0
  fp_expected <- dv_expected / (2.0 * 5.0)

  fp_from_rescaled <- dicom_mr_rescale(vol_rescaled, philips_float = TRUE)
  fp_from_raw <- dicom_mr_rescale(vol_raw, philips_float = TRUE)
  dv_from_rescaled <- dicom_mr_rescale(vol_rescaled, philips_float = FALSE)
  dv_from_raw <- dicom_mr_rescale(vol_raw, philips_float = FALSE)

  expect_s3_class(fp_from_rescaled, "dicom_volume")
  expect_equal(fp_from_rescaled$voxels, fp_expected, tolerance = 1e-6)
  expect_equal(fp_from_raw$voxels, fp_expected, tolerance = 1e-6)
  expect_equal(dv_from_rescaled$voxels, dv_expected, tolerance = 1e-6)
  expect_equal(dv_from_raw$voxels, dv_expected, tolerance = 1e-6)

  # Case 2: Classic MR with omitted public RS/RI and private (2005,100D)/(2005,100E) only
  out_dir2 <- tempfile("mr_philips_classic_")
  on.exit(unlink(out_dir2, recursive = TRUE), add = TRUE)
  dicom_synthesize(
    out_dir = out_dir2,
    modality = "MR",
    dims = c(8L, 8L, 2L),
    extra_tags = list(
      "(2005,100D)" = "10.5",
      "(2005,100E)" = "2.5"
    )
  )
  vol_c <- read_dicom_volume(out_dir2)
  expect_equal(
    dicom_mr_rescale(vol_c, philips_float = TRUE)$voxels,
    (vol_c$voxels + 10.5) / 2.5,
    tolerance = 1e-6
  )

  # Case 3: Zero ScaleSlope (2005,100E) aborts cleanly
  out_dir_zero <- tempfile("mr_philips_zero_")
  on.exit(unlink(out_dir_zero, recursive = TRUE), add = TRUE)
  dicom_synthesize(
    out_dir = out_dir_zero,
    modality = "MR",
    dims = c(8L, 8L, 1L),
    extra_tags = list("(2005,100E)" = "0")
  )
  expect_error(dicom_mr_rescale(out_dir_zero, philips_float = TRUE), "ScaleSlope")
})
