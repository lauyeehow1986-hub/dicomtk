# Internal package-scoped monotonic counter for unique DICOM UIDs
.synth_env <- new.env(parent = emptyenv())
.synth_env$uid_seq <- 0L

synth_or <- function(x, y) {
  if (!is.null(x)) x else y
}

synth_next_uid <- function(sub_id = 1L) {
  .synth_env$uid_seq <- .synth_env$uid_seq + 1L
  ts_ms <- sprintf("%.0f", as.numeric(Sys.time()) * 1000)
  if (!nzchar(ts_ms) || substr(ts_ms, 1L, 1L) == "0") {
    ts_ms <- paste0("1", ts_ms)
  }
  pid_str <- sprintf("%06d", abs(as.integer(Sys.getpid())) %% 1000000L)
  seq_str <- sprintf("%07d", .synth_env$uid_seq %% 10000000L)
  sub_str <- sprintf("%04d", abs(as.integer(sub_id)) %% 10000L)
  int_part <- paste0(ts_ms, pid_str, seq_str, sub_str)
  if (nchar(int_part) > 38L) {
    int_part <- substr(int_part, 1L, 38L)
  }
  paste0("2.25.", int_part)
}

synth_cross3 <- function(a, b) {
  c(
    a[2L] * b[3L] - a[3L] * b[2L],
    a[3L] * b[1L] - a[1L] * b[3L],
    a[1L] * b[2L] - a[2L] * b[1L]
  )
}

synth_fmt_ds <- function(x) {
  vals <- vapply(as.double(x), function(val) {
    if (!is.finite(val) || abs(val) < 1e-14) {
      return("0")
    }
    if (abs(val) >= 1 && abs(val) < 1e12 && abs(val - round(val)) < 1e-9) {
      return(sprintf("%.0f", round(val)))
    }
    s <- sprintf("%.10g", val)
    for (prec in 9:6) {
      if (nchar(s) <= 16L) break
      s <- sprintf(paste0("%.", prec, "g"), val)
    }
    s
  }, character(1L))
  paste(vals, collapse = "\\")
}

synth_direction_basis <- function(orientation, oblique_angles_deg) {
  if (orientation == "axial") {
    d_row <- c(1.0, 0.0, 0.0)
    d_col <- c(0.0, 1.0, 0.0)
  } else if (orientation == "coronal") {
    d_row <- c(1.0, 0.0, 0.0)
    d_col <- c(0.0, 0.0, -1.0)
  } else if (orientation == "sagittal") {
    d_row <- c(0.0, 1.0, 0.0)
    d_col <- c(0.0, 0.0, -1.0)
  } else {
    if (!is.numeric(oblique_angles_deg) || length(oblique_angles_deg) != 3L ||
        any(!is.finite(oblique_angles_deg))) {
      cli::cli_abort("{.arg oblique_angles_deg} must be a finite numeric vector of length 3 (ZYX Euler angles in degrees).")
    }
    rad <- as.double(oblique_angles_deg) * pi / 180.0
    az <- rad[1L]
    ay <- rad[2L]
    ax <- rad[3L]

    rz <- matrix(c(
      cos(az),  sin(az), 0.0,
     -sin(az),  cos(az), 0.0,
      0.0,      0.0,     1.0
    ), nrow = 3L, ncol = 3L)

    ry <- matrix(c(
      cos(ay), 0.0, -sin(ay),
      0.0,     1.0,  0.0,
      sin(ay), 0.0,  cos(ay)
    ), nrow = 3L, ncol = 3L)

    rx <- matrix(c(
      1.0,  0.0,      0.0,
      0.0,  cos(ax),  sin(ax),
      0.0, -sin(ax),  cos(ax)
    ), nrow = 3L, ncol = 3L)

    rot <- rz %*% ry %*% rx
    d_row <- as.double(rot[, 1L])
    d_col <- as.double(rot[, 2L])
    d_row <- d_row / sqrt(sum(d_row^2))
    d_col <- d_col - sum(d_col * d_row) * d_row
    d_col <- d_col / sqrt(sum(d_col^2))
  }

  d_row[abs(d_row) < 1e-15] <- 0.0
  d_col[abs(d_col) < 1e-15] <- 0.0
  normal <- synth_cross3(d_row, d_col)
  normal[abs(normal) < 1e-15] <- 0.0

  list(
    d_row = unname(d_row),
    d_col = unname(d_col),
    normal = unname(normal)
  )
}

