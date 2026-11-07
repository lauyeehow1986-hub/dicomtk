# Modality-Specific Quantitative Transforms
# (PET SUV, MG/DX VOI LUT, and MR Private Rescaling)

#' Calculate Standardized Uptake Value (SUV) for PET Volumes
#'
#' Computes SUV body weight (`"bw"`), lean body mass (`"lbm"`, Janmahasatian
#' 2005), or body surface area (`"bsa"`, DuBois & DuBois) from a PET
#' [`dicom_volume`][new_dicom_volume] or path.
#'
#' @param x A [`dicom_volume`][new_dicom_volume] object or path to DICOM PET files.
#' @param method SUV normalization method: `"bw"` (body weight, default),
#'   `"lbm"` (lean body mass), or `"bsa"` (body surface area).
#' @param decay_correct Decay correction handling: `"auto"` (default, uses
#'   `SeriesTime` or `AcquisitionTime` with radiopharmaceutical start time if
#'   `CorrectedImage` indicates decay correction), `"none"`, or `"force"`.
#'
#' @return A [`dicom_volume`][new_dicom_volume] object with voxel values
#'   converted to SUV (units `"g/ml"` for `"bw"` and `"lbm"`, or `"cm2/ml"` for
#'   `"bsa"`), updated metadata, and appended provenance.
#' @export
#' @examples
#' out_dir <- tempfile("pet_demo_")
#' dicom_synthesize(out_dir = out_dir, modality = "PT", dims = c(16L, 16L, 2L))
#' vol <- read_dicom_volume(out_dir)
#' suv_vol <- dicom_pet_suv(vol, method = "bw")
#' suv_vol
#' unlink(out_dir, recursive = TRUE)
dicom_pet_suv <- function(x,
                          method = c("bw", "lbm", "bsa"),
                          decay_correct = c("auto", "none", "force")) {
  method <- match.arg(method)
  decay_correct <- match.arg(decay_correct)

  vol <- if (is_dicom_volume(x)) {
    x
  } else {
    read_dicom_volume(x, warn = FALSE)
  }

  meta <- vol$frame_meta
  if (nrow(meta) == 0L) {
    cli::cli_abort("PET volume contains no metadata for SUV calculation.")
  }

  # First check source files for RadiopharmaceuticalInformationSequence if not flattened
  files <- if ("file" %in% names(meta)) unique(meta$file[!is.na(meta$file)]) else character(0)
  hdr_sq <- NULL
  if (length(files) > 0L && file.exists(files[1L])) {
    hdr_sq <- read_dicom(files[1L], include_sequences = TRUE)
  }

  # Helper to lookup tag/keyword from meta or sequence header
  find_val <- function(kw) {
    if (kw %in% names(meta)) {
      v <- meta[[kw]][1L]
      if (!is.na(v) && nzchar(trimws(v))) return(trimws(v))
    }
    if (!is.null(hdr_sq)) {
      idx <- which(hdr_sq$keyword == kw & nzchar(hdr_sq$value))
      if (length(idx) > 0L) {
        return(trimws(hdr_sq$value[idx[1L]]))
      }
    }
    NA_character_
  }

  # Verify pixel units are BQML when Units metadata is present
  units_hdr <- find_val("Units")
  if (is.na(units_hdr) && !is.na(vol$units) && nzchar(vol$units)) {
    units_hdr <- vol$units
  }
  if (!is.na(units_hdr) && toupper(trimws(units_hdr)) != "BQML") {
    cli::cli_abort(
      "PET SUV calculation requires {.field Units} = {.val BQML}, got {.val {units_hdr}}."
    )
  }

  # Injected dose and half-life
  dose_str <- find_val("RadionuclideTotalDose")
  if (is.na(dose_str)) {
    cli::cli_abort("Missing {.field RadionuclideTotalDose} in RadiopharmaceuticalInformationSequence.")
  }
  injected_dose <- as.double(dose_str)
  if (!is.finite(injected_dose) || injected_dose <= 0) {
    cli::cli_abort("Invalid {.field RadionuclideTotalDose}: {dose_str}")
  }

  halflife_str <- find_val("RadionuclideHalfLife")
  halflife <- if (!is.na(halflife_str)) as.double(halflife_str) else 6586.2 # Default F-18

  # Times and decay-correction mode
  start_tm_str <- find_val("RadiopharmaceuticalStartTime")
  scan_tm_str <- find_val("SeriesTime")
  if (is.na(scan_tm_str)) scan_tm_str <- find_val("AcquisitionTime")

  should_decay <- FALSE
  if (identical(decay_correct, "force")) {
    should_decay <- TRUE
  } else if (identical(decay_correct, "auto")) {
    decay_tag <- find_val("DecayCorrection")
    corr_tag <- find_val("CorrectedImage")
    decay_mode <- if (!is.na(decay_tag)) toupper(trimws(decay_tag)) else NA_character_
    has_decy <- !is.na(corr_tag) && grepl("DECY", toupper(corr_tag), fixed = TRUE)
    if (!is.na(decay_mode)) {
      should_decay <- identical(decay_mode, "START")
    } else if (!is.na(corr_tag)) {
      should_decay <- has_decy
    } else {
      should_decay <- TRUE
    }
  }

  decay_factor <- 1.0
  if (should_decay) {
    if (!is.na(start_tm_str) && !is.na(scan_tm_str) && is.finite(halflife) && halflife > 0) {
      t_start <- vol_parse_tm_sec(start_tm_str)
      t_scan <- vol_parse_tm_sec(scan_tm_str)
      if (is.finite(t_start) && is.finite(t_scan)) {
        dt <- t_scan - t_start
        if (dt < 0) dt <- dt + 86400.0 # midnight rollover
        decay_factor <- 2^(-dt / halflife)
      }
    }
  }

  decayed_dose <- injected_dose * decay_factor
  if (decayed_dose <= 0) {
    cli::cli_abort("Decayed dose is non-positive or invalid.")
  }

  # Weight (kg -> g)
  weight_str <- find_val("PatientWeight")
  if (is.na(weight_str) || !nzchar(weight_str)) {
    cli::cli_abort("Missing {.field PatientWeight} tag required for PET SUV calculation.")
  }
  weight_kg <- as.double(weight_str)
  if (!is.finite(weight_kg) || weight_kg <= 0) {
    cli::cli_abort("Invalid {.field PatientWeight}: {weight_str}")
  }
  weight_g <- weight_kg * 1000.0

  scale_factor <- 1.0
  unit_str <- "g/ml"

  if (method == "bw") {
    # SUVbw = (activity in Bq/mL) / (decayed_dose in Bq / weight in g)
    scale_factor <- weight_g / decayed_dose
    unit_str <- "g/ml"
  } else if (method == "lbm") {
    height_str <- find_val("PatientSize")
    sex_str <- find_val("PatientSex")
    if (is.na(height_str)) {
      cli::cli_abort("Missing {.field PatientSize} (height in meters) required for SUVlbm.")
    }
    height_m <- suppressWarnings(as.double(height_str))
    if (!is.finite(height_m) || height_m <= 0) {
      cli::cli_abort("Invalid {.field PatientSize} (height in meters): {height_str}")
    }
    bmi <- weight_kg / (height_m^2)
    is_female <- !is.na(sex_str) && toupper(sex_str) %in% c("F", "FEMALE")
    lbm_kg <- if (is_female) {
      (9270 * weight_kg) / (8780 + 244 * bmi)
    } else {
      (9270 * weight_kg) / (6680 + 216 * bmi)
    }
    lbm_g <- lbm_kg * 1000.0
    scale_factor <- lbm_g / decayed_dose
    unit_str <- "g/ml"
  } else if (method == "bsa") {
    height_str <- find_val("PatientSize")
    if (is.na(height_str)) {
      cli::cli_abort("Missing {.field PatientSize} required for SUVbsa.")
    }
    height_m <- suppressWarnings(as.double(height_str))
    if (!is.finite(height_m) || height_m <= 0) {
      cli::cli_abort("Invalid {.field PatientSize} (height in meters): {height_str}")
    }
    height_cm <- height_m * 100.0
    bsa_m2 <- 0.007184 * (weight_kg^0.425) * (height_cm^0.725)
    # SUVbsa = (activity Bq/mL) / (decayed_dose Bq / (bsa_m2 * 10000 cm2))
    scale_factor <- (bsa_m2 * 10000.0) / decayed_dose
    unit_str <- "cm2/ml"
  }

  suv_voxels <- vol$voxels * scale_factor

  new_prov <- append_provenance(
    vol$provenance,
    action = "dicom_pet_suv",
    params = list(
      method = method,
      decay_correct = decay_correct,
      decay_factor = decay_factor,
      scale_factor = scale_factor
    )
  )

  new_dicom_volume(
    voxels = suv_voxels,
    affine = vol$affine,
    coord_system = vol$coord_system,
    spacing = vol$spacing,
    direction = vol$direction,
    frame_meta = vol$frame_meta,
    uids = vol$uids,
    modality = vol$modality,
    units = unit_str,
    diagnostics = vol$diagnostics,
    provenance = new_prov
  )
}

