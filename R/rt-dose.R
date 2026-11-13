#' Compute Dose-Volume Histogram (DVH) and Clinical Radiation Metrics
#'
#' Evaluates cumulative and differential Dose-Volume Histograms (DVHs) and
#' extracts key radiation oncology clinical metrics ($D_{95}$, $D_{90}$,
#' $D_{50}$, $V_{20}$, min, max, and mean dose) across ROIs from an `RTDOSE`
#' volume and a [dicom_seg] mask.
#'
#' @param dose An `RTDOSE` [dicom_volume] or path to a DICOM `RTDOSE` file.
#' @param seg A [dicom_seg] segmentation object containing one or more ROIs.
#' @param n_bins Number of dose bins for the histogram curves. Default is `100L`.
#'
#' @return An object of class `"dicom_dvh"` containing:
#'   \item{metrics}{A tibble with clinical metrics per ROI (`roi_number`, `roi_label`, `volume_cc`, `min_dose`, `max_dose`, `mean_dose`, `D95`, `D90`, `D50`, `V20`).}
#'   \item{curves}{A tibble of dose evaluation points with cumulative (`vol_pct_cumulative`) and differential (`vol_pct_differential`) volumes.}
#' @export
#' @examples
#' synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 5L))
#' vol <- read_dicom_volume(synth[["out_dir"]])
#' # See vignette for full DVH analytics pipeline
dicom_dvh <- function(dose, seg, n_bins = 100L) {
  if (is.character(dose) && length(dose) == 1L && file.exists(dose)) {
    rt_info <- read_dicom_rt(dose)
    if (!is.null(rt_info$dose_grid)) {
      dose <- new_dicom_volume(
        voxels = rt_info$dose_grid,
        modality = "RTDOSE",
        units = "Gy"
      )
    }
  }

  if (!inherits(dose, "dicom_volume")) {
    rlang::abort("`dose` must be a `dicom_volume` object.")
  }
  if (!inherits(seg, "dicom_seg") && !inherits(seg, "dicom_volume")) {
    rlang::abort("`seg` must be a `dicom_seg` object.")
  }

  dose_vox <- dose$voxels %||% dose$array
  seg_vox <- seg$voxels %||% seg$array

  same_grid <- identical(dim(dose_vox)[1:3], dim(seg_vox)[1:3]) &&
               max(abs(dose$affine - seg$affine)) < 1e-4

  voxel_vol_cc <- prod(seg$spacing[1:3]) / 1000.0 # mm^3 to cc (cm^3)

  seg_tbl <- seg$segments %||% tibble::tibble(
    segment_id = sort(unique(as.vector(seg_vox[seg_vox > 0]))),
    label = paste0("ROI_", sort(unique(as.vector(seg_vox[seg_vox > 0]))))
  )

  metrics_list <- list()
  curves_list <- list()
  dose_dims <- dim(dose_vox)[1:3]

  for (i in seq_len(nrow(seg_tbl))) {
    s_id <- seg_tbl$segment_id[i]
    s_label <- seg_tbl$label[i]

    # Extract dose values inside this segment
    roi_mask <- (seg_vox == s_id)
    n_vox <- sum(roi_mask)

    if (n_vox == 0L) {
      next
    }

    if (same_grid) {
      roi_doses <- as.double(dose_vox[roi_mask])
    } else {
      # Map ROI voxel centers through world coordinates into the dose grid
      ijk_seg <- which(roi_mask, arr.ind = TRUE)
      xyz_world <- voxel_to_world(seg, ijk_seg, index_base = 1L)
      ijk_dose <- round(world_to_voxel(dose, xyz_world, index_base = 1L))
      r_d <- pmin(pmax(as.integer(ijk_dose[, 1L]), 1L), dose_dims[1L])
      c_d <- pmin(pmax(as.integer(ijk_dose[, 2L]), 1L), dose_dims[2L])
      s_d <- pmin(pmax(as.integer(ijk_dose[, 3L]), 1L), dose_dims[3L])
      roi_doses <- as.double(dose_vox[cbind(r_d, c_d, s_d)])
    }

    total_vol_cc <- n_vox * voxel_vol_cc

    min_d <- min(roi_doses)
    max_d <- max(roi_doses)
    mean_d <- mean(roi_doses)

    # Dose quantiles:
    # D95: Dose received by at least 95% of the volume = 5th percentile of dose
    # D90: Dose received by at least 90% of the volume = 10th percentile
    # D50: Dose received by 50% of the volume = 50th percentile (median)
    d95 <- as.double(stats::quantile(roi_doses, probs = 0.05, names = FALSE))
    d90 <- as.double(stats::quantile(roi_doses, probs = 0.10, names = FALSE))
    d50 <- as.double(stats::quantile(roi_doses, probs = 0.50, names = FALSE))

    # Volume receiving at least 20 Gy
    v20 <- sum(roi_doses >= 20.0) / n_vox * 100.0

    metrics_list[[length(metrics_list) + 1L]] <- tibble::tibble(
      roi_number = s_id,
      roi_label = s_label,
      volume_cc = total_vol_cc,
      min_dose = min_d,
      max_dose = max_d,
      mean_dose = mean_d,
      D95 = d95,
      D90 = d90,
      D50 = d50,
      V20 = v20
    )

    # Compute cumulative and differential DVH curves
    eval_doses <- seq(0.0, max(max_d * 1.05, 1.0), length.out = n_bins)
    cum_vol_pct <- vapply(eval_doses, function(d_val) {
      sum(roi_doses >= d_val) / n_vox * 100.0
    }, numeric(1L))
    diff_vol_pct <- c(-diff(cum_vol_pct), cum_vol_pct[length(cum_vol_pct)])

    curves_list[[length(curves_list) + 1L]] <- tibble::tibble(
      roi_number = s_id,
      roi_label = s_label,
      dose_gy = eval_doses,
      vol_pct_cumulative = cum_vol_pct,
      vol_pct_differential = diff_vol_pct
    )
  }

  metrics_df <- if (length(metrics_list) > 0L) {
    dplyr::bind_rows(metrics_list)
  } else {
    tibble::tibble(
      roi_number = integer(),
      roi_label = character(),
      volume_cc = numeric(),
      min_dose = numeric(),
      max_dose = numeric(),
      mean_dose = numeric(),
      D95 = numeric(),
      D90 = numeric(),
      D50 = numeric(),
      V20 = numeric()
    )
  }

  curves_df <- if (length(curves_list) > 0L) {
    dplyr::bind_rows(curves_list)
  } else {
    tibble::tibble(
      roi_number = integer(),
      roi_label = character(),
      dose_gy = numeric(),
      vol_pct_cumulative = numeric(),
      vol_pct_differential = numeric()
    )
  }

  structure(
    list(
      metrics = metrics_df,
      curves = curves_df
    ),
    class = "dicom_dvh"
  )
}

#' @keywords internal
#' @export
print.dicom_dvh <- function(x, ...) {
  cat("<dicom_dvh [", nrow(x$metrics), " ROI(s)]>\n", sep = "")
  if (nrow(x$metrics) > 0L) {
    print(x$metrics, ...)
  }
  invisible(x)
}
