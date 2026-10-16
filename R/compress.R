#' Compress a DICOM File (Lossless RLE)
#'
#' Compresses native uncompressed pixel data into DICOM Lossless RLE transfer
#' syntax (`1.2.840.10008.1.2.5`, per DICOM PS3.5 Annex G).
#'
#' @param path Input DICOM file path.
#' @param out_path Output compressed DICOM file path. Defaults to a temporary
#'   `.dcm` file.
#' @param method Compression method (`"rle"`).
#'
#' @return Invisibly returns `out_path`.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' rle_file <- dicom_compress(dcm_file)
#' file.exists(rle_file)
dicom_compress <- function(path,
                           out_path = tempfile(fileext = ".dcm"),
                           method = c("rle")) {
  method <- match.arg(method)
  if (length(path) != 1L || !file.exists(path)) {
    rlang::abort("`path` must be a single existing DICOM file path.")
  }
  cpp_dcm_transcode_rle(normalizePath(path, mustWork = TRUE), out_path, compress = TRUE)
  invisible(out_path)
}

#' Decompress an Encapsulated DICOM File
#'
#' Decompresses RLE-compressed (or encapsulated) DICOM files into standard
#' Explicit VR Little Endian (`1.2.840.10008.1.2.1`) uncompressed DICOM format.
#'
#' @param path Input compressed DICOM file path.
#' @param out_path Output uncompressed DICOM file path. Defaults to a temporary
#'   `.dcm` file.
#'
#' @return Invisibly returns `out_path`.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' rle_file <- dicom_compress(dcm_file)
#' dec_file <- dicom_decompress(rle_file)
#' is_dicom(dec_file)
dicom_decompress <- function(path, out_path = tempfile(fileext = ".dcm")) {
  if (length(path) != 1L || !file.exists(path)) {
    rlang::abort("`path` must be a single existing DICOM file path.")
  }
  cpp_dcm_transcode_rle(normalizePath(path, mustWork = TRUE), out_path, compress = FALSE)
  invisible(out_path)
}
