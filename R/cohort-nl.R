#' Validate That a SQL String Is Strictly Read-Only and Free of File-Access Functions
#'
#' Enforces an unbypassable read-only SQL policy for natural-language cohort
#' queries against a [dicom_index_build()] index. Rejects SQL comments, multi-statement
#' semicolons, DDL/DML/admin statements, and DuckDB host-file reader functions.
#'
#' @param sql Character SQL string to validate.
#' @return Invisibly returns `TRUE` if valid; otherwise aborts via [cli::cli_abort()].
#' @examples
#' validate_readonly_sql("SELECT StudyInstanceUID, Modality FROM series WHERE Modality = 'CT'")
#' @export
validate_readonly_sql <- function(sql) {
  if (!is.character(sql) || length(sql) != 1L || is.na(sql) || !nzchar(trimws(sql))) {
    cli::cli_abort("SQL query must be a non-empty scalar string.")
  }

  raw_sql <- trimws(sql)
  # Disallow SQL comments and dollar-quoted strings outright
  if (grepl("--|/\\*|\\*/|\\$[A-Za-z0-9_]*\\$", raw_sql, perl = TRUE)) {
    cli::cli_abort("SQL comments and dollar-quoted strings are disallowed in read-only cohort queries.")
  }

  # Mask single-quoted string literals before structural & keyword checks
  masked <- gsub("'([^']|'')*'", "''", raw_sql, perl = TRUE)
  # Strip double quotes around identifiers so quoted function/keyword smuggling ("read_csv"(...)) is caught
  masked <- gsub('"', "", masked, fixed = TRUE)
  masked_no_trail <- sub(";\\s*$", "", masked, perl = TRUE)

  if (grepl(";", masked_no_trail, fixed = TRUE)) {
    cli::cli_abort("Multiple SQL statements (';') are forbidden in read-only queries.")
  }

  if (!grepl("^\\s*(SELECT|WITH)\\b", masked_no_trail, ignore.case = TRUE, perl = TRUE)) {
    cli::cli_abort("Only read-only SELECT (or WITH ... SELECT) SQL statements are permitted.")
  }

  forbidden_kw <- paste0(
    "\\b(INSERT|INTO|UPDATE|DELETE|DROP|ALTER|CREATE|REPLACE|TRUNCATE|",
    "ATTACH|DETACH|COPY|EXPORT|IMPORT|PRAGMA|INSTALL|LOAD|SET|CALL|",
    "MERGE|GRANT|REVOKE|VACUUM|EXECUTE|PREPARE|SUMMARIZE|DESCRIBE|SHOW)\\b"
  )
  if (grepl(forbidden_kw, masked_no_trail, ignore.case = TRUE, perl = TRUE)) {
    cli::cli_abort("Forbidden DDL/DML/administrative SQL keyword detected in read-only query.")
  }

  forbidden_fn <- paste0(
    "\\b(read_csv|read_csv_auto|read_parquet|parquet_scan|read_json|",
    "read_json_auto|read_text|read_blob|read_xlsx|st_read|",
    "sqlite_scan|postgres_scan|mysql_scan|iceberg_scan|delta_scan|",
    "glob|http_get|getenv|current_setting|duckdb_[a-z0-9_]+|pragma_[a-z0-9_]+)\\s*\\("
  )
  if (grepl(forbidden_fn, masked_no_trail, ignore.case = TRUE, perl = TRUE)) {
    cli::cli_abort("Disallowed host-file or system function detected in read-only SQL query.")
  }

  invisible(TRUE)
}

