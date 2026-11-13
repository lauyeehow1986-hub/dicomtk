test_that("dicom_burn_annotations writes derived Secondary Capture DICOMs with ImageType DERIVED\\SECONDARY and fresh UIDs", {
  synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 4L))
  vol <- read_dicom_volume(synth[["out_dir"]])

  orig_files <- synth$files
  orig_hashes <- vapply(orig_files, function(f) {
    as.character(tools::md5sum(f))
  }, character(1L))
  orig_sop_uids <- vapply(orig_files, function(f) {
    dicom_tag_value(f, "SOPInstanceUID")[[1L]]
  }, character(1L))

  ann_tbl <- tibble::tibble(
    slice = c(2L, 3L),
    graphic_type = c("POLYLINE", "CIRCLE"),
    coords = list(
      c(8, 8, 22, 8, 22, 22, 8, 22, 8, 8),
      c(16, 16, 22, 16)
    ),
    text = c("LESION_A", "NODE_B")
  )

  out_dir <- file.path(tempdir(), "burned_export_test")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  res <- dicom_burn_annotations(
    volume = vol,
    annotations = ann_tbl,
    out_dir = out_dir,
    slices = c(2L, 3L)
  )

  expect_s3_class(res, "dicom_burned_export")
  expect_true(dir.exists(out_dir))
  expect_equal(length(res$files), 2L)
  expect_true(all(file.exists(res$files)))

  # Guard-rail 1: Source files must never be mutated
  post_hashes <- vapply(orig_files, function(f) {
    as.character(tools::md5sum(f))
  }, character(1L))
  expect_equal(post_hashes, orig_hashes)

  # Guard-rail 2: ImageType must be DERIVED\SECONDARY and new SOPInstanceUIDs minted
  for (f in res$files) {
    img_type <- dicom_tag_value(f, "ImageType")[[1L]]
    sop_uid <- dicom_tag_value(f, "SOPInstanceUID")[[1L]]
    sop_class <- dicom_tag_value(f, "SOPClassUID")[[1L]]
    expect_match(img_type, "DERIVED\\\\SECONDARY")
    expect_false(sop_uid %in% orig_sop_uids)
    expect_equal(sop_class, "1.2.840.10008.5.1.4.1.1.7") # Secondary Capture Image Storage
  }

  # Guard-rail 3: Burned pixels actually modify the annotated slice compared to raw slice
  px_burned <- read_dicom_pixels(res$files[1L], rescale = FALSE)
  raw_slice2 <- vol$voxels[, , 2L]
  # Burned overlay should introduce bright annotation pixels
  expect_gt(max(px_burned), min(px_burned))
  expect_false(identical(as.numeric(px_burned), as.numeric(raw_slice2)))
})

test_that("dicom_burn_annotations refuses to overwrite the source directory", {
  synth <- dicom_synthesize(modality = "CT", dims = c(16L, 16L, 2L))
  vol <- read_dicom_volume(synth[["out_dir"]])
  ann_tbl <- tibble::tibble(
    slice = 1L,
    graphic_type = "POLYLINE",
    coords = list(c(4, 4, 12, 4, 12, 12, 4, 12, 4, 4)),
    text = "ROI"
  )

  expect_error(
    dicom_burn_annotations(vol, ann_tbl, out_dir = synth[["out_dir"]]),
    "source"
  )
})
