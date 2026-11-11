#' De-Identify a DICOM File, Directory, or Cohort
#'
#' De-identifies single DICOM files or entire cohorts according to DICOM PS3.15 Annex E
#' application-level confidentiality profiles and optional statutory jurisdiction overlays
#' (e.g. HIPAA Safe Harbor, Singapore PDPA/HIB, GDPR). Provides deterministic pseudonymization,
#' longitudinal UID and date consistency, parallel execution via \code{mirai}, structured
#' JSONL audit logging, and ChaCha20-Poly1305 encrypted crosswalk generation.
#'
#' @param path Character vector of one or more DICOM file paths, or a directory path.
#' @param out_dir Output directory path. If \code{NULL}, a temporary directory is created.
#' @param profile Character string identifying the base profile, or a compiled
#'   \code{dicom_deid_profile} object. Default is \code{"ps3.15"}.
#' @param options Character vector of standard PS3.15 options to enable.
#' @param jurisdictions Optional character vector of statutory jurisdiction overlays.
#' @param key Optional \code{dicom_key_provider} object. If \code{NULL}, a local
#'   key provider is generated.
#' @param layout Character string specifying output directory layout:
#'   \itemize{
#'     \item \code{"preserve"} (default): Preserves relative subdirectory structure.
#'     \item \code{"hierarchy"}: Formats as \code{<pseudo_pid>/<pseudo_study>/<pseudo_sop>.dcm}.
#'     \item \code{"flat"}: Places all files directly in \code{out_dir} as \code{<pseudo_sop>.dcm}.
#'   }
#' @param workers Integer number of parallel workers. When \code{workers > 1L} and
#'   the \code{mirai} package is available, files are processed concurrently.
#' @param audit_path Optional file path where structured JSONL audit records will be written.
#' @param crosswalk_path Optional file path where the AEAD-encrypted crosswalk will be saved.
#' @param override_tags Optional named list of tag-action overrides.
#' @param drop_wsi_labels Logical. Whether whole slide microscopy (WSI) label and
#'   overview instances should be skipped. Default is \code{TRUE}.
#' @param pixel_method Character string specifying pixel de-identification method:
#'   \code{"none"} (default), \code{"blackout"}, or \code{"inpaint"}. If \code{options}
#'   contains \code{"clean_pixel"} and \code{pixel_method == "none"}, defaults to \code{"blackout"}.
#' @param pixel_boxes Optional data frame or matrix with candidate pixel bounding boxes
#'   \code{(ymin, xmin, ymax, xmax)}.
#' @param overwrite Logical. Whether existing output files should be overwritten. Default is \code{FALSE}.
#'
#' @return An object of class \code{"dicom_deid_result"} containing:
#'   \item{files}{Character vector of successfully written de-identified DICOM files.}
#'   \item{summary}{Tibble summarizing input/output paths, digests, pseudonyms, and action counts.}
#'   \item{actions_total}{Named integer vector of total tag actions applied.}
#'   \item{skipped_wsi_labels}{Count of skipped WSI label/overview instances.}
#'   \item{audit_path}{Path to audit JSONL file if requested, or \code{NULL}.}
#'   \item{crosswalk_path}{Path to encrypted crosswalk file if requested, or \code{NULL}.}
#'   \item{profile}{The resolved \code{dicom_deid_profile} object.}
#'   \item{jurisdictions}{Character vector of active jurisdictions.}
#'   \item{key_provider}{The \code{dicom_key_provider} used.}
#' @export
#'
#' @examples
#' \dontrun{
#' kp <- dicom_key_provider(passphrase = "my-secret-passphrase")
#' res <- dicom_deid("path/to/dicom/dir", "path/to/out/dir", key = kp)
#' print(res)
#' }
dicom_deid <- function(path,
                       out_dir = NULL,
                       profile = "ps3.15",
                       options = character(0),
                       jurisdictions = NULL,
                       key = NULL,
                       layout = c("preserve", "hierarchy", "flat"),
                       workers = 1L,
                       audit_path = NULL,
                       crosswalk_path = NULL,
                       override_tags = list(),
                       drop_wsi_labels = TRUE,
                       pixel_method = c("none", "blackout", "inpaint"),
                       pixel_boxes = NULL,
                       overwrite = FALSE) {
  layout <- match.arg(layout)

  if (any(c("clean_pixel", "clean_pixel_data") %in% options) &&
      (identical(pixel_method, c("none", "blackout", "inpaint")) || pixel_method[1L] == "none")) {
    pixel_method <- "blackout"
  } else {
    pixel_method <- match.arg(pixel_method)
  }

  # Resolve input files
  in_files <- resolve_dicom_paths(path, recursive = TRUE)
  if (length(in_files) == 0L) {
    cli::cli_abort("No valid DICOM files found in `path`.")
  }

  # Compute relative paths for preserve layout and audit reporting
  is_single_dir <- length(path) == 1L && dir.exists(path)
  dir_root <- if (is_single_dir) normalizePath(path, winslash = "/") else ""

  rel_paths <- vapply(in_files, function(f) {
    fn <- normalizePath(f, winslash = "/")
    if (is_single_dir && startsWith(fn, dir_root)) {
      rel <- substring(fn, nchar(dir_root) + 1L)
      sub("^[/\\\\]+", "", rel)
    } else {
      basename(fn)
    }
  }, character(1), USE.NAMES = FALSE)

  # Output directory setup
  if (is.null(out_dir)) {
    out_dir <- tempfile(pattern = "dicomtk_deid_")
  }
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_dir <- normalizePath(out_dir, winslash = "/")

  # Key provider setup
  if (is.null(key)) {
    key <- dicom_key_provider()
  } else if (!is_dicom_key_provider(key)) {
    cli::cli_abort("`key` must be a valid dicom_key_provider object or NULL.")
  }

  uid_key <- deid_get_subkey(key, "uid")
  pid_key <- deid_get_subkey(key, "pid")
  date_key <- deid_get_subkey(key, "date")
  aead_key <- deid_get_subkey(key, "aead")

  # Profile resolution
  if (inherits(profile, "dicom_deid_profile")) {
    prof_spec <- profile
  } else {
    prof_spec <- dicom_deid_profile(
      profile = profile,
      options = options,
      jurisdictions = jurisdictions,
      override_tags = override_tags
    )
  }

  # Prepare temporary output paths
  tmp_dir <- file.path(out_dir, ".deid_scratch")
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
  tmp_outs <- file.path(tmp_dir, sprintf("tmp_%07d.dcm", seq_along(in_files)))

  # Process files (mirai parallel or sequential)
  use_mirai <- as.integer(workers) > 1L && requireNamespace("mirai", quietly = TRUE)

  if (use_mirai) {
    mirai::daemons(as.integer(workers))
    on.exit(mirai::daemons(0L), add = TRUE)

    is_dev <- requireNamespace("pkgload", quietly = TRUE) && pkgload::is_dev_package("dicomtk")
    dev_dir <- if (is_dev) dirname(system.file(package = "dicomtk")) else ""

    worker_fn <- function(in_p, out_p, p_spec, u_k, p_k, d_k, drop_wsi, is_d, d_dir) {
      if (is_d) {
        pkgload::load_all(d_dir, quiet = TRUE)
      } else {
        library(dicomtk)
      }
      fn <- get("cpp_deid_file", envir = asNamespace("dicomtk"))
      fn(
        in_path = in_p,
        out_path = out_p,
        profile_spec = p_spec,
        uid_key = u_k,
        pid_key = p_k,
        date_key = d_k,
        drop_wsi_labels = drop_wsi
      )
    }

    tasks <- vector("list", length(in_files))
    for (i in seq_along(in_files)) {
      tasks[[i]] <- mirai::mirai(
        worker_fn(in_p, out_p, p_spec, u_k, p_k, d_k, drop_wsi, is_d, d_dir),
        worker_fn = worker_fn,
        in_p = in_files[i],
        out_p = tmp_outs[i],
        p_spec = prof_spec,
        u_k = uid_key,
        p_k = pid_key,
        d_k = date_key,
        drop_wsi = drop_wsi_labels,
        is_d = is_dev,
        d_dir = dev_dir
      )
    }
    raw_results <- lapply(tasks, function(m) m[])
  } else {
    raw_results <- vector("list", length(in_files))
    for (i in seq_along(in_files)) {
      raw_results[[i]] <- cpp_deid_file(
        in_path = in_files[i],
        out_path = tmp_outs[i],
        profile_spec = prof_spec,
        uid_key = uid_key,
        pid_key = pid_key,
        date_key = date_key,
        drop_wsi_labels = drop_wsi_labels
      )
    }
  }

  # Layout placement and result collection
  written_files <- character(0)
  total_actions <- c(X = 0L, Z = 0L, D = 0L, U = 0L, C = 0L, K = 0L)
  skipped_wsi <- 0L

  for (i in seq_along(in_files)) {
    res_i <- raw_results[[i]]
    if (inherits(res_i, "errorValue") || inherits(res_i, "miraiError")) {
      err_msg <- if (inherits(res_i, "condition")) conditionMessage(res_i) else as.character(res_i)
      cli::cli_abort("De-identification failed for {in_files[i]}: {err_msg}")
    }

    if (isTRUE(res_i$skipped_wsi_label)) {
      skipped_wsi <- skipped_wsi + 1L
      res_i$out_file <- ""
      raw_results[[i]] <- res_i
      next
    }

    if (!is.null(res_i$actions_applied)) {
      total_actions <- total_actions + res_i$actions_applied
    }

    # Pixel de-identification (blackout or inpaint) if requested
    if (pixel_method %in% c("blackout", "inpaint")) {
      bxs <- pixel_boxes
      if (is.null(bxs)) {
        bxs <- dicom_detect_burned_phi(tmp_outs[i])
      }
      if (!is.null(bxs) && nrow(bxs) > 0L) {
        dicom_clean_pixels(
          path = tmp_outs[i],
          out_path = tmp_outs[i],
          pixel_method = pixel_method,
          boxes = bxs,
          mask_sidecar = (pixel_method == "inpaint")
        )
        if (pixel_method == "inpaint") {
          hdr_tmp <- read_dicom(tmp_outs[i], wide = TRUE)
          if (!is.null(hdr_tmp$SOPInstanceUID) && nzchar(hdr_tmp$SOPInstanceUID)) {
            res_i$pseudo_sop_uid <- hdr_tmp$SOPInstanceUID
          }
        }
      }
    }

    # Determine final output destination
    if (layout == "preserve") {
      final_dest <- file.path(out_dir, rel_paths[i])
    } else if (layout == "hierarchy") {
      final_dest <- file.path(
        out_dir,
        res_i$pseudo_patient_id,
        res_i$pseudo_study_uid,
        paste0(res_i$pseudo_sop_uid, ".dcm")
      )
    } else { # flat
      final_dest <- file.path(out_dir, paste0(res_i$pseudo_sop_uid, ".dcm"))
    }

    dir.create(dirname(final_dest), recursive = TRUE, showWarnings = FALSE)
    if (file.exists(final_dest)) {
      if (!overwrite) {
        cli::cli_abort("Output file already exists: {final_dest}. Set `overwrite = TRUE` to overwrite.")
      }
      unlink(final_dest)
    }

    ok <- file.rename(tmp_outs[i], final_dest)
    if (!ok) {
      ok <- file.copy(tmp_outs[i], final_dest, overwrite = TRUE)
      if (!ok) {
        cli::cli_abort("Failed to move de-identified file to destination: {final_dest}")
      }
      unlink(tmp_outs[i])
    }

    # Relocate inpaint mask sidecar if generated
    if (pixel_method == "inpaint") {
      tmp_stem <- tools::file_path_sans_ext(tmp_outs[i])
      tmp_sidecar <- paste0(tmp_stem, "_inpaint_mask.rds")
      if (file.exists(tmp_sidecar)) {
        final_stem <- tools::file_path_sans_ext(final_dest)
        final_sidecar <- paste0(final_stem, "_inpaint_mask.rds")
        if (!file.rename(tmp_sidecar, final_sidecar)) {
          file.copy(tmp_sidecar, final_sidecar, overwrite = TRUE)
        }
        unlink(tmp_sidecar)
      }
    }

    if (pixel_method %in% c("blackout", "inpaint") && file.exists(final_dest)) {
      res_i$out_sha256 <- cpp_sha256_file(final_dest)
    }

    res_i$out_file <- final_dest
    written_files <- c(written_files, final_dest)
    raw_results[[i]] <- res_i
  }

  # Build summary tibble
  summary_tbl <- tibble::tibble(
    in_file = in_files,
    out_file = vapply(raw_results, function(r) r$out_file %||% "", character(1)),
    status = vapply(raw_results, function(r) r$status, character(1)),
    orig_patient_id = vapply(raw_results, function(r) r$orig_patient_id, character(1)),
    pseudo_patient_id = vapply(raw_results, function(r) r$pseudo_patient_id, character(1)),
    orig_study_uid = vapply(raw_results, function(r) r$orig_study_uid, character(1)),
    pseudo_study_uid = vapply(raw_results, function(r) r$pseudo_study_uid, character(1)),
    orig_sop_uid = vapply(raw_results, function(r) r$orig_sop_uid, character(1)),
    pseudo_sop_uid = vapply(raw_results, function(r) r$pseudo_sop_uid, character(1)),
    shift_days = vapply(raw_results, function(r) as.integer(r$shift_days), integer(1)),
    in_sha256 = vapply(raw_results, function(r) r$in_sha256, character(1)),
    out_sha256 = vapply(raw_results, function(r) r$out_sha256, character(1))
  )

  # Write structured JSONL audit log
  if (!is.null(audit_path)) {
    dir.create(dirname(audit_path), recursive = TRUE, showWarnings = FALSE)
    audit_con <- file(audit_path, open = "w", encoding = "UTF-8")
    on.exit(close(audit_con), add = TRUE)

    for (i in seq_along(in_files)) {
      r <- raw_results[[i]]
      if (isTRUE(r$skipped_wsi_label)) next

      out_rel <- if (nzchar(r$out_file)) {
        fn <- normalizePath(r$out_file, winslash = "/")
        if (startsWith(fn, out_dir)) {
          sub("^[/\\\\]+", "", substring(fn, nchar(out_dir) + 1L))
        } else {
          basename(fn)
        }
      } else {
        ""
      }

      audit_rec <- list(
        "prov:wasGeneratedBy" = "dicomtk::dicom_deid",
        "prov:used" = rel_paths[i],
        input_file = rel_paths[i],
        output_file = out_rel,
        status = r$status,
        in_sha256 = r$in_sha256,
        out_sha256 = r$out_sha256,
        profile = prof_spec$profile,
        jurisdictions = as.character(prof_spec$jurisdictions %||% character(0)),
        pseudo_patient_id = r$pseudo_patient_id,
        pseudo_study_uid = r$pseudo_study_uid,
        pseudo_sop_uid = r$pseudo_sop_uid,
        actions = as.list(r$actions_applied),
        timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
      )
      writeLines(jsonlite::toJSON(audit_rec, auto_unbox = TRUE), audit_con)
    }
  }

  # Build and encrypt crosswalk
  if (!is.null(crosswalk_path)) {
    cw_rows <- lapply(raw_results, function(r) {
      if (isTRUE(r$skipped_wsi_label)) return(NULL)
      data.frame(
        orig_patient_id = as.character(r$orig_patient_id),
        pseudo_patient_id = as.character(r$pseudo_patient_id),
        orig_study_uid = as.character(r$orig_study_uid),
        pseudo_study_uid = as.character(r$pseudo_study_uid),
        shift_days = as.integer(r$shift_days),
        stringsAsFactors = FALSE
      )
    })
    cw_rows <- Filter(Negate(is.null), cw_rows)
    cw_df <- if (length(cw_rows) > 0L) unique(do.call(rbind, cw_rows)) else NULL
    if (is.null(cw_df) || nrow(cw_df) == 0L) {
      cw_df <- data.frame(
        orig_patient_id = character(0),
        pseudo_patient_id = character(0),
        orig_study_uid = character(0),
        pseudo_study_uid = character(0),
        shift_days = integer(0),
        stringsAsFactors = FALSE
      )
    }
    cw_json <- jsonlite::toJSON(cw_df, dataframe = "rows", auto_unbox = TRUE)
    enc_bytes <- cpp_aead_encrypt(
      key = aead_key,
      plaintext = charToRaw(cw_json),
      aad = charToRaw("dicomtk-crosswalk-v1")
    )
    dir.create(dirname(crosswalk_path), recursive = TRUE, showWarnings = FALSE)
    writeBin(enc_bytes, crosswalk_path)
  }

  structure(
    list(
      files = written_files,
      summary = summary_tbl,
      actions_total = total_actions,
      skipped_wsi_labels = skipped_wsi,
      audit_path = audit_path,
      crosswalk_path = crosswalk_path,
      profile = prof_spec,
      jurisdictions = jurisdictions,
      key_provider = key
    ),
    class = "dicom_deid_result"
  )
}

