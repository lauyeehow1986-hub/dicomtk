#' Read DICOM Metadata into a Tidy Tibble
#'
#' Reads one or more DICOM files (or directories of DICOM files) using the
#' native C++17 / DCMTK parser and returns a tidy [tibble::tibble].
#'
#' @param path Character vector of DICOM file paths or directory paths.
#' @param wide Logical. If `FALSE` (default), returns long format with one row
#'   per DICOM attribute (`file`, `tag`, `group`, `element`, `vr`, `length`,
#'   `vm`, `keyword`, `name`, `value`). If `TRUE`, pivots to wide format with
#'   one row per file and one column per DICOM `keyword`.
#' @param include_sequences Logical. If `TRUE`, recursively extracts nested
#'   sequence (`SQ`) items. Default is `FALSE`.
#' @param recursive Logical. When `path` contains directories, search
#'   subdirectories recursively. Default is `TRUE`.
#'
#' @return A [tibble::tibble] of class `c("dicom_tbl", "tbl_df", "tbl", "data.frame")`.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' hdr <- read_dicom(dcm_file)
#' hdr
#'
#' # Wide format (1 row per file)
#' read_dicom(dcm_file, wide = TRUE)
read_dicom <- function(path,
                       wide = FALSE,
                       include_sequences = FALSE,
                       recursive = TRUE) {
  files <- resolve_dicom_paths(path, recursive = recursive)

  dfs <- lapply(seq_along(files), function(i) {
    df <- cpp_read_dicom_header(
      path = files[[i]],
      include_sequences = isTRUE(include_sequences),
      stop_at_pixels = TRUE
    )
    tbl <- tibble::as_tibble(df)
    tbl$.file_idx <- i
    tbl
  })

  res <- dplyr::bind_rows(dfs)

  if (isTRUE(wide)) {
    res <- res |>
      dplyr::filter(.data$depth == 0L, nzchar(.data$keyword), .data$keyword != "PixelData") |>
      dplyr::select(".file_idx", "file", "keyword", "value") |>
      tidyr::pivot_wider(
        id_cols = c(".file_idx", "file"),
        names_from = "keyword",
        values_from = "value",
        values_fn = function(x) paste(unique(x[nzchar(x)]), collapse = "; ")
      ) |>
      dplyr::select(-".file_idx")
  } else {
    res <- dplyr::select(res, -".file_idx")
  }

  class(res) <- unique(c("dicom_tbl", class(res)))
  res
}

#' Read DICOM Header Metadata
#'
#' Reads the header elements of one or more DICOM files into a tidy tibble.
#' Compatible with both `dicomtk` tidy pipelines and legacy `dcmtk::read_dicom_header()`
#' arguments.
#'
#' @param file Character vector of DICOM file paths or directory paths.
#' @param replace_names Logical. Kept for compatibility with legacy `dcmtk`;
#'   tag names are automatically resolved against the built-in DCMTK 3.7.1
#'   dictionary.
#' @param add_opts Character vector of options (ignored in native C++ mode,
#'   kept for backward compatibility).
#' @param verbose Logical. Print progress information. Default is `FALSE`.
#' @param wide Logical. Return wide format (1 row per file). Default is `FALSE`.
#' @param ... Additional arguments passed to [read_dicom()].
#'
#' @return A [tibble::tibble] containing the parsed DICOM header elements.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' read_dicom_header(dcm_file)
read_dicom_header <- function(file,
                              replace_names = FALSE,
                              add_opts = NULL,
                              verbose = FALSE,
                              wide = FALSE,
                              ...) {
  if (isTRUE(verbose)) {
    cli::cli_alert_info("Reading DICOM header(s) from {length(file)} path(s)...")
  }
  read_dicom(path = file, wide = wide, ...)
}

#' Extract Pixel Data from a DICOM File
#'
#' Reads and decodes 8-bit, 16-bit, or 32-bit monochrome or RGB pixel data
#' (including RLE-compressed frames) directly into an R matrix or array, applying
#' Modality LUT (`RescaleSlope` and `RescaleIntercept`) when `rescale = TRUE`.
#'
#' @param path Path to a single DICOM file.
#' @param frame Integer frame number (1-indexed). Use `0` (default) to read all
#'   frames.
#' @param rescale Logical. Apply `RescaleSlope` and `RescaleIntercept` to convert
#'   stored pixel values to modality units (e.g., Hounsfield Units for CT).
#'   Default is `TRUE`.
#'
#' @return A numeric matrix `[rows, cols]` (for single-frame monochrome) or
#'   3D/4D array `[rows, cols, frames/channels]` with class `"dicom_pixels"` and
#'   DICOM imaging metadata attached as attributes.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' px <- read_dicom_pixels(dcm_file)
#' dim(px)
read_dicom_pixels <- function(path, frame = 0L, rescale = TRUE) {
  if (length(path) != 1L || !file.exists(path)) {
    rlang::abort("`path` must be a single existing DICOM file path.")
  }
  norm_path <- normalizePath(path, mustWork = TRUE)
  arr <- cpp_read_dicom_pixels(norm_path, as.integer(frame), isTRUE(rescale))
  class(arr) <- unique(c("dicom_pixels", class(arr)))
  arr
}

