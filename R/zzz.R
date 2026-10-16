.onLoad <- function(libname, pkgname) {
  cpp_dcmtk_init()
}

.onUnload <- function(libpath) {
  cpp_dcmtk_cleanup()
  library.dynam.unload("dicomtk", libpath)
}

#' Check DCMTK Backend Availability and Version
#'
#' Returns `TRUE` if the bundled DCMTK C++ engine and data dictionary are
#' initialized and ready.
#'
#' @return A logical scalar (`TRUE`).
#' @export
#' @examples
#' have_dcmtk()
have_dcmtk <- function() {
  info <- cpp_dcmtk_version()
  isTRUE(info$codecs_registered)
}

#' Inspect Bundled DCMTK Configuration and Version Info
#'
#' Returns a tidy tibble describing the bundled DCMTK version, data dictionary
#' edition, number of standard tags, and active C++ backend.
#'
#' @return A [tibble::tibble] with DCMTK configuration details.
#' @export
#' @examples
#' dicom_info()
dicom_info <- function() {
  info <- cpp_dcmtk_version()
  tibble::tibble(
    dcmtk_version = info$dcmtk_version,
    dictionary_standard = info$dictionary_standard,
    dictionary_entries = info$dictionary_entries,
    backend = info$backend,
    codecs_registered = info$codecs_registered
  )
}
