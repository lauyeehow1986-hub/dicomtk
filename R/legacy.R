#' Legacy Compatibility Functions from `dcmtk`
#'
#' Backward-compatible wrappers for functions in the original `dcmtk` R package
#' (`dcmdump`, `dcmdump_full`, `dcmhd`, `wide_hdr`, `burned_annot`, `dcmodify`,
#' `dcm_anon`, `dcm_subtract_date`, `dcmj2pnm`, `dcmdjpeg`, `dcmdrle`,
#' `dcmcrle`, `check_dcmtk_cmd`), now powered by the native `dicomtk` C++17
#' engine without requiring external CLI binaries.
#'
#' @param file Path to DICOM file(s).
#' @param outfile Optional output file path.
#' @param opts Optional command-line style options (ignored in native C++ mode).
#' @param ... Additional arguments passed to modern `dicomtk` equivalents.
#'
#' @return
#' Return values depend on the specific legacy wrapper function called:
#' \describe{
#'   \item{`dcmdump`}{Character vector formatted similarly to CLI `dcmdump` output
#'     with tag, VR, value, length, VM, and keyword.}
#'   \item{`dcmdump_full`}{A [tibble::tibble] containing full header and nested
#'     sequence items as returned by [read_dicom()].}
#'   \item{`dcmhd`}{A [tibble::tibble] containing the top-level DICOM header elements.}
#'   \item{`wide_hdr`}{A wide [tibble::tibble] with one row per file and columns
#'     corresponding to DICOM element keywords.}
#'   \item{`burned_annot`}{Character scalar value of the `BurnedInAnnotation (0028,0301)` tag.}
#'   \item{`dcmodify`}{Character vector of modified DICOM file paths as returned
#'     by [dicom_modify()].}
#'   \item{`dcm_anon`, `dcm_subtract_date`}{Character vector of anonymized DICOM
#'     file paths as returned by [dicom_anonymize()].}
#'   \item{`dcmj2pnm`}{Character path to the rendered output PNG file as returned
#'     by [dicom_to_png()].}
#'   \item{`dcmdjpeg`, `dcmdrle`}{Character path to the decompressed DICOM file
#'     as returned by [dicom_decompress()].}
#'   \item{`dcmcrle`}{Character path to the compressed DICOM file as returned
#'     by [dicom_compress()].}
#'   \item{`check_dcmtk_cmd`}{Logical `TRUE` indicating the native DCMTK engine
#'     is available.}
#' }
#' @name legacy-dcmtk
#' @aliases legacy-dcmtk dcmdump dcmdump_full dcmhd wide_hdr burned_annot dcmodify dcm_anon dcm_subtract_date dcmj2pnm dcmdjpeg dcmdrle dcmcrle check_dcmtk_cmd
NULL

#' @rdname legacy-dcmtk
#' @export
dcmdump <- function(file, ...) {
  hdr <- read_dicom(file)
  sprintf("%s %s [%s] # %d, %s %s",
          hdr$tag, hdr$vr, hdr$value, hdr$length, hdr$vm, hdr$keyword)
}

#' @rdname legacy-dcmtk
#' @export
dcmdump_full <- function(file, ...) {
  read_dicom(file, include_sequences = TRUE)
}

#' @rdname legacy-dcmtk
#' @export
dcmhd <- function(file, ...) {
  read_dicom_header(file = file, ...)
}

#' @rdname legacy-dcmtk
#' @param hdr A header data frame or tibble returned by [read_dicom_header()].
#' @export
wide_hdr <- function(hdr, ...) {
  if (is.character(hdr)) {
    return(read_dicom(hdr, wide = TRUE))
  }
  name_col <- if ("keyword" %in% names(hdr)) "keyword" else "name"
  hdr |>
    dplyr::filter(!is.na(.data[[name_col]]), nzchar(.data[[name_col]])) |>
    dplyr::select("file", dplyr::all_of(name_col), "value") |>
    tidyr::pivot_wider(
      id_cols = "file",
      names_from = dplyr::all_of(name_col),
      values_from = "value",
      values_fn = function(x) paste(unique(x[nzchar(x)]), collapse = "; ")
    )
}

#' @rdname legacy-dcmtk
#' @export
burned_annot <- function(file, ...) {
  unname(dicom_tag_value(file, "(0028,0301)"))
}

#' @rdname legacy-dcmtk
#' @param tags Named list of tags and values to modify.
#' @export
dcmodify <- function(file, tags = list(), outfile = file, ...) {
  dicom_modify(path = file, tags = tags, out_path = outfile, ...)
}

#' @rdname legacy-dcmtk
#' @export
dcm_anon <- function(file, outfile = NULL, ...) {
  dicom_anonymize(path = file, out_path = outfile, ...)
}

#' @rdname legacy-dcmtk
#' @param shift_days Integer number of days to shift dates (default `-365L`).
#' @export
dcm_subtract_date <- function(file, outfile = NULL, shift_days = -365L, ...) {
  dicom_anonymize(path = file, out_path = outfile, shift_days = shift_days, ...)
}

#' @rdname legacy-dcmtk
#' @export
dcmj2pnm <- function(file, outfile = tempfile(fileext = ".png"), opts = "--write-png", ...) {
  dicom_to_png(path = file, out_path = outfile, ...)
}

#' @rdname legacy-dcmtk
#' @export
dcmdjpeg <- function(file, outfile = tempfile(fileext = ".dcm"), ...) {
  dicom_decompress(path = file, out_path = outfile)
}

#' @rdname legacy-dcmtk
#' @export
dcmdrle <- function(file, outfile = tempfile(fileext = ".dcm"), ...) {
  dicom_decompress(path = file, out_path = outfile)
}

#' @rdname legacy-dcmtk
#' @export
dcmcrle <- function(file, outfile = tempfile(fileext = ".dcm"), ...) {
  dicom_compress(path = file, out_path = outfile, method = "rle")
}

#' @rdname legacy-dcmtk
#' @param cmd Command name.
#' @export
check_dcmtk_cmd <- function(cmd = "dcmdump") {
  have_dcmtk()
}
