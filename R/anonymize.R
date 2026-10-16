#' De-identify / Anonymize a DICOM File (HIPAA & DICOM PS3.15 Profile)
#'
#' Removes or replaces Protected Health Information (PHI) tags according to
#' HIPAA Safe Harbor and the DICOM PS3.15 Basic Application Level Confidentiality
#' Profile. Supports date shifting, private tag removal, UID regeneration, and
#' custom tag overrides.
#'
#' @param path Path to input DICOM file.
#' @param out_path Output path for anonymized DICOM file. If `NULL` (default),
#'   writes to a temporary `.dcm` file.
#' @param patient_name Replacement string for `PatientName (0010,0010)`. Default
#'   is `"ANONYMOUS"`.
#' @param patient_id Replacement string for `PatientID (0010,0020)`. Default is
#'   `"ANON001"`.
#' @param shift_days Optional integer number of days to shift all date (`DA`)
#'   tags (e.g., `-365` shifts dates back by 1 year). If `NULL` (default), date
#'   tags are replaced with `"19000101"`.
#' @param erase_private Logical. Remove all odd-group private tags. Default is
#'   `TRUE`.
#' @param regenerate_uids Logical. Regenerate `SOPInstanceUID`,
#'   `StudyInstanceUID`, and `SeriesInstanceUID`. Default is `TRUE`.
#' @param extra_remove_tags Optional character vector of additional tags or
#'   keywords to remove.
#' @param replace_tags Named list of additional tag/value replacements.
#'
#' @return Invisibly returns the path to the anonymized DICOM file.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' anon_file <- dicom_anonymize(dcm_file, patient_name = "STUDY^SUBJECT01")
#' dicom_tag_value(anon_file, c("PatientName", "PatientIdentityRemoved"))
dicom_anonymize <- function(path,
                            out_path = NULL,
                            patient_name = "ANONYMOUS",
                            patient_id = "ANON001",
                            shift_days = NULL,
                            erase_private = TRUE,
                            regenerate_uids = TRUE,
                            extra_remove_tags = character(),
                            replace_tags = list()) {
  if (length(path) != 1L || !file.exists(path)) {
    rlang::abort("`path` must be a single existing DICOM file path.")
  }
  if (is.null(out_path)) {
    out_path <- tempfile(fileext = ".dcm")
  }

  hdr <- read_dicom(path)

  # Tags to remove from bundled removal_tags dataset
  rem_env <- new.env(parent = emptyenv())
  utils::data("removal_tags", package = "dicomtk", envir = rem_env)
  utils::data("date_tags", package = "dicomtk", envir = rem_env)
  utils::data("datetime_tags", package = "dicomtk", envir = rem_env)

  del_tags <- unique(c(
    toupper(rem_env$removal_tags$tag),
    toupper(rem_env$datetime_tags$tag),
    as.character(extra_remove_tags)
  ))

  # Do not delete PatientName / PatientID since we explicitly replace them
  del_tags <- setdiff(del_tags, c("(0010,0010)", "(0010,0020)"))

  mod_list <- list(
    "(0010,0010)" = as.character(patient_name),
    "(0010,0020)" = as.character(patient_id),
    "(0012,0062)" = "YES",
    "(0012,0063)" = "DICOMTK PS3.15 Basic Profile"
  )

  # Handle date tags (VR == "DA" or in date_tags)
  da_rows <- hdr[hdr$vr == "DA" | toupper(hdr$tag) %in% toupper(rem_env$date_tags$tag), , drop = FALSE]
  if (nrow(da_rows) > 0L) {
    for (i in seq_len(nrow(da_rows))) {
      tg <- da_rows$tag[i]
      val <- da_rows$value[i]
      if (!is.null(shift_days) && nzchar(val)) {
        parsed_date <- suppressWarnings(as.Date(substr(val, 1L, 8L), format = "%Y%m%d"))
        if (!is.na(parsed_date)) {
          shifted <- parsed_date + as.integer(shift_days)
          mod_list[[tg]] <- format(shifted, "%Y%m%d")
        } else {
          mod_list[[tg]] <- "19000101"
        }
      } else {
        mod_list[[tg]] <- "19000101"
      }
    }
  }

  # Handle time tags (VR == "TM"): reset to 000000
  tm_rows <- hdr[hdr$vr == "TM", , drop = FALSE]
  if (nrow(tm_rows) > 0L) {
    for (tg in tm_rows$tag) {
      mod_list[[tg]] <- "000000"
    }
  }

  if (length(replace_tags) > 0L) {
    for (nm in names(replace_tags)) {
      mod_list[[nm]] <- as.character(replace_tags[[nm]])
    }
  }

  dicom_modify(
    path = path,
    tags = mod_list,
    out_path = out_path,
    delete_tags = del_tags,
    erase_private = erase_private,
    regenerate_uids = regenerate_uids
  )
}
