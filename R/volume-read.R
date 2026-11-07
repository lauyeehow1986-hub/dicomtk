# Internal helper: parse backslash-separated DICOM numeric string (DS / IS)
vol_parse_ds <- function(s, expected_len = NULL) {
  if (is.null(s) || length(s) == 0L || is.na(s[1L])) {
    return(NULL)
  }
  txt <- trimws(as.character(s[1L]))
  if (!nzchar(txt)) {
    return(NULL)
  }
  parts <- strsplit(txt, "\\\\", fixed = FALSE)[[1L]]
  nums <- suppressWarnings(as.double(parts))
  if (!is.null(expected_len)) {
    if (length(nums) < expected_len || any(!is.finite(nums[seq_len(expected_len)]))) {
      return(NULL)
    }
    return(nums[seq_len(expected_len)])
  }
  if (length(nums) == 0L || all(!is.finite(nums))) {
    return(NULL)
  }
  nums
}

# Internal helper: parse DICOM TM (HHMMSS.FFFFFF or HH:MM:SS.FFFFFF) to seconds since midnight
vol_parse_tm_sec <- function(s) {
  if (is.null(s) || length(s) == 0L || is.na(s[1L])) {
    return(NA_real_)
  }
  txt <- gsub(":", "", trimws(as.character(s[1L])), fixed = TRUE)
  txt <- strsplit(txt, "\\\\", fixed = FALSE)[[1L]][1L]
  if (is.na(txt) || !nzchar(txt) || nchar(txt) < 2L) {
    return(NA_real_)
  }
  hh <- suppressWarnings(as.double(substr(txt, 1L, 2L)))
  mm <- if (nchar(txt) >= 4L) suppressWarnings(as.double(substr(txt, 3L, 4L))) else 0.0
  ss <- if (nchar(txt) >= 5L) suppressWarnings(as.double(substr(txt, 5L, nchar(txt)))) else 0.0
  if (!is.finite(hh) || !is.finite(mm) || !is.finite(ss)) {
    return(NA_real_)
  }
  hh * 3600.0 + mm * 60.0 + ss
}

# Internal helper: canonicalize a 6-element IOP string into a rounded orientation key
vol_orientation_key <- function(iop_str) {
  iop <- vol_parse_ds(iop_str, expected_len = 6L)
  if (is.null(iop)) {
    return("NA")
  }
  r_vec <- iop[1:3]
  c_vec <- iop[4:6]
  rn <- sqrt(sum(r_vec^2))
  cn <- sqrt(sum(c_vec^2))
  if (rn <= 1e-12 || cn <= 1e-12) {
    return("NA")
  }
  vals <- round(c(r_vec / rn, c_vec / cn), 3L)
  vals[abs(vals) < 5e-4] <- 0.0
  paste(sprintf("%.3f", vals), collapse = "\\")
}

# Internal helper: extract first matching top-level value from a header dataframe
vol_hdr_top_val <- function(df, keyword, default = NA_character_) {
  idx <- which(df$depth == 0L & df$keyword == keyword)
  if (length(idx) == 0L) {
    return(default)
  }
  val <- as.character(df$value[idx[1L]])
  if (is.na(val) || !nzchar(val)) default else val
}

# Internal helper: extract per-frame values with Shared -> Top-Level fallback
vol_extract_fg_vec <- function(hdr_df, keyword, nframes, top_default = NA_character_) {
  out <- rep(as.character(top_default), nframes)

  sh_idx <- which(
    hdr_df$keyword == keyword &
      grepl("^\\(5200,9229\\)", hdr_df$sequence_path)
  )
  if (length(sh_idx) > 0L) {
    sh_val <- as.character(hdr_df$value[sh_idx[1L]])
    if (!is.na(sh_val) && nzchar(sh_val)) {
      out[] <- sh_val
    }
  }

  pf_idx <- which(
    hdr_df$keyword == keyword &
      grepl("^\\(5200,9230\\)\\[[0-9]+\\]", hdr_df$sequence_path)
  )
  if (length(pf_idx) > 0L) {
    spaths <- hdr_df$sequence_path[pf_idx]
    f0 <- suppressWarnings(as.integer(sub("^\\(5200,9230\\)\\[([0-9]+)\\].*$", "\\1", spaths)))
    f1 <- f0 + 1L
    valid <- !is.na(f1) & f1 >= 1L & f1 <= nframes
    if (any(valid)) {
      pf_vals <- as.character(hdr_df$value[pf_idx[valid]])
      pf_pos <- f1[valid]
      # Keep first occurrence per frame item
      keep <- !duplicated(pf_pos)
      out[pf_pos[keep]] <- pf_vals[keep]
    }
  }

  out
}

