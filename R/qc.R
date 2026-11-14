#' Automated Image Quality Control for DICOM Volumes
#'
#' Evaluates signal-to-noise ratio (SNR), contrast-to-noise ratio (CNR),
#' field-of-view (FOV) border truncation, slice spacing regularity, gantry
#' tilt, and high-frequency striping/ringing artifacts on a
#' [`dicom_volume`][new_dicom_volume].
#'
#' @param vol A [`dicom_volume`][new_dicom_volume] object.
#' @param snr_warn Minimum acceptable SNR before raising a warning (default
#'   `5.0`).
#' @param border_threshold_frac Maximum fraction of FOV perimeter voxels
#'   allowed above the foreground threshold before flagging border truncation
#'   (default `0.05`).
#' @param artifact_warn High-frequency artifact score threshold for `"WARN"`
#'   (default `0.35`).
#' @param artifact_fail High-frequency artifact score threshold for `"FAIL"`
#'   (default `0.65`).
#' @param tilt_warn_deg Maximum slice-normal tilt angle in degrees before
#'   flagging `tilt_anomaly` (default `1.0`).
#'
#' @return A list with components `snr`, `cnr`, `border_truncation`,
#'   `spacing_anomaly`, `tilt_anomaly`, `artifact_score`, `qc_status`
#'   (`"PASS"`, `"WARN"`, or `"FAIL"`), and `issues` (character vector).
#' @export
dicom_image_qc <- function(vol,
                           snr_warn = 5.0,
                           border_threshold_frac = 0.05,
                           artifact_warn = 0.35,
                           artifact_fail = 0.65,
                           tilt_warn_deg = 1.0) {
  if (!inherits(vol, "dicom_volume") || is.null(vol$voxels)) {
    cli::cli_abort("{.arg vol} must be a valid {.cls dicom_volume} object.")
  }

  arr <- vol$voxels
  if (length(dim(arr)) == 4L) {
    arr <- arr[, , , 1L, drop = FALSE]
    dim(arr) <- dim(arr)[1:3]
  }
  if (length(dim(arr)) != 3L) {
    cli::cli_abort("{.arg vol} must contain a 3D or 4D voxel array.")
  }

  vals <- as.numeric(arr)
  vals_fin <- vals[is.finite(vals)]
  if (length(vals_fin) == 0L) {
    return(list(
      snr = 0.0,
      cnr = 0.0,
      border_truncation = FALSE,
      spacing_anomaly = TRUE,
      tilt_anomaly = FALSE,
      artifact_score = 1.0,
      qc_status = "FAIL",
      issues = "no_finite_voxels"
    ))
  }

  vmin <- min(vals_fin)
  vmax <- max(vals_fin)
  vrange <- vmax - vmin

  if (vrange < 1e-9) {
    snr <- 0.0
    cnr <- 0.0
    border_truncation <- FALSE
    artifact_score <- 0.0
  } else {
    fg_thresh <- vmin + 0.25 * vrange
    fg <- vals_fin[vals_fin > fg_thresh]
    bg <- vals_fin[vals_fin <= fg_thresh]
    mean_fg <- if (length(fg) > 0L) mean(fg) else vmax
    mean_bg <- if (length(bg) > 0L) mean(bg) else vmin
    sd_fg <- if (length(fg) > 1L) stats::sd(fg) else 0.0
    sd_bg <- if (length(bg) > 1L) stats::sd(bg) else 0.0

    diff_means <- abs(mean_fg - mean_bg)
    noise_floor <- max(sd_bg, 1.0)
    snr <- diff_means / noise_floor
    cnr <- diff_means / sqrt(0.5 * (sd_fg^2 + sd_bg^2) + 1.0)

    # Border truncation: outer 1-voxel perimeter across all slices
    nr <- dim(arr)[1L]
    nc <- dim(arr)[2L]
    if (nr >= 3L && nc >= 3L) {
      perim_vals <- c(
        as.numeric(arr[1L, , , drop = FALSE]),
        as.numeric(arr[nr, , , drop = FALSE]),
        as.numeric(arr[2:(nr - 1L), 1L, , drop = FALSE]),
        as.numeric(arr[2:(nr - 1L), nc, , drop = FALSE])
      )
      perim_fin <- perim_vals[is.finite(perim_vals)]
      trunc_frac <- if (length(perim_fin) > 0L) {
        mean(perim_fin > (vmin + 0.35 * vrange))
      } else {
        0.0
      }
      border_truncation <- isTRUE(trunc_frac > border_threshold_frac)
    } else {
      border_truncation <- FALSE
    }

    # High-frequency striping / ringing score normalized by signal variance
    tot_var <- stats::var(vals_fin)
    if (!is.finite(tot_var) || tot_var < 1e-12) {
      artifact_score <- 0.0
    } else {
      hf_x <- if (nr >= 2L) mean((arr[-1L, , , drop = FALSE] - arr[-nr, , , drop = FALSE])^2, na.rm = TRUE) else 0.0
      hf_y <- if (nc >= 2L) mean((arr[, -1L, , drop = FALSE] - arr[, -nc, , drop = FALSE])^2, na.rm = TRUE) else 0.0
      raw_score <- (hf_x + hf_y) / (4.0 * tot_var)
      artifact_score <- max(0.0, min(1.0, as.numeric(raw_score)))
    }
  }

  spacing_anomaly <- isTRUE(vol$diagnostics$irregular_spacing) ||
    any(!is.finite(vol$spacing)) || any(vol$spacing <= 0)

  tilt_anomaly <- FALSE
  if (!is.null(vol$affine) && is.matrix(vol$affine) && all(dim(vol$affine) >= c(3L, 3L))) {
    m3 <- vol$affine[1:3, 1:3, drop = FALSE]
    norms <- sqrt(colSums(m3^2))
    if (all(norms > 1e-9)) {
      c1 <- m3[, 1L] / norms[1L]
      c2 <- m3[, 2L] / norms[2L]
      c3 <- m3[, 3L] / norms[3L]
      nrm <- c(
        c1[2L] * c2[3L] - c1[3L] * c2[2L],
        c1[3L] * c2[1L] - c1[1L] * c2[3L],
        c1[1L] * c2[2L] - c1[2L] * c2[1L]
      )
      nrm_len <- sqrt(sum(nrm^2))
      if (nrm_len > 1e-9) {
        nrm <- nrm / nrm_len
        ang_deg <- acos(min(1.0, abs(sum(c3 * nrm)))) * 180.0 / pi
        tilt_anomaly <- isTRUE(ang_deg > tilt_warn_deg)
      }
    }
  }

  issues <- character(0)
  if (snr < snr_warn) issues <- c(issues, "low_snr")
  if (border_truncation) issues <- c(issues, "border_truncation")
  if (spacing_anomaly) issues <- c(issues, "spacing_anomaly")
  if (tilt_anomaly) issues <- c(issues, "tilt_anomaly")
  if (artifact_score >= artifact_warn) issues <- c(issues, "high_frequency_artifact")

  qc_status <- if (artifact_score >= artifact_fail || length(issues) >= 2L) {
    "FAIL"
  } else if (length(issues) >= 1L) {
    "WARN"
  } else {
    "PASS"
  }

  list(
    snr = as.numeric(snr),
    cnr = as.numeric(cnr),
    border_truncation = border_truncation,
    spacing_anomaly = spacing_anomaly,
    tilt_anomaly = tilt_anomaly,
    artifact_score = as.numeric(artifact_score),
    qc_status = qc_status,
    issues = issues
  )
}
