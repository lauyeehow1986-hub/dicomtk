# Helper: construct a DICOM CodeSequence item list (CodeValue, CodingSchemeDesignator, CodeMeaning)
make_code_sq_item <- function(code_value, scheme_designator, code_meaning) {
  list(list(
    `(0008,0100)` = as.character(code_value)[1L],
    `(0008,0102)` = as.character(scheme_designator)[1L],
    `(0008,0104)` = as.character(code_meaning)[1L]
  ))
}

# Helper: construct a TID 300 / TID 1419 NUM Content Sequence item
make_sr_num_item <- function(concept_code, concept_scheme, concept_meaning,
                             numeric_val, unit_code, unit_scheme = "UCUM", unit_meaning) {
  list(
    `(0040,A010)` = "CONTAINS",
    `(0040,A040)` = "NUM",
    `(0040,A043)` = make_code_sq_item(concept_code, concept_scheme, concept_meaning),
    `(0040,A300)` = list(list(
      `(0040,A30A)` = format(round(as.double(numeric_val), 6), scientific = FALSE, trim = TRUE),
      `(0040,08EA)` = make_code_sq_item(unit_code, unit_scheme, unit_meaning)
    ))
  )
}

# Helper: compute maximum 2D in-plane axial Euclidean diameter (RECIST 1.1 longest diameter) in mm
compute_recist_diameter_mm <- function(roi_mask, spacing) {
  dims <- dim(roi_mask)
  if (length(dims) < 3L) {
    dims <- c(dims, 1L)
    roi_mask <- array(roi_mask, dim = dims)
  }
  dr <- as.double(spacing[1L])
  dc <- as.double(spacing[2L])
  max_diam <- 0.0

  for (k in seq_len(dims[3L])) {
    slice_m <- roi_mask[, , k]
    if (!any(slice_m)) next

    # Extract boundary pixels on this slice (pixels in ROI with at least one 4-neighbor outside)
    idx <- which(slice_m, arr.ind = TRUE)
    n_pts <- nrow(idx)
    if (n_pts <= 1L) {
      diam_k <- sqrt(dr^2 + dc^2)
      if (diam_k > max_diam) max_diam <- diam_k
      next
    }

    # Physical 2D coordinates in mm (spanning outer edges of voxel extent)
    r_mm <- idx[, 1L] * dr
    c_mm <- idx[, 2L] * dc

    # Use convex hull of 2D points to compute exact maximum pairwise Euclidean distance in O(H^2)
    hull_idx <- grDevices::chull(r_mm, c_mm)
    hr <- r_mm[hull_idx]
    hc <- c_mm[hull_idx]
    nh <- length(hull_idx)
    if (nh >= 2L) {
      d_mat <- outer(hr, hr, "-")^2 + outer(hc, hc, "-")^2
      # Add 1 voxel width for outer boundary extent
      diam_k <- sqrt(max(d_mat)) + 0.5 * (dr + dc)
    } else {
      diam_k <- sqrt(dr^2 + dc^2)
    }
    if (diam_k > max_diam) max_diam <- diam_k
  }

  max_diam
}

