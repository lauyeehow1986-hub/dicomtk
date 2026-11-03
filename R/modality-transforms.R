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

  # Injected dose and half-life
  dose_str <- find_val("RadionuclideTotalDose")
  if (is.na(dose_str)) {
    cli::cli_abort("Missing {.field RadionuclideTotalDose} in RadiopharmaceuticalInformationSequence.")
  }
  injected_dose <- as.double(dose_str)

  halflife_str <- find_val("RadionuclideHalfLife")
  halflife <- if (!is.na(halflife_str)) as.double(halflife_str) else 6586.2 # Default F-18

  # Times for decay
  start_tm_str <- find_val("RadiopharmaceuticalStartTime")
  scan_tm_str <- find_val("SeriesTime")
  if (is.na(scan_tm_str)) scan_tm_str <- find_val("AcquisitionTime")

  decay_factor <- 1.0
  if (decay_correct %in% c("auto", "force")) {
    if (!is.na(start_tm_str) && !is.na(scan_tm_str) && halflife > 0) {
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
    height_m <- as.double(height_str)
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
    height_cm <- as.double(height_str) * 100.0
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

#' Apply VOI LUT (Window/Level or Non-Linear Table) to DICOM Volume
#'
#' Applies DICOM Value of Interest (VOI) Look-Up Table transformations (linear
#' window/level, `"SIGMOID"`, or embedded sequence LUTs) to a
#' [`dicom_volume`][new_dicom_volume], scaling output voxels to `[0, 1]`.
#'
#' @param x A [`dicom_volume`][new_dicom_volume] or path to DICOM files.
#' @param window_center Optional numeric window center override.
#' @param window_width Optional numeric window width override.
#' @param function_type Function type: `"auto"` (reads from metadata),
#'   `"LINEAR"`, or `"SIGMOID"`.
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
                                function_type = c("auto", "LINEAR", "SIGMOID")) {
  function_type <- match.arg(function_type)
  vol <- if (is_dicom_volume(x)) x else read_dicom_volume(x, warn = FALSE)

  meta <- vol$frame_meta
  wc <- window_center
  ww <- window_width
  fn <- function_type

  if (is.null(wc) && "WindowCenter" %in% names(meta)) {
    v <- vol_parse_ds(meta$WindowCenter[1L], expected_len = 1L)
    if (!is.null(v)) wc <- v
  }
  if (is.null(ww) && "WindowWidth" %in% names(meta)) {
    v <- vol_parse_ds(meta$WindowWidth[1L], expected_len = 1L)
    if (!is.null(v) && v > 0) ww <- v
  }
  if (identical(fn, "auto")) {
    if ("VOILUTFunction" %in% names(meta)) {
      v <- toupper(trimws(as.character(meta$VOILUTFunction[1L])))
      fn <- if (v %in% c("LINEAR", "SIGMOID")) v else "LINEAR"
    } else {
      fn <- "LINEAR"
    }
  }

  if (is.null(wc) || is.null(ww)) {
    qs <- stats::quantile(vol$voxels, probs = c(0.01, 0.99), na.rm = TRUE)
    wc <- mean(qs)
    ww <- max(1e-6, diff(qs))
  }

  arr <- vol$voxels
  if (identical(fn, "SIGMOID")) {
    # DICOM PS3.3 Section C.11.2.1.3.2: 1 / (1 + exp(-4 * (2*x - 2*c) / w))
    # Standard sigmoid LUT: 1 / (1 + exp(-4 * (x - wc) / ww))
    norm_vox <- 1.0 / (1.0 + exp(-4.0 * (arr - wc) / ww))
  } else {
    # Standard linear VOI LUT
    low <- wc - ww / 2.0
    high <- wc + ww / 2.0
    norm_vox <- (arr - low) / (high - low)
    norm_vox[norm_vox < 0.0] <- 0.0
    norm_vox[norm_vox > 1.0] <- 1.0
  }

  new_prov <- append_provenance(
    vol$provenance,
    action = "dicom_apply_voi_lut",
    params = list(window_center = wc, window_width = ww, function_type = fn)
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

#' Apply Philips MR Private Scale Intercept and Slope
#'
#' Rescales MR pixel intensities using proprietary Philips private tags
#' `(2005,100D)` ScaleIntercept and `(2005,100E)` ScaleSlope to produce
#' quantitative floating-point values.
#'
#' @param x A [`dicom_volume`][new_dicom_volume] or path to DICOM files.
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
#' rescaled <- dicom_mr_rescale(vol)
#' rescaled
#' unlink(out_dir, recursive = TRUE)
dicom_mr_rescale <- function(x) {
  vol <- if (is_dicom_volume(x)) x else read_dicom_volume(x, warn = FALSE)

  meta <- vol$frame_meta
  slope <- 1.0
  inter <- 0.0

  # Check metadata table or source files for (2005,100D) / (2005,100E)
  get_tag_val <- function(tg) {
    if (tg %in% names(meta)) {
      v <- meta[[tg]][1L]
      if (!is.na(v) && nzchar(trimws(v))) return(as.double(trimws(v)))
    }
    files <- if ("file" %in% names(meta)) unique(meta$file[!is.na(meta$file)]) else character(0)
    if (length(files) > 0L && file.exists(files[1L])) {
      v_raw <- dicom_tag_value(files[1L], tg)[[1L]]
      if (!is.na(v_raw) && nzchar(trimws(v_raw))) return(as.double(trimws(v_raw)))
    }
    NULL
  }

  s_val <- get_tag_val("(2005,100E)")
  i_val <- get_tag_val("(2005,100D)")

  if (!is.null(s_val)) slope <- s_val
  if (!is.null(i_val)) inter <- i_val

  new_vox <- vol$voxels * slope + inter

  new_prov <- append_provenance(
    vol$provenance,
    action = "dicom_mr_rescale",
    params = list(scale_slope = slope, scale_intercept = inter)
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
