#' Convert a DICOM File to JSON (DICOM JSON Model PS3.18)
#'
#' Exports the DICOM header and dataset elements to standard DICOMWeb JSON
#' format (PS3.18).
#'
#' @param file Path to input DICOM file.
#' @param out_path Optional output `.json` file path. If `NULL` (default),
#'   returns the JSON string directly.
#'
#' @return Character string of DICOM JSON (or invisibly `out_path` if written to
#'   a file).
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' json_txt <- dcm2json(dcm_file)
#' substr(json_txt, 1, 200)
dcm2json <- function(file, out_path = NULL) {
  if (length(file) != 1L || !file.exists(file)) {
    rlang::abort("`file` must be a single existing DICOM file path.")
  }
  json_str <- cpp_dcm_to_json(normalizePath(file, mustWork = TRUE))
  if (!is.null(out_path)) {
    writeLines(json_str, out_path, useBytes = TRUE)
    return(invisible(out_path))
  }
  json_str
}

#' Read Radiation Therapy (RT) DICOM Objects (`dcmrt`)
#'
#' Reads DICOM Radiation Therapy objects (`RTPLAN`, `RTDOSE`, `RTSTRUCT`,
#' `RTIMAGE`), extracting group `0x3002`, `0x3004`, `0x3006`, `0x3008`, `0x300A`,
#' and `0x300C` elements and nested sequences into a tidy [tibble::tibble], along
#' with dose grids if pixel data is present (`RTDOSE`).
#'
#' @param path Path to a DICOM RT file.
#'
#' @return A list of class `"dicom_rt"` containing `modality`, `summary` (tidy
#'   tibble of top-level RT attributes), `rt_elements` (full hierarchical RT
#'   sequence tibble), and `dose_grid` (3D dose array if `Modality == "RTDOSE"`).
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' rt_info <- read_dicom_rt(dcm_file)
#' rt_info$modality
read_dicom_rt <- function(path) {
  hdr <- read_dicom(path, include_sequences = TRUE)
  mod <- dicom_tag_value(path, "Modality")[["Modality"]]
  rt_groups <- c("3002", "3004", "3006", "3008", "300A", "300C")
  rt_elems <- hdr[hdr$group %in% rt_groups | hdr$depth > 0L, , drop = FALSE]
  top_summary <- hdr[hdr$depth == 0L, , drop = FALSE]

  dose_grid <- NULL
  if (identical(mod, "RTDOSE") || any(hdr$tag == "(7FE0,0010)")) {
    dose_grid <- tryCatch(read_dicom_pixels(path, rescale = TRUE), error = function(e) NULL)
    scaling <- suppressWarnings(as.numeric(dicom_tag_value(path, "(3004,000E)")[[1L]]))
    if (!is.null(dose_grid) && !is.na(scaling) && scaling > 0) {
      dose_grid <- dose_grid * scaling
    }
  }

  structure(
    list(
      modality = mod,
      summary = top_summary,
      rt_elements = rt_elems,
      dose_grid = dose_grid
    ),
    class = "dicom_rt"
  )
}

#' Read DICOM Segmentation Objects (`dcmseg`)
#'
#' Reads a DICOM Segmentation (`SEG`) dataset, extracting segment descriptions
#' (`SegmentSequence (0062,0002)`) and the binary/fractional 3D segmentation
#' mask array.
#'
#' @param path Path to a DICOM Segmentation file.
#'
#' @return A list of class `"dicom_seg"` containing `segments` (tibble of
#'   segment metadata) and `mask` (pixel/voxel mask array).
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' seg <- read_dicom_seg(dcm_file)
#' dim(seg$mask)
read_dicom_seg <- function(path) {
  hdr <- read_dicom(path, include_sequences = TRUE)
  seg_rows <- hdr[hdr$group == "0062" | grepl("0062,0002", hdr$sequence_path, fixed = TRUE), , drop = FALSE]
  mask <- tryCatch(read_dicom_pixels(path, rescale = FALSE), error = function(e) NULL)
  structure(
    list(
      segments = seg_rows,
      mask = mask,
      header = hdr[hdr$depth == 0L, , drop = FALSE]
    ),
    class = "dicom_seg"
  )
}

#' Read DICOM Parametric Map Objects (`dcmpmap`)
#'
#' Reads a DICOM Parametric Map (`PMAP`) dataset and applies `RealWorldValueSlope`
#' and `RealWorldValueIntercept` transformations.
#'
#' @param path Path to a DICOM Parametric Map file.
#'
#' @return A list of class `"dicom_pmap"` containing `values` (real-world mapped
#'   numeric array) and `metadata` (tibble of header tags).
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' pmap <- read_dicom_pmap(dcm_file)
#' dim(pmap$values)
read_dicom_pmap <- function(path) {
  hdr <- read_dicom(path, include_sequences = TRUE)
  px <- tryCatch(read_dicom_pixels(path, rescale = TRUE), error = function(e) NULL)
  structure(
    list(
      values = px,
      metadata = hdr
    ),
    class = "dicom_pmap"
  )
}

