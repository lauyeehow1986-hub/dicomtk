#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @useDynLib dicomtk, .registration = TRUE
#' @importFrom Rcpp sourceCpp
#' @import ggplot2
#' @importFrom tibble tibble as_tibble
#' @importFrom dplyr mutate filter select bind_rows arrange left_join
#' @importFrom tidyr pivot_wider pivot_longer
#' @importFrom rlang abort warn inform caller_env .data
#' @importFrom cli cli_alert_success cli_alert_info cli_alert_warning cli_alert_danger cli_progress_bar cli_progress_update cli_progress_done
#' @importFrom httr2 request req_url_path_append req_headers req_body_json req_perform resp_body_json
#' @importFrom jsonlite toJSON fromJSON
#' @importFrom grDevices gray as.raster
#' @importFrom graphics plot
#' @importFrom stats median quantile sd na.omit
#' @importFrom utils packageVersion head tail glob2rx
#' @importFrom tools file_ext
## usethis namespace: end
NULL

#' Standard DICOM Data Dictionary (DCMTK 3.7.1 / PS 3.6-2026d)
#'
#' A data frame containing 5,354 standard DICOM tags from the OFFIS DCMTK 3.7.1
#' data dictionary (`dicom.dic`).
#'
#' @format A `data.frame` with 5,354 rows and 6 columns:
#' \describe{
#'   \item{tag}{Tag identifier formatted as `"(GGGG,EEEE)"`}
#'   \item{name}{Human-readable tag description}
#'   \item{keyword}{DICOM standard keyword without spaces}
#'   \item{vr}{Value Representation (e.g., `"PN"`, `"DA"`, `"UI"`, `"US"`)}
#'   \item{vm}{Value Multiplicity (e.g., `"1"`, `"1-n"`)}
#'   \item{retired}{`"RET"` if the tag is retired, `""` otherwise}
#' }
"dicom_tags"

#' DICOM Date Tags
#'
#' Standard DICOM tags with Value Representation `DA` (Date).
#'
#' @format A `data.frame` with columns `tag` and `name`.
"date_tags"

#' DICOM DateTime Tags
#'
#' Standard DICOM tags with Value Representation `DT` (DateTime).
#'
#' @format A `data.frame` with columns `tag` and `name`.
"datetime_tags"

#' HIPAA / DICOM De-identification Removal Tags
#'
#' Standard DICOM tags containing Protected Health Information (PHI) targeted
#' for removal or replacement during anonymization.
#'
#' @format A `data.frame` with columns `tag` and `name`.
"removal_tags"
