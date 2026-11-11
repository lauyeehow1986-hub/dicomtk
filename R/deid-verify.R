#' Verify De-Identification Residual PHI and Generate Cryptographic Attestation
#'
#' Scans DICOM files across four forensic surfaces (tag policy violations, unallowlisted
#' private tags, free-text/structured report PII regexes/canaries, and pixel/WSI artifacts)
#' to verify complete residual PHI elimination. Optionally emits and signs a canonical
#' JSON cryptographic attestation with HMAC-SHA256 or X.509 PKI signatures.
#'
#' @param path Character vector of one or more DICOM file paths, or a directory path.
#' @param profile Character string identifying the base profile, or a compiled
#'   \code{dicom_deid_profile} object. Default is \code{"ps3.15"}.
#' @param options Character vector of standard PS3.15 options enabled during de-identification.
#' @param jurisdictions Optional character vector of statutory jurisdiction overlays.
#' @param canaries Character vector of user-supplied canary strings or identifiers to detect.
#' @param attest_path Optional file path where the signed JSON attestation will be saved.
#' @param key Optional \code{dicom_key_provider} or 32-byte raw key used for HMAC-SHA256 attestation signing.
#' @param cert Optional public certificate or public key object for PKI verification.
#' @param private_key Optional private key object (e.g. from \code{openssl::rsa_keygen}) for PKI signing.
#' @param allowed_private_tags Optional list or character vector of allowlisted private tags or creators.
#'
#' @return An S3 object of class \code{"dicom_deid_report"} containing:
#'   \item{passed}{Logical scalar. \code{TRUE} if zero findings were detected, \code{FALSE} otherwise.}
#'   \item{findings}{A tibble of detected residual PHI violations with columns
#'     \code{file}, \code{surface}, \code{tag}, \code{keyword}, \code{value}, and \code{rule}.}
#'   \item{files_scanned}{Integer count of scanned files.}
#'   \item{profile}{Profile identifier.}
#'   \item{options}{Active confidentiality options.}
#'   \item{jurisdictions}{Active jurisdictions.}
#'   \item{attest_path}{Path to generated attestation file, or \code{NULL}.}
#' @export
#'
#' @examples
#' \dontrun{
#' v <- dicom_deid_verify("path/to/clean_dir", canaries = "TAN^AH^KOW")
#' if (!v$passed) print(v$findings)
#' }
dicom_deid_verify <- function(path,
                              profile = "ps3.15",
                              options = character(0),
                              jurisdictions = NULL,
                              canaries = character(0),
                              attest_path = NULL,
                              key = NULL,
                              cert = NULL,
                              private_key = NULL,
                              allowed_private_tags = NULL) {
  files <- resolve_dicom_paths(path, recursive = TRUE)
  if (length(files) == 0L) {
    cli::cli_abort("No valid DICOM files found in `path`.")
  }

  is_single_dir <- length(path) == 1L && dir.exists(path)
  dir_root <- if (is_single_dir) normalizePath(path, winslash = "/") else ""

  rel_paths <- vapply(files, function(f) {
    fn <- normalizePath(f, winslash = "/")
    if (is_single_dir && startsWith(fn, dir_root)) {
      rel <- substring(fn, nchar(dir_root) + 1L)
      sub("^[/\\\\]+", "", rel)
    } else {
      basename(fn)
    }
  }, character(1), USE.NAMES = FALSE)

  prof <- if (inherits(profile, "dicom_deid_profile")) {
    profile
  } else {
    dicom_deid_profile(
      profile = profile,
      options = options,
      jurisdictions = jurisdictions
    )
  }

  retain_uids <- any(c("retain_uids", "retain_uid") %in% options)
  retain_safe_priv <- any(c("retain_safe_private") %in% options) || !is.null(allowed_private_tags)

  # Safe private creators and explicit tags allowlist
  safe_creators <- list()
  if (is.list(prof$safe_private)) {
    safe_creators <- prof$safe_private
  }
  if (is.list(allowed_private_tags)) {
    safe_creators <- c(safe_creators, allowed_private_tags)
  }
  explicit_allowed_tags <- if (is.character(allowed_private_tags)) {
    toupper(gsub("[ \t]", "", allowed_private_tags))
  } else {
    character(0)
  }

  # Tag policies from profile
  x_tags <- prof$tags$tag[prof$tags$action == "X"]
  age_cap <- prof$age_cap_years
  # (0010,0020) PatientID is replaced with deterministic pseudonym in de-identification
  # (0010,1010) PatientAge is retained under statutory age cap if age_cap is specified
  exempt_z <- "(0010,0020)"
  if (!is.null(age_cap) && !is.na(age_cap)) {
    exempt_z <- c(exempt_z, "(0010,1010)")
  }
  z_tags <- setdiff(prof$tags$tag[prof$tags$action == "Z"], exempt_z)

  # Compile PII regex scrubbers and canaries
  default_pii_patterns <- list(
    "Email" = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
    "US SSN" = "\\b[0-9]{3}-[0-9]{2}-[0-9]{4}\\b",
    "SG NRIC/FIN" = "[STFGM][0-9]{7}[A-Z]",
    "MY MyKad" = "\\b[0-9]{6}-[0-9]{2}-[0-9]{4}\\b",
    "UK NHS" = "\\b[0-9]{3}[ -]?[0-9]{3}[ -]?[0-9]{4}\\b",
    "Phone" = "\\b(?:\\+?[0-9]{1,3}[ -]?)?\\(?[0-9]{3}\\)?[ -]?[0-9]{3}[ -]?[0-9]{4}\\b",
    "Date" = "\\b(?:19|20)[0-9]{2}[-/](?:0[1-9]|1[0-2])[-/](?:0[1-9]|[12][0-9]|3[01])\\b",
    "URL" = "https?://[^\\s]+",
    "IPv4" = "\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\\b"
  )

  custom_patterns <- prof$regex_scrubbers
  active_canaries <- as.character(canaries[nzchar(canaries)])

  findings_list <- list()

  # Scan each file across all 4 surfaces
  for (i in seq_along(files)) {
    f <- files[i]
    rel_f <- rel_paths[i]
    hdr <- tryCatch(
      read_dicom(f, include_sequences = TRUE),
      error = function(e) NULL
    )
    if (is.null(hdr) || nrow(hdr) == 0L) next

    # Surface 1: Tag policy violations (X tags, non-empty Z tags, non-2.25 UIDs, age cap)
    # Surviving forbidden X tags
    x_hits <- hdr[hdr$tag %in% x_tags & !is.na(hdr$value) & nzchar(hdr$value), , drop = FALSE]
    if (nrow(x_hits) > 0L) {
      for (r in seq_len(nrow(x_hits))) {
        findings_list[[length(findings_list) + 1L]] <- tibble::tibble(
          file = rel_f,
          surface = "tag_policy",
          tag = x_hits$tag[r],
          keyword = x_hits$keyword[r],
          value = x_hits$value[r],
          rule = "Surviving forbidden X tag"
        )
      }
    }

    # Non-empty Z tags (excluding PatientID)
    z_hits <- hdr[hdr$tag %in% z_tags & !is.na(hdr$value) & nzchar(hdr$value), , drop = FALSE]
    if (nrow(z_hits) > 0L) {
      for (r in seq_len(nrow(z_hits))) {
        # For (0010,0010) PatientName, allow empty string "" or permitted dummy values
        if (z_hits$tag[r] == "(0010,0010)") {
          raw_pn <- toupper(trimws(z_hits$value[r]))
          clean_pn <- toupper(trimws(gsub("[\\^ ]+", " ", z_hits$value[r])))
          if (raw_pn %in% c("", "ANONYMOUS", "NO NAME") || clean_pn %in% c("", "ANONYMOUS", "NO NAME")) {
            next
          }
        }
        findings_list[[length(findings_list) + 1L]] <- tibble::tibble(
          file = rel_f,
          surface = "tag_policy",
          tag = z_hits$tag[r],
          keyword = z_hits$keyword[r],
          value = z_hits$value[r],
          rule = "Non-empty Z tag"
        )
      }
    }

    # Non-2.25 Instance UIDs
    if (!retain_uids) {
      uid_tags <- c(
        "(0008,0018)", "(0020,000D)", "(0020,000E)", "(0002,0003)",
        "(0020,0052)", "(0008,1155)", "(0020,0200)", "(0020,9161)"
      )
      uid_hits <- hdr[
        (hdr$tag %in% uid_tags | (hdr$vr == "UI" & hdr$keyword %in% c("SOPInstanceUID", "StudyInstanceUID", "SeriesInstanceUID", "ReferencedSOPInstanceUID"))) &
        !is.na(hdr$value) & nzchar(hdr$value),
        , drop = FALSE
      ]
      if (nrow(uid_hits) > 0L) {
        for (r in seq_len(nrow(uid_hits))) {
          val_uids <- strsplit(uid_hits$value[r], "\\\\")[[1L]]
          for (u in val_uids) {
            # Skip standard DICOM root UIDs (1.2.840.10008.*)
            if (!startsWith(u, "1.2.840.10008.") && !startsWith(u, "2.25.") && nzchar(u)) {
              findings_list[[length(findings_list) + 1L]] <- tibble::tibble(
                file = rel_f,
                surface = "tag_policy",
                tag = uid_hits$tag[r],
                keyword = uid_hits$keyword[r],
                value = u,
                rule = "Unmapped non-2.25 instance UID"
              )
            }
          }
        }
      }
    }

    # PatientAge exceeding cap
    if (!is.null(age_cap) && !is.na(age_cap)) {
      age_rows <- hdr[hdr$keyword == "PatientAge" & !is.na(hdr$value) & nzchar(hdr$value), , drop = FALSE]
      if (nrow(age_rows) > 0L) {
        for (r in seq_len(nrow(age_rows))) {
          raw_age <- age_rows$value[r]
          if (grepl("Y$", raw_age, ignore.case = TRUE)) {
            num_age <- suppressWarnings(as.integer(sub("[^0-9].*$", "", raw_age)))
            if (!is.na(num_age) && num_age > (as.integer(age_cap) + 1L)) {
              findings_list[[length(findings_list) + 1L]] <- tibble::tibble(
                file = rel_f,
                surface = "tag_policy",
                tag = age_rows$tag[r],
                keyword = age_rows$keyword[r],
                value = raw_age,
                rule = paste0("PatientAge exceeds statutory cap of ", age_cap, " years")
              )
            }
          }
        }
      }
    }

    # Surface 2: Private tags (odd groups > 0x0007)
    priv_rows <- hdr[hdr$group != "0000" & hdr$group != "0002", , drop = FALSE]
    grp_ints <- suppressWarnings(strtoi(priv_rows$group, 16L))
    is_odd <- !is.na(grp_ints) & (grp_ints %% 2L == 1L) & (grp_ints > 7L)
    priv_hits <- priv_rows[is_odd, , drop = FALSE]

    if (nrow(priv_hits) > 0L) {
      # Build mapping of creator reservation tags within the dataset scope
      # Reservation tags are in element range 0x0010..0x00FF
      all_grp_ints <- suppressWarnings(strtoi(hdr$group, 16L))
      all_elem_ints <- suppressWarnings(strtoi(hdr$element, 16L))
      is_res <- !is.na(all_grp_ints) & (all_grp_ints %% 2L == 1L) & (all_grp_ints > 7L) &
                !is.na(all_elem_ints) & (all_elem_ints >= 0x0010 & all_elem_ints <= 0x00FF)
      res_rows <- hdr[is_res, , drop = FALSE]

      creator_map <- list()
      if (nrow(res_rows) > 0L) {
        for (idx in seq_len(nrow(res_rows))) {
          rg <- toupper(trimws(res_rows$group[idx]))
          re <- suppressWarnings(strtoi(res_rows$element[idx], 16L))
          rc <- toupper(trimws(res_rows$value[idx]))
          depth_val <- if (!is.null(res_rows$depth)) res_rows$depth[idx] else 0L
          seq_path_val <- if (!is.null(res_rows$sequence_path)) res_rows$sequence_path[idx] else ""
          scope_id <- paste(depth_val, seq_path_val, rg, sprintf("%02X", re), sep = "::")
          creator_map[[scope_id]] <- rc
          glob_id <- paste(rg, sprintf("%02X", re), sep = "::")
          if (is.null(creator_map[[glob_id]])) {
            creator_map[[glob_id]] <- rc
          }
        }
      }

      for (r in seq_len(nrow(priv_hits))) {
        is_safe <- FALSE
        p_tag <- toupper(gsub("[ \t]", "", priv_hits$tag[r]))
        p_grp <- toupper(trimws(priv_hits$group[r]))
        p_elem_int <- suppressWarnings(strtoi(priv_hits$element[r], 16L))

        if (p_tag %in% explicit_allowed_tags) {
          is_safe <- TRUE
        } else if (retain_safe_priv && length(safe_creators) > 0L && !is.na(p_elem_int)) {
          # Case 1: Creator reservation tag (0x0010..0x00FF)
          if (p_elem_int >= 0x0010 && p_elem_int <= 0x00FF) {
            c_val <- toupper(trimws(priv_hits$value[r]))
            for (c_name in names(safe_creators)) {
              if (toupper(trimws(c_name)) == c_val) {
                entry <- safe_creators[[c_name]]
                e_grp <- if (is.list(entry) && !is.null(entry$group)) toupper(trimws(entry$group)) else "0000"
                if (e_grp %in% c("0000", p_grp)) {
                  is_safe <- TRUE
                  break
                }
              }
            }
          } else if (p_elem_int >= 0x1000) {
            # Case 2: Private data element (0x1000..0xFFFF)
            p_blk <- bitwShiftR(p_elem_int, 8L)
            p_off <- bitwAnd(p_elem_int, 0xFFL)

            depth_val <- if (!is.null(priv_hits$depth)) priv_hits$depth[r] else 0L
            seq_path_val <- if (!is.null(priv_hits$sequence_path)) priv_hits$sequence_path[r] else ""
            scope_id <- paste(depth_val, seq_path_val, p_grp, sprintf("%02X", p_blk), sep = "::")
            glob_id <- paste(p_grp, sprintf("%02X", p_blk), sep = "::")

            creator_found <- creator_map[[scope_id]] %||% creator_map[[glob_id]] %||% toupper(trimws(priv_hits$keyword[r]))

            if (nzchar(creator_found)) {
              for (c_name in names(safe_creators)) {
                if (toupper(trimws(c_name)) == creator_found) {
                  entry <- safe_creators[[c_name]]
                  e_grp <- if (is.list(entry) && !is.null(entry$group)) toupper(trimws(entry$group)) else "0000"
                  e_offsets <- if (is.list(entry) && !is.null(entry$offsets)) as.integer(entry$offsets) else integer(0)
                  if (e_grp %in% c("0000", p_grp) && (p_off %in% e_offsets)) {
                    is_safe <- TRUE
                    break
                  }
                }
              }
            }
          }
        }

        if (!is_safe) {
          findings_list[[length(findings_list) + 1L]] <- tibble::tibble(
            file = rel_f,
            surface = "private_tags",
            tag = priv_hits$tag[r],
            keyword = priv_hits$keyword[r],
            value = priv_hits$value[r],
            rule = "Unallowlisted private tag"
          )
        }
      }
    }

    # Surface 3: Free-text & Structured Report PII regex scan
    # 1. User canaries: check across all string/text VRs
    canary_vrs <- c("AE", "AS", "CS", "DA", "DS", "DT", "IS", "LO", "LT", "PN", "SH", "ST", "TM", "UC", "UI", "UR", "UT")
    all_str_rows <- hdr[
      (hdr$vr %in% canary_vrs | hdr$tag == "(0040,A160)") &
      !is.na(hdr$value) & nzchar(hdr$value),
      , drop = FALSE
    ]
    if (nrow(all_str_rows) > 0L && length(active_canaries) > 0L) {
      for (r in seq_len(nrow(all_str_rows))) {
        val <- all_str_rows$value[r]
        val_upper <- toupper(val)
        val_norm_space <- toupper(gsub("[\\^\\s]+", " ", val, perl = TRUE))
        val_norm_clean <- toupper(gsub("[\\^\\s_]+", "", val, perl = TRUE))

        for (canary in active_canaries) {
          canary_upper <- toupper(canary)
          canary_norm_space <- toupper(trimws(gsub("[\\^\\s]+", " ", canary, perl = TRUE)))
          canary_norm_clean <- toupper(trimws(gsub("[\\^\\s_]+", "", canary, perl = TRUE)))

          matched <- grepl(canary, val, fixed = TRUE) ||
                     grepl(canary_upper, val_upper, fixed = TRUE) ||
                     grepl(canary_norm_space, val_norm_space, fixed = TRUE) ||
                     (nzchar(canary_norm_clean) && grepl(canary_norm_clean, val_norm_clean, fixed = TRUE))

          if (matched) {
            findings_list[[length(findings_list) + 1L]] <- tibble::tibble(
              file = rel_f,
              surface = "free_text_pii",
              tag = all_str_rows$tag[r],
              keyword = all_str_rows$keyword[r],
              value = val,
              rule = paste0("PII canary detected: ", canary)
            )
          }
        }
      }
    }

    # 2. PII patterns (emails, SSN, NRIC, phones, postal codes):
    # Scan free-text attributes (LT, ST, UT, PN, LO, SH), excluding timestamps, dates, UIDs,
    # and standard de-identification metadata tags (0012,xxxx) or CID 7050 codes.
    is_free_text <- (hdr$vr %in% c("LT", "ST", "UT", "PN", "LO", "SH", "UC") |
                     hdr$tag == "(0040,A160)" |
                     hdr$keyword %in% c("TextValue", "ImageComments", "StudyDescription", "SeriesDescription", "ProtocolName", "PatientComments", "ReasonForStudy")) &
                    !(hdr$vr %in% c("TM", "DA", "DT", "UI")) &
                    !(hdr$group == "0012") &
                    !(hdr$keyword %in% c("CodeValue", "CodingSchemeDesignator", "CodeMeaning", "Modality")) &
                    !is.na(hdr$value) & nzchar(hdr$value)
    free_text_rows <- hdr[is_free_text, , drop = FALSE]

    if (nrow(free_text_rows) > 0L) {
      for (r in seq_len(nrow(free_text_rows))) {
        val <- free_text_rows$value[r]

        for (p_name in names(default_pii_patterns)) {
          pat <- default_pii_patterns[[p_name]]
          if (grepl(pat, val, perl = TRUE)) {
            findings_list[[length(findings_list) + 1L]] <- tibble::tibble(
              file = rel_f,
              surface = "free_text_pii",
              tag = free_text_rows$tag[r],
              keyword = free_text_rows$keyword[r],
              value = val,
              rule = paste0("PII pattern detected: ", p_name)
            )
          }
        }

        if (length(custom_patterns) > 0L) {
          for (c_pat in custom_patterns) {
            if (grepl(c_pat, val, perl = TRUE)) {
              findings_list[[length(findings_list) + 1L]] <- tibble::tibble(
                file = rel_f,
                surface = "free_text_pii",
                tag = free_text_rows$tag[r],
                keyword = free_text_rows$keyword[r],
                value = val,
                rule = paste0("PII regex scrubber matched: ", c_pat)
              )
            }
          }
        }
      }
    }

    # Surface 4: Pixel & WSI artifacts
    # BurnedInAnnotation == "YES"
    burn_row <- hdr[hdr$tag == "(0028,0301)" | hdr$keyword == "BurnedInAnnotation", , drop = FALSE]
    if (nrow(burn_row) > 0L && any(toupper(burn_row$value) == "YES")) {
      findings_list[[length(findings_list) + 1L]] <- tibble::tibble(
        file = rel_f,
        surface = "pixel_wsi",
        tag = "(0028,0301)",
        keyword = "BurnedInAnnotation",
        value = "YES",
        rule = "BurnedInAnnotation is YES"
      )
    }

    # WSI LABEL / OVERVIEW images
    img_type_row <- hdr[hdr$tag == "(0008,0008)" | hdr$keyword == "ImageType", , drop = FALSE]
    if (nrow(img_type_row) > 0L) {
      val_it <- toupper(img_type_row$value[1L])
      if (grepl("\\bLABEL\\b", val_it) || grepl("\\bOVERVIEW\\b", val_it)) {
        findings_list[[length(findings_list) + 1L]] <- tibble::tibble(
          file = rel_f,
          surface = "pixel_wsi",
          tag = "(0008,0008)",
          keyword = "ImageType",
          value = img_type_row$value[1L],
          rule = "Surviving WSI LABEL or OVERVIEW instance"
        )
      }
    }
  }

  findings_tbl <- if (length(findings_list) > 0L) {
    dplyr::distinct(dplyr::bind_rows(findings_list))
  } else {
    tibble::tibble(
      file = character(0),
      surface = character(0),
      tag = character(0),
      keyword = character(0),
      value = character(0),
      rule = character(0)
    )
  }

  passed <- nrow(findings_tbl) == 0L

  # Attestation Generation
  generated_attest <- NULL
  if (isTRUE(passed) && !is.null(attest_path)) {
    hashes <- vapply(files, cpp_sha256_file, character(1L), USE.NAMES = FALSE)
    file_order <- order(rel_paths)
    sorted_files <- data.frame(
      rel_path = rel_paths[file_order],
      sha256 = hashes[file_order],
      stringsAsFactors = FALSE
    )

    payload_list <- list(
      version = "1.0",
      profile = prof$profile,
      options = as.character(options),
      jurisdictions = as.character(jurisdictions %||% character(0)),
      timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      files = lapply(seq_len(nrow(sorted_files)), function(idx) {
        list(rel_path = sorted_files$rel_path[idx], sha256 = sorted_files$sha256[idx])
      })
    )

    canonical_json <- jsonlite::toJSON(payload_list, auto_unbox = TRUE)

    sig_type <- "none"
    sig_str <- ""

    if (!is.null(private_key) && requireNamespace("openssl", quietly = TRUE)) {
      sig_bytes <- openssl::signature_create(charToRaw(canonical_json), key = private_key, hash = openssl::sha256)
      sig_str <- openssl::base64_encode(sig_bytes)
      sig_type <- "openssl_pki"
    } else if (!is.null(key)) {
      attest_k <- if (is_dicom_key_provider(key)) {
        deid_get_subkey(key, "attest")
      } else if (is.raw(key)) {
        key
      } else {
        charToRaw(as.character(key))
      }
      sig_str <- cpp_hmac_sha256_hex(attest_k, charToRaw(as.character(canonical_json)))
      sig_type <- "hmac_sha256"
    }

    attest_doc <- list(
      payload = payload_list,
      signature_type = sig_type,
      signature = sig_str
    )

    dir.create(dirname(attest_path), recursive = TRUE, showWarnings = FALSE)
    writeLines(jsonlite::toJSON(attest_doc, auto_unbox = TRUE, pretty = TRUE), attest_path)
    generated_attest <- normalizePath(attest_path, winslash = "/", mustWork = FALSE)
  }

  structure(
    list(
      passed = passed,
      findings = findings_tbl,
      files_scanned = length(files),
      profile = prof$profile,
      options = options,
      jurisdictions = jurisdictions,
      attest_path = generated_attest
    ),
    class = "dicom_deid_report"
  )
}

