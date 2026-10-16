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

#' DICOM Date Tags
#'
#' Standard DICOM tags with Value Representation `DA` (Date).
#'
#' @usage data(date_tags)
#' @format A `data.frame` with columns `tag` and `name`.
"date_tags"

#' DICOM DateTime Tags
#'
#' Standard DICOM tags with Value Representation `DT` (DateTime).
#'
#' @usage data(datetime_tags)
#' @format A `data.frame` with columns `tag` and `name`.
"datetime_tags"

#' HIPAA / DICOM De-identification Removal Tags
#'
#' Standard DICOM tags containing Protected Health Information (PHI) targeted
#' for removal or replacement during anonymization.
#'
#' @usage data(removal_tags)
#' @format A `data.frame` with columns `tag` and `name`.
"removal_tags"

