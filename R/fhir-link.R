#' Post a FHIR Resource to a FHIR REST Server or Local Mock Directory
#'
#' @param resource A named list representing a FHIR resource (must contain
#'   `resourceType`).
#' @param base_url Base URL of the FHIR server (e.g., `"http://localhost:8080/fhir"`)
#'   or a local directory path for offline mock storage.
#' @param token Optional Bearer/SMART access token.
#' @param headers Optional named character vector of HTTP headers.
#' @return The created/stored FHIR resource list (with `id` populated).
#' @export
fhir_post <- function(resource, base_url, token = NULL, headers = character(0)) {
  if (!is.list(resource) || is.null(resource$resourceType)) {
    cli::cli_abort("{.arg resource} must be a list with {.field resourceType}.")
  }
  rtype <- as.character(resource$resourceType)

  if (dir.exists(base_url) || !grepl("^https?://", base_url, ignore.case = TRUE)) {
    dir.create(file.path(base_url, rtype), recursive = TRUE, showWarnings = FALSE)
    rid <- as.character(resource$id %||% paste0(tolower(rtype), "-", as.integer(Sys.time())))
    resource$id <- rid
    out_file <- file.path(base_url, rtype, paste0(rid, ".json"))
    jsonlite::write_json(resource, out_file, auto_unbox = TRUE, pretty = TRUE)
    return(resource)
  }

  req <- httr2::request(base_url) |>
    httr2::req_url_path_append(rtype) |>
    httr2::req_headers("Content-Type" = "application/fhir+json", Accept = "application/fhir+json") |>
    httr2::req_body_json(resource, auto_unbox = TRUE)
  if (!is.null(token) && nzchar(token)) {
    req <- httr2::req_auth_bearer_token(req, token)
  }
  if (length(headers) > 0L) {
    req <- do.call(httr2::req_headers, c(list(.req = req), as.list(headers)))
  }
  resp <- httr2::req_perform(req)
  httr2::resp_body_json(resp, simplifyVector = FALSE)
}

#' Retrieve or Search FHIR Resources From a FHIR Server or Local Mock Directory
#'
#' @param resource_type FHIR resource type (e.g., `"ImagingStudy"`, `"Patient"`).
#' @param id Optional resource ID for direct read.
#' @param query Optional named list of FHIR search parameters.
#' @param base_url Base URL of the FHIR server or a local mock directory path.
#' @param token Optional Bearer/SMART access token.
#' @param headers Optional named character vector of HTTP headers.
#' @return A parsed FHIR resource or Bundle list.
#' @export
fhir_get <- function(resource_type,
                     id = NULL,
                     query = list(),
                     base_url,
                     token = NULL,
                     headers = character(0)) {
  if (dir.exists(base_url) || !grepl("^https?://", base_url, ignore.case = TRUE)) {
    rdir <- file.path(base_url, resource_type)
    if (!is.null(id)) {
      fpath <- file.path(rdir, paste0(id, ".json"))
      if (!file.exists(fpath)) {
        cli::cli_abort("Local FHIR resource not found: {.path {fpath}}.")
      }
      return(jsonlite::fromJSON(fpath, simplifyVector = FALSE))
    }
    files <- list.files(rdir, pattern = "\\.json$", full.names = TRUE)
    entries <- lapply(files, function(f) {
      list(resource = jsonlite::fromJSON(f, simplifyVector = FALSE))
    })
    return(list(resourceType = "Bundle", type = "searchset", entry = entries))
  }

  req <- httr2::request(base_url) |>
    httr2::req_url_path_append(resource_type)
  if (!is.null(id)) {
    req <- httr2::req_url_path_append(req, id)
  } else if (length(query) > 0L) {
    req <- do.call(httr2::req_url_query, c(list(.req = req), query))
  }
  req <- req |> httr2::req_headers(Accept = "application/fhir+json")
  if (!is.null(token) && nzchar(token)) {
    req <- httr2::req_auth_bearer_token(req, token)
  }
  if (length(headers) > 0L) {
    req <- do.call(httr2::req_headers, c(list(.req = req), as.list(headers)))
  }
  resp <- httr2::req_perform(req)
  httr2::resp_body_json(resp, simplifyVector = FALSE)
}