#' Discover and Split Homogeneous DICOM Sub-Series
#'
#' Scans a directory or vector of DICOM file paths and partitions image files
#' into homogeneous volumetric sub-series grouped by `SeriesInstanceUID`,
#' `Modality`, `SOPClassUID`, matrix dimensions (`Rows`, `Columns`), rounded
#' `ImageOrientationPatient` direction cosines, `EchoNumbers`, and localizer
#' status (`LOCALIZER` / `SCOUT`). Primary 3D volumetric stacks are ordered
#' ahead of scout/localizer slices, and multi-echo acquisitions are ordered by
#' ascending echo number.
#'
#' @param path Directory path or character vector of DICOM file/directory paths.
#' @param recursive Logical. When `path` includes directories, search
#'   subdirectories recursively. Default is `TRUE`.
#'
#' @return A [tibble::tibble] with one row per discovered homogeneous sub-series
#'   and columns `series_uid`, `subseries_id`, `modality`, `rows`, `cols`,
#'   `n_files`, `n_frames`, `orientation_key`, `echo_number`, `is_localizer`,
#'   and `files` (list-column of normalized file path vectors).
#' @export
#' @examples
#' out_dir <- tempfile("split_demo_")
#' dicom_synthesize(out_dir = out_dir, modality = "CT", dims = c(16L, 16L, 4L), mixed_series = TRUE)
#' dicom_split_series(out_dir)
#' unlink(out_dir, recursive = TRUE)
dicom_split_series <- function(path, recursive = TRUE) {
  if (!is.logical(recursive) || length(recursive) != 1L || is.na(recursive)) {
    cli::cli_abort("{.arg recursive} must be {.val TRUE} or {.val FALSE}.")
  }

  raw_files <- resolve_dicom_paths(path, recursive = recursive)
  norm_files <- vapply(
    raw_files,
    function(f) normalizePath(f, winslash = "/", mustWork = TRUE),
    character(1L),
    USE.NAMES = FALSE
  )

  recs <- vector("list", length(norm_files))
  n_keep <- 0L

  for (i in seq_along(norm_files)) {
    f <- norm_files[i]
    df <- cpp_read_dicom_header(path = f, include_sequences = FALSE, stop_at_pixels = TRUE)

    rows_num <- vol_parse_ds(vol_hdr_top_val(df, "Rows"), expected_len = 1L)
    cols_num <- vol_parse_ds(vol_hdr_top_val(df, "Columns"), expected_len = 1L)
    if (is.null(rows_num) || is.null(cols_num) || rows_num <= 0 || cols_num <= 0) {
      next
    }

    rows_int <- as.integer(round(rows_num))
    cols_int <- as.integer(round(cols_num))
    nf_num <- vol_parse_ds(vol_hdr_top_val(df, "NumberOfFrames", "1"), expected_len = 1L)
    nf_int <- if (!is.null(nf_num) && nf_num >= 1) as.integer(round(nf_num)) else 1L

    iop_str <- vol_hdr_top_val(df, "ImageOrientationPatient")
    echo_str <- vol_hdr_top_val(df, "EchoNumbers")

    if (is.na(iop_str) || (nf_int > 1L && is.na(echo_str))) {
      df_sq <- cpp_read_dicom_header(path = f, include_sequences = TRUE, stop_at_pixels = TRUE)
      if (is.na(iop_str)) {
        sh_iop <- which(df_sq$keyword == "ImageOrientationPatient" & grepl("^\\(5200,9229\\)", df_sq$sequence_path))
        if (length(sh_iop) > 0L) {
          iop_str <- as.character(df_sq$value[sh_iop[1L]])
        } else {
          pf_iop <- which(df_sq$keyword == "ImageOrientationPatient" & grepl("^\\(5200,9230\\)", df_sq$sequence_path))
          if (length(pf_iop) > 0L) {
            iop_str <- as.character(df_sq$value[pf_iop[1L]])
          }
        }
      }
      if (is.na(echo_str)) {
        eq_idx <- which(df_sq$keyword %in% c("EchoNumbers", "EffectiveEchoTime") & df_sq$depth > 0L)
        if (length(eq_idx) > 0L) {
          vals_eq <- unique(as.character(df_sq$value[eq_idx]))
          if (length(vals_eq) == 1L && nzchar(vals_eq[1L])) {
            echo_str <- vals_eq[1L]
          }
        }
      }
    }

    ori_key <- vol_orientation_key(iop_str)
    series_uid <- vol_hdr_top_val(df, "SeriesInstanceUID")
    sop_class <- vol_hdr_top_val(df, "SOPClassUID")
    mod_str <- vol_hdr_top_val(df, "Modality")
    img_type <- vol_hdr_top_val(df, "ImageType", "")
    ser_desc <- vol_hdr_top_val(df, "SeriesDescription", "")
    inst_num <- vol_parse_ds(vol_hdr_top_val(df, "InstanceNumber"), expected_len = 1L)
    echo_num <- vol_parse_ds(echo_str, expected_len = 1L)

    is_loc <- grepl("LOCALIZER|SCOUT", paste(img_type, ser_desc), ignore.case = TRUE)

    group_key <- paste(
      if (is.na(series_uid)) "<NO_SERIES_UID>" else series_uid,
      if (is.na(mod_str)) "<NO_MOD>" else mod_str,
      if (is.na(sop_class)) "<NO_SOP_CLASS>" else sop_class,
      rows_int,
      cols_int,
      ori_key,
      if (is.na(echo_str)) "" else trimws(echo_str),
      is_loc,
      sep = "||"
    )

    n_keep <- n_keep + 1L
    recs[[n_keep]] <- list(
      input_idx = i,
      file = f,
      group_key = group_key,
      series_uid = series_uid,
      modality = mod_str,
      rows = rows_int,
      cols = cols_int,
      nframes = nf_int,
      orientation_key = ori_key,
      echo_number = echo_str,
      echo_num_val = if (!is.null(echo_num)) echo_num else Inf,
      inst_num_val = if (!is.null(inst_num)) inst_num else Inf,
      is_localizer = is_loc
    )
  }

  if (n_keep == 0L) {
    cli::cli_abort(
      "No valid DICOM image files (containing positive {.field Rows} and {.field Columns}) found in {.arg path}."
    )
  }

  recs <- recs[seq_len(n_keep)]
  keys <- vapply(recs, `[[`, character(1L), "group_key")
  uniq_keys <- unique(keys)

  groups <- lapply(uniq_keys, function(k) {
    idx <- which(keys == k)
    sub_recs <- recs[idx]
    first <- sub_recs[[1L]]
    fls <- vapply(sub_recs, `[[`, character(1L), "file")
    total_frames <- sum(vapply(sub_recs, `[[`, integer(1L), "nframes"))
    min_echo <- min(vapply(sub_recs, `[[`, double(1L), "echo_num_val"))
    min_inst <- min(vapply(sub_recs, `[[`, double(1L), "inst_num_val"))
    first_in <- min(vapply(sub_recs, `[[`, integer(1L), "input_idx"))

    list(
      series_uid = first$series_uid,
      modality = first$modality,
      rows = first$rows,
      cols = first$cols,
      n_files = length(fls),
      n_frames = as.integer(total_frames),
      orientation_key = first$orientation_key,
      echo_number = first$echo_number,
      is_localizer = first$is_localizer,
      files = fls,
      sort_loc = as.integer(first$is_localizer),
      sort_neg_frames = -as.double(total_frames),
      sort_echo = min_echo,
      sort_inst = min_inst,
      sort_in = first_in
    )
  })

  ord <- order(
    vapply(groups, `[[`, integer(1L), "sort_loc"),
    vapply(groups, `[[`, double(1L), "sort_neg_frames"),
    vapply(groups, `[[`, double(1L), "sort_echo"),
    vapply(groups, `[[`, double(1L), "sort_inst"),
    vapply(groups, `[[`, integer(1L), "sort_in")
  )
  groups <- groups[ord]

  tibble::tibble(
    series_uid = vapply(groups, `[[`, character(1L), "series_uid"),
    subseries_id = seq_along(groups),
    modality = vapply(groups, `[[`, character(1L), "modality"),
    rows = vapply(groups, `[[`, integer(1L), "rows"),
    cols = vapply(groups, `[[`, integer(1L), "cols"),
    n_files = vapply(groups, `[[`, integer(1L), "n_files"),
    n_frames = vapply(groups, `[[`, integer(1L), "n_frames"),
    orientation_key = vapply(groups, `[[`, character(1L), "orientation_key"),
    echo_number = vapply(groups, `[[`, character(1L), "echo_number"),
    is_localizer = vapply(groups, `[[`, logical(1L), "is_localizer"),
    files = lapply(groups, `[[`, "files")
  )
}