#' Create a Quantitative Imaging DICOM SR TID 1500 Measurement Report
#'
#' Computes volumetric and morphologic quantitative imaging biomarkers (volume in
#' cubic millimeters and cubic centimeters, RECIST longest in-plane diameter in
#' millimeters, and mean, standard deviation, minimum, and maximum voxel
#' intensity) for each segment in a [dicom_seg] object against a reference
#' [dicom_volume], and optionally writes a DICOM Structured Report following
#' **TID 1500 (Measurement Report)**.
#'
#' @param vol Reference [dicom_volume] object containing image intensities.
#' @param seg A [dicom_seg] segmentation object aligned with `vol`.
#' @param out_path Optional output `.dcm` file path. If provided, writes a
#'   DICOM Comprehensive 3D SR (`1.2.840.10008.5.1.4.1.1.88.34`) Part 10 file.
#' @param patient_name Optional `PatientName (0010,0010)`. Defaults to `"ANONYMOUS"`.
#' @param patient_id Optional `PatientID (0010,0020)`. Defaults to `"ANON001"`.
#' @param study_uid Optional `StudyInstanceUID (0020,000D)`. Defaults to
#'   `vol$uids$study_instance_uid` or a newly generated UID.
#' @param title Report title (`SeriesDescription`). Default is `"Imaging Measurement Report"`.
#'
#' @return An S3 object of class `"dicom_sr_tid1500"` containing:
#'   \item{summary}{A tibble with one row per ROI (`segment_id`, `label`, `volume_mm3`, `volume_cm3`, `recist_diameter_mm`, `mean_intensity`, `sd_intensity`, `min_intensity`, `max_intensity`, `units`).}
#'   \item{measurements}{A tidy long-format tibble of all TID 1500 `NUM` measurement items.}
#'   \item{content_tree}{Nested list representation of the DICOM `ContentSequence (0040,A730)` tree.}
#'   \item{file}{Normalized path to `out_path` if written, otherwise `NULL`.}
#' @export
#' @examples
#' synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 4L))
#' vol <- read_dicom_volume(synth[["out_dir"]])
#' m <- array(0L, dim = c(32L, 32L, 4L))
#' m[10:19, 10:19, 2:3] <- 1L
#' seg <- dicom_seg(m, vol, tibble::tibble(segment_id = 1L, label = "Lesion_1"))
#' sr <- dicom_sr_tid1500(vol, seg)
#' sr$summary
dicom_sr_tid1500 <- function(vol,
                             seg,
                             out_path = NULL,
                             patient_name = "ANONYMOUS",
                             patient_id = "ANON001",
                             study_uid = NULL,
                             title = "Imaging Measurement Report") {
  if (!inherits(vol, "dicom_volume")) {
    rlang::abort("`vol` must be a `dicom_volume` object.")
  }
  if (!inherits(seg, "dicom_seg") && !inherits(seg, "dicom_volume")) {
    rlang::abort("`seg` must be a `dicom_seg` object.")
  }

  img_vox <- vol$voxels
  seg_vox <- seg$voxels %||% seg$array

  if (!identical(dim(img_vox)[1:3], dim(seg_vox)[1:3])) {
    rlang::abort("`vol` and `seg` must have matching 3D spatial dimensions.")
  }

  voxel_vol_mm3 <- prod(vol$spacing[1:3])
  img_units <- if (!is.null(vol$units) && !is.na(vol$units) && nzchar(vol$units)) {
    vol$units
  } else if (identical(vol$modality, "CT")) {
    "HU"
  } else {
    "1"
  }

  ucum_intensity <- switch(
    img_units,
    "HU" = list(code = "[hnsf'U]", meaning = "Hounsfield unit"),
    "BQML" = list(code = "Bq/mL", meaning = "Becquerels per milliliter"),
    "g/mL" = list(code = "g/mL", meaning = "Grams per milliliter"),
    list(code = "1", meaning = "arbitrary unit")
  )

  seg_tbl <- seg$segments
  if (is.null(seg_tbl) || nrow(seg_tbl) == 0L) {
    u_ids <- sort(unique(as.integer(seg_vox[seg_vox > 0])))
    seg_tbl <- tibble::tibble(
      segment_id = u_ids,
      label = paste0("ROI_", u_ids)
    )
  }

  summary_rows <- list()
  meas_rows <- list()
  measurement_groups <- list()

  for (i in seq_len(nrow(seg_tbl))) {
    s_id <- as.integer(seg_tbl$segment_id[i])
    s_label <- as.character(seg_tbl$label[i])

    roi_mask <- (seg_vox == s_id)
    n_vox <- sum(roi_mask)
    if (n_vox == 0L) next

    roi_vals <- as.double(img_vox[roi_mask])
    vol_mm3 <- n_vox * voxel_vol_mm3
    vol_cm3 <- vol_mm3 / 1000.0
    recist_mm <- compute_recist_diameter_mm(roi_mask, vol$spacing)
    mean_val <- mean(roi_vals)
    sd_val <- if (n_vox > 1L) stats::sd(roi_vals) else 0.0
    min_val <- min(roi_vals)
    max_val <- max(roi_vals)

    track_uid <- paste0("2.25.", s_id, ".", sample.int(1e8, 1L))

    summary_rows[[length(summary_rows) + 1L]] <- tibble::tibble(
      segment_id = s_id,
      label = s_label,
      volume_mm3 = vol_mm3,
      volume_cm3 = vol_cm3,
      recist_diameter_mm = recist_mm,
      mean_intensity = mean_val,
      sd_intensity = sd_val,
      min_intensity = min_val,
      max_intensity = max_val,
      units = img_units
    )

    # Record long-format measurement entries
    roi_metrics <- list(
      list(code = "118565006", scheme = "SCT", meaning = "Volume", val = vol_mm3, u_code = "mm3", u_meaning = "cubic millimeter"),
      list(code = "118565006", scheme = "SCT", meaning = "Volume cm3", val = vol_cm3, u_code = "cm3", u_meaning = "cubic centimeter"),
      list(code = "103339001", scheme = "SCT", meaning = "Long Axis", val = recist_mm, u_code = "mm", u_meaning = "millimeter"),
      list(code = "373098007", scheme = "SCT", meaning = "Mean Value", val = mean_val, u_code = ucum_intensity$code, u_meaning = ucum_intensity$meaning),
      list(code = "386136009", scheme = "SCT", meaning = "Standard Deviation", val = sd_val, u_code = ucum_intensity$code, u_meaning = ucum_intensity$meaning)
    )

    num_items <- list()
    for (m_item in roi_metrics) {
      meas_rows[[length(meas_rows) + 1L]] <- tibble::tibble(
        tracking_id = s_label,
        tracking_uid = track_uid,
        concept_code = m_item$code,
        concept_scheme = m_item$scheme,
        concept_meaning = m_item$meaning,
        numeric_value = m_item$val,
        unit_code = m_item$u_code,
        unit_scheme = "UCUM",
        unit_meaning = m_item$u_meaning
      )

      num_items[[length(num_items) + 1L]] <- make_sr_num_item(
        concept_code = m_item$code,
        concept_scheme = m_item$scheme,
        concept_meaning = m_item$meaning,
        numeric_val = m_item$val,
        unit_code = m_item$u_code,
        unit_scheme = "UCUM",
        unit_meaning = m_item$u_meaning
      )
    }

    # TID 1411 Measurement Group container item
    grp_children <- c(
      list(
        list(
          `(0040,A010)` = "HAS OBS CONTEXT",
          `(0040,A040)` = "TEXT",
          `(0040,A043)` = make_code_sq_item("112039", "DCM", "Tracking Identifier"),
          `(0040,A160)` = s_label
        ),
        list(
          `(0040,A010)` = "HAS OBS CONTEXT",
          `(0040,A040)` = "UIDREF",
          `(0040,A043)` = make_code_sq_item("112040", "DCM", "Tracking Unique Identifier"),
          `(0040,A124)` = track_uid
        )
      ),
      num_items
    )

    measurement_groups[[length(measurement_groups) + 1L]] <- list(
      `(0040,A010)` = "CONTAINS",
      `(0040,A040)` = "CONTAINER",
      `(0040,A043)` = make_code_sq_item("125007", "DCM", "Measurement Group"),
      `(0040,A730)` = grp_children
    )
  }

  # Root ContentSequence (TID 1500 -> Imaging Measurements 126010)
  content_seq <- list(
    list(
      `(0040,A010)` = "CONTAINS",
      `(0040,A040)` = "CONTAINER",
      `(0040,A043)` = make_code_sq_item("126010", "DCM", "Imaging Measurements"),
      `(0040,A730)` = measurement_groups
    )
  )

  written_path <- NULL
  if (!is.null(out_path)) {
    st_uid <- study_uid %||% vol$uids$study_instance_uid %||% ""
    meta_tags <- c(
      "SOPClassUID",
      "Modality",
      "SeriesDescription",
      "PatientName",
      "PatientID",
      "ValueType",
      "CompletionFlag",
      "VerificationFlag",
      "ContinuityOfContent"
    )
    meta_vals <- c(
      "1.2.840.10008.5.1.4.1.1.88.34", # Comprehensive 3D SR Storage
      "SR",
      as.character(title)[1L],
      as.character(patient_name)[1L],
      as.character(patient_id)[1L],
      "CONTAINER",
      "COMPLETE",
      "UNVERIFIED",
      "SEPARATE"
    )
    if (nzchar(st_uid)) {
      meta_tags <- c(meta_tags, "StudyInstanceUID")
      meta_vals <- c(meta_vals, as.character(st_uid)[1L])
    }

    extra_sq <- list(
      `(0040,A043)` = make_code_sq_item("126000", "DCM", "Imaging Measurement Report"),
      `(0040,A504)` = list(list(
        `(0008,0105)` = "DCMR",
        `(0040,DB00)` = "1500"
      )),
      `(0040,A730)` = content_seq
    )

    ok <- cpp_write_dicom_dataset(
      out_path = out_path,
      meta_tags = meta_tags,
      meta_values = meta_vals,
      extra_sequences = extra_sq
    )
    if (!isTRUE(ok)) {
      rlang::abort(paste0("Failed to write DICOM SR TID 1500 file: ", out_path))
    }
    written_path <- normalizePath(out_path, mustWork = FALSE)
  }

  summary_df <- if (length(summary_rows) > 0L) {
    dplyr::bind_rows(summary_rows)
  } else {
    tibble::tibble(
      segment_id = integer(),
      label = character(),
      volume_mm3 = numeric(),
      volume_cm3 = numeric(),
      recist_diameter_mm = numeric(),
      mean_intensity = numeric(),
      sd_intensity = numeric(),
      min_intensity = numeric(),
      max_intensity = numeric(),
      units = character()
    )
  }

  meas_df <- if (length(meas_rows) > 0L) {
    dplyr::bind_rows(meas_rows)
  } else {
    tibble::tibble(
      tracking_id = character(),
      tracking_uid = character(),
      concept_code = character(),
      concept_scheme = character(),
      concept_meaning = character(),
      numeric_value = numeric(),
      unit_code = character(),
      unit_scheme = character(),
      unit_meaning = character()
    )
  }

  structure(
    list(
      summary = summary_df,
      measurements = meas_df,
      content_tree = content_seq,
      file = written_path
    ),
    class = "dicom_sr_tid1500"
  )
}

