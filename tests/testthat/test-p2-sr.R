test_that("dicom_sr_tid1500 computes quantitative volumetric and RECIST biomarkers and round-trips via read_sr_tid1500", {
  synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 8L))
  vol <- read_dicom_volume(synth[["out_dir"]])

  # Known 10 x 10 x 4 voxel box with uniform 100 HU intensity
  vol$voxels[, , ] <- 0.0
  vol$voxels[10:19, 10:19, 3:6] <- 100.0

  mask_arr <- array(0L, dim = c(32L, 32L, 8L))
  mask_arr[10:19, 10:19, 3:6] <- 1L
  # Second ROI: 5 x 5 x 2 box with 250 HU intensity
  vol$voxels[22:26, 22:26, 4:5] <- 250.0
  mask_arr[22:26, 22:26, 4:5] <- 2L

  seg_meta <- tibble::tibble(
    segment_id = c(1L, 2L),
    label = c("Liver_Lesion_1", "Liver_Lesion_2"),
    category = c("Tumor", "Tumor")
  )
  seg <- dicom_seg(mask_arr, vol, seg_meta)

  sr_file <- tempfile(fileext = ".dcm")
  on.exit(unlink(sr_file), add = TRUE)

  sr <- dicom_sr_tid1500(vol = vol, seg = seg, out_path = sr_file)
  expect_s3_class(sr, "dicom_sr_tid1500")
  expect_true(file.exists(sr_file))
  expect_equal(nrow(sr$summary), 2L)

  # Check analytical volume for ROI 1: 10 * 10 * 4 = 400 voxels * prod(vol$spacing)
  expected_vol_mm3 <- 400.0 * prod(vol$spacing)
  s1 <- sr$summary[sr$summary$label == "Liver_Lesion_1", ]
  expect_equal(s1$volume_mm3, expected_vol_mm3, tolerance = 1e-3)
  expect_equal(s1$volume_cm3, expected_vol_mm3 / 1000.0, tolerance = 1e-4)
  expect_equal(s1$mean_intensity, 100.0, tolerance = 1e-4)
  expect_equal(s1$sd_intensity, 0.0, tolerance = 1e-4)
  # Diagonal of a 10x10 pixel square with 1x1 mm spacing is sqrt(9^2 + 9^2) or sqrt(10^2 + 10^2)
  expect_gt(s1$recist_diameter_mm, 12.0)
  expect_lt(s1$recist_diameter_mm, 15.0)

  # Read back from DICOM file via read_sr_tid1500()
  sr_read <- read_sr_tid1500(sr_file)
  expect_s3_class(sr_read, "dicom_sr_tid1500")
  expect_true("Liver_Lesion_1" %in% sr_read$measurements$tracking_id)
  expect_true("Liver_Lesion_2" %in% sr_read$measurements$tracking_id)
  expect_true("mm3" %in% sr_read$measurements$unit_code)
  expect_true("mm" %in% sr_read$measurements$unit_code)

  vol_meas <- sr_read$measurements[
    sr_read$measurements$tracking_id == "Liver_Lesion_1" &
      sr_read$measurements$unit_code == "mm3",
  ]
  expect_equal(vol_meas$numeric_value[1L], expected_vol_mm3, tolerance = 1e-2)
})

test_that("write_dicom_gsps and read_dicom_gsps round-trip graphic and text annotations and VOI LUT", {
  synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 4L))
  vol <- read_dicom_volume(synth[["out_dir"]])

  ann_tbl <- tibble::tibble(
    slice = c(2L, 3L),
    layer = c("LAYER_ROI", "LAYER_ROI"),
    graphic_type = c("POLYLINE", "CIRCLE"),
    coords = list(
      c(10.0, 10.0, 20.0, 10.0, 20.0, 20.0, 10.0, 20.0, 10.0, 10.0),
      c(16.0, 16.0, 22.0, 16.0)
    ),
    text = c("Target Lesion A", "Reference Node B")
  )

  gsps_file <- tempfile(fileext = ".dcm")
  on.exit(unlink(gsps_file), add = TRUE)

  out_p <- write_dicom_gsps(
    annotations = ann_tbl,
    out_path = gsps_file,
    ref_volume = vol,
    window_center = 40.0,
    window_width = 400.0
  )
  expect_true(file.exists(out_p))

  gsps <- read_dicom_gsps(gsps_file)
  expect_s3_class(gsps, "dicom_gsps")
  expect_s3_class(gsps, "dicom_pstate")
  expect_equal(nrow(gsps$graphics), 2L)
  expect_equal(gsps$graphics$graphic_type, c("POLYLINE", "CIRCLE"))
  expect_equal(gsps$graphics$coords[[1L]], c(10.0, 10.0, 20.0, 10.0, 20.0, 20.0, 10.0, 20.0, 10.0, 10.0), tolerance = 1e-4)
  expect_equal(nrow(gsps$texts), 2L)
  expect_equal(gsps$texts$text, c("Target Lesion A", "Reference Node B"))
  expect_equal(gsps$window_center, 40.0, tolerance = 1e-4)
  expect_equal(gsps$window_width, 400.0, tolerance = 1e-4)
})