#' Apply VOI LUT (Window/Level or Sigmoidal Transfer Function) to DICOM Volume
#'
#' Applies DICOM PS3.3 Section C.11.2.1 Value of Interest (VOI) transformations
#' (`"LINEAR"`, `"LINEAR_EXACT"`, or `"SIGMOID"`) to a
#' [`dicom_volume`][new_dicom_volume], scaling output voxels to `[0, 1]` and
#' optionally inverting `PhotometricInterpretation == "MONOCHROME1"` so higher
#' attenuation appears brighter.
#'
#' @param x A [`dicom_volume`][new_dicom_volume] or path to DICOM files.
#' @param window_center Optional numeric window center override.
#' @param window_width Optional numeric window width override.
#' @param function_type VOI LUT function type: `"auto"` (reads `VOILUTFunction`
#'   from metadata, defaulting to `"LINEAR"`), `"LINEAR"`, `"LINEAR_EXACT"`, or
#'   `"SIGMOID"`.
#' @param index 1-based integer index selecting which `(WindowCenter,
#'   WindowWidth)` preset to apply when multi-valued presets (e.g. `"40\\400"`)
#'   are stored in the DICOM header. Default is `1L`.
#' @param invert_monochrome1 Logical. When `TRUE` (default) and
#'   `PhotometricInterpretation == "MONOCHROME1"`, inverts normalized intensities
#'   (`1 - y`) for standard presentation polarity.
#'
#' @return A [`dicom_volume`][new_dicom_volume] with voxels scaled to `[0, 1]`
#'   and `units = "normalized"`.
#' @export
#' @examples
#' out_dir <- tempfile("mg_demo_")
#' dicom_synthesize(out_dir = out_dir, modality = "MG", dims = c(16L, 16L, 1L))
#' vol <- read_dicom_volume(out_dir)
#' voi_vol <- dicom_apply_voi_lut(vol)
#' range(voi_vol$voxels)
#' unlink(out_dir, recursive = TRUE)
dicom_apply_voi_lut <- function(x,
                                window_center = NULL,
                                window_width = NULL,
                                function_type = c("auto", "LINEAR", "LINEAR_EXACT", "SIGMOID"),
                                index = 1L,
                                invert_monochrome1 = TRUE) {
  function_type <- match.arg(function_type)
  if (!is.numeric(index) || length(index) != 1L || !is.finite(index) ||
      index < 1 || index != floor(index)) {
    cli::cli_abort("{.arg index} must be a positive integer.")
  }
  idx <- as.integer(index)
  if (!is.logical(invert_monochrome1) || length(invert_monochrome1) != 1L || is.na(invert_monochrome1)) {
    cli::cli_abort("{.arg invert_monochrome1} must be {.val TRUE} or {.val FALSE}.")
  }

  vol <- if (is_dicom_volume(x)) x else read_dicom_volume(x, warn = FALSE)

  meta <- vol$frame_meta
  wc <- window_center
  ww <- window_width
  fn <- function_type

  if (is.null(wc) && "WindowCenter" %in% names(meta) && nrow(meta) > 0L) {
    vals <- vol_parse_ds(meta$WindowCenter[1L])
    if (!is.null(vals) && length(vals) > 0L) {
      if (idx > length(vals)) {
        cli::cli_abort("Requested VOI {.arg index} = {idx}, but only {length(vals)} WindowCenter value(s) present.")
      }
      if (is.finite(vals[idx])) wc <- vals[idx]
    }
  }
  if (is.null(ww) && "WindowWidth" %in% names(meta) && nrow(meta) > 0L) {
    vals <- vol_parse_ds(meta$WindowWidth[1L])
    if (!is.null(vals) && length(vals) > 0L) {
      if (idx > length(vals)) {
        cli::cli_abort("Requested VOI {.arg index} = {idx}, but only {length(vals)} WindowWidth value(s) present.")
      }
      if (is.finite(vals[idx]) && vals[idx] > 0) ww <- vals[idx]
    }
  }
  if (identical(fn, "auto")) {
    if ("VOILUTFunction" %in% names(meta) && nrow(meta) > 0L) {
      v <- toupper(trimws(as.character(meta$VOILUTFunction[1L])))
      fn <- if (v %in% c("LINEAR", "LINEAR_EXACT", "SIGMOID")) v else "LINEAR"
    } else {
      fn <- "LINEAR"
    }
  }

  if (is.null(wc) || is.null(ww)) {
    qs <- stats::quantile(vol$voxels, probs = c(0.01, 0.99), na.rm = TRUE)
    wc <- mean(qs)
    ww <- max(1e-6, diff(qs))
  }
  if (!is.numeric(wc) || length(wc) != 1L || !is.finite(wc)) {
    cli::cli_abort("{.arg window_center} must be a single finite number.")
  }
  if (!is.numeric(ww) || length(ww) != 1L || !is.finite(ww) || ww <= 0) {
    cli::cli_abort("{.arg window_width} must be a single positive number.")
  }

  arr <- vol$voxels
  if (identical(fn, "SIGMOID")) {
    # DICOM PS3.3 Section C.11.2.1.3.1
    norm_vox <- 1.0 / (1.0 + exp(-4.0 * (arr - wc) / ww))
  } else if (identical(fn, "LINEAR_EXACT")) {
    # DICOM PS3.3 Section C.11.2.1.3.2
    norm_vox <- (arr - wc) / ww + 0.5
    norm_vox[norm_vox < 0.0] <- 0.0
    norm_vox[norm_vox > 1.0] <- 1.0
  } else {
    # DICOM PS3.3 Section C.11.2.1.2.1 (LINEAR)
    if (ww <= 1.0) {
      norm_vox <- array(ifelse(arr <= (wc - 0.5), 0.0, 1.0), dim = dim(arr), dimnames = dimnames(arr))
    } else {
      norm_vox <- ((arr - (wc - 0.5)) / (ww - 1.0)) + 0.5
      norm_vox[norm_vox < 0.0] <- 0.0
      norm_vox[norm_vox > 1.0] <- 1.0
    }
  }

  photo <- if ("PhotometricInterpretation" %in% names(meta) && nrow(meta) > 0L) {
    toupper(trimws(as.character(meta$PhotometricInterpretation[1L])))
  } else {
    ""
  }
  inverted <- isTRUE(invert_monochrome1) && identical(photo, "MONOCHROME1")
  if (inverted) {
    norm_vox <- 1.0 - norm_vox
  }

  new_prov <- append_provenance(
    vol$provenance,
    action = "dicom_apply_voi_lut",
    params = list(
      window_center = wc,
      window_width = ww,
      function_type = fn,
      index = idx,
      monochrome1_inverted = inverted
    )
  )

  new_dicom_volume(
    voxels = norm_vox,
    affine = vol$affine,
    coord_system = vol$coord_system,
    spacing = vol$spacing,
    direction = vol$direction,
    frame_meta = vol$frame_meta,
    uids = vol$uids,
    modality = vol$modality,
    units = "normalized",
    diagnostics = vol$diagnostics,
    provenance = new_prov
  )
}

