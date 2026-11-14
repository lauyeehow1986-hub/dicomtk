test_that("dicom_image_qc returns PASS and finite metrics on clean synthetic volume", {
  synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 8L))
  on.exit(unlink(synth[["out_dir"]], recursive = TRUE), add = TRUE)
  vol <- read_dicom_volume(synth[["out_dir"]])

  # Create clean centered phantom signal with low background
  vox <- array(0, dim = c(32L, 32L, 8L))
  vox[10:22, 10:22, 3:6] <- 200
  vol$voxels <- vox

  qc <- dicom_image_qc(vol)
  expect_type(qc, "list")
  expect_true(all(c(
    "snr", "cnr", "border_truncation", "spacing_anomaly",
    "tilt_anomaly", "artifact_score", "qc_status", "issues"
  ) %in% names(qc)))
  expect_true(is.finite(qc$snr) && qc$snr > 1)
  expect_true(is.finite(qc$cnr) && qc$cnr > 1)
  expect_false(qc$border_truncation)
  expect_false(qc$spacing_anomaly)
  expect_false(qc$tilt_anomaly)
  expect_true(qc$artifact_score >= 0 && qc$artifact_score <= 1)
  expect_equal(qc$qc_status, "PASS")
  expect_length(qc$issues, 0L)
})

test_that("dicom_image_qc detects border truncation, spacing anomaly, and ringing artifacts", {
  synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 8L))
  on.exit(unlink(synth[["out_dir"]], recursive = TRUE), add = TRUE)
  vol <- read_dicom_volume(synth[["out_dir"]])

  # 1. Border truncation
  vol_trunc <- vol
  vol_trunc$voxels[, , ] <- 0
  vol_trunc$voxels[1:32, 1:2, ] <- 500
  vol_trunc$voxels[1:32, 31:32, ] <- 500
  qc_trunc <- dicom_image_qc(vol_trunc)
  expect_true(qc_trunc$border_truncation)
  expect_true(qc_trunc$qc_status %in% c("WARN", "FAIL"))
  expect_true(length(qc_trunc$issues) >= 1L)

  # 2. Spacing anomaly via diagnostics flag
  vol_gap <- vol
  vol_gap$diagnostics$irregular_spacing <- TRUE
  qc_gap <- dicom_image_qc(vol_gap)
  expect_true(qc_gap$spacing_anomaly)
  expect_true(qc_gap$qc_status %in% c("WARN", "FAIL"))

  # 3. High-frequency striping / ringing artifact
  vol_ring <- vol
  vox_r <- array(0, dim = c(32L, 32L, 8L))
  for (i in seq_len(32L)) {
    vox_r[i, , ] <- if (i %% 2L == 0L) 150 else -150
  }
  vol_ring$voxels <- vox_r
  qc_ring <- dicom_image_qc(vol_ring)
  expect_true(qc_ring$artifact_score > 0.4)
  expect_true(qc_ring$qc_status %in% c("WARN", "FAIL"))
})