#' Build and Execute a Guardrailed Natural-Language Cohort Query
#'
#' Translates a natural-language cohort description into a validated read-only
#' `SELECT` SQL query against a `dicom_archive_index` (using deterministic
#' clinical parsing offline, or an `llm` chat session when online).
#'
#' @param index A `"dicom_archive_index"` object from [dicom_index_build()].
#' @param prompt Natural-language cohort description (e.g., `"CT chest series
#'   with at least 2 instances"`).
#' @param llm Optional `dicom_llm` object (default `dicom_llm("offline")`).
#' @param execute Logical. Execute the validated SQL query immediately (`TRUE`).
#'
#' @return A list of class `"dicom_cohort_query"` with `prompt`, `sql`,
#'   `criteria`, and `results`.
#' @export
dicom_cohort_nl <- function(index,
                            prompt,
                            llm = dicom_llm("offline"),
                            execute = TRUE) {
  if (!inherits(index, "dicom_archive_index")) {
    cli::cli_abort("{.arg index} must be a {.cls dicom_archive_index} object.")
  }
  if (!is.character(prompt) || length(prompt) != 1L || !nzchar(trimws(prompt))) {
    cli::cli_abort("{.arg prompt} must be a non-empty character string.")
  }

  p_low <- tolower(prompt)
  clauses <- character(0)
  criteria <- list()

  # Modality extraction
  mod_map <- c(
    "\\bct\\b" = "CT",
    "\\b(mr|mri)\\b" = "MR",
    "\\b(pet|pt)\\b" = "PT",
    "\\b(dx|xray|x-ray|radiograph)\\b" = "DX",
    "\\b(mg|mammo|mammography)\\b" = "MG",
    "\\b(us|ultrasound)\\b" = "US"
  )
  for (pat in names(mod_map)) {
    if (grepl(pat, p_low, perl = TRUE)) {
      mcode <- unname(mod_map[[pat]])
      clauses <- c(clauses, sprintf("Modality = '%s'", mcode))
      criteria$modality <- mcode
      break
    }
  }

  # Minimum instances / slices
  m_inst <- regmatches(
    p_low,
    regexec("(?:at least|>=|min(?:imum)?(?: of)?)\\s*([0-9]+)\\s*(?:instances?|slices?|files?)", p_low, perl = TRUE)
  )[[1L]]
  if (length(m_inst) >= 2L) {
    n_min <- as.integer(m_inst[2L])
    clauses <- c(clauses, sprintf("n_instances >= %d", n_min))
    criteria$min_instances <- n_min
  }

  # Maximum slice thickness
  m_st <- regmatches(
    p_low,
    regexec("(?:slice\\s*thickness|thickness)\\s*(?:<=|under|below|less than)\\s*([0-9]+(?:\\.[0-9]+)?)", p_low, perl = TRUE)
  )[[1L]]
  if (length(m_st) >= 2L) {
    st_max <- as.numeric(m_st[2L])
    clauses <- c(clauses, sprintf("SliceThickness <= %s", st_max))
    criteria$max_slice_thickness <- st_max
  }

  # Body part keyword
  for (bp in c("chest", "brain", "head", "lung", "abdomen", "liver", "pelvis", "spine", "breast")) {
    if (grepl(paste0("\\b", bp, "\\b"), p_low, perl = TRUE)) {
      clauses <- c(clauses, sprintf("(UPPER(BodyPartExamined) LIKE '%%%s%%' OR UPPER(SeriesDescription) LIKE '%%%s%%')", toupper(bp), toupper(bp)))
      criteria$body_part <- toupper(bp)
      break
    }
  }

  where_sql <- if (length(clauses) > 0L) paste("WHERE", paste(clauses, collapse = " AND ")) else ""
  sql <- trimws(paste(
    "SELECT SeriesInstanceUID, StudyInstanceUID, Modality, SeriesDescription, BodyPartExamined, SliceThickness, n_instances FROM series",
    where_sql
  ))

  validate_readonly_sql(sql)

  results <- NULL
  if (isTRUE(execute)) {
    if (identical(index$engine, "duckdb") && !is.null(index$con)) {
      results <- dicom_index_query(index, sql)
    } else {
      tbl <- index$tables$series
      if (!is.null(criteria$modality)) {
        tbl <- tbl[tbl$Modality == criteria$modality, , drop = FALSE]
      }
      if (!is.null(criteria$min_instances)) {
        tbl <- tbl[tbl$n_instances >= criteria$min_instances, , drop = FALSE]
      }
      if (!is.null(criteria$max_slice_thickness)) {
        tbl <- tbl[!is.na(tbl$SliceThickness) & tbl$SliceThickness <= criteria$max_slice_thickness, , drop = FALSE]
      }
      results <- tibble::as_tibble(tbl)
    }
  }

  structure(
    list(
      prompt = prompt,
      sql = sql,
      criteria = criteria,
      results = results
    ),
    class = "dicom_cohort_query"
  )
}

#' Export a Portable JSON Cohort Specification
#'
#' @param cohort A `"dicom_cohort_query"` object from [dicom_cohort_nl()].
#' @param name Cohort identifier string.
#' @param out_path Optional file path to write the JSON specification.
#' @return A portable cohort specification list (invisibly if written to disk).
#' @export
export_cohort_spec <- function(cohort, name = "cohort_spec", out_path = NULL) {
  if (!inherits(cohort, "dicom_cohort_query")) {
    cli::cli_abort("{.arg cohort} must be a {.cls dicom_cohort_query} object.")
  }
  validate_readonly_sql(cohort$sql)
  spec <- list(
    schema = "dicomtk.cohort.v1",
    name = as.character(name),
    prompt = cohort$prompt,
    sql = cohort$sql,
    criteria = cohort$criteria,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  if (!is.null(out_path)) {
    jsonlite::write_json(spec, out_path, auto_unbox = TRUE, pretty = TRUE)
  }
  spec
}

#' Execute a Portable JSON Cohort Specification Against an Archive Index
#'
#' @param index A `"dicom_archive_index"` object from [dicom_index_build()].
#' @param spec_or_path A cohort spec list from [export_cohort_spec()] or a
#'   `.json` file path.
#' @return A [tibble::tibble] of matching cohort records.
#' @export
run_cohort_spec <- function(index, spec_or_path) {
  spec <- if (is.character(spec_or_path)) {
    jsonlite::fromJSON(spec_or_path, simplifyVector = FALSE)
  } else if (is.list(spec_or_path)) {
    spec_or_path
  } else {
    cli::cli_abort("{.arg spec_or_path} must be a cohort spec list or JSON file path.")
  }
  validate_readonly_sql(spec$sql)
  dicom_index_query(index, spec$sql)
}