#' Apply Philips MR Quantitative Floating-Point or Console Display Scaling
#'
#' Rescales MR pixel intensities following Chenevert et al. (2014) and the
#' Philips DICOM Conformance Statement using public `RescaleIntercept
#' (0028,1052)` (`RI`) / `RescaleSlope (0028,1053)` (`RS`) and proprietary
#' Philips private tags `(2005,100D)` (`ScaleIntercept`, `SI`) and `(2005,100E)`
#' (`ScaleSlope`, `SS`).
#'
#' For stored integer pixel values `R`, console display values are
#' \eqn{D = R \times RS + RI}{D = R * RS + RI} and quantitative floating-point
#' values are \eqn{P = D / (RS \times SS)}{P = D / (RS * SS)}. Automatically
#' accounts for whether `x` was already `RS`/`RI`-rescaled by
#' [read_dicom_volume()], preventing double-rescaling.
#'
#' @param x A [`dicom_volume`][new_dicom_volume] or path to DICOM files.
#' @param philips_float Logical. When `TRUE` (default) and Philips `ScaleSlope`
#'   `(2005,100E)` is present, returns quantitative floating-point values
#'   \eqn{P = D / (RS \times SS)}{P = D / (RS * SS)}; when `FALSE`, returns
#'   console display values `D`.
#'
#' @return A [`dicom_volume`][new_dicom_volume] with rescaled voxel values and
#'   appended provenance.
#' @export
#' @examples
#' out_dir <- tempfile("mr_demo_")
#' dicom_synthesize(
#'   out_dir = out_dir,
#'   modality = "MR",
#'   dims = c(16L, 16L, 2L),
#'   extra_tags = list("(2005,100D)" = "5.0", "(2005,100E)" = "2.0")
#' )
#' vol <- read_dicom_volume(out_dir)
#' rescaled <- dicom_mr_rescale(vol, philips_float = TRUE)
#' rescaled
#' unlink(out_dir, recursive = TRUE)
dicom_mr_rescale <- function(x, philips_float = TRUE) {
  if (!is.logical(philips_float) || length(philips_float) != 1L || is.na(philips_float)) {
    cli::cli_abort("{.arg philips_float} must be {.val TRUE} or {.val FALSE}.")
  }

  vol <- if (is_dicom_volume(x)) x else read_dicom_volume(x, rescale = FALSE, warn = FALSE)
  meta <- vol$frame_meta

  was_rescaled <- FALSE
  for (entry in vol$provenance) {
    if (is.list(entry) && identical(entry$action, "read_dicom_volume")) {
      was_rescaled <- isTRUE(entry$params$rescale)
    }
  }

  get_tag_val <- function(candidates) {
    for (tg in candidates) {
      if (tg %in% names(meta) && nrow(meta) > 0L) {
        v <- meta[[tg]][1L]
        if (!is.na(v) && nzchar(trimws(as.character(v)))) {
          num <- suppressWarnings(as.double(trimws(as.character(v))))
          if (is.finite(num)) return(num)
        }
      }
    }
    files <- if ("file" %in% names(meta)) unique(meta$file[!is.na(meta$file)]) else character(0)
    if (length(files) > 0L && file.exists(files[1L])) {
      for (tg in candidates) {
        v_raw <- tryCatch(dicom_tag_value(files[1L], tg)[[1L]], error = function(e) NA_character_)
        if (!is.na(v_raw) && nzchar(trimws(v_raw))) {
          num <- suppressWarnings(as.double(trimws(v_raw)))
          if (is.finite(num)) return(num)
        }
      }
    }
    NULL
  }

  # Recover raw stored pixel values PV if read_dicom_volume(rescale = TRUE) already applied RS/RI
  rs_applied <- if ("rescale_slope" %in% names(meta) && nrow(meta) > 0L &&
                    is.finite(as.double(meta$rescale_slope[1L])) &&
                    as.double(meta$rescale_slope[1L]) != 0) {
    as.double(meta$rescale_slope[1L])
  } else {
    1.0
  }
  ri_applied <- if ("rescale_intercept" %in% names(meta) && nrow(meta) > 0L &&
                    is.finite(as.double(meta$rescale_intercept[1L]))) {
    as.double(meta$rescale_intercept[1L])
  } else {
    0.0
  }

  pv <- if (was_rescaled) {
    (vol$voxels - ri_applied) / rs_applied
  } else {
    vol$voxels
  }

  rs_pub_raw <- get_tag_val(c("RescaleSlope", "(0028,1053)"))
  ri_pub_raw <- get_tag_val(c("RescaleIntercept", "(0028,1052)"))
  si_priv <- get_tag_val(c("(2005,100D)", "(2005,100d)"))
  ss_priv <- get_tag_val(c("(2005,100E)", "(2005,100e)"))

  # Also detect explicit zero ScaleSlope strings before numeric coercion drops non-finite
  if (is.null(ss_priv)) {
    files <- if ("file" %in% names(meta)) unique(meta$file[!is.na(meta$file)]) else character(0)
    if (length(files) > 0L && file.exists(files[1L])) {
      raw_ss <- tryCatch(dicom_tag_value(files[1L], "(2005,100E)")[[1L]], error = function(e) NA_character_)
      if (!is.na(raw_ss) && nzchar(trimws(raw_ss))) {
        cli::cli_abort("Invalid Philips private {.field ScaleSlope} (2005,100E): {raw_ss}")
      }
    }
  }
  if (!is.null(ss_priv) && abs(ss_priv) < 1e-12) {
    cli::cli_abort("Invalid Philips private {.field ScaleSlope} (2005,100E): must be non-zero.")
  }

  rs_eff <- if (!is.null(rs_pub_raw) && abs(rs_pub_raw) >= 1e-12) rs_pub_raw else rs_applied
  ri_eff <- if (!is.null(ri_pub_raw)) {
    ri_pub_raw
  } else if (!is.null(si_priv)) {
    si_priv
  } else {
    ri_applied
  }

  dv <- pv * rs_eff + ri_eff
  use_fp <- isTRUE(philips_float) && !is.null(ss_priv)
  new_vox <- if (use_fp) {
    dv / (rs_eff * ss_priv)
  } else {
    dv
  }

  new_prov <- append_provenance(
    vol$provenance,
    action = "dicom_mr_rescale",
    params = list(
      philips_float = philips_float,
      used_philips_float = use_fp,
      rescale_slope = rs_eff,
      rescale_intercept = ri_eff,
      scale_slope = ss_priv,
      scale_intercept = si_priv
    )
  )

  new_dicom_volume(
    voxels = new_vox,
    affine = vol$affine,
    coord_system = vol$coord_system,
    spacing = vol$spacing,
    direction = vol$direction,
    frame_meta = vol$frame_meta,
    uids = vol$uids,
    modality = vol$modality,
    units = vol$units,
    diagnostics = vol$diagnostics,
    provenance = new_prov
  )
}
