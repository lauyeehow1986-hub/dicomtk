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

  # SUVbsa: BSA = 0.007184 * (70^0.425) * (175^0.725) = 0.007184 * 6.07928 * 42.4414 = 1.8537 m^2
  # SUVbsa = (activity / 1000) / (decayed_dose / (BSA * 10000))
  suv_bsa <- dicom_pet_suv(vol, method = "bsa")
  expect_equal(suv_bsa$units, "cm2/ml")
  expect_gt(as.numeric(suv_bsa$voxels[8, 8, 2]), 0)

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
  expect_error(dicom_pet_suv(vol_ct), "RadiopharmaceuticalInformationSequence")

  # Synthesize PT without weight
  out_dir_pt <- tempfile("pet_no_wt_")
  on.exit(unlink(out_dir_pt, recursive = TRUE), add = TRUE)
  dicom_synthesize(out_dir = out_dir_pt, modality = "PT", extra_tags = list(PatientWeight = ""))
  vol_pt <- read_dicom_volume(out_dir_pt)
  expect_error(dicom_pet_suv(vol_pt), "PatientWeight")
})

test_that("dicom_apply_voi_lut applies linear and sigmoid VOI LUTs", {
  # Synthesize MG
  out_dir <- tempfile("mg_voi_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  dicom_synthesize(
    out_dir = out_dir,
    modality = "MG",
    dims = c(16L, 16L, 1L),
    voi_params = list(
      window_center = 2048,
      window_width = 1024,
      voi_lut_function = "LINEAR"
    )
  )
  vol_mg <- read_dicom_volume(out_dir)
  voi_lin <- dicom_apply_voi_lut(vol_mg)
  expect_s3_class(voi_lin, "dicom_volume")
  expect_gte(min(voi_lin$voxels), 0.0)
  expect_lte(max(voi_lin$voxels), 1.0)
  expect_equal(voi_lin$units, "normalized")

  # Sigmoid VOI LUT function
  dicom_synthesize(
    out_dir = out_dir,
    modality = "MG",
    dims = c(16L, 16L, 1L),
    voi_params = list(
      window_center = 2048,
      window_width = 1024,
      voi_lut_function = "SIGMOID"
    )
  )
  vol_sig <- read_dicom_volume(out_dir)
  voi_sig <- dicom_apply_voi_lut(vol_sig)
  expect_s3_class(voi_sig, "dicom_volume")
  expect_gte(min(voi_sig$voxels), 0.0)
  expect_lte(max(voi_sig$voxels), 1.0)
})

test_that("dicom_mr_rescale applies Philips private scale intercept and slope", {
  out_dir <- tempfile("mr_philips_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  # MR with Philips private tags (2005,100D) and (2005,100E)
  dicom_synthesize(
    out_dir = out_dir,
    modality = "MR",
    dims = c(16L, 16L, 2L),
    extra_tags = list(
      "(2005,100D)" = "10.5",
      "(2005,100E)" = "2.5"
    )
  )
  vol_mr <- read_dicom_volume(out_dir)
  orig_vals <- vol_mr$voxels
  rescaled_mr <- dicom_mr_rescale(vol_mr)
  expect_s3_class(rescaled_mr, "dicom_volume")
  # Expected: orig_vals * 2.5 + 10.5
  expect_equal(rescaled_mr$voxels, orig_vals * 2.5 + 10.5, tolerance = 1e-4)
})
