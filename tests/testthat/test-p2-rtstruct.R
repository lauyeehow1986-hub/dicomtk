test_that("rtstruct_to_seg converts planar contours to a 3D dicom_seg object aligned with ref_volume", {
  # Synthesize a 32x32x10 CT volume
  synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 10L))
  vol <- read_dicom_volume(synth[["out_dir"]])

  # Retrieve slice z positions from affine and origins
  origin <- vol$affine[1:3, 4L]
  dz <- vol$spacing[3L]

  # Create an artificial RTSTRUCT list representing 2 slices (slice 4 and slice 5)
  # A 10x10 mm square in LPS coordinates on slice 4: z = origin[3] + 3 * dz
  z4 <- origin[3L] + 3 * dz
  z5 <- origin[3L] + 4 * dz

  # In LPS mm: say x from 10 to 20, y from 10 to 20
  pts_s4 <- c(
    10, 10, z4,
    20, 10, z4,
    20, 20, z4,
    10, 20, z4
  )
  pts_s5 <- c(
    10, 10, z5,
    20, 10, z5,
    20, 20, z5,
    10, 20, z5
  )

  rt_obj <- structure(
    list(
      modality = "RTSTRUCT",
      rois = tibble::tibble(
        roi_number = 1L,
        roi_name = "PTV_Prostate",
        roi_color = "255\\0\\0"
      ),
      contours = tibble::tibble(
        roi_number = c(1L, 1L),
        geometric_type = c("CLOSED_PLANAR", "CLOSED_PLANAR"),
        n_points = c(4L, 4L),
        contour_data = list(pts_s4, pts_s5)
      )
    ),
    class = "dicom_rt"
  )

  seg <- rtstruct_to_seg(rt_obj, ref_volume = vol)
  expect_s3_class(seg, "dicom_seg")
  expect_s3_class(seg, "dicom_volume")
  expect_equal(dim(seg$array), c(32L, 32L, 10L))

  # Slices 4 and 5 should have non-zero voxels, other slices zero
  expect_gt(sum(seg$array[, , 4L]), 0L)
  expect_gt(sum(seg$array[, , 5L]), 0L)
  expect_equal(sum(seg$array[, , 1:3]), 0L)
  expect_equal(sum(seg$array[, , 6:10]), 0L)
  expect_equal(seg$segments$label, "PTV_Prostate")
})

test_that("seg_to_rtstruct extracts planar polygonal contours and round-trips with ref_volume", {
  synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 5L))
  vol <- read_dicom_volume(synth[["out_dir"]])

  mask_arr <- array(0L, dim = c(32L, 32L, 5L))
  mask_arr[10:20, 10:20, 3L] <- 1L

  seg_meta <- tibble::tibble(
    segment_id = 1L,
    label = "Bladder",
    category = "Anatomy"
  )
  seg <- dicom_seg(mask_arr, vol, seg_meta)

  rt_out <- seg_to_rtstruct(seg, ref_volume = vol)
  expect_s3_class(rt_out, "dicom_rt")
  expect_equal(rt_out$modality, "RTSTRUCT")
  expect_equal(nrow(rt_out$rois), 1L)
  expect_equal(rt_out$rois$roi_name, "Bladder")

  # Contours should be extracted for slice 3
  expect_gte(nrow(rt_out$contours), 1L)
  cdata <- rt_out$contours$contour_data[[1L]]
  expect_equal(length(cdata) %% 3L, 0L) # (x, y, z) triplets

  # Rasterize back and verify Dice > 0.85
  re_seg <- rtstruct_to_seg(rt_out, ref_volume = vol)
  dice <- 2 * sum(seg$array & re_seg$array) / (sum(seg$array) + sum(re_seg$array))
  expect_gt(dice, 0.85)
})