#' Read and Decrypt a DICOM De-Identification Crosswalk
#'
#' Reads and decrypts a ChaCha20-Poly1305 encrypted crosswalk file produced
#' by \code{\link{dicom_deid}}.
#'
#' @param path File path to the encrypted crosswalk file.
#' @param key A \code{dicom_key_provider} object or 32-byte raw vector.
#'
#' @return A tibble with columns:
#'   \item{orig_patient_id}{Original PatientID.}
#'   \item{pseudo_patient_id}{Pseudonymous PatientID.}
#'   \item{orig_study_uid}{Original StudyInstanceUID.}
#'   \item{pseudo_study_uid}{Pseudonymous StudyInstanceUID.}
#'   \item{shift_days}{Integer number of days shifted for dates.}
#' @export
#'
#' @examples
#' \dontrun{
#' kp <- dicom_key_provider(passphrase = "my-secret-passphrase")
#' cw <- dicom_crosswalk_read("path/to/crosswalk.enc", kp)
#' print(cw)
#' }
dicom_crosswalk_read <- function(path, key) {
  if (missing(path) || length(path) != 1L || !file.exists(path)) {
    cli::cli_abort("Crosswalk file does not exist: {path}")
  }
  if (is_dicom_key_provider(key)) {
    aead_key <- deid_get_subkey(key, "aead")
  } else if (is.raw(key) && length(key) == 32L) {
    aead_key <- key
  } else {
    cli::cli_abort("`key` must be a valid dicom_key_provider or 32 raw bytes.")
  }

  enc_bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  pt_bytes <- cpp_aead_decrypt(
    key = aead_key,
    ciphertext = enc_bytes,
    aad = charToRaw("dicomtk-crosswalk-v1")
  )
  if (length(pt_bytes) == 0L) {
    cli::cli_abort("Failed to decrypt crosswalk: empty plaintext.")
  }
  json_str <- rawToChar(pt_bytes)
  parsed <- jsonlite::fromJSON(json_str)
  res <- tibble::as_tibble(parsed)
  expected_cols <- c("orig_patient_id", "pseudo_patient_id", "orig_study_uid", "pseudo_study_uid", "shift_days")
  if (!all(expected_cols %in% names(res))) {
    if (nrow(res) == 0L) {
      res <- tibble::tibble(
        orig_patient_id = character(0),
        pseudo_patient_id = character(0),
        orig_study_uid = character(0),
        pseudo_study_uid = character(0),
        shift_days = integer(0)
      )
    }
  }
  res
}

#' Print DICOM De-Identification Result
#'
#' @param x A \code{dicom_deid_result} object.
#' @param ... Additional arguments passed to methods.
#' @return Invisibly returns \code{x}.
#' @keywords internal
#' @export
print.dicom_deid_result <- function(x, ...) {
  cat("<dicom_deid_result>\n")
  cat(sprintf("  Files processed: %d (%d written, %d skipped WSI labels)\n",
              nrow(x$summary), length(x$files), x$skipped_wsi_labels))
  if (!is.null(x$actions_total)) {
    acts <- paste(names(x$actions_total), x$actions_total, sep = ": ", collapse = ", ")
    cat(sprintf("  Actions applied: %s\n", acts))
  }
  if (!is.null(x$crosswalk_path)) {
    cat(sprintf("  Encrypted crosswalk: %s\n", x$crosswalk_path))
  }
  if (!is.null(x$audit_path)) {
    cat(sprintf("  Audit log: %s\n", x$audit_path))
  }
  invisible(x)
}
