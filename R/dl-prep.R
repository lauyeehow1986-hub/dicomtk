#' Resample a 3D `dicom_volume` or `dicom_seg` to Target Voxel Spacing
#'
#' Resamples a 3D [dicom_volume] or [dicom_seg] object to `target_spacing` (in
#' millimeters) using high-speed C++17 trilinear interpolation (for continuous
#' imaging intensities) or nearest-neighbor interpolation (for discrete
#' segmentation masks and label-maps), updating the 4x4 spatial affine
#' matrix and spacing metadata while preserving the physical origin.
#'
#' @param vol A [dicom_volume] or [dicom_seg] object.
#' @param target_spacing Numeric vector of length 3 giving target spacing
#'   `c(dr, dc, dz)` in millimeters. Default is `c(1, 1, 1)`.
#' @param method Interpolation method: `"trilinear"` (default for images) or
#'   `"nearest"` (default automatically when `vol` is a `dicom_seg` if not
#'   explicitly overridden).
#'
#' @return A resampled [dicom_volume] (or [dicom_seg]) object with updated
#'   `voxels`, `affine`, and `spacing`.
#' @export
#' @examples
#' synth <- dicom_synthesize(modality = "CT", dims = c(16L, 16L, 4L))
#' vol <- read_dicom_volume(synth[["out_dir"]])
#' vol_iso <- volume_resample(vol, target_spacing = c(1, 1, 1))
#' dim(vol_iso)
#' unlink(synth[["out_dir"]], recursive = TRUE)
volume_resample <- function(vol,
                            target_spacing = c(1.0, 1.0, 1.0),
                            method = c("trilinear", "nearest")) {
  if (!inherits(vol, "dicom_volume")) {
    rlang::abort("`vol` must be a `dicom_volume` or `dicom_seg` object.")
  }
  if (!is.numeric(target_spacing) || length(target_spacing) != 3L ||
      any(!is.finite(target_spacing)) || any(target_spacing <= 0)) {
    rlang::abort("`target_spacing` must be a positive finite numeric vector of length 3.")
  }
  if (missing(method) && inherits(vol, "dicom_seg")) {
    method <- "nearest"
  } else {
    method <- match.arg(method)
  }

  old_dims <- dim(vol$voxels)
  if (length(old_dims) != 3L) {
    rlang::abort("`volume_resample()` currently supports 3D volumes.")
  }

  old_spacing <- as.double(vol$spacing[1:3])
  new_spacing <- as.double(target_spacing)

  # Compute new dimensions preserving physical FOV
  new_dims <- as.integer(pmax(1L, round(old_dims * (old_spacing / new_spacing))))

  res_vox <- cpp_resample_volume_3d(
    vox = as.double(vol$voxels),
    old_dims = as.integer(old_dims),
    old_spacing = old_spacing,
    new_dims = new_dims,
    new_spacing = new_spacing,
    method = method
  )

  if (inherits(vol, "dicom_seg") || identical(method, "nearest")) {
    storage.mode(res_vox) <- if (is.integer(vol$voxels)) "integer" else "double"
  }

  # Update 4x4 affine matrix: preserve unit direction vectors and origin, scale columns 1..3
  new_affine <- vol$affine
  for (j in 1:3) {
    col_vec <- as.double(vol$affine[1:3, j])
    col_norm <- sqrt(sum(col_vec^2))
    unit_vec <- if (col_norm > 1e-12) col_vec / col_norm else {
      v <- numeric(3L); v[j] <- 1.0; v
    }
    new_affine[1:3, j] <- unit_vec * new_spacing[j]
  }

  new_prov <- c(
    vol$provenance %||% list(),
    list(list(
      timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      action = "resample",
      params = list(
        old_spacing = old_spacing,
        new_spacing = new_spacing,
        method = method
      )
    ))
  )

  out_vol <- new_dicom_volume(
    voxels = res_vox,
    affine = new_affine,
    coord_system = vol$coord_system %||% "LPS",
    spacing = new_spacing,
    direction = vol$direction,
    uids = vol$uids %||% list(),
    modality = vol$modality %||% NA_character_,
    units = vol$units %||% NA_character_,
    provenance = new_prov
  )

  if (inherits(vol, "dicom_seg")) {
    return(dicom_seg(mask = res_vox, ref_volume = out_vol, segments = vol$segments))
  }
  out_vol
}

