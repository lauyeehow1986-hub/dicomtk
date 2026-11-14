# Internal: normalize DICOM UID into FHIR urn:dicom:uid format
.fhir_dicom_urn <- function(uid) {
  u <- as.character(uid %||% "")
  if (!nzchar(u) || is.na(u)) return("urn:dicom:uid:unknown")
  if (startsWith(u, "urn:dicom:uid:")) u else paste0("urn:dicom:uid:", u)
}

.fhir_strip_urn <- function(u) {
  sub("^urn:dicom:uid:", "", as.character(u %||% ""))
}

#' Build an HL7 FHIR R4/R5 `ImagingStudy` Resource
#'
#' Converts a `dicom_volume`, DICOM directory path, or header summary tibble
#' into an HL7 FHIR `ImagingStudy` resource list.
#'
#' @param x A `dicom_volume` object, a directory/file path, or a data frame from
#'   [read_dicom()].
#' @param patient_ref FHIR Patient reference (e.g., `"Patient/p-001"`).
#' @param endpoint_ref Optional FHIR Endpoint reference.
#' @return A named list representing a FHIR `ImagingStudy` resource.
#' @examples
#' synth <- dicom_synthesize(modality = "CT", dims = c(8L, 8L, 2L))
#' on.exit(unlink(synth$out_dir, recursive = TRUE), add = TRUE)
#' vol <- read_dicom_volume(synth$out_dir)
#' as_fhir_imaging_study(vol, patient_ref = "Patient/p-001")$resourceType
#' @export
as_fhir_imaging_study <- function(x,
                                  patient_ref = "Patient/unknown",
                                  endpoint_ref = NULL) {
  if (is.character(x)) {
    x <- read_dicom(x, wide = TRUE)
  }

  if (inherits(x, "dicom_volume")) {
    study_uid <- x$uids$study %||% "1.2.826.0.1.3680043.8.498.1"
    series_uid <- x$uids$series %||% paste0(study_uid, ".1")
    mod <- x$modality %||% "OT"
    n_inst <- if (!is.null(x$metadata) && nrow(x$metadata) > 0L) nrow(x$metadata) else dim(x)[3L]
    series_list <- list(list(
      uid = series_uid,
      number = 1L,
      modality = list(
        system = "http://dicom.nema.org/resources/ontology/DCM",
        code = as.character(mod)
      ),
      numberOfInstances = as.integer(n_inst)
    ))
    mods <- list(list(
      system = "http://dicom.nema.org/resources/ontology/DCM",
      code = as.character(mod)
    ))
    total_inst <- as.integer(n_inst)
  } else if (is.data.frame(x)) {
    study_uid <- if ("StudyInstanceUID" %in% names(x) && nrow(x) > 0L) x$StudyInstanceUID[1L] else "unknown"
    ser_uids <- if ("SeriesInstanceUID" %in% names(x)) unique(x$SeriesInstanceUID) else "series-1"
    series_list <- lapply(seq_along(ser_uids), function(i) {
      sub <- if ("SeriesInstanceUID" %in% names(x)) x[x$SeriesInstanceUID == ser_uids[i], , drop = FALSE] else x
      mod <- if ("Modality" %in% names(sub) && nrow(sub) > 0L) sub$Modality[1L] else "OT"
      list(
        uid = as.character(ser_uids[i]),
        number = as.integer(i),
        modality = list(
          system = "http://dicom.nema.org/resources/ontology/DCM",
          code = as.character(mod)
        ),
        numberOfInstances = as.integer(nrow(sub))
      )
    })
    umods <- unique(vapply(series_list, function(s) s$modality$code, character(1L)))
    mods <- lapply(umods, function(m) {
      list(system = "http://dicom.nema.org/resources/ontology/DCM", code = m)
    })
    total_inst <- as.integer(nrow(x))
  } else {
    cli::cli_abort("{.arg x} must be a {.cls dicom_volume}, path, or data.frame.")
  }

  res <- list(
    resourceType = "ImagingStudy",
    status = "available",
    identifier = list(list(
      system = "urn:dicom:uid",
      value = .fhir_dicom_urn(study_uid)
    )),
    subject = list(reference = as.character(patient_ref)),
    modality = mods,
    numberOfSeries = as.integer(length(series_list)),
    numberOfInstances = total_inst,
    series = series_list
  )
  if (!is.null(endpoint_ref)) {
    res$endpoint <- list(list(reference = as.character(endpoint_ref)))
  }
  res
}

