#' Check Whether File(s) Are Valid DICOM Files
#'
#' Inspects the file header for the standard 128-byte preamble + `"DICM"` magic
#' bytes or valid initial DICOM group/element tags.
#'
#' @param path Character vector of file paths.
#' @return A logical vector of the same length as `path`.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' is_dicom(dcm_file)
is_dicom <- function(path) {
  if (length(path) == 0) return(logical(0))
  vapply(path, function(p) {
    if (is.na(p) || !file.exists(p) || dir.exists(p)) return(FALSE)
    tryCatch(cpp_is_dicom(normalizePath(p, mustWork = TRUE)), error = function(e) FALSE)
  }, logical(1), USE.NAMES = FALSE)
}

# Internal helper to resolve files from a path or directory
resolve_dicom_paths <- function(path, recursive = TRUE) {
  if (missing(path) || length(path) == 0) {
    rlang::abort("`path` must be a non-empty character vector of file or directory paths.")
  }
  out <- character(0)
  for (p in path) {
    if (!file.exists(p)) {
      rlang::abort(paste0("Path does not exist: ", p))
    }
    if (dir.exists(p)) {
      candidates <- list.files(p, full.names = TRUE, recursive = recursive)
      candidates <- candidates[!dir.exists(candidates)]
      valid <- candidates[is_dicom(candidates)]
      out <- c(out, valid)
    } else {
      out <- c(out, normalizePath(p, mustWork = TRUE))
    }
  }
  if (length(out) == 0) {
    rlang::abort("No valid DICOM files found in the specified `path`.")
  }
  out
}

# Base64 encoder for raw bytes (used by LLM vision APIs without extra deps)
base64_encode_raw <- function(raw_bytes) {
  alphabet <- c(LETTERS, letters, 0:9, "+", "/")
  n <- length(raw_bytes)
  if (n == 0) return("")
  ints <- as.integer(raw_bytes)
  rem <- n %% 3L
  if (rem > 0L) {
    ints <- c(ints, rep(0L, 3L - rem))
  }
  m <- matrix(ints, nrow = 3L)
  b1 <- m[1L, ]
  b2 <- m[2L, ]
  b3 <- m[3L, ]

  c1 <- bitwShiftR(b1, 2L) + 1L
  c2 <- bitwOr(bitwShiftL(bitwAnd(b1, 3L), 4L), bitwShiftR(b2, 4L)) + 1L
  c3 <- bitwOr(bitwShiftL(bitwAnd(b2, 15L), 2L), bitwShiftR(b3, 6L)) + 1L
  c4 <- bitwAnd(b3, 63L) + 1L

  chars <- rbind(alphabet[c1], alphabet[c2], alphabet[c3], alphabet[c4])
  if (rem == 1L) {
    chars[3L, ncol(chars)] <- "="
    chars[4L, ncol(chars)] <- "="
  } else if (rem == 2L) {
    chars[4L, ncol(chars)] <- "="
  }
  paste(as.character(chars), collapse = "")
}

#' Check or Synchronize with Upstream OFFIS DCMTK Repository
#'
#' Checks the official upstream DCMTK GitHub mirror
#' (`https://github.com/DCMTK/dcmtk`) for new commits, dictionary releases, or
#' C++ module header updates, and optionally synchronizes a local `dicomtk`
#' source checkout by running `tools/bundle_dcmtk.R`.
#'
#' @param pkg_dir Optional path to a local `dicomtk` package source directory
#'   when `apply = TRUE`. Defaults to `"."`.
#' @param apply Logical; if `TRUE`, clones the latest `DCMTK/dcmtk` `master`
#'   branch and executes `tools/bundle_dcmtk.R` inside `pkg_dir`. Default is
#'   `FALSE` (check-only mode).
#' @param repo GitHub repository slug. Default is `"DCMTK/dcmtk"`.
#'
#' @return A [tibble::tibble] summarizing the bundled DCMTK version/commit,
#'   the latest upstream commit SHA/date/message from GitHub, and whether the
#'   bundle is up to date.
#' @export
#' @examples
#' \donttest{
#' dicom_sync_upstream(apply = FALSE)
#' }
dicom_sync_upstream <- function(pkg_dir = ".", apply = FALSE, repo = "DCMTK/dcmtk") {
  meta_file <- system.file("extdata", "dcmtk_upstream_version.txt", package = "dicomtk")
  bundled_ver <- "3.7.1"
  bundled_sha <- "unknown"
  if (nzchar(meta_file) && file.exists(meta_file)) {
    lines <- readLines(meta_file, warn = FALSE)
    ver_line <- grep("^version=", lines, value = TRUE)
    sha_line <- grep("^commit=", lines, value = TRUE)
    if (length(ver_line) > 0) bundled_ver <- sub("^version=", "", ver_line[1L])
    if (length(sha_line) > 0) bundled_sha <- sub("^commit=", "", sha_line[1L])
  }

  api_url <- sprintf("https://api.github.com/repos/%s/commits/master", repo)
  upstream_info <- tryCatch({
    req <- httr2::request(api_url) |>
      httr2::req_headers(Accept = "application/vnd.github+json") |>
      httr2::req_timeout(10)
    resp <- httr2::req_perform(req)
    body <- httr2::resp_body_json(resp)
    list(
      sha = as.character(body$sha %||% "unknown"),
      date = as.character(body$commit$committer$date %||% NA_character_),
      message = strsplit(as.character(body$commit$message %||% ""), "\n")[[1L]][1L]
    )
  }, error = function(e) {
    list(sha = "offline", date = NA_character_, message = conditionMessage(e))
  })

  up_to_date <- identical(bundled_sha, upstream_info$sha) && bundled_sha != "unknown"

  if (isTRUE(apply)) {
    bundle_script <- file.path(pkg_dir, "tools", "bundle_dcmtk.R")
    if (!file.exists(bundle_script)) {
      rlang::abort(paste0("Cannot find `tools/bundle_dcmtk.R` in `pkg_dir`: ", pkg_dir))
    }
    tmp_clone <- file.path(tempdir(), "dcmtk_upstream_sync")
    unlink(tmp_clone, recursive = TRUE)
    clone_url <- sprintf("https://github.com/%s.git", repo)
    cli::cli_alert_info("Cloning latest {.url {clone_url}}...")
    status <- system2("git", c("clone", "--depth", "1", clone_url, shQuote(tmp_clone)))
    if (status != 0L) {
      rlang::abort("`git clone` failed when fetching upstream DCMTK.")
    }
    old_wd <- setwd(pkg_dir)
    on.exit(setwd(old_wd), add = TRUE)
    sys_r <- file.path(R.home("bin"), "Rscript")
    system2(sys_r, c(shQuote(bundle_script), shQuote(tmp_clone)))
    up_to_date <- TRUE
    bundled_sha <- upstream_info$sha
  }

  tibble::tibble(
    bundled_version = bundled_ver,
    bundled_commit = substr(bundled_sha, 1L, 12L),
    upstream_commit = substr(upstream_info$sha, 1L, 12L),
    upstream_date = upstream_info$date,
    upstream_message = upstream_info$message,
    up_to_date = up_to_date
  )
}