#' Read a DICOM SR TID 1500 Measurement Report
#'
#' Parses a DICOM Structured Report following **TID 1500 (Measurement Report)**
#' and extracts all quantitative `NUM` measurements along with their
#' `TrackingIdentifier (112039, DCM)`, `TrackingUniqueIdentifier (112040, DCM)`,
#' concept codes, and UCUM measurement units into a tidy [tibble::tibble].
#'
#' @param path Path to a DICOM SR `.dcm` file.
#'
#' @return An S3 object of class `"dicom_sr_tid1500"` containing `measurements`
#'   (tidy tibble), `header` (top-level DICOM tags), and `raw_sr` (full sequence
#'   hierarchy tibble).
#' @export
#' @examples
#' synth <- dicom_synthesize(modality = "CT", dims = c(16L, 16L, 4L))
#' vol <- read_dicom_volume(synth[["out_dir"]])
#' m <- array(0L, dim = c(16L, 16L, 4L))
#' m[5:10, 5:10, 2L] <- 1L
#' seg <- dicom_seg(m, vol, tibble::tibble(segment_id = 1L, label = "Node_1"))
#' tmp_sr <- tempfile(fileext = ".dcm")
#' dicom_sr_tid1500(vol, seg, out_path = tmp_sr)
#' sr_in <- read_sr_tid1500(tmp_sr)
#' sr_in$measurements
#' unlink(tmp_sr)
read_sr_tid1500 <- function(path) {
  if (length(path) != 1L || !file.exists(path)) {
    rlang::abort("`path` must be a single existing DICOM SR file path.")
  }
  hdr <- read_dicom(path, include_sequences = TRUE)

  # Group elements by Measurement Group sequence path prefix
  # Measurement Group items live under (0040,A730)[0]/(0040,A730)[g]
  # Find all NumericValue (0040,A30A) rows
  num_rows <- which(hdr$tag == "(0040,A30A)")
  meas_list <- list()

  # Also map each Measurement Group prefix to its Tracking Identifier & Tracking UID
  # A Measurement Group container has children at prefix "(0040,A730)[0].(0040,A730)[g]"
  text_rows <- which(hdr$tag == "(0040,A160)")
  uid_rows <- which(hdr$tag == "(0040,A124)")

  for (r_idx in num_rows) {
    num_val <- suppressWarnings(as.double(hdr$value[r_idx]))
    sp <- hdr$sequence_path[r_idx]
    # Parent NUM item path is sp without trailing "/(0040,A300)[...]"
    num_item_prefix <- sub("/?\\(0040,A300\\)\\[[0-9]+\\].*$", "", sp)
    # Measurement group prefix is one "/(0040,A730)[k]" higher
    grp_prefix <- sub("/?\\(0040,A730\\)\\[[0-9]+\\]$", "", num_item_prefix)

    # Find concept code in (0040,A043) under num_item_prefix
    c_prefix <- paste0(num_item_prefix, "/(0040,A043)")
    c_rows <- which(startsWith(hdr$sequence_path, c_prefix))
    c_code <- hdr$value[c_rows[hdr$tag[c_rows] == "(0008,0100)"]][1L] %||% NA_character_
    c_scheme <- hdr$value[c_rows[hdr$tag[c_rows] == "(0008,0102)"]][1L] %||% NA_character_
    c_meaning <- hdr$value[c_rows[hdr$tag[c_rows] == "(0008,0104)"]][1L] %||% NA_character_

    # Find unit code in (0040,08EA) under sp
    u_rows <- which(startsWith(hdr$sequence_path, sp) & grepl("0040,08EA", hdr$sequence_path, fixed = TRUE))
    u_code <- hdr$value[u_rows[hdr$tag[u_rows] == "(0008,0100)"]][1L] %||% NA_character_
    u_scheme <- hdr$value[u_rows[hdr$tag[u_rows] == "(0008,0102)"]][1L] %||% NA_character_
    u_meaning <- hdr$value[u_rows[hdr$tag[u_rows] == "(0008,0104)"]][1L] %||% NA_character_

    # Find Tracking Identifier and Tracking UID under grp_prefix
    t_rows <- text_rows[startsWith(hdr$sequence_path[text_rows], paste0(grp_prefix, "/"))]
    track_id <- if (length(t_rows) > 0L) hdr$value[t_rows[1L]] else "ROI_1"

    u_id_rows <- uid_rows[startsWith(hdr$sequence_path[uid_rows], paste0(grp_prefix, "/"))]
    track_uid <- if (length(u_id_rows) > 0L) hdr$value[u_id_rows[1L]] else NA_character_

    meas_list[[length(meas_list) + 1L]] <- tibble::tibble(
      tracking_id = track_id,
      tracking_uid = track_uid,
      concept_code = c_code,
      concept_scheme = c_scheme,
      concept_meaning = c_meaning,
      numeric_value = num_val,
      unit_code = u_code,
      unit_scheme = u_scheme,
      unit_meaning = u_meaning
    )
  }

  meas_df <- if (length(meas_list) > 0L) {
    dplyr::bind_rows(meas_list)
  } else {
    tibble::tibble(
      tracking_id = character(),
      tracking_uid = character(),
      concept_code = character(),
      concept_scheme = character(),
      concept_meaning = character(),
      numeric_value = numeric(),
      unit_code = character(),
      unit_scheme = character(),
      unit_meaning = character()
    )
  }

  structure(
    list(
      measurements = meas_df,
      header = hdr[hdr$depth == 0L, , drop = FALSE],
      raw_sr = hdr,
      file = normalizePath(path, mustWork = TRUE)
    ),
    class = "dicom_sr_tid1500"
  )
}

#' @keywords internal
#' @export
print.dicom_sr_tid1500 <- function(x, ...) {
  n_meas <- if (!is.null(x$measurements)) nrow(x$measurements) else 0L
  cat("<dicom_sr_tid1500 [", n_meas, " measurement(s)]>\n", sep = "")
  if (!is.null(x$summary) && nrow(x$summary) > 0L) {
    print(x$summary, ...)
  } else if (n_meas > 0L) {
    print(x$measurements, ...)
  }
  invisible(x)
}
