test_that("dicom_dvh computes accurate cumulative and differential DVHs and clinical dose metrics", {
  # Synthesize a reference CT volume
  synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 10L))
  vol <- read_dicom_volume(synth[["out_dir"]])

  # Create an artificial 3D dose grid in Gy matching volume geometry:
  # Sphere/cube with gradient from 40 to 60 Gy
  dose_arr <- array(0.0, dim = c(32L, 32L, 10L))
  dose_arr[10:20, 10:20, 3:7] <- 50.0 # 50 Gy uniform inside target

  dose_vol <- new_dicom_volume(
    voxels = dose_arr,
    affine = vol$affine,
    coord_system = "LPS",
    spacing = vol$spacing,
    direction = vol$direction,
    modality = "RTDOSE",
    units = "Gy"
  )

  # Create a segment mask enclosing the target
  mask_arr <- array(0L, dim = c(32L, 32L, 10L))
  mask_arr[10:20, 10:20, 3:7] <- 1L
  seg <- dicom_seg(mask_arr, vol, tibble::tibble(segment_id = 1L, label = "PTV_Target"))

  # Compute DVH
  dvh <- dicom_dvh(dose = dose_vol, seg = seg)
  expect_s3_class(dvh, "dicom_dvh")
  expect_true(is.list(dvh))
  expect_true("metrics" %in% names(dvh))
  expect_true("curves" %in% names(dvh))

  # Metrics verification for uniform 50 Gy target:
  # Mean dose should be exactly 50 Gy
  m <- dvh$metrics
  expect_equal(m$roi_label, "PTV_Target")
  expect_equal(m$mean_dose, 50.0, tolerance = 1e-3)
  expect_equal(m$min_dose, 50.0, tolerance = 1e-3)
  expect_equal(m$max_dose, 50.0, tolerance = 1e-3)
  expect_equal(m$D95, 50.0, tolerance = 1e-3)
  expect_equal(m$D50, 50.0, tolerance = 1e-3)
  expect_equal(m$V20, 100.0, tolerance = 1e-3) # 100% of volume receives >= 20 Gy
})

test_that("dicom_dvh handles multi-ROI segmentations and non-uniform dose gradients", {
  synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 5L))
  vol <- read_dicom_volume(synth[["out_dir"]])

  # Linear dose gradient: dose(x, y, z) = x * 2 Gy
  dose_arr <- array(0.0, dim = c(32L, 32L, 5L))
  for (x in 1:32) {
    dose_arr[x, , ] <- x * 2.0
  }
  dose_vol <- new_dicom_volume(
    voxels = dose_arr,
    affine = vol$affine,
    coord_system = "LPS",
    spacing = vol$spacing,
    direction = vol$direction,
    modality = "RTDOSE",
    units = "Gy"
  )

  # ROI 1: x = 10..15 (dose 20..30 Gy)
  # ROI 2: x = 20..25 (dose 40..50 Gy)
  mask_arr <- array(0L, dim = c(32L, 32L, 5L))
  mask_arr[10:15, 10:15, 2:4] <- 1L
  mask_arr[20:25, 10:15, 2:4] <- 2L

  seg_meta <- tibble::tibble(
    segment_id = c(1L, 2L),
    label = c("Organ_At_Risk", "Target_PTV")
  )
  seg <- dicom_seg(mask_arr, vol, seg_meta)

  dvh <- dicom_dvh(dose = dose_vol, seg = seg)
  expect_equal(nrow(dvh$metrics), 2L)

  m_oar <- dvh$metrics[dvh$metrics$roi_label == "Organ_At_Risk", ]
  m_ptv <- dvh$metrics[dvh$metrics$roi_label == "Target_PTV", ]

  expect_lt(m_oar$mean_dose, m_ptv$mean_dose)
  expect_gte(m_oar$min_dose, 20.0)
  expect_lte(m_oar$max_dose, 30.0)
  expect_gte(m_ptv$min_dose, 40.0)
  expect_lte(m_ptv$max_dose, 50.0)
})
