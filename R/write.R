#' Write a Matrix, Array, or DICOM Series to a DICOM File
#'
#' Creates a standard DICOM Part 10 Explicit VR Little Endian file from an R
#' 2D matrix or 3D array of pixel values and an optional named list or character
#' vector of DICOM metadata tags.
#'
#' @param x A numeric 2D matrix `[rows, cols]`, 3D array `[rows, cols, frames]`,
#'   or `"dicom_pixels"` object.
#' @param path Output file path for the written `.dcm` file.
#' @param metadata Named list or named character vector of DICOM tags/keywords
#'   and values (e.g., `list(PatientName = "DOE^JOHN", Modality = "CT")`).
#'
#' @return Invisibly returns the normalized output `path`.
#' @export
#' @examples
#' mat <- matrix(seq(0, 255), nrow = 16, ncol = 16)
#' out <- tempfile(fileext = ".dcm")
#' write_dicom(mat, out, metadata = list(PatientName = "TEST^PATIENT", Modality = "CT"))
#' read_dicom(out, wide = TRUE)
write_dicom <- function(x, path, metadata = list()) {
  if (inherits(x, "dicom_series")) {
    x <- x$volume
  }
  if (!is.numeric(x) || length(dim(x)) < 2L) {
    rlang::abort("`x` must be a 2D numeric matrix or 3D numeric array of pixel values.")
  }

  meta_tags <- character(0)
  meta_vals <- character(0)
  if (length(metadata) > 0) {
    if (is.null(names(metadata)) || any(!nzchar(names(metadata)))) {
      rlang::abort("`metadata` must be a named list or named character vector.")
    }
    meta_tags <- names(metadata)
    meta_vals <- vapply(metadata, as.character, character(1))
  }

  ok <- cpp_write_dicom_matrix(
    pixels = as.double(x) |> structure(dim = dim(x)),
    out_path = path,
    meta_tags = meta_tags,
    meta_values = meta_vals
  )
  if (!isTRUE(ok)) {
    rlang::abort(paste0("Failed to write DICOM file to: ", path))
  }
  invisible(normalizePath(path, mustWork = FALSE))
}
