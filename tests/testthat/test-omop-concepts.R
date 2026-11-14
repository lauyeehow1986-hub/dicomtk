test_that("omop_imaging_concepts dataset is bundled with standard OMOP MI-CDM columns", {
  env <- new.env(parent = emptyenv())
  utils::data("omop_imaging_concepts", package = "dicomtk", envir = env)
  df <- env$omop_imaging_concepts

  expect_s3_class(df, "tbl_df")
  expect_gte(nrow(df), 45L)
  expect_true(all(c(
    "concept_id", "concept_name", "domain_id", "vocabulary_id",
    "concept_class_id", "concept_code", "dicom_code", "category"
  ) %in% names(df)))
  expect_true("CT" %in% df$dicom_code)
  expect_true("MR" %in% df$dicom_code)
  expect_true("PT" %in% df$dicom_code)
})