synth_modality_spec <- function(modality, voi_params = list()) {
  pres_intent <- as.character(synth_or(
    voi_params$presentation_intent,
    synth_or(
      voi_params$PresentationIntentType,
      if (modality == "MG") "FOR PROCESSING" else "FOR PRESENTATION"
    )
  ))

  mg_classic_sop <- if (identical(pres_intent, "FOR PROCESSING")) {
    "1.2.840.10008.5.1.4.1.1.1.2.1"
  } else {
    "1.2.840.10008.5.1.4.1.1.1.2"
  }
  dx_classic_sop <- if (identical(pres_intent, "FOR PROCESSING")) {
    "1.2.840.10008.5.1.4.1.1.1.1.1"
  } else {
    "1.2.840.10008.5.1.4.1.1.1.1"
  }

  switch(
    modality,
    CT = list(
      dicom_modality = "CT",
      sop_class_uid = "1.2.840.10008.5.1.4.1.1.2",
      scout_sop_class_uid = "1.2.840.10008.5.1.4.1.1.2",
      kind = "classic"
    ),
    MR = list(
      dicom_modality = "MR",
      sop_class_uid = "1.2.840.10008.5.1.4.1.1.4",
      scout_sop_class_uid = "1.2.840.10008.5.1.4.1.1.4",
      kind = "classic"
    ),
    PT = list(
      dicom_modality = "PT",
      sop_class_uid = "1.2.840.10008.5.1.4.1.1.128",
      scout_sop_class_uid = "1.2.840.10008.5.1.4.1.1.128",
      kind = "classic"
    ),
    DX = list(
      dicom_modality = "DX",
      sop_class_uid = dx_classic_sop,
      scout_sop_class_uid = dx_classic_sop,
      kind = "classic"
    ),
    MG = list(
      dicom_modality = "MG",
      sop_class_uid = mg_classic_sop,
      scout_sop_class_uid = mg_classic_sop,
      kind = "classic"
    ),
    US = list(
      dicom_modality = "US",
      sop_class_uid = "1.2.840.10008.5.1.4.1.1.6.1",
      scout_sop_class_uid = "1.2.840.10008.5.1.4.1.1.6.1",
      kind = "classic"
    ),
    XA = list(
      dicom_modality = "XA",
      sop_class_uid = "1.2.840.10008.5.1.4.1.1.12.1",
      scout_sop_class_uid = "1.2.840.10008.5.1.4.1.1.12.1",
      kind = "classic"
    ),
    ENHCT = list(
      dicom_modality = "CT",
      sop_class_uid = "1.2.840.10008.5.1.4.1.1.2.1",
      scout_sop_class_uid = "1.2.840.10008.5.1.4.1.1.2",
      kind = "enhanced"
    ),
    ENHMR = list(
      dicom_modality = "MR",
      sop_class_uid = "1.2.840.10008.5.1.4.1.1.4.1",
      scout_sop_class_uid = "1.2.840.10008.5.1.4.1.1.4",
      kind = "enhanced"
    ),
    DBT = list(
      dicom_modality = "MG",
      sop_class_uid = "1.2.840.10008.5.1.4.1.1.13.1.3",
      scout_sop_class_uid = mg_classic_sop,
      kind = "enhanced"
    ),
    XA_CINE = list(
      dicom_modality = "XA",
      sop_class_uid = "1.2.840.10008.5.1.4.1.1.12.1",
      scout_sop_class_uid = "1.2.840.10008.5.1.4.1.1.12.1",
      kind = "cine"
    ),
    US_CINE = list(
      dicom_modality = "US",
      sop_class_uid = "1.2.840.10008.5.1.4.1.1.3.1",
      scout_sop_class_uid = "1.2.840.10008.5.1.4.1.1.6.1",
      kind = "cine"
    )
  )
}

