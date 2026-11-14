test_that("validate_readonly_sql rejects 100+ adversarial SQLi and DuckDB file-access payloads", {
  expect_true(validate_readonly_sql("SELECT StudyInstanceUID, Modality FROM series WHERE Modality = 'CT'"))
  expect_true(validate_readonly_sql("WITH ct AS (SELECT * FROM series WHERE Modality = 'CT') SELECT * FROM ct;"))

  base_attacks <- c(
    "DROP TABLE studies",
    "DELETE FROM series WHERE 1=1",
    "INSERT INTO studies VALUES ('x')",
    "UPDATE series SET Modality = 'XX'",
    "ALTER TABLE studies ADD COLUMN hack TEXT",
    "CREATE TABLE evil (x INT)",
    "ATTACH '/tmp/evil.db' AS evil",
    "DETACH evil",
    "COPY studies TO '/tmp/leak.csv'",
    "EXPORT DATABASE '/tmp/leak'",
    "PRAGMA database_list",
    "INSTALL httpfs",
    "LOAD httpfs",
    "SET memory_limit='1GB'",
    "SELECT * FROM studies; DROP TABLE studies",
    "SELECT * FROM series WHERE Modality = 'CT' -- comment",
    "SELECT /* block */ * FROM series",
    "SELECT * FROM read_csv('/etc/passwd')",
    "SELECT * FROM read_csv_auto('secret.csv')",
    "SELECT * FROM read_parquet('secret.parquet')",
    "SELECT * FROM read_json('secret.json')",
    "SELECT * FROM read_text('/etc/hosts')",
    "SELECT * FROM glob('*')",
    "SELECT * FROM parquet_scan('x.parquet')",
    "CALL duckdb_tables()"
  )

  set.seed(20261114L)
  for (i in seq_len(105L)) {
    atk <- base_attacks[((i - 1L) %% length(base_attacks)) + 1L]
    if (i %% 2L == 0L) atk <- tolower(atk)
    if (i %% 3L == 0L) atk <- paste0("  ", atk, "  ")
    expect_error(validate_readonly_sql(atk), regexp = "read-only|disallowed|forbidden|SQL")
  }
})

test_that("dicom_cohort_nl, export_cohort_spec, and run_cohort_spec build and execute cohorts", {
  s_ct <- dicom_synthesize(modality = "CT", dims = c(8L, 8L, 2L))
  s_mr <- dicom_synthesize(modality = "MR", dims = c(8L, 8L, 3L))
  arch_dir <- tempfile("cohort_arch_")
  spec_path <- tempfile(fileext = ".json")
  dir.create(arch_dir, recursive = TRUE)
  file.copy(s_ct[["files"]], file.path(arch_dir, paste0("ct_", basename(s_ct[["files"]]))))
  file.copy(s_mr[["files"]], file.path(arch_dir, paste0("mr_", basename(s_mr[["files"]]))))

  idx <- dicom_index_build(arch_dir)
  on.exit({
    dicom_index_close(idx)
    unlink(c(s_ct[["out_dir"]], s_mr[["out_dir"]], arch_dir, spec_path), recursive = TRUE)
  }, add = TRUE)

  res <- dicom_cohort_nl(idx, prompt = "CT series with at least 2 instances", execute = TRUE)
  expect_type(res, "list")
  expect_true(validate_readonly_sql(res$sql))
  expect_s3_class(res$results, "tbl_df")
  expect_gte(nrow(res$results), 1L)
  expect_true(all(res$results$Modality == "CT"))

  spec <- export_cohort_spec(res, name = "ct_min2", out_path = spec_path)
  expect_true(file.exists(spec_path))
  expect_equal(spec$name, "ct_min2")

  re_run <- run_cohort_spec(idx, spec_or_path = spec_path)
  expect_s3_class(re_run, "tbl_df")
  expect_equal(nrow(re_run), nrow(res$results))
})
