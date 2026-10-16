#' Read a DICOM Structured Report (SR) or Advanced IOD
#'
#' Parses a DICOM Structured Report (`dcmsr`) or hierarchical DICOM dataset
#' (including RT Plan/Dose/Structure Set, Segmentation, Parametric Map, and
#' Tractography objects) into a tidy [tibble::tibble] preserving sequence
#' hierarchy (`depth` and `sequence_path`).
#'
#' @param path Path to a DICOM Structured Report (`.dcm`) file.
#'
#' @return A [tibble::tibble] with columns `depth`, `sequence_path`, `tag`,
#'   `keyword`, `vr`, and `value`.
#' @export
#' @examples
#' sr_file <- tempfile(fileext = ".dcm")
#' create_dicom_sr(
#'   sr_file,
#'   title = "Chest CT Report",
#'   text = "No acute cardiopulmonary abnormality."
#' )
#' read_dicom_sr(sr_file)
read_dicom_sr <- function(path) {
  if (length(path) != 1L || !file.exists(path)) {
    rlang::abort("`path` must be a single existing DICOM file path.")
  }
  df <- cpp_read_dicom_sr(normalizePath(path, mustWork = TRUE))
  tibble::as_tibble(df)
}

#' Create a DICOM Basic Text Structured Report (SR)
#'
#' Writes a valid DICOM Basic Text SR Storage (`1.2.840.10008.5.1.4.1.1.88.11`)
#' Part 10 file containing a structured report title, text content, and patient
#'/study identifiers.
#'
#' @param out_path Output `.dcm` file path.
#' @param title Document / Series title (`SeriesDescription (0008,103E)`).
#' @param text Report body text (`TextValue (0040,A160)`).
#' @param patient_name Patient name (`(0010,0010)`). Default is `"ANONYMOUS"`.
#' @param patient_id Patient ID (`(0010,0020)`). Default is `"ANON001"`.
#' @param study_uid Optional `StudyInstanceUID` to link the report to an
#'   existing study. If `""`, generates a new UID.
#'
#' @return Invisibly returns `out_path`.
#' @export
#' @examples
#' sr_file <- tempfile(fileext = ".dcm")
#' create_dicom_sr(
#'   sr_file,
#'   title = "AI Radiology Summary",
#'   text = "FINDINGS: Unremarkable brain parenchyma. IMPRESSION: Normal head CT."
#' )
#' read_dicom_sr(sr_file)
create_dicom_sr <- function(out_path,
                            title = "Radiology Structured Report",
                            text,
                            patient_name = "ANONYMOUS",
                            patient_id = "ANON001",
                            study_uid = "") {
  if (missing(text) || !is.character(text) || length(text) == 0L) {
    rlang::abort("`text` must be a non-empty character string.")
  }
  ok <- cpp_create_dicom_sr(
    out_path = out_path,
    title = as.character(title)[1L],
    text_content = paste(text, collapse = "\n"),
    patient_name = as.character(patient_name)[1L],
    patient_id = as.character(patient_id)[1L],
    study_uid = as.character(study_uid)[1L]
  )
  if (!isTRUE(ok)) {
    rlang::abort(paste0("Failed to create DICOM Structured Report at: ", out_path))
  }
  invisible(normalizePath(out_path, mustWork = FALSE))
}