#' Apply Intensity Windowing and Normalization to a `dicom_volume`
#'
#' Clips voxel intensities to `[center - width / 2, center + width / 2]` and
#' optionally normalizes to `[0, 1]` (`"minmax"`) or zero-mean unit-variance
#' (`"zscore"`).
#'
#' @param vol A [dicom_volume] object.
#' @param center Numeric window center (level). If `NULL`, no clipping is applied.
#' @param width Numeric window width (must be positive if `center` is supplied).
#' @param normalize Normalization mode: `"none"` (default, clip only),
#'   `"minmax"` (rescale to `[0, 1]`), or `"zscore"` (standardize to mean 0, SD 1).
#'
#' @return A [dicom_volume] object with transformed voxel intensities.
#' @export
#' @examples
#' vox <- array(c(-1000, 0, 40, 200, 1000, 2000, 3000, 4000), dim = c(2L, 2L, 2L))
#' vol <- new_dicom_volume(vox, modality = "CT", units = "HU")
#' w <- volume_window(vol, center = 40, width = 400, normalize = "minmax")
#' range(w$voxels)
volume_window <- function(vol,
                          center = NULL,
                          width = NULL,
                          normalize = c("none", "minmax", "zscore")) {
  if (!inherits(vol, "dicom_volume")) {
    rlang::abort("`vol` must be a `dicom_volume` object.")
  }
  normalize <- match.arg(normalize)

  vox <- as.double(vol$voxels)
  d <- dim(vol$voxels)

  if (!is.null(center) && !is.null(width)) {
    if (!is.numeric(center) || !is.numeric(width) || width <= 0) {
      rlang::abort("`center` must be numeric and `width` must be strictly positive.")
    }
    lo <- as.double(center) - as.double(width) / 2.0
    hi <- as.double(center) + as.double(width) / 2.0
    vox <- pmin(pmax(vox, lo), hi)
  }

  if (identical(normalize, "minmax")) {
    vmin <- min(vox, na.rm = TRUE)
    vmax <- max(vox, na.rm = TRUE)
    if (vmax > vmin) {
      vox <- (vox - vmin) / (vmax - vmin)
    } else {
      vox[] <- 0.0
    }
  } else if (identical(normalize, "zscore")) {
    mu <- mean(vox, na.rm = TRUE)
    sd_val <- stats::sd(vox, na.rm = TRUE)
    if (is.finite(sd_val) && sd_val > 1e-12) {
      vox <- (vox - mu) / sd_val
    } else {
      vox <- vox - mu
    }
  }

  dim(vox) <- d
  out <- vol
  out$voxels <- vox
  if (!identical(normalize, "none")) {
    out$units <- normalize
  }
  out
}

#' Generate Leakage-Free Patient-Level Train / Validation / Test Splits
#'
#' Partitions a cohort manifest `data.frame` or [tibble::tibble] into `"train"`,
#' `"val"`, and `"test"` splits strictly grouped by `patient_col` so that all
#' series and studies belonging to a patient remain in the same fold.
#'
#' @param cohort A `data.frame` or [tibble::tibble] with one row per scan/series.
#' @param patient_col Name of the patient identifier column. Default is `"patient_id"`.
#' @param val_frac Fraction of patients assigned to validation. Default is `0.15`.
#' @param test_frac Fraction of patients assigned to test. Default is `0.15`.
#' @param seed Optional integer random seed for reproducible splitting.
#'
#' @return The input `cohort` tibble with an added `split` character column
#'   (`"train"`, `"val"`, or `"test"`).
#' @export
#' @examples
#' df <- tibble::tibble(
#'   patient_id = rep(paste0("P", 1:10), each = 2L),
#'   series = seq_len(20L)
#' )
#' dicom_patient_splits(df, val_frac = 0.2, test_frac = 0.2, seed = 42L)
dicom_patient_splits <- function(cohort,
                                 patient_col = "patient_id",
                                 val_frac = 0.15,
                                 test_frac = 0.15,
                                 seed = NULL) {
  if (!inherits(cohort, "data.frame")) {
    rlang::abort("`cohort` must be a data.frame or tibble.")
  }
  if (!(patient_col %in% names(cohort))) {
    rlang::abort(paste0("Column `", patient_col, "` not found in `cohort`."))
  }
  if (!is.numeric(val_frac) || !is.numeric(test_frac) ||
      val_frac < 0 || test_frac < 0 || (val_frac + test_frac) >= 1.0) {
    rlang::abort("`val_frac` and `test_frac` must be non-negative and sum to < 1.0.")
  }

  pats <- unique(as.character(cohort[[patient_col]]))
  n_pats <- length(pats)
  if (n_pats == 0L) {
    out <- tibble::as_tibble(cohort)
    out$split <- character(0)
    return(out)
  }

  if (!is.null(seed)) {
    had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
    old_seed <- if (had_seed) get(".Random.seed", envir = .GlobalEnv, inherits = FALSE) else NULL
    on.exit({
      if (had_seed) {
        assign(".Random.seed", old_seed, envir = .GlobalEnv)
      } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
        rm(".Random.seed", envir = .GlobalEnv)
      }
    }, add = TRUE)
    set.seed(as.integer(seed))
  }
  perm_pats <- sample(pats, size = n_pats, replace = FALSE)

  n_val <- if (val_frac > 0) max(1L, as.integer(round(n_pats * val_frac))) else 0L
  n_test <- if (test_frac > 0) max(1L, as.integer(round(n_pats * test_frac))) else 0L
  if (n_val + n_test >= n_pats && n_pats >= 3L) {
    n_val <- 1L
    n_test <- 1L
  }

  split_map <- stats::setNames(rep("train", n_pats), perm_pats)
  if (n_val > 0L) {
    split_map[seq_len(n_val)] <- "val"
  }
  if (n_test > 0L && (n_val + n_test) <= n_pats) {
    split_map[(n_val + 1L):(n_val + n_test)] <- "test"
  }

  out <- tibble::as_tibble(cohort)
  out$split <- unname(split_map[as.character(out[[patient_col]])])
  out
}