# Internal helper: read all frames + wide/functional-group metadata for a single DICOM file
vol_read_file_frames <- function(file_path, rescale = TRUE) {
  hdr <- read_dicom(file_path, include_sequences = TRUE)
  top <- hdr[hdr$depth == 0L & nzchar(hdr$keyword) & hdr$keyword != "PixelData", , drop = FALSE]

  # Build 1-row wide list of top-level tags
  top_vals <- list(file = file_path)
  if (nrow(top) > 0L) {
    uniq_kw <- unique(top$keyword)
    for (kw in uniq_kw) {
      v <- top$value[top$keyword == kw]
      v <- unique(v[nzchar(v)])
      top_vals[[kw]] <- if (length(v) > 0L) paste(v, collapse = "; ") else ""
    }
  }

  nf_num <- vol_parse_ds(top_vals[["NumberOfFrames"]], expected_len = 1L)
  nframes <- if (!is.null(nf_num) && nf_num >= 1) as.integer(round(nf_num)) else 1L

  has_fg <- any(hdr$tag %in% c("(5200,9229)", "(5200,9230)")) ||
    any(grepl("^\\(5200,92(29|30)\\)", hdr$sequence_path))

  # Read raw stored pixels once and apply per-frame slope/intercept in R
  raw_px <- cpp_read_dicom_pixels(file_path, frame = 0L, rescale = FALSE)
  rows <- as.integer(attr(raw_px, "rows"))
  cols <- as.integer(attr(raw_px, "columns"))
  out_frames <- as.integer(attr(raw_px, "frames"))
  samples <- as.integer(attr(raw_px, "samples_per_pixel"))
  nframes <- out_frames

  # Convert to [rows, cols, nframes] monochrome numeric array
  if (samples > 1L) {
    d_raw <- dim(raw_px)
    if (out_frames == 1L) {
      rgb3 <- array(as.double(raw_px), dim = c(rows, cols, samples))
      lum <- if (samples >= 3L) {
        0.299 * rgb3[, , 1L] + 0.587 * rgb3[, , 2L] + 0.114 * rgb3[, , 3L]
      } else {
        rgb3[, , 1L]
      }
      arr <- array(as.double(lum), dim = c(rows, cols, 1L))
    } else {
      rgb4 <- array(as.double(raw_px), dim = c(rows, cols, samples, out_frames))
      arr <- array(0.0, dim = c(rows, cols, out_frames))
      for (f in seq_len(out_frames)) {
        arr[, , f] <- if (samples >= 3L) {
          0.299 * rgb4[, , 1L, f] + 0.587 * rgb4[, , 2L, f] + 0.114 * rgb4[, , 3L, f]
        } else {
          rgb4[, , 1L, f]
        }
      }
    }
  } else {
    arr <- array(as.double(raw_px), dim = c(rows, cols, nframes))
  }

  # Replicate top-level metadata to nframes rows
  meta_cols <- lapply(top_vals, function(val) rep(as.character(val), nframes))
  meta_cols$frame <- seq_len(nframes)

  fg_keywords <- c(
    "ImagePositionPatient", "ImageOrientationPatient", "PixelSpacing",
    "ImagerPixelSpacing", "SliceThickness", "SpacingBetweenSlices",
    "RescaleSlope", "RescaleIntercept", "RescaleType",
    "WindowCenter", "WindowWidth", "VOILUTFunction",
    "TemporalPositionIndex", "TemporalPositionIdentifier",
    "InStackPositionNumber", "StackID", "TriggerTime",
    "FrameReferenceDateTime", "EffectiveEchoTime", "EchoNumbers", "FrameTime"
  )

  if (has_fg) {
    for (kw in fg_keywords) {
      top_def <- if (!is.null(top_vals[[kw]])) as.character(top_vals[[kw]]) else NA_character_
      vec <- vol_extract_fg_vec(hdr, kw, nframes, top_default = top_def)
      if (!all(is.na(vec))) {
        meta_cols[[kw]] <- vec
      }
    }
  }

  # Per-frame rescaling
  slope_str <- if (!is.null(meta_cols$RescaleSlope)) meta_cols$RescaleSlope else rep("1", nframes)
  inter_str <- if (!is.null(meta_cols$RescaleIntercept)) meta_cols$RescaleIntercept else rep("0", nframes)

  slope_vec <- vapply(slope_str, function(s) {
    v <- vol_parse_ds(s, expected_len = 1L)
    if (is.null(v)) 1.0 else v
  }, double(1L), USE.NAMES = FALSE)

  inter_vec <- vapply(inter_str, function(s) {
    v <- vol_parse_ds(s, expected_len = 1L)
    if (is.null(v)) 0.0 else v
  }, double(1L), USE.NAMES = FALSE)

  if (isTRUE(rescale) && samples == 1L) {
    for (f in seq_len(nframes)) {
      if (slope_vec[f] != 1.0 || inter_vec[f] != 0.0) {
        arr[, , f] <- arr[, , f] * slope_vec[f] + inter_vec[f]
      }
    }
  }

  meta_cols$rescale_slope <- slope_vec
  meta_cols$rescale_intercept <- inter_vec
  meta_tbl <- tibble::as_tibble(meta_cols)

  list(
    voxels = arr,
    meta = meta_tbl,
    has_fg = has_fg,
    nframes = nframes
  )
}

