test_that("dicom_index_build indexes studies/series/instances in DuckDB and exports Parquet", {
  s_ct <- dicom_synthesize(modality = "CT", dims = c(8L, 8L, 2L))
  s_mr <- dicom_synthesize(modality = "MR", dims = c(8L, 8L, 3L))
  arch_dir <- tempfile("arch_src_")
  pq_dir <- tempfile("arch_pq_")
  db_path <- tempfile(fileext = ".duckdb")
  dir.create(arch_dir, recursive = TRUE)
  file.copy(s_ct[["files"]], file.path(arch_dir, paste0("ct_", basename(s_ct[["files"]]))))
  file.copy(s_mr[["files"]], file.path(arch_dir, paste0("mr_", basename(s_mr[["files"]]))))

  idx <- dicom_index_build(arch_dir, db_path = db_path, parquet_dir = pq_dir)
  on.exit({
    dicom_index_close(idx)
    unlink(c(s_ct[["out_dir"]], s_mr[["out_dir"]], arch_dir, pq_dir, db_path, paste0(db_path, ".wal")), recursive = TRUE)
  }, add = TRUE)

  expect_s3_class(idx, "dicom_archive_index")
  expect_true(all(c("studies", "series", "instances") %in% names(idx$tables)))
  expect_equal(nrow(idx$tables$studies), 2L)
  expect_equal(nrow(idx$tables$series), 2L)
  expect_equal(nrow(idx$tables$instances), 5L)

  res <- dicom_index_query(idx, "SELECT Modality, COUNT(*) AS n_series FROM series GROUP BY Modality ORDER BY Modality")
  expect_s3_class(res, "tbl_df")
  expect_equal(res$Modality, c("CT", "MR"))
  expect_equal(as.integer(res$n_series), c(1L, 1L))

  if (requireNamespace("duckdb", quietly = TRUE) && requireNamespace("DBI", quietly = TRUE)) {
    expect_true(file.exists(file.path(pq_dir, "studies.parquet")))
    expect_true(file.exists(file.path(pq_dir, "series.parquet")))
    expect_true(file.exists(file.path(pq_dir, "instances.parquet")))
  }

  # Pure-R tibble fallback engine
  idx_tib <- dicom_index_build(arch_dir, engine = "tibble")
  on.exit(dicom_index_close(idx_tib), add = TRUE)
  expect_equal(idx_tib$engine, "tibble")
  expect_equal(nrow(idx_tib$tables$instances), 5L)
})