#' Read DICOM Tractography Results (`dcmtract`) and Enhanced Multi-Frame IODs (`dcmect` / `dcmfg`)
#'
#' Extracts functional groups (`SharedFunctionalGroupsSequence (5200,9229)`,
#' `PerFrameFunctionalGroupsSequence (5200,9230)`) and tractography sequences
#' (`TrackSetSequence (0066,0101)`) into a tidy [tibble::tibble].
#'
#' @param path Path to a DICOM Enhanced CT or Tractography file.
#'
#' @return A [tibble::tibble] of functional group and tractography elements.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' read_dicom_ect(dcm_file)
read_dicom_ect <- function(path) {
  read_dicom(path, include_sequences = TRUE)
}

#' Inspect Digital Signatures in a DICOM File (`dcmsign`)
#'
#' Checks whether a DICOM dataset contains digital signatures in
#' `DigitalSignaturesSequence (FFFA,FFFA)` or `MACParametersSequence (4FFE,0001)`
#' and returns a tidy summary tibble.
#'
#' @param path Path to a DICOM file.
#'
#' @return A [tibble::tibble] of signature elements (0 rows if unsigned).
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' dicom_verify_signature(dcm_file)
dicom_verify_signature <- function(path) {
  hdr <- read_dicom(path, include_sequences = TRUE)
  hdr[hdr$group %in% c("4FFE", "FFFA") |
        grepl("FFFA,FFFA|4FFE,0001", hdr$sequence_path), , drop = FALSE]
}

#' Read DICOM Tractography Results (`dcmtract`)
#'
#' Reads a DICOM Tractography Results (`1.2.840.10008.5.1.4.1.1.66.6`) dataset,
#' extracting `TrackSetSequence (0066,0101)` and streamline metadata into a tidy
#' [tibble::tibble].
#'
#' @param path Path to a DICOM Tractography file.
#'
#' @return A list of class `"dicom_tract"` containing `track_sets` (tibble of
#'   group `0x0066` elements) and `header` (top-level metadata tibble).
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' tr <- read_dicom_tract(dcm_file)
#' tr
read_dicom_tract <- function(path) {
  hdr <- read_dicom(path, include_sequences = TRUE)
  tract_rows <- hdr[hdr$group == "0066" | grepl("0066,0101", hdr$sequence_path, fixed = TRUE), , drop = FALSE]
  structure(
    list(
      track_sets = tract_rows,
      header = hdr[hdr$depth == 0L, , drop = FALSE]
    ),
    class = "dicom_tract"
  )
}

#' Read DICOM Grayscale Softcopy Presentation State (`dcmpstat`)
#'
#' Extracts display shutter, VOI LUT, graphic annotation (`0x0070`), and spatial
#' transformation parameters from a DICOM Presentation State (`PR`) object.
#'
#' @param path Path to a DICOM Presentation State file.
#'
#' @return A list of class `"dicom_pstate"` containing `annotations` (group
#'   `0x0070` elements), `voi_lut` (window/LUT attributes), and `header`.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' ps <- read_dicom_pstate(dcm_file)
#' ps
read_dicom_pstate <- function(path) {
  hdr <- read_dicom(path, include_sequences = TRUE)
  structure(
    list(
      annotations = hdr[hdr$group == "0070", , drop = FALSE],
      voi_lut = hdr[hdr$tag %in% c("(0028,1050)", "(0028,1051)", "(0028,1052)", "(0028,1053)", "(0028,3010)"), , drop = FALSE],
      header = hdr[hdr$depth == 0L, , drop = FALSE]
    ),
    class = "dicom_pstate"
  )
}

#' Build or Query a Local DICOM Query/Retrieve Index Database (`dcmqrdb`)
#'
#' Scans a directory of DICOM files and builds a tidy index table organized by
#' Patient, Study, Series, and Instance UIDs (`dcmqrdb` model).
#'
#' @param directory Path to a directory containing DICOM files.
#' @param recursive Logical. Scan subdirectories recursively. Default is `TRUE`.
#'
#' @return A [tibble::tibble] with columns `file`, `PatientID`, `PatientName`,
#'   `StudyInstanceUID`, `StudyDate`, `Modality`, `SeriesInstanceUID`,
#'   `SOPInstanceUID`, `Rows`, and `Columns`.
#' @export
#' @examples
#' ext_dir <- system.file("extdata", package = "dicomtk")
#' dicom_qrdb_index(ext_dir)
dicom_qrdb_index <- function(directory, recursive = TRUE) {
  wide <- read_dicom(directory, wide = TRUE, recursive = recursive)
  key_cols <- c(
    "file", "PatientID", "PatientName", "StudyInstanceUID", "StudyDate",
    "Modality", "SeriesInstanceUID", "SOPInstanceUID", "Rows", "Columns"
  )
  for (col in key_cols) {
    if (!col %in% names(wide)) {
      wide[[col]] <- NA_character_
    }
  }
  wide[, c(key_cols, setdiff(names(wide), key_cols)), drop = FALSE]
}