#' Parse an HL7 FHIR `ImagingStudy` Resource Into a Tidy Tibble
#'
#' @param study A FHIR `ImagingStudy` list or JSON string.
#' @return A [tibble::tibble] with one row per series (`study_uid`, `series_uid`,
#'   `modality`, `number_of_instances`, `patient_ref`).
#' @examples
#' st <- list(
#'   resourceType = "ImagingStudy",
#'   identifier = list(list(value = "urn:dicom:uid:1.2.3")),
#'   subject = list(reference = "Patient/p1"),
#'   series = list(list(uid = "1.2.3.1", modality = list(code = "CT"), numberOfInstances = 10L))
#' )
#' from_fhir_imaging_study(st)
#' @export
from_fhir_imaging_study <- function(study) {
  if (is.character(study)) {
    study <- jsonlite::fromJSON(study, simplifyVector = FALSE)
  }
  if (!is.list(study) || !identical(study$resourceType, "ImagingStudy")) {
    cli::cli_abort("{.arg study} must be a FHIR {.field ImagingStudy} resource.")
  }

  study_uid <- if (length(study$identifier) > 0L) {
    .fhir_strip_urn(study$identifier[[1L]]$value)
  } else {
    NA_character_
  }
  patient_ref <- study$subject$reference %||% NA_character_
  ser <- study$series %||% list()
  if (length(ser) == 0L) {
    return(tibble::tibble(
      study_uid = study_uid,
      series_uid = NA_character_,
      modality = NA_character_,
      number_of_instances = as.integer(study$numberOfInstances %||% 0L),
      patient_ref = patient_ref
    ))
  }

  rows <- lapply(ser, function(s) {
    tibble::tibble(
      study_uid = study_uid,
      series_uid = as.character(s$uid %||% NA_character_),
      modality = as.character(s$modality$code %||% NA_character_),
      number_of_instances = as.integer(s$numberOfInstances %||% 0L),
      patient_ref = patient_ref
    )
  })
  do.call(rbind, rows)
}

#' Build an HL7 FHIR R5 `ImagingSelection` Resource From a Segmentation or GSPS
#'
#' @param x A `dicom_seg` or `dicom_gsps` object.
#' @param study_ref FHIR `ImagingStudy` reference string.
#' @return A named list representing a FHIR `ImagingSelection` resource.
#' @export
as_fhir_imaging_selection <- function(x, study_ref = "ImagingStudy/unknown") {
  if (inherits(x, "dicom_seg")) {
    idx <- which(x$array > 0L, arr.ind = TRUE)
    coords <- if (nrow(idx) > 0L) {
      as.numeric(c(
        min(idx[, 1L]), min(idx[, 2L]), min(idx[, 3L]),
        max(idx[, 1L]), max(idx[, 2L]), max(idx[, 3L])
      ))
    } else {
      c(0, 0, 0, 0, 0, 0)
    }
    return(list(
      resourceType = "ImagingSelection",
      status = "available",
      code = list(text = paste(x$segments$label, collapse = ", ")),
      studyUid = x$ref_uids$study %||% NA_character_,
      derivedFrom = list(list(reference = as.character(study_ref))),
      imageRegion3D = list(list(
        regionType = "box",
        coordinate = coords
      ))
    ))
  }

  if (inherits(x, "dicom_gsps") || (is.list(x) && !is.null(x$graphics))) {
    gr <- x$graphics
    coords <- if (is.data.frame(gr) && nrow(gr) > 0L && "coords" %in% names(gr)) {
      as.numeric(unlist(gr$coords[[1L]]))
    } else {
      as.numeric(x$bbox %||% c(0, 0, 0, 0))
    }
    sl <- if (is.data.frame(gr) && nrow(gr) > 0L && "slice" %in% names(gr)) {
      as.integer(gr$slice[1L])
    } else {
      as.integer(x$slice %||% 1L)
    }
    lbl <- if (is.data.frame(gr) && nrow(gr) > 0L && "layer" %in% names(gr)) {
      as.character(gr$layer[1L])
    } else {
      as.character(x$label %||% "Annotation")
    }
    return(list(
      resourceType = "ImagingSelection",
      status = "available",
      code = list(text = lbl),
      derivedFrom = list(list(reference = as.character(study_ref))),
      imageRegion2D = list(list(
        regionType = "polyline",
        coordinate = coords,
        frameNumber = sl
      ))
    ))
  }

  cli::cli_abort("{.arg x} must be a {.cls dicom_seg} or {.cls dicom_gsps} object.")
}