#' Print Method for DICOM De-Identification Report
#'
#' @param x A \code{dicom_deid_report} object.
#' @param ... Additional arguments ignored.
#' @return Invisibly returns \code{x}.
#' @keywords internal
#' @export
print.dicom_deid_report <- function(x, ...) {
  status_icon <- if (isTRUE(x$passed)) cli::col_green("[PASSED]") else cli::col_red("[FAILED]")
  cli::cli_h1("DICOM De-Identification Residual PHI Audit: {status_icon}")
  cli::cli_bullets(c(
    "*" = paste0("Files Scanned: ", x$files_scanned),
    "*" = paste0("Profile: ", x$profile),
    "*" = paste0("Options: ", if (length(x$options) > 0L) paste(x$options, collapse = ", ") else "none"),
    "*" = paste0("Jurisdictions: ", if (length(x$jurisdictions) > 0L) paste(x$jurisdictions, collapse = ", ") else "none"),
    "*" = paste0("Attestation: ", if (!is.null(x$attest_path)) x$attest_path else "none")
  ))

  if (isTRUE(x$passed)) {
    cli::cli_alert_success("Zero residual PHI findings detected across all 4 surfaces.")
  } else {
    cli::cli_alert_danger("Residual PHI findings detected ({nrow(x$findings)} total):")
    surf_counts <- table(x$findings$surface)
    for (s in names(surf_counts)) {
      cli::cli_bullets(c("!" = paste0(s, ": ", surf_counts[[s]], " finding(s)")))
    }
  }
  invisible(x)
}

