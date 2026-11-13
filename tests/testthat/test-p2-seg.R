test_that("dicom_seg S3 constructor creates a valid spatial segmentation object inheriting from dicom_volume", {
  # Synthetic 32x32x10 volume for reference geometry
  synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 10L))
  vol <- read_dicom_volume(synth[["out_dir"]])

  # Create a 3D binary mask with a 10x10 cube inside
  mask_arr <- array(0L, dim = c(32L, 32L, 10L))
  mask_arr[10:19, 10:19, 3:7] <- 1L

  seg_meta <- tibble::tibble(
    segment_id = 1L,
    label = "Liver",
    category = "Anatomy",
    type = "binary",
    algorithm_type = "MANUAL",
    anatomic_region = "Liver",
    property_category = "Anatomical Structure"
  )

  seg <- dicom_seg(
    mask = mask_arr,
    ref_volume = vol,
    segments = seg_meta
  )

  expect_s3_class(seg, "dicom_seg")
  expect_s3_class(seg, "dicom_volume")
  expect_equal(dim(seg$array), c(32L, 32L, 10L))
  expect_equal(seg$affine, vol$affine)
  expect_equal(seg$spacing, vol$spacing)
  expect_equal(nrow(seg$segments), 1L)
  expect_equal(seg$segments$label, "Liver")
})

test_that("C++17 1-bit frame packer encodes and decodes DICOM-SEG binary frames accurately", {
  # 32 x 32 frame = 1024 pixels = 128 bytes
  w <- 32L
  h <- 32L
  m <- matrix(0L, nrow = h, ncol = w)
  m[5:15, 5:15] <- 1L

  packed <- cpp_pack_binary_frame(m)
  expect_equal(length(packed), 128L)

  unpacked <- cpp_unpack_binary_frame(packed, width = w, height = h)
  expect_equal(dim(unpacked), c(h, w))
  expect_equal(sum(unpacked), sum(m))
  expect_equal(unpacked, m)
})

test_that("write_dicom_seg and read_dicom_seg round-trip with full geometry and segment metadata", {
  synth <- dicom_synthesize(modality = "MR", dims = c(32L, 32L, 5L))
  vol <- read_dicom_volume(synth[["out_dir"]])

  mask_arr <- array(0L, dim = c(32L, 32L, 5L))
  mask_arr[8:18, 8:18, 2:4] <- 1L

  seg_meta <- tibble::tibble(
    segment_id = 1L,
    label = "GTV_Tumor",
    category = "Tissue",
    type = "binary",
    algorithm_type = "AUTOMATIC",
    anatomic_region = "Brain",
    property_category = "Tumor"
  )

  seg <- dicom_seg(
    mask = mask_arr,
    ref_volume = vol,
    segments = seg_meta
  )

  tmp_dcm <- file.path(tempdir(), "test_seg.dcm")
  on.exit(unlink(tmp_dcm), add = TRUE)

  written_file <- write_dicom_seg(seg, tmp_dcm)
  expect_true(file.exists(written_file))

  # Read back using read_dicom_seg()
  seg_read <- read_dicom_seg(written_file, ref_volume = vol)
  expect_s3_class(seg_read, "dicom_seg")
  expect_s3_class(seg_read, "dicom_volume")
  expect_equal(dim(seg_read$array), c(32L, 32L, 5L))
  expect_equal(sum(seg_read$array), sum(mask_arr))
  expect_equal(seg_read$affine, vol$affine, tolerance = 1e-5)
  expect_equal(seg_read$segments$label, "GTV_Tumor")

  # Verify as_labelmap() on 4D multi-segment dicom_seg
  m4 <- array(0L, dim = c(32L, 32L, 5L, 2L))
  m4[4:10, 4:10, 2L, 1L] <- 1L
  m4[15:22, 15:22, 2L, 2L] <- 1L
  seg4 <- dicom_seg(
    mask = m4,
    ref_volume = vol,
    segments = tibble::tibble(segment_id = c(1L, 2L), label = c("Left", "Right"))
  )
  lmap <- as_labelmap(seg4)
  expect_equal(dim(lmap$array), c(32L, 32L, 5L))
  expect_equal(lmap$array[6L, 6L, 2L], 1L)
  expect_equal(lmap$array[18L, 18L, 2L], 2L)
})