#' Build an HL7 FHIR `DiagnosticReport` Resource From a DICOM SR / TID 1500 Report
#'
#' @param sr A structured report object from [read_sr_tid1500()] or
#'   [read_dicom_sr()].
#' @param patient_ref FHIR Patient reference string.
#' @param imaging_study_ref Optional FHIR `ImagingStudy` reference string.
#' @return A named list representing a FHIR `DiagnosticReport` with `contained`
#'   `Observation` resources.
#' @export
as_fhir_diagnostic_report <- function(sr,
                                      patient_ref = "Patient/unknown",
                                      imaging_study_ref = NULL) {
  if (!is.list(sr)) {
    cli::cli_abort("{.arg sr} must be a parsed DICOM SR / TID 1500 object.")
  }

  meas <- sr$measurements
  contained <- list()
  result_refs <- list()

  if (is.data.frame(meas) && nrow(meas) > 0L) {
    for (i in seq_len(nrow(meas))) {
      obs_id <- sprintf("obs-%d", i)
      raw_val <- if ("numeric_value" %in% names(meas)) {
        meas$numeric_value[i]
      } else if ("value" %in% names(meas)) {
        meas$value[i]
      } else {
        NA
      }
      val_num <- suppressWarnings(as.numeric(raw_val))
      c_name <- if ("concept_meaning" %in% names(meas)) {
        meas$concept_meaning[i]
      } else if ("concept_name" %in% names(meas)) {
        meas$concept_name[i]
      } else if ("name" %in% names(meas)) {
        meas$name[i]
      } else {
        "Measurement"
      }
      u_txt <- if ("unit_code" %in% names(meas)) {
        meas$unit_code[i]
      } else if ("unit" %in% names(meas)) {
        meas$unit[i]
      } else {
        "1"
      }
      obs <- list(
        resourceType = "Observation",
        id = obs_id,
        status = "final",
        code = list(text = as.character(c_name %||% "Measurement")),
        subject = list(reference = as.character(patient_ref))
      )
      if (length(val_num) == 1L && is.finite(val_num)) {
        obs$valueQuantity <- list(
          value = val_num,
          unit = as.character(u_txt %||% "1")
        )
      } else {
        obs$valueString <- as.character(raw_val %||% "")
      }
      contained[[length(contained) + 1L]] <- obs
      result_refs[[length(result_refs) + 1L]] <- list(reference = paste0("#", obs_id))
    }
  } else {
    contained[[1L]] <- list(
      resourceType = "Observation",
      id = "obs-1",
      status = "final",
      code = list(text = "Imaging Narrative"),
      subject = list(reference = as.character(patient_ref)),
      valueString = paste(as.character(sr$text %||% "Completed"), collapse = "\n")
    )
    result_refs[[1L]] <- list(reference = "#obs-1")
  }

  dr <- list(
    resourceType = "DiagnosticReport",
    status = "final",
    code = list(text = as.character(sr$title %||% "Imaging Measurement Report")),
    subject = list(reference = as.character(patient_ref)),
    contained = contained,
    result = result_refs
  )
  if (!is.null(imaging_study_ref)) {
    dr$imagingStudy <- list(list(reference = as.character(imaging_study_ref)))
  }
  dr
}

#' Build an HL7 FHIR `Provenance` Resource From De-Identification or Volume Provenance
#'
#' @param x A result from [dicom_deid()] or a `dicom_volume` object.
#' @param target_ref FHIR target resource reference.
#' @param agent_name Software/pipeline agent identifier.
#' @return A named list representing a FHIR `Provenance` resource.
#' @export
as_fhir_provenance <- function(x,
                               target_ref = "ImagingStudy/unknown",
                               agent_name = "dicomtk") {
  recorded <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  activity_code <- if (is.list(x) && !is.null(x$profile)) "deidentify" else "transform"
  summary_txt <- if (is.list(x) && !is.null(x$n_files)) {
    sprintf("Processed %d file(s)", as.integer(x$n_files))
  } else {
    "DICOM processing pipeline"
  }

  list(
    resourceType = "Provenance",
    target = list(list(reference = as.character(target_ref))),
    recorded = recorded,
    activity = list(
      coding = list(list(
        system = "http://terminology.hl7.org/CodeSystem/iso-21089-lifecycle",
        code = activity_code
      )),
      text = summary_txt
    ),
    agent = list(list(
      who = list(display = as.character(agent_name))
    ))
  )
}

#' Convert DICOM Processing Provenance to W3C PROV-JSON
#'
#' @param x A result from [dicom_deid()] or a `dicom_volume` object.
#' @param agent_name Software agent identifier.
#' @return A named list conforming to W3C PROV-JSON (`entity`, `activity`, `agent`).
#' @export
as_w3c_prov <- function(x, agent_name = "dicomtk") {
  ts <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  list(
    prefix = list(dicomtk = "https://github.com/lauyeehow1986-hub/dicomtk#"),
    entity = list("dicomtk:output" = list("prov:type" = "DICOMStudy")),
    activity = list("dicomtk:pipeline" = list("prov:startTime" = ts, "prov:endTime" = ts)),
    agent = stats::setNames(list(list("prov:type" = "prov:SoftwareAgent")), paste0("dicomtk:", agent_name))
  )
}