#' Link Synthea FHIR Clinical Bundles With Local DICOM Studies
#'
#' Reads Synthea FHIR `Bundle` JSON files from `fhir_dir` (`Patient`,
#' `Condition`, and `ImagingStudy` resources) and joins them with DICOM series
#' metadata from `dicom_source` by `StudyInstanceUID` or `PatientID`.
#'
#' @param dicom_source A DICOM directory path or header data frame from
#'   [read_dicom()].
#' @param fhir_dir Directory containing Synthea FHIR `.json` bundle files.
#' @return A [tibble::tibble] joining clinical patient/condition fields with
#'   DICOM study/series metadata.
#' @export
link_synthea_cohort <- function(dicom_source, fhir_dir) {
  df <- if (is.character(dicom_source)) {
    read_dicom(dicom_source, wide = TRUE)
  } else if (is.data.frame(dicom_source)) {
    dicom_source
  } else {
    cli::cli_abort("{.arg dicom_source} must be a DICOM directory path or data.frame.")
  }

  json_files <- list.files(fhir_dir, pattern = "\\.json$", full.names = TRUE, recursive = TRUE)
  patients <- list()
  conditions <- list()
  img_studies <- list()

  for (jf in json_files) {
    doc <- jsonlite::fromJSON(jf, simplifyVector = FALSE)
    resources <- if (identical(doc$resourceType, "Bundle") && is.list(doc$entry)) {
      lapply(doc$entry, function(e) e$resource)
    } else if (!is.null(doc$resourceType)) {
      list(doc)
    } else {
      list()
    }
    for (r in resources) {
      if (!is.list(r) || is.null(r$resourceType)) next
      rt <- r$resourceType
      if (identical(rt, "Patient")) {
        pid_ref <- paste0("Patient/", r$id %||% "")
        dicom_pid <- if (length(r$identifier) > 0L) as.character(r$identifier[[1L]]$value %||% r$id) else as.character(r$id %||% NA_character_)
        patients[[pid_ref]] <- list(
          patient_ref = pid_ref,
          patient_id = dicom_pid,
          gender = as.character(r$gender %||% NA_character_),
          birth_date = as.character(r$birthDate %||% NA_character_)
        )
      } else if (identical(rt, "Condition")) {
        pref <- as.character(r$subject$reference %||% "")
        coding <- if (!is.null(r$code$coding) && length(r$code$coding) > 0L) r$code$coding[[1L]] else list()
        conditions[[pref]] <- list(
          condition_code = as.character(coding$code %||% NA_character_),
          condition_display = as.character(coding$display %||% r$code$text %||% NA_character_)
        )
      } else if (identical(rt, "ImagingStudy")) {
        suid <- if (length(r$identifier) > 0L) .fhir_strip_urn(r$identifier[[1L]]$value) else NA_character_
        pref <- as.character(r$subject$reference %||% "")
        if (!is.na(suid) && nzchar(suid)) {
          img_studies[[suid]] <- pref
        }
      }
    }
  }

  # Summarize DICOM by study + series
  ser_keys <- unique(df$SeriesInstanceUID)
  rows <- lapply(ser_keys, function(su) {
    sub <- df[df$SeriesInstanceUID == su, , drop = FALSE]
    st_uid <- as.character(sub$StudyInstanceUID[1L] %||% NA_character_)
    dcm_pid <- if ("PatientID" %in% names(sub)) as.character(sub$PatientID[1L]) else NA_character_
    pref <- img_studies[[st_uid]] %||% NULL
    if (is.null(pref) && !is.na(dcm_pid)) {
      for (p in patients) {
        if (identical(p$patient_id, dcm_pid)) {
          pref <- p$patient_ref
          break
        }
      }
    }
    p_info <- if (!is.null(pref)) patients[[pref]] else NULL
    c_info <- if (!is.null(pref)) conditions[[pref]] else NULL

    tibble::tibble(
      patient_id = as.character(p_info$patient_id %||% dcm_pid %||% NA_character_),
      gender = as.character(p_info$gender %||% NA_character_),
      birth_date = as.character(p_info$birth_date %||% NA_character_),
      condition_code = as.character(c_info$condition_code %||% NA_character_),
      condition_display = as.character(c_info$condition_display %||% NA_character_),
      study_uid = st_uid,
      series_uid = as.character(su),
      modality = as.character(sub$Modality[1L] %||% NA_character_),
      n_instances = as.integer(nrow(sub))
    )
  })

  if (length(rows) == 0L) {
    return(tibble::tibble(
      patient_id = character(0), gender = character(0), birth_date = character(0),
      condition_code = character(0), condition_display = character(0),
      study_uid = character(0), series_uid = character(0),
      modality = character(0), n_instances = integer(0)
    ))
  }
  do.call(rbind, rows)
}