# Internal helper: infer physical voxel units from modality, rescale flag, and header tags
vol_infer_units <- function(modality, meta_tbl, rescale) {
  if (!isTRUE(rescale)) {
    return(NA_character_)
  }
  if ("Units" %in% names(meta_tbl)) {
    u <- trimws(as.character(meta_tbl$Units[1L]))
    if (!is.na(u) && nzchar(u)) {
      return(u)
    }
  }
  if ("RescaleType" %in% names(meta_tbl)) {
    rt <- trimws(as.character(meta_tbl$RescaleType[1L]))
    if (!is.na(rt) && nzchar(rt) && !identical(toupper(rt), "US")) {
      return(rt)
    }
  }
  if (!is.na(modality) && identical(toupper(modality), "CT")) {
    return("HU")
  }
  NA_character_
}

# Internal helper: read and assemble a single homogeneous sub-series into a dicom_volume
vol_read_subseries <- function(sub_row,
                               rescale = TRUE,
                               warn = TRUE,
                               n_subseries_detected = 1L) {
  files <- sub_row$files[[1L]]
  pieces <- lapply(files, vol_read_file_frames, rescale = rescale)

  rows <- sub_row$rows[1L]
  cols <- sub_row$cols[1L]
  frame_counts <- vapply(pieces, `[[`, integer(1L), "nframes")
  total_frames <- sum(frame_counts)

  vox_all <- array(0.0, dim = c(rows, cols, total_frames))
  offset <- 0L
  for (p in pieces) {
    nf <- p$nframes
    vox_all[, , (offset + 1L):(offset + nf)] <- p$voxels
    offset <- offset + nf
  }

  meta_all <- dplyr::bind_rows(lapply(pieces, `[[`, "meta"))
  meta_all$.input_idx <- seq_len(total_frames)

  # 1. Determine orthonormal direction cosines (d_row, d_col, normal) in LPS
  iop_col <- if ("ImageOrientationPatient" %in% names(meta_all)) {
    meta_all$ImageOrientationPatient
  } else {
    rep(NA_character_, total_frames)
  }
  iop_vec <- NULL
  for (val in iop_col) {
    iop_vec <- vol_parse_ds(val, expected_len = 6L)
    if (!is.null(iop_vec)) break
  }

  missing_iop <- is.null(iop_vec)
  if (!missing_iop) {
    d_row <- iop_vec[1:3]
    d_col <- iop_vec[4:6]
    rn <- sqrt(sum(d_row^2))
    cn <- sqrt(sum(d_col^2))
    if (rn > 1e-12 && cn > 1e-12) {
      d_row <- d_row / rn
      d_col <- d_col / cn
    } else {
      d_row <- c(1.0, 0.0, 0.0)
      d_col <- c(0.0, 1.0, 0.0)
      missing_iop <- TRUE
    }
  } else {
    d_row <- c(1.0, 0.0, 0.0)
    d_col <- c(0.0, 1.0, 0.0)
  }
  d_row[abs(d_row) < 1e-15] <- 0.0
  d_col[abs(d_col) < 1e-15] <- 0.0
  n_raw <- vol_cross3(d_row, d_col)
  n_len <- sqrt(sum(n_raw^2))
  normal <- if (n_len > 1e-12) n_raw / n_len else c(0.0, 0.0, 1.0)
  normal[abs(normal) < 1e-15] <- 0.0

  # 2. Extract in-plane PixelSpacing (dr, dc), nominal dz, and header GantryDetectorTilt
  ps_vec <- NULL
  for (ps_col_nm in c("PixelSpacing", "ImagerPixelSpacing")) {
    if (ps_col_nm %in% names(meta_all)) {
      for (val in meta_all[[ps_col_nm]]) {
        ps_vec <- vol_parse_ds(val, expected_len = 2L)
        if (!is.null(ps_vec) && all(ps_vec > 0)) break
        ps_vec <- NULL
      }
    }
    if (!is.null(ps_vec)) break
  }
  if (is.null(ps_vec)) ps_vec <- c(1.0, 1.0)
  dr <- ps_vec[1L]
  dc <- ps_vec[2L]

  dz_nom <- NULL
  for (dz_col_nm in c("SpacingBetweenSlices", "SliceThickness")) {
    if (dz_col_nm %in% names(meta_all)) {
      for (val in meta_all[[dz_col_nm]]) {
        v <- vol_parse_ds(val, expected_len = 1L)
        if (!is.null(v) && abs(v) > 0) {
          dz_nom <- abs(v)
          break
        }
      }
    }
    if (!is.null(dz_nom)) break
  }
  if (is.null(dz_nom)) dz_nom <- 1.0

  hdr_tilt_deg <- 0.0
  if ("GantryDetectorTilt" %in% names(meta_all)) {
    tv <- vol_parse_ds(meta_all$GantryDetectorTilt[1L], expected_len = 1L)
    if (!is.null(tv)) hdr_tilt_deg <- tv
  }
  theta_nom <- hdr_tilt_deg * pi / 180.0
  step_dir_nom <- cos(theta_nom) * normal + sin(theta_nom) * d_col

  # 3. Parse per-frame ImagePositionPatient (total_frames x 3)
  ipp_mat <- matrix(NA_real_, nrow = total_frames, ncol = 3L)
  if ("ImagePositionPatient" %in% names(meta_all)) {
    for (m in seq_len(total_frames)) {
      p3 <- vol_parse_ds(meta_all$ImagePositionPatient[m], expected_len = 3L)
      if (!is.null(p3)) {
        ipp_mat[m, ] <- p3
      }
    }
  }

  valid_ipp <- stats::complete.cases(ipp_mat)
  missing_ipp <- !all(valid_ipp)

  inst_nums <- if ("InstanceNumber" %in% names(meta_all)) {
    vapply(meta_all$InstanceNumber, function(s) {
      v <- vol_parse_ds(s, expected_len = 1L)
      if (is.null(v)) Inf else v
    }, double(1L), USE.NAMES = FALSE)
  } else {
    rep(Inf, total_frames)
  }

  is_single_multiframe_file <- (length(files) == 1L && total_frames > 1L)

  if (missing_ipp) {
    if (!any(valid_ipp)) {
      if (is_single_multiframe_file) {
        # Multi-frame cine without IPP -> stationary plane 4D [rows, cols, 1L, total_frames]
        ipp_mat[, ] <- 0.0
      } else {
        # Order by InstanceNumber (fallback to input order) along slice normal
        ord_no_ipp <- order(inst_nums, meta_all$frame, meta_all$.input_idx)
        for (s_pos in seq_along(ord_no_ipp)) {
          ipp_mat[ord_no_ipp[s_pos], ] <- (s_pos - 1.0) * dz_nom * normal
        }
      }
    } else {
      for (m in which(!valid_ipp)) {
        ipp_mat[m, ] <- (m - 1.0) * dz_nom * normal
      }
    }
  }

  proj <- as.double(ipp_mat %*% normal)

  # 4. Cluster spatial positions within 1e-2 mm along normal AND in 3D space
  pos_tol <- 1e-2
  ord_proj <- order(proj, seq_len(total_frames))
  cluster_id_sorted <- integer(total_frames)
  cluster_rep_idx <- integer(0)

  for (idx_pos in seq_len(total_frames)) {
    m <- ord_proj[idx_pos]
    assigned <- 0L
    if (length(cluster_rep_idx) > 0L) {
      # Check recent clusters whose projection is within pos_tol
      for (cid in rev(seq_along(cluster_rep_idx))) {
        rep_m <- cluster_rep_idx[cid]
        if (abs(proj[m] - proj[rep_m]) > pos_tol) {
          break
        }
        dist3 <- sqrt(sum((ipp_mat[m, ] - ipp_mat[rep_m, ])^2))
        if (dist3 <= pos_tol) {
          assigned <- cid
          break
        }
      }
    }
    if (assigned == 0L) {
      cluster_rep_idx <- c(cluster_rep_idx, m)
      assigned <- length(cluster_rep_idx)
    }
    cluster_id_sorted[idx_pos] <- assigned
  }

  # Re-order cluster IDs strictly by ascending projection of representative IPPs
  rep_projs <- proj[cluster_rep_idx]
  canon_cluster_ord <- order(rep_projs, seq_along(cluster_rep_idx))
  remap <- integer(length(cluster_rep_idx))
  remap[canon_cluster_ord] <- seq_along(cluster_rep_idx)

  slice_group <- integer(total_frames)
  slice_group[ord_proj] <- remap[cluster_id_sorted]
  n_unique_slices <- length(cluster_rep_idx)

  # Extract temporal sorting keys for potential 4D cine / dynamic series
  get_num_col <- function(col_nm) {
    if (!(col_nm %in% names(meta_all))) return(rep(NA_real_, total_frames))
    vapply(meta_all[[col_nm]], function(s) {
      v <- vol_parse_ds(s, expected_len = 1L)
      if (is.null(v)) NA_real_ else v
    }, double(1L), USE.NAMES = FALSE)
  }
  get_tm_col <- function(col_nm) {
    if (!(col_nm %in% names(meta_all))) return(rep(NA_real_, total_frames))
    vapply(meta_all[[col_nm]], vol_parse_tm_sec, double(1L), USE.NAMES = FALSE)
  }

  tp_idx <- get_num_col("TemporalPositionIndex")
  tp_id  <- get_num_col("TemporalPositionIdentifier")
  trig_t <- get_num_col("TriggerTime")
  acq_n  <- get_num_col("AcquisitionNumber")
  acq_t  <- get_tm_col("AcquisitionTime")
  cnt_t  <- get_tm_col("ContentTime")
  fref_dt <- if ("FrameReferenceDateTime" %in% names(meta_all)) {
    as.character(meta_all$FrameReferenceDateTime)
  } else {
    rep(NA_character_, total_frames)
  }

  duplicate_positions <- FALSE

  if (n_unique_slices == total_frames) {
    # Pure 3D (or single-slice 2D promoted to [rows, cols, 1L]) stack
    ord <- order(proj, inst_nums, meta_all$frame, meta_all$.input_idx)
    final_voxels <- vox_all[, , ord, drop = FALSE]
    final_meta <- meta_all[ord, , drop = FALSE]
    final_meta$slice_index <- seq_len(total_frames)
    final_meta$temporal_index <- rep(1L, total_frames)
    spatial_ipps <- ipp_mat[ord, , drop = FALSE]
  } else {
    # Repeated spatial positions: test if valid regular 4D cine / dynamic volume
    counts <- tabulate(slice_group, nbins = n_unique_slices)
    t_rep <- counts[1L]
    regular_grid <- (t_rep >= 2L) && all(counts == t_rep)

    has_temporal_variation <- FALSE
    if (regular_grid) {
      if (is_single_multiframe_file) {
        has_temporal_variation <- TRUE
      } else {
        # Check if any temporal identifier varies within spatial slice 1
        g1 <- which(slice_group == 1L)
        varies_num <- function(v) {
          fin <- v[g1][is.finite(v[g1])]
          length(unique(fin)) > 1L
        }
        varies_chr <- function(v) {
          ok <- v[g1][!is.na(v[g1]) & nzchar(v[g1])]
          length(unique(ok)) > 1L
        }
        has_temporal_variation <- varies_num(tp_idx) ||
          varies_num(tp_id) ||
          varies_num(trig_t) ||
          varies_num(acq_n) ||
          varies_num(acq_t) ||
          varies_num(cnt_t) ||
          varies_chr(fref_dt)
      }
    }

    if (regular_grid && has_temporal_variation) {
      # Reconstruct 4D [rows, cols, n_unique_slices, t_rep]
      na_to_inf <- function(v) ifelse(is.finite(v), v, Inf)
      fref_missing <- ifelse(is.na(fref_dt) | !nzchar(fref_dt), 1L, 0L)
      fref_clean <- ifelse(fref_missing == 1L, "", fref_dt)

      idx_matrix <- matrix(0L, nrow = n_unique_slices, ncol = t_rep)
      spatial_ipps <- matrix(0.0, nrow = n_unique_slices, ncol = 3L)

      for (s in seq_len(n_unique_slices)) {
        g <- which(slice_group == s)
        t_ord <- order(
          na_to_inf(tp_idx[g]),
          na_to_inf(tp_id[g]),
          na_to_inf(trig_t[g]),
          fref_missing[g],
          fref_clean[g],
          na_to_inf(acq_n[g]),
          na_to_inf(acq_t[g]),
          na_to_inf(cnt_t[g]),
          meta_all$frame[g],
          inst_nums[g],
          meta_all$.input_idx[g]
        )
        g_sorted <- g[t_ord]
        idx_matrix[s, ] <- g_sorted
        spatial_ipps[s, ] <- ipp_mat[g_sorted[1L], ]
      }

      # Grid order: slice s (1..n_unique_slices) fastest, temporal t (1..t_rep) second
      grid_ord <- as.vector(idx_matrix)
      final_voxels <- array(
        vox_all[, , grid_ord],
        dim = c(rows, cols, n_unique_slices, t_rep)
      )
      final_meta <- meta_all[grid_ord, , drop = FALSE]
      final_meta$slice_index <- rep(seq_len(n_unique_slices), times = t_rep)
      final_meta$temporal_index <- rep(seq_len(t_rep), each = n_unique_slices)
    } else {
      # Unexpected / duplicate slice positions without temporal variation
      duplicate_positions <- TRUE
      if (isTRUE(warn)) {
        cli::cli_warn(
          "Duplicate spatial slice positions detected without regular temporal identifiers; stacking {total_frames} slice(s) along dimension 3."
        )
      }
      ord <- order(proj, inst_nums, meta_all$frame, meta_all$.input_idx)
      final_voxels <- vox_all[, , ord, drop = FALSE]
      final_meta <- meta_all[ord, , drop = FALSE]
      final_meta$slice_index <- seq_len(total_frames)
      final_meta$temporal_index <- rep(1L, total_frames)
      spatial_ipps <- ipp_mat[ord, , drop = FALSE]
    }
  }

  # Attach convenient parsed coordinates to frame_meta and drop internal .input_idx
  meta_ipps <- matrix(NA_real_, nrow = nrow(final_meta), ncol = 3L)
  if ("ImagePositionPatient" %in% names(final_meta)) {
    for (r_i in seq_len(nrow(final_meta))) {
      p3 <- vol_parse_ds(final_meta$ImagePositionPatient[r_i], expected_len = 3L)
      if (!is.null(p3)) meta_ipps[r_i, ] <- p3
    }
  }
  final_meta$ipp_x <- meta_ipps[, 1L]
  final_meta$ipp_y <- meta_ipps[, 2L]
  final_meta$ipp_z <- meta_ipps[, 3L]
  final_meta$slice_location_mm <- as.double(meta_ipps %*% normal)
  final_meta <- dplyr::select(final_meta, -".input_idx")

  # 5. Construct exact 4x4 DICOM LPS affine & geometry diagnostics
  n_spatial <- nrow(spatial_ipps)
  ipp_first <- spatial_ipps[1L, ]
  ipp_last <- spatial_ipps[n_spatial, ]
  total_disp <- ipp_last - ipp_first
  disp_norm <- sqrt(sum(total_disp^2))

  if (n_spatial > 1L && disp_norm > 1e-7) {
    s_vec <- total_disp / (n_spatial - 1.0)
  } else {
    s_vec <- dz_nom * step_dir_nom
  }

  affine <- diag(4L)
  affine[1:3, 1L] <- d_col * dr + 0.0
  affine[1:3, 2L] <- d_row * dc + 0.0
  affine[1:3, 3L] <- s_vec + 0.0
  affine[1:3, 4L] <- ipp_first + 0.0
  affine[4L, ] <- c(0.0, 0.0, 0.0, 1.0)

  dz_eff <- sqrt(sum(s_vec^2))
  spacing <- c(dr, dc, dz_eff)
  direction <- list(
    d_row = unname(d_row),
    d_col = unname(d_col),
    normal = unname(normal)
  )

  # Gantry/detector tilt check
  if (n_spatial > 1L && disp_norm > 1e-7) {
    u_step <- s_vec / dz_eff
    sin_mag <- sqrt(sum(vol_cross3(normal, u_step)^2))
    cos_val <- sum(normal * u_step)
    tilt_mag_deg <- atan2(sin_mag, cos_val) * 180.0 / pi
    col_proj <- sum(u_step * d_col)
    tilt_sign <- if (abs(col_proj) > 1e-6) {
      sign(col_proj)
    } else if (abs(hdr_tilt_deg) > 1e-6) {
      sign(hdr_tilt_deg)
    } else {
      1.0
    }
    tilt_deg <- tilt_sign * tilt_mag_deg
  } else {
    tilt_deg <- hdr_tilt_deg
  }

  has_gantry_tilt <- abs(tilt_deg) > 0.05
  if (!has_gantry_tilt && abs(tilt_deg) < 1e-4) {
    tilt_deg <- 0.0
  }
  if (has_gantry_tilt && isTRUE(warn)) {
    cli::cli_warn(
      "Gantry/detector tilt detected ({round(tilt_deg, 2)} deg): slice step vector is sheared relative to slice normal."
    )
  }

  # Irregular inter-slice spacing check
  if (n_spatial >= 3L && !duplicate_positions) {
    step_vecs <- spatial_ipps[2:n_spatial, , drop = FALSE] -
      spatial_ipps[1:(n_spatial - 1L), , drop = FALSE]
    step_dists <- sqrt(rowSums(step_vecs^2))
    ref_step <- stats::median(step_dists)
    u_mean <- if (dz_eff > 1e-12) s_vec / dz_eff else normal
    lat_devs <- sqrt(pmax(0.0, step_dists^2 - as.double(step_vecs %*% u_mean)^2))
    max_spacing_dev_mm <- max(c(abs(step_dists - ref_step), lat_devs))
    tol_mm <- max(0.01, 0.005 * ref_step)
    irregular_spacing <- max_spacing_dev_mm > tol_mm
  } else {
    max_spacing_dev_mm <- 0.0
    irregular_spacing <- FALSE
  }

  if (irregular_spacing && isTRUE(warn)) {
    cli::cli_warn(
      "Irregular inter-slice spacing detected (max deviation {round(max_spacing_dev_mm, 3)} mm from median slice step)."
    )
  }

  st_val <- if ("SliceThickness" %in% names(final_meta)) {
    vol_parse_ds(final_meta$SliceThickness[1L], expected_len = 1L)
  } else {
    NULL
  }
  has_gap_or_overlap <- irregular_spacing || (
    n_spatial > 1L &&
      !duplicate_positions &&
      !is.null(st_val) &&
      st_val > 0 &&
      abs(sum(s_vec * normal) - st_val) > max(0.05, 0.05 * st_val)
  )

  diagnostics <- list(
    irregular_spacing = irregular_spacing,
    max_spacing_dev_mm = as.double(max_spacing_dev_mm),
    has_gap_or_overlap = has_gap_or_overlap,
    has_gantry_tilt = has_gantry_tilt,
    gantry_tilt_deg = as.double(tilt_deg),
    duplicate_positions = duplicate_positions,
    missing_geometry = (missing_iop || missing_ipp),
    n_subseries_detected = as.integer(n_subseries_detected)
  )

  first_or_na <- function(col_nm) {
    if (!(col_nm %in% names(final_meta))) return(NA_character_)
    v <- as.character(final_meta[[col_nm]][1L])
    if (is.na(v) || !nzchar(v)) NA_character_ else v
  }

  uids <- list(
    study_uid = first_or_na("StudyInstanceUID"),
    series_uid = first_or_na("SeriesInstanceUID"),
    frame_of_reference_uid = first_or_na("FrameOfReferenceUID"),
    sop_class_uid = first_or_na("SOPClassUID"),
    sop_instance_uids = if ("SOPInstanceUID" %in% names(final_meta)) {
      unique(as.character(final_meta$SOPInstanceUID))
    } else {
      character(0)
    },
    files = unique(as.character(final_meta$file))
  )

  mod_val <- sub_row$modality[1L]
  units_val <- vol_infer_units(mod_val, final_meta, rescale = rescale)

  prov <- list(make_provenance_entry(
    action = "read_dicom_volume",
    params = list(
      n_files = length(files),
      dims = as.integer(dim(final_voxels)),
      modality = mod_val,
      rescale = isTRUE(rescale)
    )
  ))

  new_dicom_volume(
    voxels = final_voxels,
    affine = affine,
    coord_system = "LPS",
    spacing = spacing,
    direction = direction,
    frame_meta = final_meta,
    uids = uids,
    modality = mod_val,
    units = units_val,
    diagnostics = diagnostics,
    provenance = prov
  )
}