synth_build_voxels <- function(rows,
                               cols,
                               nslices,
                               modality,
                               phi,
                               pet_params) {
  if (modality %in% c("CT", "ENHCT")) {
    intercept <- -1024.0
    slope <- 1.0
    bg_val <- -1000.0
    ellip_val <- 50.0
    core_val <- 120.0
    corners <- c(1000.0, 1500.0, 2000.0, 2500.0, 3000.0)
  } else if (modality == "PT") {
    act_raw <- synth_or(pet_params$activity_bqml, 10000.0)
    if (!is.numeric(act_raw) || length(act_raw) != 1L || !is.finite(act_raw)) {
      cli::cli_abort("{.field activity_bqml} in {.arg pet_params} must be a single finite number.")
    }
    act <- as.double(act_raw)

    inter_raw <- synth_or(
      pet_params$rescale_intercept,
      synth_or(pet_params$RescaleIntercept, 0.0)
    )
    if (!is.numeric(inter_raw) || length(inter_raw) != 1L || !is.finite(inter_raw)) {
      cli::cli_abort("{.field rescale_intercept} in {.arg pet_params} must be a single finite number.")
    }
    intercept <- as.double(inter_raw)

    user_slope <- synth_or(pet_params$rescale_slope, pet_params$RescaleSlope)
    if (!is.null(user_slope)) {
      if (!is.numeric(user_slope) || length(user_slope) != 1L ||
          !is.finite(user_slope) || user_slope <= 0) {
        cli::cli_abort("{.field rescale_slope} in {.arg pet_params} must be a strictly positive finite number.")
      }
      slope <- as.double(user_slope)
    } else if ((act + 5000.0 - intercept) > 60000.0) {
      slope <- (act + 5000.0 - intercept) / 30000.0
    } else {
      slope <- 1.0
    }

    slope <- as.double(synth_fmt_ds(slope))
    intercept <- as.double(synth_fmt_ds(intercept))
    if (!is.finite(slope) || slope <= 0) {
      cli::cli_abort("{.field rescale_slope} in {.arg pet_params} must serialize to a strictly positive DICOM DS value.")
    }

    bg_val <- 100.0
    ellip_val <- act
    core_val <- act
    base_c <- if (act > 0) act else 0.0
    corners <- base_c + c(1000.0, 2000.0, 3000.0, 4000.0, 5000.0) * slope
  } else {
    intercept <- 0.0
    slope <- 1.0
    bg_val <- 20.0
    ellip_val <- 300.0
    core_val <- 600.0
    corners <- c(1000.0, 1500.0, 2000.0, 2500.0, 3000.0)
  }

  slope <- as.double(synth_fmt_ds(slope))
  intercept <- as.double(synth_fmt_ds(intercept))

  voxels <- array(bg_val, dim = c(rows, cols, nslices))

  ur <- if (rows > 1L) (seq_len(rows) - (rows + 1.0) / 2.0) / (rows / 2.0) else 0.0
  uc <- if (cols > 1L) (seq_len(cols) - (cols + 1.0) / 2.0) / (cols / 2.0) else 0.0
  us <- if (nslices > 1L) (seq_len(nslices) - (nslices + 1.0) / 2.0) / (nslices / 2.0) else 0.0

  ur2 <- (ur / 0.65)^2
  uc2 <- (uc / 0.55)^2

  for (s in seq_len(nslices)) {
    # Subtle temporal shift of inner core for cine multi-frame sequences
    cine_shift <- if (modality %in% c("XA_CINE", "US_CINE") && nslices > 1L) {
      0.15 * sin(2.0 * pi * (s - 1.0) / nslices)
    } else {
      0.0
    }
    uc_shifted2 <- ((uc - cine_shift) / 0.55)^2
    us_term <- if (modality %in% c("XA_CINE", "US_CINE")) 0.0 else (us[s] / 0.75)^2

    r2_outer <- outer(ur2, uc2, "+") + us_term
    r2_inner <- outer(ur2, uc_shifted2, "+") + us_term

    slice_mat <- voxels[, , s]
    slice_mat[r2_outer <= 1.0] <- ellip_val
    slice_mat[r2_inner <= 0.22] <- core_val
    voxels[, , s] <- slice_mat
  }

  # US / US_CINE burned-in top annotation row when phi = TRUE
  if (modality %in% c("US", "US_CINE") && isTRUE(phi)) {
    burn_pattern <- ifelse((seq_len(cols) %% 2L) == 1L, 900.0, 750.0)
    for (s in seq_len(nslices)) {
      voxels[1L, , s] <- burn_pattern
    }
  }

  # Deterministic asymmetric corner fiducials to catch any axis transpose/flip
  voxels[1L, 1L, 1L] <- corners[1L]
  if (rows > 1L) {
    voxels[rows, 1L, 1L] <- corners[2L]
  }
  if (cols > 1L) {
    voxels[1L, cols, 1L] <- corners[3L]
  }
  if (nslices > 1L) {
    voxels[1L, 1L, nslices] <- corners[4L]
    if (cols > 1L) {
      voxels[1L, cols, nslices] <- corners[5L]
    }
  }

  raw_voxels <- round((voxels - intercept) / slope)
  use_signed <- any(raw_voxels < 0)
  if (use_signed) {
    raw_voxels <- pmax(-32768.0, pmin(32767.0, raw_voxels))
  } else {
    raw_voxels <- pmax(0.0, pmin(65535.0, raw_voxels))
  }
  dim(raw_voxels) <- c(rows, cols, nslices)

  truth_voxels <- raw_voxels * slope + intercept
  dim(truth_voxels) <- c(rows, cols, nslices)

  list(
    raw_voxels = raw_voxels,
    truth_voxels = truth_voxels,
    slope = slope,
    intercept = intercept,
    use_signed = use_signed
  )
}