#' Read a Multi-Slice DICOM Series into a 3D Volume
#'
#' `r lifecycle::badge("deprecated")`
#'
#' `read_dicom_series()` was soft-deprecated in `dicomtk` 0.2.0 in favor of
#' [read_dicom_volume()], which returns a geometry-aware [`dicom_volume`][new_dicom_volume]
#' object with full multi-frame and 4D support. `read_dicom_series()` now
#' delegates slice ordering and patient-space affine reconstruction to
#' [read_dicom_volume()] so reversed or oblique slices are ordered accurately
#' by `ImagePositionPatient` projected onto the slice normal.
#'
#' @param path Directory path or character vector of DICOM file paths.
#' @param recursive Logical. Search subdirectories recursively. Default is `TRUE`.
#' @param rescale Logical. Apply `RescaleSlope` and `RescaleIntercept`. Default
#'   is `TRUE`.
#'
#' @return An object of class `"dicom_series"` (a named list with elements
#'   `volume` (`[rows, cols, slices]` numeric array), `metadata` (wide tibble of
#'   sorted slice headers), `files` (sorted file paths), `dims` (named integer
#'   vector), and `affine` (4x4 DICOM LPS voxel-to-world matrix)).
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' series <- read_dicom_series(c(dcm_file, dcm_file))
#' dim(series$volume)
read_dicom_series <- function(path, recursive = TRUE, rescale = TRUE) {
  lifecycle::deprecate_soft(
    when = "0.2.0",
    what = "read_dicom_series()",
    with = "read_dicom_volume()"
  )

  dv <- read_dicom_volume(
    path = path,
    rescale = rescale,
    recursive = recursive,
    warn = FALSE
  )

  vol <- dv$voxels
  vd <- dim(vol)
  if (length(vd) == 4L) {
    vol <- array(vol, dim = c(vd[1L], vd[2L], vd[3L] * vd[4L]))
  }
  d3 <- dim(vol)
  meta <- dv$frame_meta

  mod_attr <- if (!is.na(dv$modality) && nzchar(dv$modality)) dv$modality else "OT"
  photo_attr <- if ("PhotometricInterpretation" %in% names(meta) && nrow(meta) > 0L &&
                    !is.na(meta$PhotometricInterpretation[1L]) && nzchar(meta$PhotometricInterpretation[1L])) {
    as.character(meta$PhotometricInterpretation[1L])
  } else {
    "MONOCHROME2"
  }
  wc_num <- if ("WindowCenter" %in% names(meta) && nrow(meta) > 0L) {
    v <- vol_parse_ds(meta$WindowCenter[1L], expected_len = 1L)
    if (is.null(v)) NA_real_ else v
  } else {
    NA_real_
  }
  ww_num <- if ("WindowWidth" %in% names(meta) && nrow(meta) > 0L) {
    v <- vol_parse_ds(meta$WindowWidth[1L], expected_len = 1L)
    if (is.null(v)) NA_real_ else v
  } else {
    NA_real_
  }
  slope_num <- if ("rescale_slope" %in% names(meta) && nrow(meta) > 0L) {
    as.double(meta$rescale_slope[1L])
  } else {
    1.0
  }
  inter_num <- if ("rescale_intercept" %in% names(meta) && nrow(meta) > 0L) {
    as.double(meta$rescale_intercept[1L])
  } else {
    0.0
  }

  attr(vol, "modality") <- mod_attr
  attr(vol, "photometric") <- photo_attr
  attr(vol, "window_center") <- wc_num
  attr(vol, "window_width") <- ww_num
  attr(vol, "pixel_spacing") <- dv$spacing[1:2]
  attr(vol, "slice_thickness") <- dv$spacing[3L]
  attr(vol, "rescale_slope") <- slope_num
  attr(vol, "rescale_intercept") <- inter_num

  structure(
    list(
      volume = vol,
      metadata = meta,
      files = if ("file" %in% names(meta)) as.character(meta$file) else character(0),
      dims = c(rows = d3[1L], cols = d3[2L], slices = d3[3L]),
      affine = dv$affine
    ),
    class = "dicom_series"
  )
}