#' Read a 3D or 4D DICOM Volume with Exact Patient-Space Geometry
#'
#' Reconstructs a 3D (`[rows, cols, slices]`) or 4D
#' (`[rows, cols, slices, frames]`) [`dicom_volume`][new_dicom_volume] object
#' from classical multi-file DICOM series, single-file Enhanced Multi-Frame IODs
#' (`SharedFunctionalGroupsSequence` / `PerFrameFunctionalGroupsSequence`),
#' stationary cine loops (`XA`, `US`), or dynamic multi-timepoint stacks.
#'
#' Slices are ordered strictly by projecting `ImagePositionPatient (0020,0032)`
#' onto the right-handed slice normal `cross(d_row, d_col)` derived from
#' `ImageOrientationPatient (0020,0037)` (never trusting `InstanceNumber` when
#' spatial positions are present). Computes the exact 4x4 DICOM LPS
#' voxel-to-world affine matrix (including gantry/detector tilt shear when
#' present) and records geometry diagnostics for irregular spacing, slice
#' gaps/overlaps, gantry tilt, and duplicate positions.
#'
#' @param path Directory path or character vector of DICOM file/directory paths.
#' @param series_uid Optional `SeriesInstanceUID` string to select a specific
#'   DICOM series when `path` contains multiple series.
#' @param subseries Optional 1-based integer index selecting which homogeneous
#'   sub-series from [dicom_split_series()] to read when `split = FALSE`. When
#'   `NULL` (default), reads primary sub-series `1L` and emits a warning if
#'   multiple sub-series (e.g. a localizer scout or multiple echoes) were
#'   detected.
#' @param rescale Logical. Apply per-frame or top-level `RescaleSlope` and
#'   `RescaleIntercept` to convert stored integers to physical modality units
#'   (e.g. `"HU"` for CT, `"BQML"` for PET). Default is `TRUE`.
#' @param split Logical. If `TRUE`, returns a `list` of `dicom_volume` objects,
#'   one for every homogeneous sub-series discovered by [dicom_split_series()].
#'   Default is `FALSE`.
#' @param recursive Logical. When `path` contains directories, search
#'   subdirectories recursively. Default is `TRUE`.
#' @param warn Logical. Emit informative [cli::cli_warn()] diagnostics when
#'   multiple sub-series, irregular slice spacing, gantry tilt shear, or
#'   duplicate slice positions are encountered. Default is `TRUE`.
#'
#' @return A [`dicom_volume`][new_dicom_volume] object when `split = FALSE`, or
#'   a `list` of `dicom_volume` objects when `split = TRUE`.
#' @export
#' @examples
#' out_dir <- tempfile("vol_read_demo_")
#' dicom_synthesize(
#'   out_dir = out_dir,
#'   modality = "CT",
#'   dims = c(16L, 16L, 4L),
#'   orientation = "oblique",
#'   reverse_order = TRUE
#' )
#' vol <- read_dicom_volume(out_dir)
#' vol
#' unlink(out_dir, recursive = TRUE)
read_dicom_volume <- function(path,
                              series_uid = NULL,
                              subseries = NULL,
                              rescale = TRUE,
                              split = FALSE,
                              recursive = TRUE,
                              warn = TRUE) {
  for (arg_nm in c("rescale", "split", "recursive", "warn")) {
    val <- get(arg_nm, inherits = FALSE)
    if (!is.logical(val) || length(val) != 1L || is.na(val)) {
      cli::cli_abort("{.arg {arg_nm}} must be {.val TRUE} or {.val FALSE}.")
    }
  }

  split_tbl <- dicom_split_series(path, recursive = recursive)

  if (!is.null(series_uid)) {
    if (!is.character(series_uid) || length(series_uid) != 1L ||
        is.na(series_uid) || !nzchar(series_uid)) {
      cli::cli_abort("{.arg series_uid} must be a single non-empty character string or {.val NULL}.")
    }
    keep <- !is.na(split_tbl$series_uid) & split_tbl$series_uid == series_uid
    split_tbl <- split_tbl[keep, , drop = FALSE]
    if (nrow(split_tbl) == 0L) {
      cli::cli_abort("No DICOM sub-series found matching {.arg series_uid} = {.val {series_uid}}.")
    }
    split_tbl$subseries_id <- seq_len(nrow(split_tbl))
  }

  n_detected <- nrow(split_tbl)

  if (isTRUE(split)) {
    return(lapply(seq_len(n_detected), function(idx) {
      vol_read_subseries(
        split_tbl[idx, , drop = FALSE],
        rescale = rescale,
        warn = warn,
        n_subseries_detected = n_detected
      )
    }))
  }

  if (is.null(subseries)) {
    sel_idx <- 1L
    if (n_detected > 1L && isTRUE(warn)) {
      cli::cli_warn(c(
        "Multiple DICOM sub-series ({n_detected}) detected in {.arg path}; reading primary sub-series 1 ({split_tbl$rows[1L]}x{split_tbl$cols[1L]}, {split_tbl$n_frames[1L]} frame(s)).",
        "i" = "Supply {.arg subseries} (1..{n_detected}) or {.code split = TRUE} to select other sub-series."
      ))
    }
  } else {
    if (!is.numeric(subseries) || length(subseries) != 1L || !is.finite(subseries) ||
        subseries < 1 || subseries > n_detected || subseries != floor(subseries)) {
      cli::cli_abort(
        "{.arg subseries} must be a single integer between 1 and {n_detected}."
      )
    }
    sel_idx <- as.integer(subseries)
  }

  vol_read_subseries(
    split_tbl[sel_idx, , drop = FALSE],
    rescale = rescale,
    warn = warn,
    n_subseries_detected = n_detected
  )
}
