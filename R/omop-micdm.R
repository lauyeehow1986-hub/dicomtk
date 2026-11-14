# Internal: load bundled omop_imaging_concepts crosswalk
.omop_concepts <- function() {
  env <- new.env(parent = emptyenv())
  utils::data("omop_imaging_concepts", package = "dicomtk", envir = env)
  env$omop_imaging_concepts
}

.omop_lookup_id <- function(code, category, default_id = 0L) {
  tbl <- .omop_concepts()
  sub <- tbl[tbl$category == category, , drop = FALSE]
  c_str <- toupper(trimws(as.character(code %||% "")))
  if (!nzchar(c_str) || is.na(c_str)) return(as.integer(default_id))
  idx <- which(toupper(sub$dicom_code) == c_str)
  if (length(idx) > 0L) return(as.integer(sub$concept_id[idx[1L]]))
  # Partial match fallback
  idx2 <- which(vapply(sub$dicom_code, function(dc) grepl(toupper(dc), c_str, fixed = TRUE), logical(1L)))
  if (length(idx2) > 0L) return(as.integer(sub$concept_id[idx2[1L]]))
  as.integer(default_id)
}

# Internal: format YYYYMMDD DICOM date as YYYY-MM-DD Date
.omop_parse_date <- function(dstr) {
  s <- gsub("[^0-9]", "", as.character(dstr %||% ""))
  if (nchar(s) == 8L) {
    as.Date(sprintf("%s-%s-%s", substr(s, 1L, 4L), substr(s, 5L, 6L), substr(s, 7L, 8L)))
  } else {
    Sys.Date()
  }
}

#' Map DICOM Studies and Series to OHDSI OMOP `IMAGE_OCCURRENCE`
#'
#' Converts a [dicom_archive_index], DICOM directory path, or header tibble
#' into a standard OHDSI Medical Imaging CDM (`MI-CDM`) `image_occurrence`
#' table using the bundled [omop_imaging_concepts] crosswalk.
#'
#' @param source A `dicom_archive_index`, DICOM directory path, or header
#'   data frame from [read_dicom()].
#' @param person_map Optional named integer vector mapping `PatientID` strings
#'   to integer OMOP `person_id` values.
#' @param wadors_base Optional base DICOMweb WADO-RS URL for constructing
#'   `wadors_uri` values.
#'
#' @return A [tibble::tibble] conforming to OHDSI `image_occurrence`.
#' @export
to_omop_image_occurrence <- function(source, person_map = NULL, wadors_base = NULL) {
  if (inherits(source, "dicom_archive_index")) {
    ser <- source$tables$series
    st <- source$tables$studies
    inst <- source$tables$instances
  } else {
    idx <- dicom_index_build(source, engine = "tibble")
    ser <- idx$tables$series
    st <- idx$tables$studies
    inst <- idx$tables$instances
  }

  if (nrow(ser) == 0L) {
    return(tibble::tibble(
      image_occurrence_id = integer(0),
      person_id = integer(0),
      image_occurrence_date = as.Date(character(0)),
      image_study_uid = character(0),
      image_series_uid = character(0),
      modality_concept_id = integer(0),
      anatomic_site_concept_id = integer(0),
      local_path = character(0),
      wadors_uri = character(0)
    ))
  }

  rows <- lapply(seq_len(nrow(ser)), function(i) {
    suid <- ser$StudyInstanceUID[i]
    seuid <- ser$SeriesInstanceUID[i]
    st_row <- st[st$StudyInstanceUID == suid, , drop = FALSE]
    pid_raw <- if (nrow(st_row) > 0L) st_row$PatientID[1L] else "1"
    pid_int <- if (!is.null(person_map) && pid_raw %in% names(person_map)) {
      as.integer(person_map[[pid_raw]])
    } else {
      as.integer(i)
    }
    sdate <- if (nrow(st_row) > 0L) .omop_parse_date(st_row$StudyDate[1L]) else Sys.Date()
    mod_id <- .omop_lookup_id(ser$Modality[i], "modality", default_id = 4089756L)
    bp_id <- .omop_lookup_id(ser$BodyPartExamined[i], "anatomic_site", default_id = 0L)

    inst_sub <- inst[inst$SeriesInstanceUID == seuid, , drop = FALSE]
    lpath <- if (nrow(inst_sub) > 0L && !is.na(inst_sub$file[1L])) dirname(inst_sub$file[1L]) else NA_character_
    wuri <- if (!is.null(wadors_base) && nzchar(wadors_base)) {
      sprintf("%s/studies/%s/series/%s", sub("/+$", "", wadors_base), suid, seuid)
    } else {
      NA_character_
    }

    tibble::tibble(
      image_occurrence_id = as.integer(i),
      person_id = pid_int,
      image_occurrence_date = sdate,
      image_study_uid = as.character(suid),
      image_series_uid = as.character(seuid),
      modality_concept_id = mod_id,
      anatomic_site_concept_id = bp_id,
      local_path = as.character(lpath),
      wadors_uri = as.character(wuri)
    )
  })
  do.call(rbind, rows)
}