#' Synthesize Multi-Modality DICOM Phantoms with Exact Ground-Truth Geometry
#'
#' Generates standards-compliant synthetic DICOM Part 10 datasets across
#' classical multi-file 3D series (`"CT"`, `"MR"`, `"PT"`, `"DX"`, `"MG"`,
#' `"US"`, `"XA"`), single-file Enhanced Multi-Frame IODs (`"ENHCT"`, `"ENHMR"`,
#' `"DBT"`), and cine multi-frame sequences (`"XA_CINE"`, `"US_CINE"`). Returns
#' the analytical 4x4 DICOM LPS voxel-to-world affine, rescaled ground-truth
#' voxel array with asymmetric corner fiducials, and planted synthetic PHI
#' metadata for deterministic validation of geometry, quantitative transforms,
#' de-identification, and NIfTI export.
#'
#' @param out_dir Output directory where synthesized `.dcm` file(s) will be
#'   written. Created automatically if it does not exist. Defaults to a new
#'   temporary directory.
#' @param modality Imaging modality / IOD preset. One of `"CT"`, `"MR"`, `"PT"`,
#'   `"DX"`, `"MG"`, `"US"`, `"XA"`, `"ENHCT"`, `"ENHMR"`, `"DBT"`,
#'   `"XA_CINE"`, or `"US_CINE"`.
#' @param dims Integer vector `c(rows, cols, slices)` (or `c(rows, cols)` for a
#'   single slice). Default is `c(32L, 32L, 8L)`.
#' @param spacing Numeric vector `c(dr, dc, dz)` in millimeters, where `dr` is
#'   row spacing (along `d_col`), `dc` is column spacing (along `d_row`), and
#'   `dz` is nominal slice step. Default is `c(1.0, 1.0, 2.5)`.
#' @param origin Numeric vector `c(x, y, z)` in DICOM LPS millimeters for voxel
#'   `(r = 0, c = 0, s = 0)` (`[1, 1, 1]` 1-based). Default is
#'   `c(-16.0, -16.0, 0.0)`.
#' @param orientation Anatomical acquisition plane: `"axial"`, `"coronal"`,
#'   `"sagittal"`, or `"oblique"`.
#' @param oblique_angles_deg Numeric vector of 3 ZYX Euler angles in degrees
#'   applied when `orientation = "oblique"`. Default is `c(15, -10, 5)`.
#' @param gantry_tilt_deg Numeric gantry/detector tilt angle in degrees rotating
#'   the slice step direction in the `(normal, d_col)` plane. Default is `0`.
#' @param irregular_z Logical. If `TRUE` (and `slices >= 2`), introduces a
#'   deterministic `2 * dz` slice gap after slice `floor(slices / 2)`. Default
#'   is `FALSE`.
#' @param reverse_order Logical. If `TRUE`, writes slices/frames on disk in
#'   reverse spatial order (`slices:1`) while keeping `truth_affine_lps` and
#'   `truth_voxels` in canonical ascending `IPP . normal` order. Default is
#'   `FALSE`.
#' @param mixed_series Logical. If `TRUE`, writes an additional scout/localizer
#'   DICOM slice with distinct orientation and matrix dimensions into `out_dir`
#'   (recorded in `phantom$extra_files`) sharing the same `SeriesInstanceUID`.
#'   Default is `FALSE`.
#' @param phi Logical. If `TRUE` (default), plants synthetic fictitious PHI tags
#'   (and burned-in top-row pixels for `"US"` / `"US_CINE"`). If `FALSE`, writes
#'   clean de-identified tags.
#' @param pet_params Optional named list configuring quantitative PET (`"PT"`)
#'   attributes (`patient_weight`, `patient_size`, `patient_sex`, `series_time`,
#'   `acquisition_time`, `total_dose`, `half_life`, `start_time`, `units`,
#'   `corrected_image`, `decay_correction`, `activity_bqml`, `rescale_slope`,
#'   `rescale_intercept`).
#' @param voi_params Optional named list configuring `"MG"` / `"DX"` / `"DBT"`
#'   VOI LUT and presentation attributes (`presentation_intent`, `photometric`,
#'   `voi_lut_function`, `window_center`, `window_width`).
#' @param extra_tags Optional named list of additional top-level DICOM tags or
#'   private tags (e.g. `list("(2005,100D)" = "0", "(2005,100E)" = "2.5")`) to
#'   embed in every written file.
#' @param seed Optional integer seed reserved for deterministic phantom
#'   extensions without mutating the caller's `.Random.seed`. Default is `42L`.
#'
#' @return Invisibly returns an S3 object of class `"dicom_phantom"` containing:
#'   - `files`: character vector of primary `.dcm` file paths
#'   - `extra_files`: character vector of extra `.dcm` files when `mixed_series = TRUE`
#'   - `out_dir`: normalized output directory path
#'   - `modality`: requested modality string
#'   - `dims`: integer vector `c(rows, cols, slices)`
#'   - `orientation`: canonical orientation string (`"axial"`, `"coronal"`, `"sagittal"`, or `"oblique"`)
#'   - `truth_affine_lps`: 4x4 numeric LPS voxel-to-world affine matrix (0-based `[r, c, s, 1]`)
#'   - `truth_voxels`: `[rows, cols, slices]` numeric array in rescaled units
#'   - `direction`: list with `d_row`, `d_col`, and `normal` unit vectors in LPS
#'   - `spacing`: numeric vector `c(dr, dc, dz)`
#'   - `slice_positions_lps`: `nslices x 3` numeric matrix of canonical slice origins in LPS
#'   - `planted_phi`: named list of planted synthetic PHI tags (empty `list()` when `phi = FALSE`)
#'   - `uids`: list with `study_uid`, `series_uid`, and `frame_of_reference_uid`
#' @export
#' @examples
#' out_dir <- tempfile("ct_phantom_")
#' phantom <- dicom_synthesize(
#'   out_dir = out_dir,
#'   modality = "CT",
#'   dims = c(16L, 16L, 4L),
#'   spacing = c(0.8, 0.8, 2.5),
#'   orientation = "oblique"
#' )
#' phantom
#' unlink(out_dir, recursive = TRUE)
dicom_synthesize <- function(out_dir = tempfile("dicom_synth_"),
                             modality = c("CT", "MR", "PT", "DX", "MG", "US", "XA",
                                          "ENHCT", "ENHMR", "DBT", "XA_CINE", "US_CINE"),
                             dims = c(32L, 32L, 8L),
                             spacing = c(1.0, 1.0, 2.5),
                             origin = c(-16.0, -16.0, 0.0),
                             orientation = c("axial", "coronal", "sagittal", "oblique"),
                             oblique_angles_deg = c(15, -10, 5),
                             gantry_tilt_deg = 0,
                             irregular_z = FALSE,
                             reverse_order = FALSE,
                             mixed_series = FALSE,
                             phi = TRUE,
                             pet_params = list(),
                             voi_params = list(),
                             extra_tags = list(),
                             seed = 42L) {
  if (!is.character(out_dir) || length(out_dir) != 1L || is.na(out_dir) || !nzchar(out_dir)) {
    cli::cli_abort("{.arg out_dir} must be a single non-empty directory path.")
  }
  if (!is.character(modality) || length(modality) < 1L || is.na(modality[1L])) {
    cli::cli_abort("{.arg modality} must be a non-empty character string.")
  }
  modality <- match.arg(toupper(modality[1L]), c(
    "CT", "MR", "PT", "DX", "MG", "US", "XA",
    "ENHCT", "ENHMR", "DBT", "XA_CINE", "US_CINE"
  ))
  orientation <- match.arg(orientation)

  if (!is.numeric(dims) || !(length(dims) %in% c(2L, 3L)) || any(is.na(dims)) || any(dims < 1)) {
    cli::cli_abort("{.arg dims} must be a positive integer vector of length 2 or 3: {.code c(rows, cols[, slices])}.")
  }
  dims <- as.integer(dims)
  if (length(dims) == 2L) dims <- c(dims, 1L)
  rows <- dims[1L]
  cols <- dims[2L]
  nslices <- dims[3L]

  if (!is.numeric(spacing) || !(length(spacing) %in% c(2L, 3L)) ||
      any(!is.finite(spacing)) || any(spacing <= 0)) {
    cli::cli_abort("{.arg spacing} must be a strictly positive numeric vector of length 2 or 3: {.code c(dr, dc[, dz])}.")
  }
  spacing <- as.double(unname(spacing))
  if (length(spacing) == 2L) spacing <- c(spacing, 1.0)
  dr <- spacing[1L]
  dc <- spacing[2L]
  dz <- spacing[3L]

  if (!is.numeric(origin) || length(origin) != 3L || any(!is.finite(origin))) {
    cli::cli_abort("{.arg origin} must be a finite numeric vector of length 3 in LPS millimeters.")
  }
  origin <- as.double(unname(origin))

  if (!is.numeric(gantry_tilt_deg) || length(gantry_tilt_deg) != 1L ||
      !is.finite(gantry_tilt_deg) || abs(gantry_tilt_deg) >= 89.0) {
    cli::cli_abort("{.arg gantry_tilt_deg} must be a finite numeric angle in (-89, 89) degrees.")
  }
  gantry_tilt_deg <- as.double(gantry_tilt_deg)

  if (length(extra_tags) > 0L) {
    if (is.null(names(extra_tags)) || any(!nzchar(names(extra_tags)))) {
      cli::cli_abort("{.arg extra_tags} must be a named list of DICOM tags/keywords and values.")
    }
  }

  if (!is.null(seed)) {
    has_old_seed <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
    if (has_old_seed) {
      old_seed <- get(".Random.seed", envir = globalenv(), inherits = FALSE)
    }
    set.seed(as.integer(seed))
    on.exit({
      if (has_old_seed) {
        assign(".Random.seed", old_seed, envir = globalenv())
      } else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
        rm(".Random.seed", envir = globalenv())
      }
    }, add = TRUE)
  }

  # 1. Compute orthonormal direction cosines & canonical slice positions in LPS
  direction <- synth_direction_basis(orientation, oblique_angles_deg)
  d_row <- direction$d_row
  d_col <- direction$d_col
  normal <- direction$normal

  theta <- gantry_tilt_deg * pi / 180.0
  step_dir <- cos(theta) * normal + sin(theta) * d_col

  if (nslices <= 1L) {
    z_offsets <- 0.0
  } else {
    steps <- rep(dz, nslices - 1L)
    if (isTRUE(irregular_z)) {
      gap_idx <- max(1L, as.integer(floor(nslices / 2L)))
      steps[gap_idx] <- 2.0 * dz
    }
    z_offsets <- c(0.0, cumsum(steps))
  }

  slice_positions_lps <- matrix(0.0, nrow = nslices, ncol = 3L)
  for (s in seq_len(nslices)) {
    slice_positions_lps[s, ] <- origin + z_offsets[s] * step_dir
  }

  ipp_first <- slice_positions_lps[1L, ]
  ipp_last <- slice_positions_lps[nslices, ]
  s_step <- if (nslices > 1L) {
    (ipp_last - ipp_first) / (nslices - 1L)
  } else {
    dz * step_dir
  }

  truth_affine_lps <- diag(4L)
  truth_affine_lps[1:3, 1L] <- d_col * dr
  truth_affine_lps[1:3, 2L] <- d_row * dc
  truth_affine_lps[1:3, 3L] <- s_step
  truth_affine_lps[1:3, 4L] <- ipp_first

  # 2. Build phantom voxels & stored 16-bit integer representation
  vox_info <- synth_build_voxels(
    rows = rows,
    cols = cols,
    nslices = nslices,
    modality = modality,
    phi = phi,
    pet_params = pet_params
  )
  raw_voxels <- vox_info$raw_voxels
  truth_voxels <- vox_info$truth_voxels
  slope <- vox_info$slope
  intercept <- vox_info$intercept
  pixel_rep_str <- if (vox_info$use_signed) "1" else "0"

  # 3. Assemble PHI / anonymous identity tags & modality metadata
  spec <- synth_modality_spec(modality, voi_params = voi_params)
  study_uid <- synth_next_uid(1L)
  series_uid <- synth_next_uid(2L)
  for_uid <- synth_next_uid(3L)

  if (isTRUE(phi)) {
    planted_phi <- list(
      PatientName = "SYNTHETIC^PHANTOM^TEST",
      PatientID = "SYNTH-PHI-0001",
      PatientBirthDate = "19750412",
      InstitutionName = "DICOMTK SYNTHETIC GENERAL HOSPITAL",
      ReferringPhysicianName = "DR^SYNTHETIC^REFERRING",
      AccessionNumber = "ACC-SYNTH-987654",
      DeviceSerialNumber = "SN-DICOMTK-424242"
    )
    ident_tags <- c(
      planted_phi,
      list(
        StudyDate = "20240518",
        SeriesDate = "20240518",
        AcquisitionDate = "20240518",
        ContentDate = "20240518"
      )
    )
  } else {
    planted_phi <- list()
    ident_tags <- list(
      PatientName = "ANONYMOUS",
      PatientID = "ANON001",
      PatientBirthDate = "",
      ReferringPhysicianName = "",
      AccessionNumber = "",
      PatientIdentityRemoved = "YES",
      StudyDate = "19000101",
      SeriesDate = "19000101",
      AcquisitionDate = "19000101",
      ContentDate = "19000101"
    )
  }

  common_tags <- c(
    list(
      SOPClassUID = spec$sop_class_uid,
      Modality = spec$dicom_modality,
      StudyInstanceUID = study_uid,
      SeriesInstanceUID = series_uid,
      FrameOfReferenceUID = for_uid,
      ImageType = "ORIGINAL\\PRIMARY\\AXIAL",
      Manufacturer = "DICOMTK",
      PixelRepresentation = pixel_rep_str,
      PhotometricInterpretation = "MONOCHROME2"
    ),
    ident_tags
  )

  if (abs(gantry_tilt_deg) > 0) {
    common_tags$GantryDetectorTilt <- synth_fmt_ds(gantry_tilt_deg)
  }

  extra_sq <- NULL

  # Modality-specific tags & sequences
  if (modality == "CT") {
    common_tags$RescaleIntercept <- synth_fmt_ds(intercept)
    common_tags$RescaleSlope <- synth_fmt_ds(slope)
    common_tags$RescaleType <- "HU"
    common_tags$WindowCenter <- "40"
    common_tags$WindowWidth <- "400"
  } else if (modality == "MR") {
    common_tags$EchoNumbers <- "1"
    common_tags$WindowCenter <- "400"
    common_tags$WindowWidth <- "800"
  } else if (modality == "PT") {
    pt_weight <- synth_or(pet_params$patient_weight, synth_or(pet_params$PatientWeight, 70))
    pt_size <- synth_or(pet_params$patient_size, synth_or(pet_params$PatientSize, 1.75))
    pt_sex <- as.character(synth_or(pet_params$patient_sex, synth_or(pet_params$PatientSex, "M")))
    pt_stime <- as.character(synth_or(pet_params$series_time, synth_or(pet_params$SeriesTime, "094946.200000")))
    pt_atime <- as.character(synth_or(pet_params$acquisition_time, synth_or(pet_params$AcquisitionTime, pt_stime)))
    pt_units <- as.character(synth_or(pet_params$units, synth_or(pet_params$Units, "BQML")))
    pt_corr <- as.character(synth_or(pet_params$corrected_image, synth_or(pet_params$CorrectedImage, "DECY\\ATTN")))
    pt_decay <- as.character(synth_or(pet_params$decay_correction, synth_or(pet_params$DecayCorrection, "START")))
    pt_dose <- synth_or(pet_params$total_dose, synth_or(pet_params$RadionuclideTotalDose, 350000000))
    pt_hl <- synth_or(pet_params$half_life, synth_or(pet_params$RadionuclideHalfLife, 6586.2))
    pt_start <- as.character(synth_or(
      pet_params$start_time,
      synth_or(pet_params$RadiopharmaceuticalStartTime, "080000.000000")
    ))

    common_tags$PatientWeight <- synth_fmt_ds(pt_weight)
    common_tags$PatientSize <- synth_fmt_ds(pt_size)
    common_tags$PatientSex <- pt_sex
    common_tags$SeriesTime <- pt_stime
    common_tags$AcquisitionTime <- pt_atime
    common_tags$Units <- pt_units
    common_tags$CorrectedImage <- pt_corr
    common_tags$DecayCorrection <- pt_decay
    common_tags$RescaleIntercept <- synth_fmt_ds(intercept)
    common_tags$RescaleSlope <- synth_fmt_ds(slope)

    extra_sq <- list(
      RadiopharmaceuticalInformationSequence = list(
        list(
          RadionuclideTotalDose = synth_fmt_ds(pt_dose),
          RadionuclideHalfLife = synth_fmt_ds(pt_hl),
          RadiopharmaceuticalStartTime = pt_start
        )
      )
    )
  } else if (modality %in% c("MG", "DX", "DBT")) {
    default_intent <- if (modality == "MG") "FOR PROCESSING" else "FOR PRESENTATION"
    pres_intent <- as.character(synth_or(
      voi_params$presentation_intent,
      synth_or(voi_params$PresentationIntentType, default_intent)
    ))
    default_photo <- if (identical(pres_intent, "FOR PROCESSING")) "MONOCHROME1" else "MONOCHROME2"
    photo <- as.character(synth_or(
      voi_params$photometric,
      synth_or(voi_params$PhotometricInterpretation, default_photo)
    ))
    default_voi_fn <- if (modality %in% c("MG", "DBT")) "SIGMOID" else "LINEAR"
    voi_fn <- as.character(synth_or(
      voi_params$voi_lut_function,
      synth_or(voi_params$VOILUTFunction, default_voi_fn)
    ))
    wc <- synth_or(voi_params$window_center, synth_or(voi_params$WindowCenter, 1500))
    ww <- synth_or(voi_params$window_width, synth_or(voi_params$WindowWidth, 3000))

    common_tags$PresentationIntentType <- pres_intent
    common_tags$PhotometricInterpretation <- photo
    common_tags$VOILUTFunction <- voi_fn
    common_tags$WindowCenter <- synth_fmt_ds(wc)
    common_tags$WindowWidth <- synth_fmt_ds(ww)
    common_tags$ImagerPixelSpacing <- synth_fmt_ds(c(dr, dc))
  } else if (modality %in% c("US", "US_CINE")) {
    common_tags$BurnedInAnnotation <- if (isTRUE(phi)) "YES" else "NO"
  } else if (modality %in% c("XA", "XA_CINE")) {
    common_tags$ImagerPixelSpacing <- synth_fmt_ds(c(dr, dc))
    common_tags$WindowCenter <- "500"
    common_tags$WindowWidth <- "1000"
  }

  # Apply user extra_tags overrides if provided
  if (length(extra_tags) > 0L) {
    for (nm in names(extra_tags)) {
      common_tags[[nm]] <- as.character(extra_tags[[nm]])
    }
  }

  iop_str <- synth_fmt_ds(c(d_row, d_col))
  ps_str <- synth_fmt_ds(c(dr, dc))
  st_str <- synth_fmt_ds(dz)

  disk_order <- if (isTRUE(reverse_order)) rev(seq_len(nslices)) else seq_len(nslices)
  written_files <- character(0)

  # Create output directory only after all validations succeed, with rollback on failure
  dir_existed <- dir.exists(out_dir)
  wrote_ok <- FALSE
  if (!dir_existed) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  }
  on.exit({
    if (!wrote_ok && !dir_existed && dir.exists(out_dir)) {
      unlink(out_dir, recursive = TRUE)
    }
  }, add = TRUE)
  out_dir_norm <- normalizePath(out_dir, winslash = "/", mustWork = TRUE)

  # 4. Write DICOM files according to IOD kind
  if (spec$kind == "classic") {
    written_files <- character(nslices)
    for (k in seq_len(nslices)) {
      canon_s <- disk_order[k]
      sop_uid <- synth_next_uid(100L + k)
      slice_tags <- common_tags
      slice_tags$SOPInstanceUID <- sop_uid
      slice_tags$InstanceNumber <- as.character(k)
      slice_tags$ImagePositionPatient <- synth_fmt_ds(slice_positions_lps[canon_s, ])
      slice_tags$ImageOrientationPatient <- iop_str
      slice_tags$PixelSpacing <- ps_str
      slice_tags$SliceThickness <- st_str
      slice_tags$SpacingBetweenSlices <- st_str

      out_file <- file.path(out_dir_norm, sprintf("slice_%04d.dcm", k))
      ok <- cpp_write_dicom_multiframe(
        pixels = as.double(raw_voxels[, , canon_s]),
        dims = c(rows, cols, 1L),
        out_path = out_file,
        meta_tags = names(slice_tags),
        meta_values = vapply(slice_tags, as.character, character(1L)),
        extra_sequences = extra_sq
      )
      if (!isTRUE(ok)) {
        cli::cli_abort("Failed to write synthesized DICOM slice: {.path {out_file}}")
      }
      written_files[k] <- normalizePath(out_file, winslash = "/", mustWork = TRUE)
    }
  } else if (spec$kind == "enhanced") {
    sop_uid <- synth_next_uid(101L)
    mf_tags <- common_tags
    mf_tags$SOPInstanceUID <- sop_uid
    mf_tags$InstanceNumber <- "1"
    mf_tags$NumberOfFrames <- as.character(nslices)

    shared_fg <- list(
      list(
        PlaneOrientationSequence = list(list(ImageOrientationPatient = iop_str)),
        PixelMeasuresSequence = list(list(
          PixelSpacing = ps_str,
          SliceThickness = st_str,
          SpacingBetweenSlices = st_str
        ))
      )
    )

    resc_type <- if (modality == "ENHCT") "HU" else "US"
    per_frame_fg <- vector("list", nslices)
    disk_raw <- array(0.0, dim = c(rows, cols, nslices))

    for (k in seq_len(nslices)) {
      canon_s <- disk_order[k]
      disk_raw[, , k] <- raw_voxels[, , canon_s]
      per_frame_fg[[k]] <- list(
        PlanePositionSequence = list(list(
          ImagePositionPatient = synth_fmt_ds(slice_positions_lps[canon_s, ])
        )),
        PixelValueTransformationSequence = list(list(
          RescaleIntercept = synth_fmt_ds(intercept),
          RescaleSlope = synth_fmt_ds(slope),
          RescaleType = resc_type
        ))
      )
    }

    out_file <- file.path(out_dir_norm, sprintf("%s_multiframe.dcm", tolower(modality)))
    ok <- cpp_write_dicom_multiframe(
      pixels = as.double(disk_raw),
      dims = c(rows, cols, nslices),
      out_path = out_file,
      meta_tags = names(mf_tags),
      meta_values = vapply(mf_tags, as.character, character(1L)),
      shared_fg = shared_fg,
      per_frame_fg = per_frame_fg,
      extra_sequences = extra_sq
    )
    if (!isTRUE(ok)) {
      cli::cli_abort("Failed to write synthesized enhanced multi-frame DICOM: {.path {out_file}}")
    }
    written_files <- normalizePath(out_file, winslash = "/", mustWork = TRUE)
  } else if (spec$kind == "cine") {
    sop_uid <- synth_next_uid(101L)
    cine_tags <- common_tags
    cine_tags$SOPInstanceUID <- sop_uid
    cine_tags$InstanceNumber <- "1"
    cine_tags$NumberOfFrames <- as.character(nslices)
    cine_tags$FrameTime <- "33.3333"
    cine_tags$FrameIncrementPointer <- "(0018,1063)"
    cine_tags$ImagePositionPatient <- synth_fmt_ds(slice_positions_lps[1L, ])
    cine_tags$ImageOrientationPatient <- iop_str
    cine_tags$PixelSpacing <- ps_str
    cine_tags$SliceThickness <- st_str

    disk_raw <- array(0.0, dim = c(rows, cols, nslices))
    for (k in seq_len(nslices)) {
      disk_raw[, , k] <- raw_voxels[, , disk_order[k]]
    }

    out_file <- file.path(out_dir_norm, sprintf("%s_cine.dcm", tolower(modality)))
    ok <- cpp_write_dicom_multiframe(
      pixels = as.double(disk_raw),
      dims = c(rows, cols, nslices),
      out_path = out_file,
      meta_tags = names(cine_tags),
      meta_values = vapply(cine_tags, as.character, character(1L)),
      extra_sequences = extra_sq
    )
    if (!isTRUE(ok)) {
      cli::cli_abort("Failed to write synthesized cine multi-frame DICOM: {.path {out_file}}")
    }
    written_files <- normalizePath(out_file, winslash = "/", mustWork = TRUE)
  }

  # 5. Optional mixed-series scout/localizer slice in the same out_dir & SeriesInstanceUID
  extra_files <- character(0)
  if (isTRUE(mixed_series)) {
    scout_rows <- rows + 8L
    scout_cols <- cols + 8L
    scout_iop <- if (orientation == "sagittal") {
      synth_fmt_ds(c(1, 0, 0, 0, 1, 0))
    } else {
      synth_fmt_ds(c(0, 1, 0, 0, 0, -1))
    }
    scout_tags <- common_tags
    scout_tags$SOPClassUID <- spec$scout_sop_class_uid
    scout_tags$SOPInstanceUID <- synth_next_uid(999L)
    scout_tags$InstanceNumber <- "999"
    scout_tags$ImageType <- "ORIGINAL\\PRIMARY\\LOCALIZER"
    scout_tags$SeriesDescription <- "SCOUT LOCALIZER"
    scout_tags$ImagePositionPatient <- synth_fmt_ds(c(0, 0, 0))
    scout_tags$ImageOrientationPatient <- scout_iop
    scout_tags$PixelSpacing <- "1\\1"
    scout_tags$SliceThickness <- "5"

    scout_px <- seq_len(scout_rows * scout_cols) %% 256L
    scout_file <- file.path(out_dir_norm, "scout_localizer.dcm")
    ok_scout <- cpp_write_dicom_multiframe(
      pixels = as.double(scout_px),
      dims = c(scout_rows, scout_cols, 1L),
      out_path = scout_file,
      meta_tags = names(scout_tags),
      meta_values = vapply(scout_tags, as.character, character(1L))
    )
    if (!isTRUE(ok_scout)) {
      cli::cli_abort("Failed to write mixed-series localizer DICOM: {.path {scout_file}}")
    }
    extra_files <- normalizePath(scout_file, winslash = "/", mustWork = TRUE)
  }

  wrote_ok <- TRUE

  phantom <- structure(
    list(
      files = written_files,
      extra_files = extra_files,
      out_dir = out_dir_norm,
      modality = modality,
      dims = c(rows, cols, nslices),
      orientation = orientation,
      truth_affine_lps = truth_affine_lps,
      truth_voxels = truth_voxels,
      direction = direction,
      spacing = spacing,
      slice_positions_lps = slice_positions_lps,
      planted_phi = planted_phi,
      uids = list(
        study_uid = study_uid,
        series_uid = series_uid,
        frame_of_reference_uid = for_uid
      )
    ),
    class = "dicom_phantom"
  )

  invisible(phantom)
}

#' @export
print.dicom_phantom <- function(x, ...) {
  d <- dim(x$truth_voxels)
  sp <- x$spacing
  phi_label <- if (length(x$planted_phi) > 0L) "planted" else "anonymous"
  cat(sprintf(
    "<dicom_phantom [%s] %dx%dx%d | spacing=(%.3g, %.3g, %.3g) mm | orientation=%s | files=%d | phi=%s>\n",
    x$modality, d[1L], d[2L], d[3L],
    sp[1L], sp[2L], sp[3L],
    x$orientation, length(x$files), phi_label
  ))
  invisible(x)
}
