#' Export a DICOM Image Slice to PNG
#'
#' Renders a DICOM slice with window/level transformation to a PNG image file.
#'
#' @param path Path to a DICOM file, or a `"dicom_pixels"` matrix/array.
#' @param out_path Output PNG file path. Defaults to a temporary `.png` file.
#' @param frame Integer frame/slice index (1-based). Default is `1L`.
#' @param window Window preset name (e.g., `"auto"`, `"brain"`, `"lung"`,
#'   `"bone"`, `"abdomen"`) or numeric `c(center, width)`. Default is `"auto"`.
#' @param width,height Output PNG dimensions in pixels. Defaults to the native
#'   DICOM image dimensions.
#'
#' @return Invisibly returns `out_path`.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' png_file <- dicom_to_png(dcm_file)
#' file.exists(png_file)
#' unlink(png_file)
dicom_to_png <- function(path,
                         out_path = tempfile(fileext = ".png"),
                         frame = 1L,
                         window = "auto",
                         width = NULL,
                         height = NULL) {
  px <- if (is.character(path)) {
    read_dicom_pixels(path, frame = frame, rescale = TRUE)
  } else {
    path
  }

  win_px <- dicom_window(px, preset = window)
  dims <- dim(win_px)
  rows <- dims[1L]
  cols <- dims[2L]

  if (is.null(width)) width <- cols
  if (is.null(height)) height <- rows

  grDevices::png(filename = out_path, width = width, height = height, bg = "black")
  on.exit(grDevices::dev.off(), add = TRUE)
  oldpar <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(oldpar), add = TRUE)
  graphics::par(mar = c(0, 0, 0, 0), oma = c(0, 0, 0, 0))

  if (length(dims) == 3L && dims[3L] == 3L) {
    ras <- grDevices::as.raster(win_px)
  } else {
    mat <- if (length(dims) >= 3L) win_px[, , 1L] else win_px
    ras <- grDevices::as.raster(mat)
  }
  graphics::plot(ras, interpolate = FALSE)
  invisible(out_path)
}

#' Convert DICOM File(s) or Series to NIfTI-1 Format
#'
#' Converts a single DICOM file, vector of DICOM files, directory of DICOM
#' slices, or `"dicom_series"` object into a standard NIfTI-1 (`.nii` or
#' `.nii.gz`) volumetric file. Uses `RNifti` when installed or a built-in
#' native NIfTI-1 binary writer with zero external dependencies.
#'
#' @param path Path to a DICOM file, directory, vector of files, or a
#'   `"dicom_series"` object.
#' @param out_path Output `.nii` (or `.nii.gz`) path. If `NULL`, creates a
#'   temporary `.nii` file.
#'
#' @return Invisibly returns `out_path`.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' nii_file <- dicom_to_nifti(dcm_file)
#' file.exists(nii_file)
#' unlink(nii_file)
dicom_to_nifti <- function(path, out_path = NULL) {
  write_nifti(path, out_path = out_path, json_sidecar = FALSE)
}

#' Convert a DICOM File to XML (Native DICOM Model PS3.19)
#'
#' Exports the DICOM header and dataset elements to XML format.
#'
#' @param file Path to input DICOM file.
#' @param out_path Optional output `.xml` file path. If `NULL` (default), writes
#'   to a temporary `.xml` file and returns its path (with the XML string
#'   attached as attribute `"xml"`).
#' @param opts Optional arguments (ignored in native C++ mode, kept for legacy
#'   compatibility).
#' @param ... Additional unused arguments.
#'
#' @return Character string of the output `.xml` file path.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' xml_file <- dcm2xml(dcm_file)
#' head(readLines(xml_file), 10)
#' unlink(xml_file)
dcm2xml <- function(file, out_path = NULL, opts = "", ...) {
  if (length(file) != 1L || !file.exists(file)) {
    rlang::abort("`file` must be a single existing DICOM file path.")
  }
  xml_str <- cpp_dcm_to_xml(normalizePath(file, mustWork = TRUE))
  if (is.null(out_path)) {
    out_path <- tempfile(fileext = ".xml")
  }
  writeLines(xml_str, out_path, useBytes = TRUE)
  attr(out_path, "xml") <- xml_str
  out_path
}

#' Extract Encapsulated PDF from a DICOM File
#'
#' Extracts the binary PDF document stored in tag `(0042,0011) EncapsulatedDocument`.
#'
#' @param file Path to an Encapsulated PDF DICOM file.
#' @param out_path Output `.pdf` path. Defaults to a temporary `.pdf` file.
#' @param opts Optional arguments (kept for legacy compatibility).
#' @param ... Additional unused arguments.
#'
#' @return Character string of the output `.pdf` file path.
#' @export
dcm2pdf <- function(file, out_path = tempfile(fileext = ".pdf"), opts = "", ...) {
  if (length(file) != 1L || !file.exists(file)) {
    rlang::abort("`file` must be a single existing DICOM file path.")
  }
  cpp_dcm_extract_pdf(normalizePath(file, mustWork = TRUE), out_path)
  out_path
}