#' Map Segmentation Masks or TID 1500 SR Reports to OHDSI OMOP `IMAGE_FEATURE`
#'
#' @param x A `dicom_seg` object or a parsed `dicom_sr_tid1500` report from
#'   [read_sr_tid1500()].
#' @param image_occurrence_id Integer foreign key referencing
#'   `image_occurrence$image_occurrence_id`.
#' @param person_id Integer OMOP `person_id`.
#' @param alg_system Character name of the algorithm or pipeline producing the
#'   feature (default `"dicomtk"`).
#'
#' @return A [tibble::tibble] conforming to OHDSI `image_feature`.
#' @export
to_omop_image_feature <- function(x,
                                  image_occurrence_id = 1L,
                                  person_id = 1L,
                                  alg_system = "dicomtk") {
  type_id <- .omop_lookup_id("derived", "feature_type", default_id = 32856L)

  if (inherits(x, "dicom_seg")) {
    segs <- x$segments
    if (nrow(segs) == 0L) {
      return(tibble::tibble(
        image_feature_id = integer(0), image_occurrence_id = integer(0),
        person_id = integer(0), image_feature_concept_id = integer(0),
        image_feature_type_concept_id = integer(0), image_finding_concept_id = integer(0),
        alg_system = character(0), value_as_number = numeric(0), unit_concept_id = integer(0)
      ))
    }
    vox_vol_mm3 <- prod(as.numeric(x$spacing %||% c(1, 1, 1)))
    rows <- lapply(seq_len(nrow(segs)), function(i) {
      sid <- segs$segment_id[i]
      n_vox <- sum(x$array == sid)
      vol_mm3 <- n_vox * vox_vol_mm3
      tibble::tibble(
        image_feature_id = as.integer(i),
        image_occurrence_id = as.integer(image_occurrence_id),
        person_id = as.integer(person_id),
        image_feature_concept_id = .omop_lookup_id("volume", "feature", default_id = 3000963L),
        image_feature_type_concept_id = type_id,
        image_finding_concept_id = .omop_lookup_id("segmentation", "feature", default_id = 3067890L),
        alg_system = as.character(alg_system),
        value_as_number = as.numeric(vol_mm3),
        unit_concept_id = .omop_lookup_id("mm3", "unit", default_id = 8519L)
      )
    })
    return(do.call(rbind, rows))
  }

  if (inherits(x, "dicom_sr_tid1500") || (is.list(x) && is.data.frame(x$measurements))) {
    meas <- x$measurements
    if (nrow(meas) == 0L) {
      return(tibble::tibble(
        image_feature_id = integer(0), image_occurrence_id = integer(0),
        person_id = integer(0), image_feature_concept_id = integer(0),
        image_feature_type_concept_id = integer(0), image_finding_concept_id = integer(0),
        alg_system = character(0), value_as_number = numeric(0), unit_concept_id = integer(0)
      ))
    }
    rows <- lapply(seq_len(nrow(meas)), function(i) {
      cname <- as.character(meas$concept_meaning[i] %||% "volume")
      fkey <- if (grepl("volume", cname, ignore.case = TRUE)) {
        "volume"
      } else if (grepl("diameter", cname, ignore.case = TRUE)) {
        "diameter"
      } else if (grepl("mean", cname, ignore.case = TRUE)) {
        "mean_hu"
      } else {
        cname
      }
      u_code <- as.character(meas$unit_code[i] %||% "mm3")
      val <- suppressWarnings(as.numeric(meas$numeric_value[i] %||% NA_real_))
      tibble::tibble(
        image_feature_id = as.integer(i),
        image_occurrence_id = as.integer(image_occurrence_id),
        person_id = as.integer(person_id),
        image_feature_concept_id = .omop_lookup_id(fkey, "feature", default_id = 3000963L),
        image_feature_type_concept_id = type_id,
        image_finding_concept_id = .omop_lookup_id("segmentation", "feature", default_id = 3067890L),
        alg_system = as.character(alg_system),
        value_as_number = val,
        unit_concept_id = .omop_lookup_id(u_code, "unit", default_id = 8519L)
      )
    })
    return(do.call(rbind, rows))
  }

  cli::cli_abort("{.arg x} must be a {.cls dicom_seg} or {.cls dicom_sr_tid1500} object.")
}

#' Write and Validate OHDSI OMOP MI-CDM Tables in a DBI / DuckDB Database
#'
#' @param con An active `DBI` connection (e.g., DuckDB or PostgreSQL).
#' @param occurrence_df Data frame from [to_omop_image_occurrence()].
#' @param feature_df Data frame from [to_omop_image_feature()].
#' @return A list with `valid_fk`, `n_occurrences`, and `n_features`.
#' @export
write_omop_micdm <- function(con, occurrence_df, feature_df) {
  rlang::check_installed("DBI", reason = "to write OMOP MI-CDM tables to a database.")
  valid_fk <- all(feature_df$image_occurrence_id %in% occurrence_df$image_occurrence_id)
  if (!isTRUE(valid_fk)) {
    cli::cli_abort("Foreign key violation: {.field image_feature$image_occurrence_id} contains IDs missing from {.field image_occurrence}.")
  }
  DBI::dbWriteTable(con, "image_occurrence", occurrence_df, overwrite = TRUE)
  DBI::dbWriteTable(con, "image_feature", feature_df, overwrite = TRUE)
  list(
    valid_fk = valid_fk,
    n_occurrences = nrow(occurrence_df),
    n_features = nrow(feature_df)
  )
}
