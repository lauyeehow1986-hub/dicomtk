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
