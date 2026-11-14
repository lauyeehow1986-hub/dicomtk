# Internal: safe column extractor with default NA vector
.idx_col <- function(df, col, default = NA_character_) {
  if (col %in% names(df)) as.character(df[[col]]) else rep(as.character(default), nrow(df))
}

#' Build a Normalized 3-Table DICOM Archive Index (DuckDB / Parquet / Tibble)
#'
#' Scans a DICOM directory (or header tibble) and constructs normalized
#' `studies`, `series`, and `instances` tables backed by `duckdb` (with optional
#' Parquet export) or a pure-R `tibble` fallback.
#'
#' @param path Directory containing `.dcm` files, or a data frame from
#'   [read_dicom()].
#' @param db_path Path to a DuckDB database file or `":memory:"`.
#' @param parquet_dir Optional directory where `studies.parquet`,
#'   `series.parquet`, and `instances.parquet` are written when `duckdb` is used.
#' @param engine Backend engine: `"auto"` (uses `duckdb` if installed, otherwise
#'   `"tibble"`), `"duckdb"`, or `"tibble"`.
#'
#' @return A `"dicom_archive_index"` S3 object.
#' @export
dicom_index_build <- function(path,
                              db_path = ":memory:",
                              parquet_dir = NULL,
                              engine = c("auto", "duckdb", "tibble")) {
  engine <- match.arg(engine)
  raw_df <- if (is.character(path)) {
    read_dicom(path, wide = TRUE)
  } else if (is.data.frame(path)) {
    path
  } else {
    cli::cli_abort("{.arg path} must be a DICOM directory path or data.frame.")
  }

  n <- nrow(raw_df)
  if (n == 0L) {
    studies_tbl <- tibble::tibble(
      StudyInstanceUID = character(0), PatientID = character(0),
      PatientName = character(0), StudyDate = character(0),
      StudyDescription = character(0), n_series = integer(0), n_instances = integer(0)
    )
    series_tbl <- tibble::tibble(
      SeriesInstanceUID = character(0), StudyInstanceUID = character(0),
      Modality = character(0), SeriesDescription = character(0),
      BodyPartExamined = character(0), SliceThickness = numeric(0), n_instances = integer(0)
    )
    instances_tbl <- tibble::tibble(
      SOPInstanceUID = character(0), SeriesInstanceUID = character(0),
      StudyInstanceUID = character(0), InstanceNumber = integer(0), file = character(0)
    )
  } else {
    st_uids <- .idx_col(raw_df, "StudyInstanceUID", "unknown_study")
    se_uids <- .idx_col(raw_df, "SeriesInstanceUID", "unknown_series")
    sop_uids <- .idx_col(raw_df, "SOPInstanceUID", paste0("sop_", seq_len(n)))
    files_v <- .idx_col(raw_df, "file", NA_character_)
    inst_num <- suppressWarnings(as.integer(.idx_col(raw_df, "InstanceNumber", NA_character_)))

    instances_tbl <- tibble::tibble(
      SOPInstanceUID = sop_uids,
      SeriesInstanceUID = se_uids,
      StudyInstanceUID = st_uids,
      InstanceNumber = inst_num,
      file = files_v
    )

    u_se <- unique(se_uids)
    series_rows <- lapply(u_se, function(su) {
      idx <- which(se_uids == su)
      i1 <- idx[1L]
      st_num <- suppressWarnings(as.numeric(.idx_col(raw_df, "SliceThickness", NA_character_)[i1]))
      tibble::tibble(
        SeriesInstanceUID = su,
        StudyInstanceUID = st_uids[i1],
        Modality = .idx_col(raw_df, "Modality", "OT")[i1],
        SeriesDescription = .idx_col(raw_df, "SeriesDescription", "")[i1],
        BodyPartExamined = .idx_col(raw_df, "BodyPartExamined", "")[i1],
        SliceThickness = st_num,
        n_instances = as.integer(length(idx))
      )
    })
    series_tbl <- do.call(rbind, series_rows)

    u_st <- unique(st_uids)
    studies_rows <- lapply(u_st, function(su) {
      idx <- which(st_uids == su)
      i1 <- idx[1L]
      tibble::tibble(
        StudyInstanceUID = su,
        PatientID = .idx_col(raw_df, "PatientID", "")[i1],
        PatientName = .idx_col(raw_df, "PatientName", "")[i1],
        StudyDate = .idx_col(raw_df, "StudyDate", "")[i1],
        StudyDescription = .idx_col(raw_df, "StudyDescription", "")[i1],
        n_series = as.integer(length(unique(se_uids[idx]))),
        n_instances = as.integer(length(idx))
      )
    })
    studies_tbl <- do.call(rbind, studies_rows)
  }

  has_duck <- requireNamespace("duckdb", quietly = TRUE) &&
    requireNamespace("DBI", quietly = TRUE)
  use_duck <- identical(engine, "duckdb") || (identical(engine, "auto") && has_duck)

  con <- NULL
  actual_engine <- "tibble"
  if (use_duck) {
    if (!has_duck) {
      rlang::check_installed(c("DBI", "duckdb"), reason = "to build a DuckDB archive index.")
    }
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path)
    DBI::dbWriteTable(con, "studies", studies_tbl, overwrite = TRUE)
    DBI::dbWriteTable(con, "series", series_tbl, overwrite = TRUE)
    DBI::dbWriteTable(con, "instances", instances_tbl, overwrite = TRUE)

    if (!is.null(parquet_dir) && nzchar(parquet_dir)) {
      dir.create(parquet_dir, recursive = TRUE, showWarnings = FALSE)
      for (tname in c("studies", "series", "instances")) {
        pq_path <- normalizePath(file.path(parquet_dir, paste0(tname, ".parquet")), winslash = "/", mustWork = FALSE)
        DBI::dbExecute(con, sprintf("COPY %s TO '%s' (FORMAT PARQUET)", tname, gsub("'", "''", pq_path)))
      }
    }
    actual_engine <- "duckdb"
  }

  structure(
    list(
      engine = actual_engine,
      db_path = db_path,
      parquet_dir = parquet_dir,
      con = con,
      tables = list(
        studies = studies_tbl,
        series = series_tbl,
        instances = instances_tbl
      )
    ),
    class = "dicom_archive_index"
  )
}

#' Execute a Read-Only SQL Query Against a `dicom_archive_index`
#'
#' @param index A `"dicom_archive_index"` object from [dicom_index_build()].
#' @param sql A read-only `SELECT` (or `WITH ... SELECT`) SQL query string.
#' @return A [tibble::tibble] of query results.
#' @export
dicom_index_query <- function(index, sql) {
  if (!inherits(index, "dicom_archive_index")) {
    cli::cli_abort("{.arg index} must be a {.cls dicom_archive_index} object.")
  }
  if (exists("validate_readonly_sql", mode = "function")) {
    validate_readonly_sql(sql)
  }
  if (identical(index$engine, "duckdb") && !is.null(index$con)) {
    return(tibble::as_tibble(DBI::dbGetQuery(index$con, sql)))
  }
  cli::cli_abort("SQL queries require {.pkg duckdb} and {.pkg DBI} (or use {.code index$tables} in tibble mode).")
}

#' Close a `dicom_archive_index` Database Connection
#'
#' @param index A `"dicom_archive_index"` object.
#' @return Invisibly returns `TRUE`.
#' @export
dicom_index_close <- function(index) {
  if (inherits(index, "dicom_archive_index") && !is.null(index$con)) {
    try(DBI::dbDisconnect(index$con, shutdown = TRUE), silent = TRUE)
  }
  invisible(TRUE)
}
