test_that("export_nnunet creates valid nnU-Net v2 directory layout, NIfTIs, and dataset.json", {
  synth1 <- dicom_synthesize(modality = "CT", dims = c(16L, 16L, 4L))
  vol1 <- read_dicom_volume(synth1[["out_dir"]])
  m1 <- array(0L, dim = c(16L, 16L, 4L))
  m1[4:10, 4:10, 2:3] <- 1L
  seg1 <- dicom_seg(m1, vol1, tibble::tibble(segment_id = 1L, label = "Liver"))

  synth2 <- dicom_synthesize(modality = "CT", dims = c(16L, 16L, 4L))
  vol2 <- read_dicom_volume(synth2[["out_dir"]])
  m2 <- array(0L, dim = c(16L, 16L, 4L))
  m2[5:12, 5:12, 2:3] <- 1L
  seg2 <- dicom_seg(m2, vol2, tibble::tibble(segment_id = 1L, label = "Liver"))

  out_dir <- file.path(tempdir(), "nnunet_export_test")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  res <- export_nnunet(
    volumes = list(case_001 = vol1, case_002 = vol2),
    segmentations = list(case_001 = seg1, case_002 = seg2),
    out_dir = out_dir,
    dataset_name = "LiverSeg",
    dataset_id = 101L
  )

  expect_true(dir.exists(res$dataset_dir))
  expect_true(dir.exists(file.path(res$dataset_dir, "imagesTr")))
  expect_true(dir.exists(file.path(res$dataset_dir, "labelsTr")))
  expect_true(file.exists(res$dataset_json))

  dj <- jsonlite::fromJSON(res$dataset_json)
  expect_equal(dj$numTraining, 2L)
  expect_true("background" %in% names(dj$labels))
  expect_true("Liver" %in% names(dj$labels))
  expect_true("0" %in% names(dj$channel_names))
  expect_equal(length(list.files(file.path(res$dataset_dir, "imagesTr"))), 2L)
  expect_equal(length(list.files(file.path(res$dataset_dir, "labelsTr"))), 2L)
})

test_that("export_monai generates MONAI datalist.json with training/validation splits", {
  synth1 <- dicom_synthesize(modality = "MR", dims = c(16L, 16L, 4L))
  vol1 <- read_dicom_volume(synth1[["out_dir"]])
  m1 <- array(0L, dim = c(16L, 16L, 4L))
  m1[4:10, 4:10, 2L] <- 1L
  seg1 <- dicom_seg(m1, vol1, tibble::tibble(segment_id = 1L, label = "Tumor"))

  out_dir <- file.path(tempdir(), "monai_export_test")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  res <- export_monai(
    volumes = list(sub_01 = vol1, sub_02 = vol1),
    segmentations = list(sub_01 = seg1, sub_02 = seg1),
    splits = c("training", "validation"),
    out_dir = out_dir
  )

  expect_true(file.exists(res$datalist_json))
  dl <- jsonlite::fromJSON(res$datalist_json, simplifyVector = FALSE)
  expect_true("training" %in% names(dl))
  expect_true("validation" %in% names(dl))
  expect_equal(length(dl$training), 1L)
  expect_equal(length(dl$validation), 1L)
  expect_true(all(c("image", "label") %in% names(dl$training[[1L]])))
})

test_that("export_rocrate and export_croissant emit standards-compliant JSON-LD metadata", {
  out_dir <- file.path(tempdir(), "metadata_export_test")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  rc_path <- export_rocrate(
    out_dir = out_dir,
    name = "Liver CT Benchmark",
    description = "Synthetic CT liver segmentation cohort"
  )
  expect_true(file.exists(rc_path))
  rc <- jsonlite::fromJSON(rc_path, simplifyVector = FALSE)
  expect_equal(rc[["@context"]], "https://w3id.org/ro/crate/1.1/context")
  expect_true("@graph" %in% names(rc))

  cr_path <- export_croissant(
    out_dir = out_dir,
    name = "Liver CT Benchmark",
    description = "Synthetic CT liver segmentation cohort",
    num_records = 2L
  )
  expect_true(file.exists(cr_path))
  cr <- jsonlite::fromJSON(cr_path, simplifyVector = FALSE)
  expect_equal(cr[["@context"]], "https://schema.org/")
  expect_equal(cr[["conformsTo"]], "http://mlcommons.org/croissant/1.0")
  expect_equal(cr[["name"]], "Liver CT Benchmark")
})