#' Query or Create Modality Worklist Entries (`dcmwlm`)
#'
#' Reads or constructs a tidy Modality Worklist (`MWL`) schedule table containing
#' `ScheduledProcedureStepSequence (0040,0100)` attributes (`Modality`,
#' `ScheduledStationAETitle`, `ScheduledProcedureStepStartDate`, `PatientName`,
#' `PatientID`, `AccessionNumber`).
#'
#' @param path Optional path to a DICOM worklist `.dcm`/`.wl` file or directory.
#'   If `NULL`, returns an empty template worklist tibble.
#'
#' @return A [tibble::tibble] representing Modality Worklist scheduled items.
#' @export
#' @examples
#' dicom_worklist()
dicom_worklist <- function(path = NULL) {
  if (is.null(path)) {
    return(tibble::tibble(
      AccessionNumber = character(),
      PatientID = character(),
      PatientName = character(),
      Modality = character(),
      ScheduledStationAETitle = character(),
      ScheduledProcedureStepStartDate = character(),
      ScheduledProcedureStepDescription = character()
    ))
  }
  read_dicom(path, wide = TRUE, include_sequences = TRUE)
}

#' Configure DICOM TLS Transport Security Parameters (`dcmtls`)
#'
#' Attaches TLS certificate, private key, and CA bundle paths to a
#' `"dicom_connection"` object for secure DICOM-over-TLS communication (RFC 3240 /
#' DICOM PS3.15).
#'
#' @param conn A `"dicom_connection"` object created by [dicom_connect()].
#' @param cert_file Optional path to client X.509 PEM certificate.
#' @param key_file Optional path to client private key.
#' @param ca_file Optional path to trusted CA certificate bundle.
#' @param profile DICOM TLS security profile (`"BCP195"`, `"BCP195-ND"`, or
#'   `"AES"`). Default is `"BCP195"`.
#'
#' @return Updated `"dicom_connection"` object with TLS settings enabled.
#' @export
#' @examples
#' conn <- dicom_connect("pacs.hospital.org", port = 2762) |>
#'   dicom_tls_config(profile = "BCP195")
#' conn
dicom_tls_config <- function(conn,
                             cert_file = NULL,
                             key_file = NULL,
                             ca_file = NULL,
                             profile = c("BCP195", "BCP195-ND", "AES")) {
  if (!inherits(conn, "dicom_connection")) {
    rlang::abort("`conn` must be a `dicom_connection` object from `dicom_connect()`.")
  }
  profile <- match.arg(profile)
  conn$tls <- list(
    enabled = TRUE,
    profile = profile,
    cert_file = cert_file,
    key_file = key_file,
    ca_file = ca_file
  )
  conn
}

#' @export
print.dicom_series <- function(x, ...) {
  cli::cli_alert_info(
    "DICOM Series: {x$dims[['rows']]} x {x$dims[['cols']]} x {x$dims[['slices']]} slices ({length(x$files)} files)"
  )
  invisible(x)
}

#' @export
print.dicom_rt <- function(x, ...) {
  cli::cli_alert_info(
    "DICOM RT Object (Modality: {x$modality %||% 'RT'}, RT Elements: {nrow(x$rt_elements)})"
  )
  invisible(x)
}

#' @export
print.dicom_seg <- function(x, ...) {
  cli::cli_alert_info(
    "DICOM Segmentation Object (Segment rows: {nrow(x$segments)}, Mask dims: {paste(dim(x$mask), collapse = 'x')})"
  )
  invisible(x)
}

#' @export
print.dicom_pmap <- function(x, ...) {
  cli::cli_alert_info(
    "DICOM Parametric Map (Dims: {paste(dim(x$values), collapse = 'x')})"
  )
  invisible(x)
}

#' @export
print.dicom_tract <- function(x, ...) {
  cli::cli_alert_info(
    "DICOM Tractography Object (Track Set elements: {nrow(x$track_sets)})"
  )
  invisible(x)
}

#' @export
print.dicom_pstate <- function(x, ...) {
  cli::cli_alert_info(
    "DICOM Presentation State (Annotations: {nrow(x$annotations)}, VOI LUT entries: {nrow(x$voi_lut)})"
  )
  invisible(x)
}