#' Verify Cryptographic Attestation Manifest
#'
#' Verifies the integrity and authenticity of a signed JSON attestation manifest
#' against a directory or cohort of de-identified DICOM files.
#'
#' @param path Directory path containing the de-identified DICOM files.
#' @param attest_path File path to the JSON attestation manifest.
#' @param key Optional \code{dicom_key_provider} or raw key used to verify HMAC-SHA256 signatures.
#' @param cert Optional public certificate, RSA/ECDSA public key, or raw cert for PKI verification.
#' @param rsa_pubkey Optional alias for \code{cert}.
#'
#' @return Logical scalar. \code{TRUE} if all file hashes and the cryptographic signature match; \code{FALSE} otherwise.
#' @export
#'
#' @examples
#' \dontrun{
#' kp <- dicom_key_provider(passphrase = "my-secret")
#' ok <- dicom_verify_attestation("path/to/clean", "attest.json", key = kp)
#' print(ok)
#' }
dicom_verify_attestation <- function(path, attest_path, key = NULL, cert = NULL, rsa_pubkey = cert) {
  if (!file.exists(attest_path)) {
    return(FALSE)
  }

  pubkey <- cert %||% rsa_pubkey

  doc <- tryCatch(
    jsonlite::fromJSON(attest_path, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(doc) || is.null(doc$payload) || is.null(doc$payload$files)) {
    return(FALSE)
  }

  payload <- doc$payload
  canonical_json <- jsonlite::toJSON(payload, auto_unbox = TRUE)

  # Check all files match digests
  dir_norm <- normalizePath(path, winslash = "/", mustWork = FALSE)
  manifest_files <- payload$files

  # Check count match
  actual_files <- resolve_dicom_paths(path, recursive = TRUE)
  if (length(actual_files) != length(manifest_files)) {
    return(FALSE)
  }

  for (mf in manifest_files) {
    target <- file.path(dir_norm, mf$rel_path)
    if (!file.exists(target)) {
      return(FALSE)
    }
    actual_hash <- cpp_sha256_file(target)
    if (!identical(tolower(actual_hash), tolower(mf$sha256))) {
      return(FALSE)
    }
  }

  # Verify signature
  sig_type <- doc$signature_type
  sig <- doc$signature

  # Strict signature type checking to prevent downgrade/bypass attacks:
  # 1. If key is provided, sig_type MUST be "hmac_sha256", otherwise FALSE.
  # 2. If rsa_pubkey/cert is provided, sig_type MUST be "openssl_pki", otherwise FALSE.
  # 3. If neither key nor pubkey is provided, sig_type MUST be "none", otherwise FALSE.
  # Never allow sig_type == "none" to pass if the caller supplied a key or rsa_pubkey!
  if (!is.null(key)) {
    if (!identical(sig_type, "hmac_sha256")) {
      return(FALSE)
    }
  } else if (!is.null(pubkey)) {
    if (!identical(sig_type, "openssl_pki")) {
      return(FALSE)
    }
  } else {
    if (!identical(sig_type, "none")) {
      return(FALSE)
    }
  }

  if (identical(sig_type, "hmac_sha256")) {
    if (is.null(key)) return(FALSE)
    attest_k <- if (is_dicom_key_provider(key)) {
      deid_get_subkey(key, "attest")
    } else if (is.raw(key)) {
      key
    } else {
      charToRaw(as.character(key))
    }
    expected_hmac <- cpp_hmac_sha256_hex(attest_k, charToRaw(as.character(canonical_json)))
    if (!identical(tolower(sig), tolower(expected_hmac))) {
      return(FALSE)
    }
  } else if (identical(sig_type, "openssl_pki")) {
    if (is.null(pubkey) || !requireNamespace("openssl", quietly = TRUE)) {
      return(FALSE)
    }
    sig_raw <- tryCatch(openssl::base64_decode(sig), error = function(e) NULL)
    if (is.null(sig_raw)) return(FALSE)

    ok <- tryCatch(
      openssl::signature_verify(
        charToRaw(canonical_json),
        sig_raw,
        hash = openssl::sha256,
        pubkey = pubkey
      ),
      error = function(e) FALSE
    )
    if (!isTRUE(ok)) return(FALSE)
  } else if (identical(sig_type, "none")) {
    if (!is.null(key) || !is.null(pubkey)) {
      return(FALSE)
    }
    return(TRUE)
  } else {
    return(FALSE)
  }

  TRUE
}
