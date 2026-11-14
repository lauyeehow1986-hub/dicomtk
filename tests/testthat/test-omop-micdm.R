test_that("to_omop_image_occurrence and to_omop_image_feature generate valid OHDSI MI-CDM tables", {
  s_ct <- dicom_synthesize(modality = "CT", dims = c(16L, 16L, 3L))
  sr_path <- tempfile(fileext = ".dcm")
  db_path <- tempfile(fileext = ".duckdb")
  on.exit(unlink(c(s_ct[["out_dir"]], sr_path, db_path, paste0(db_path, ".wal")), recursive = TRUE), add = TRUE)

  idx <- dicom_index_build(s_ct[["out_dir"]])
  on.exit(dicom_index_close(idx), add = TRUE)

  occ <- to_omop_image_occurrence(idx)
  expect_s3_class(occ, "tbl_df")
  expect_gte(nrow(occ), 1L)
  expect_true(all(c(
    "image_occurrence_id", "person_id", "image_occurrence_date",
    "image_study_uid", "image_series_uid", "modality_concept_id",
    "anatomic_site_concept_id", "local_path", "wadors_uri"
  ) %in% names(occ)))
  expect_equal(occ$modality_concept_id[1L], 4300757L)

  vol <- read_dicom_volume(s_ct[["out_dir"]])
  mask <- array(0L, dim = dim(vol))
  mask[5:10, 5:10, 1:2] <- 1L
  seg <- dicom_seg(mask, vol, tibble::tibble(segment_id = 1L, label = "Lesion"))
  dicom_sr_tid1500(vol = vol, seg = seg, out_path = sr_path, title = "OMOP Feature Report")
  sr <- read_sr_tid1500(sr_path)

  feat_seg <- to_omop_image_feature(
    seg,
    image_occurrence_id = occ$image_occurrence_id[1L],
    person_id = occ$person_id[1L]
  )
  expect_s3_class(feat_seg, "tbl_df")
  expect_gte(nrow(feat_seg), 1L)
  expect_true(all(c(
    "image_feature_id", "image_occurrence_id", "person_id",
    "image_feature_concept_id", "image_feature_type_concept_id",
    "image_finding_concept_id", "alg_system", "value_as_number", "unit_concept_id"
  ) %in% names(feat_seg)))

  feat_sr <- to_omop_image_feature(
    sr,
    image_occurrence_id = occ$image_occurrence_id[1L],
    person_id = occ$person_id[1L]
  )
  expect_s3_class(feat_sr, "tbl_df")
  expect_gte(nrow(feat_sr), 1L)
  expect_true(all(feat_sr$image_occurrence_id %in% occ$image_occurrence_id))

  if (requireNamespace("duckdb", quietly = TRUE) && requireNamespace("DBI", quietly = TRUE)) {
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path)
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
    wres <- write_omop_micdm(con, occurrence_df = occ, feature_df = feat_sr)
    expect_true(isTRUE(wres$valid_fk))
    expect_true("image_occurrence" %in% DBI::dbListTables(con))
    expect_true("image_feature" %in% DBI::dbListTables(con))
  }
})
