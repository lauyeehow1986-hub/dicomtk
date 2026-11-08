#' DICOM De-Identification Profiles and Composable Jurisdictions
#'
#' Compiles declarative DICOM PS3.15 Annex E Table E.1-1 confidentiality profiles,
#' standard confidentiality options, safe-private creator allowlists, and composable
#' statutory jurisdiction overlays into a concrete, deterministic tag mutator table.
#'
#' @details
#' Conflicting tag rules across composed options and jurisdictions merge monotonically
#' along the strictest-wins join-semilattice:
#' \preformatted{
#'   K (keep) < C (clean) < U (UID) < D (dummy) < Z (zero) < X (remove)
#' }
#' Adding any statutory jurisdiction overlay (e.g., \code{"hipaa_safe_harbor"},
#' \code{"sg_pdpa_hib"}, \code{"gdpr"}) cannot weaken base protection.
#'
#' @param profile Character string identifying the base profile. Default is
#'   \code{"ps3.15"} (DICOM PS3.15 Annex E Basic Application Level Confidentiality Profile).
#' @param options Character vector of standard PS3.15 options to enable. Valid
#'   options include:
#'   \itemize{
#'     \item \code{"clean_pixel_data"} (CID 7050 113101)
#'     \item \code{"clean_recognizable_visual_features"} (CID 7050 113102)
#'     \item \code{"clean_graphics"} (CID 7050 113103)
#'     \item \code{"clean_structured_content"} (CID 7050 113104)
#'     \item \code{"clean_descriptors"} (CID 7050 113105)
#'     \item \code{"retain_longitudinal_full_dates"} (CID 7050 113106)
#'     \item \code{"retain_longitudinal_modified_dates"} (CID 7050 113107)
#'     \item \code{"retain_patient_characteristics"} (CID 7050 113108)
#'     \item \code{"retain_device_identity"} (CID 7050 113109)
#'     \item \code{"retain_institution_identity"} (CID 7050 113110)
#'     \item \code{"retain_safe_private"} (CID 7050 113111)
#'     \item \code{"retain_uids"} (CID 7050 113112)
#'   }
#' @param jurisdictions Optional character vector of statutory jurisdiction overlays
#'   to compose onto the profile. See \code{\link{dicom_list_jurisdictions}} for available presets.
#'   Default is \code{NULL} (pure PS3.15 standard rules).
#' @param file Optional file path to a custom YAML profile definition. If provided,
#'   overrides \code{profile}.
#' @param override_tags Optional named list of tag-action overrides
#'   (e.g., \code{list("(0010,0010)" = "X", "(0008,1030)" = "C")}) applied after all
#'   base rules, options, and jurisdictions have been resolved.
#'
#' @return An object of class \code{"dicom_deid_profile"} containing:
#'   \item{profile}{Profile name or file identifier.}
#'   \item{description}{Human-readable profile description.}
#'   \item{cid7050_codes}{Named character vector of CID 7050 codes and meanings.}
#'   \item{date_policy}{Resolved date policy (\code{"dummy"}, \code{"shift_per_patient"}, \code{"year_only"}, or \code{"keep"}).}
#'   \item{age_cap_years}{Integer age cap (e.g. 89L) or NULL.}
#'   \item{zip_prefix_digits}{Integer retained zip prefix digits (e.g. 3L) or NULL.}
#'   \item{regex_scrubbers}{Character vector of regular expression patterns for text scrubbing.}
#'   \item{disclaimers}{Character vector of legal disclaimers associated with active jurisdictions.}
#'   \item{flags}{Named list of arbitrary jurisdictional or workflow flags.}
#'   \item{safe_private}{Named list of allowlisted private creators and offset numbers.}
#'   \item{tags}{Data frame of compiled tags with columns \code{tag}, \code{action}, \code{name}, \code{keyword}, and \code{vr}.}
#' @export
#' @examples
#' # Basic PS3.15 Profile
#' prof <- dicom_deid_profile()
#' print(prof)
#'
#' # Longitudinal research with safe private tags and Singapore HIB + HIPAA
#' prof_multi <- dicom_deid_profile(
#'   options = c("retain_longitudinal_modified_dates", "retain_safe_private"),
#'   jurisdictions = c("sg_pdpa_hib", "hipaa_safe_harbor")
#' )
dicom_deid_profile <- function(profile = "ps3.15",
                               options = character(0),
                               jurisdictions = NULL,
                               file = NULL,
                               override_tags = list()) {
  compile_deid_profile(
    profile = profile,
    options = options,
    jurisdictions = jurisdictions,
    file = file,
    override_tags = override_tags
  )
}

#' List Built-In Statutory De-Identification Jurisdictions
#'
#' Returns the identifiers of all built-in statutory privacy jurisdiction profiles
#' available in dicomtk.
#'
#' @return A character vector of jurisdiction identifiers.
#' @export
#' @examples
#' dicom_list_jurisdictions()
dicom_list_jurisdictions <- function() {
  jur_dir <- find_jurisdiction_dir()
  if (nzchar(jur_dir) && dir.exists(jur_dir)) {
    files <- list.files(jur_dir, pattern = "\\.ya?ml$", full.names = FALSE)
    jurs <- sort(sub("\\.ya?ml$", "", files))
    if (length(jurs) > 0L) return(jurs)
  }
  # Fallback to standard 8 built-in jurisdictions
  c(
    "au_privacy_nhmrc",
    "gdpr",
    "hipaa_expert_determination",
    "hipaa_safe_harbor",
    "my_pdpa_2024",
    "sg_pdpa_hib",
    "tcia_ctp",
    "uk_gdpr"
  )
}

# Find profile directory across installed package or source worktree
find_profile_dir <- function() {
  d <- system.file("profiles", package = "dicomtk")
  if (nzchar(d) && dir.exists(d)) return(d)
  candidates <- c("inst/profiles", "../inst/profiles", "../../inst/profiles")
  for (cand in candidates) {
    if (dir.exists(cand)) return(normalizePath(cand))
  }
  ""
}

find_jurisdiction_dir <- function() {
  base_dir <- find_profile_dir()
  if (nzchar(base_dir)) {
    j_dir <- file.path(base_dir, "jurisdictions")
    if (dir.exists(j_dir)) return(j_dir)
  }
  ""
}

# Resolve PS3.15 compound action codes into concrete atomic actions:
# X/Z/U* -> U
# X/Z/D  -> X
# Z/D    -> Z
# X/D    -> X
# X/Z    -> X
# D, Z, X, K, C, U -> unchanged
resolve_ps315_action <- function(code) {
  if (is.null(code) || !nzchar(code)) return("X")
  code <- toupper(trimws(code))
  switch(
    code,
    "X/Z/U*" = "U",
    "X/Z/D"  = "X",
    "Z/D"    = "Z",
    "X/D"    = "X",
    "X/Z"    = "X",
    "D"      = "D",
    "Z"      = "Z",
    "X"      = "X",
    "K"      = "K",
    "C"      = "C",
    "U"      = "U",
    # Fallback for other compound codes
    if (grepl("U", code, fixed = TRUE)) "U" else if (grepl("X", code, fixed = TRUE)) "X" else "Z"
  )
}

# Core compiler
compile_deid_profile <- function(profile = "ps3.15",
                                 options = character(0),
                                 jurisdictions = NULL,
                                 file = NULL,
                                 override_tags = list()) {
  ranks <- c(K = 1L, C = 2L, U = 3L, D = 4L, Z = 5L, X = 6L)
  valid_options <- c(
    "clean_pixel_data",
    "clean_recognizable_visual_features",
    "clean_graphics",
    "clean_structured_content",
    "clean_descriptors",
    "retain_longitudinal_full_dates",
    "retain_longitudinal_modified_dates",
    "retain_patient_characteristics",
    "retain_device_identity",
    "retain_institution_identity",
    "retain_safe_private",
    "retain_uids"
  )

  # Validate options
  options <- as.character(options)
  invalid_opts <- setdiff(options, valid_options)
  if (length(invalid_opts) > 0L) {
    cli::cli_abort("Unknown de-identification option(s): {.val {invalid_opts}}. Valid options: {.val {valid_options}}")
  }

  # Validate jurisdictions
  valid_jurs <- dicom_list_jurisdictions()
  if (!is.null(jurisdictions)) {
    jurisdictions <- as.character(jurisdictions)
    invalid_jurs <- setdiff(jurisdictions, valid_jurs)
    if (length(invalid_jurs) > 0L) {
      cli::cli_abort("Unknown jurisdiction(s): {.val {invalid_jurs}}. Available: {.val {valid_jurs}}")
    }
  } else {
    jurisdictions <- character(0)
  }

  prof_dir <- find_profile_dir()

  # Load base YAML or user-provided file
  if (!is.null(file) && nzchar(file)) {
    if (!file.exists(file)) {
      cli::cli_abort("Custom profile YAML file not found: {.path {file}}")
    }
    raw_prof <- yaml::read_yaml(file)
    prof_name <- if (!is.null(raw_prof$name)) raw_prof$name else basename(file)
    prof_desc <- if (!is.null(raw_prof$description)) raw_prof$description else "Custom de-identification profile"
  } else {
    base_file <- file.path(prof_dir, sprintf("%s-basic.yml", profile))
    if (!file.exists(base_file)) {
      # try direct name
      base_file <- file.path(prof_dir, sprintf("%s.yml", profile))
    }
    if (!file.exists(base_file)) {
      cli::cli_abort("Base profile YAML not found for profile: {.val {profile}} at {.path {base_file}}")
    }
    raw_prof <- yaml::read_yaml(base_file)
    prof_name <- if (!is.null(raw_prof$name)) raw_prof$name else profile
    prof_desc <- if (!is.null(raw_prof$description)) raw_prof$description else "DICOM PS3.15 Confidentiality Profile"
  }

  # Initialize CID 7050 codes
  cid7050_codes <- character(0)
  if (!is.null(raw_prof$cid7050_codes) && length(raw_prof$cid7050_codes) > 0L) {
    for (i in seq_along(raw_prof$cid7050_codes)) {
      cd <- names(raw_prof$cid7050_codes)[i]
      val <- raw_prof$cid7050_codes[[i]]
      if (is.null(cd) || !nzchar(cd)) {
        cid7050_codes[[as.character(val)]] <- as.character(val)
      } else {
        cid7050_codes[[cd]] <- as.character(val)
      }
    }
  } else if (!is.null(raw_prof$cid7050_code)) {
    cd <- as.character(raw_prof$cid7050_code)
    nm <- if (!is.null(raw_prof$cid7050_meaning)) as.character(raw_prof$cid7050_meaning) else "Confidentiality Profile"
    cid7050_codes[[cd]] <- nm
  } else {
    cid7050_codes[["113100"]] <- "Basic Application Confidentiality Profile"
  }

  # Initial date policy, age cap, zip prefix
  date_policy <- if (!is.null(raw_prof$date_policy)) as.character(raw_prof$date_policy) else "dummy"
  age_cap_years <- if (!is.null(raw_prof$age_cap_years)) as.integer(raw_prof$age_cap_years) else NULL
  zip_prefix_digits <- if (!is.null(raw_prof$zip_prefix_digits)) as.integer(raw_prof$zip_prefix_digits) else NULL
  regex_scrubbers <- if (!is.null(raw_prof$regex_scrubbers)) as.character(unlist(raw_prof$regex_scrubbers)) else character(0)
  disclaimers <- character(0)
  flags <- if (!is.null(raw_prof$flags)) as.list(raw_prof$flags) else list()
  safe_private <- list()

  # Apply standard options to CID 7050 codes and policies
  if (!is.null(raw_prof$options) && length(options) > 0L) {
    for (opt in options) {
      opt_def <- raw_prof$options[[opt]]
      if (!is.null(opt_def)) {
        if (!is.null(opt_def$code)) {
          cd <- as.character(opt_def$code)
          nm <- if (!is.null(opt_def$meaning)) as.character(opt_def$meaning) else opt
          cid7050_codes[[cd]] <- nm
        }
        if (!is.null(opt_def$date_policy)) {
          date_policy <- as.character(opt_def$date_policy)
        }
      }
    }
  }

  # Direct options overrides if not set in YAML
  if ("retain_longitudinal_modified_dates" %in% options) {
    if (!("113107" %in% names(cid7050_codes))) {
      cid7050_codes[["113107"]] <- "Retain Longitudinal Temporal Information With Modified Dates Option"
    }
    date_policy <- "shift_per_patient"
  }
  if ("retain_longitudinal_full_dates" %in% options) {
    if (!("113106" %in% names(cid7050_codes))) {
      cid7050_codes[["113106"]] <- "Retain Longitudinal Temporal Information With Full Dates Option"
    }
    date_policy <- "keep"
  }
  if ("retain_safe_private" %in% options) {
    if (!("113111" %in% names(cid7050_codes))) {
      cid7050_codes[["113111"]] <- "Retain Safe Private Option"
    }
    sp_file <- file.path(prof_dir, "safe-private.yml")
    if (file.exists(sp_file)) {
      sp_yaml <- yaml::read_yaml(sp_file)
      safe_private <- if (!is.null(sp_yaml$creators)) sp_yaml$creators else sp_yaml
    }
  }

  # Parse base tags
  raw_tags <- if (!is.null(raw_prof$tags)) raw_prof$tags else list()
  compiled_tags <- list()

  for (tg in names(raw_tags)) {
    entry <- raw_tags[[tg]]
    base_act_raw <- if (is.character(entry)) entry else entry$action
    tag_opts <- if (is.list(entry) && !is.null(entry$options)) entry$options else list()

    # Check if any enabled option overrides the base action
    resolved_act <- NULL
    if (length(options) > 0L && length(tag_opts) > 0L) {
      active_opts <- intersect(options, names(tag_opts))
      if (length(active_opts) > 0L) {
        # Retention options retain/loosen before jurisdictions are applied
        opt_acts <- vapply(active_opts, function(o) as.character(tag_opts[[o]]), character(1L))
        opt_ranks <- ranks[opt_acts]
        resolved_act <- opt_acts[which.min(opt_ranks)]
      }
    }
    if (is.null(resolved_act)) {
      resolved_act <- resolve_ps315_action(base_act_raw)
    }

    tg_name <- if (is.list(entry) && !is.null(entry$name)) as.character(entry$name) else ""
    tg_kw <- if (is.list(entry) && !is.null(entry$keyword)) as.character(entry$keyword) else ""
    tg_vr <- if (is.list(entry) && !is.null(entry$vr)) as.character(entry$vr) else ""

    compiled_tags[[toupper(tg)]] <- list(
      tag = toupper(tg),
      action = resolved_act,
      name = tg_name,
      keyword = tg_kw,
      vr = tg_vr,
      original_action = as.character(base_act_raw)
    )
  }

  # Overlay composable statutory jurisdictions monotonically (strictest wins: K < C < U < D < Z < X)
  jur_dir <- find_jurisdiction_dir()
  if (length(jurisdictions) > 0L && nzchar(jur_dir)) {
    for (jur_id in jurisdictions) {
      jf <- file.path(jur_dir, sprintf("%s.yml", jur_id))
      if (!file.exists(jf)) {
        jf <- file.path(jur_dir, sprintf("%s.yaml", jur_id))
      }
      if (!file.exists(jf)) next

      jur_yaml <- yaml::read_yaml(jf)

      # Disclaimer
      if (!is.null(jur_yaml$disclaimer)) {
        disclaimers <- unique(c(disclaimers, as.character(jur_yaml$disclaimer)))
      }

      # Age cap: minimum non-null wins
      if (!is.null(jur_yaml$age_cap_years)) {
        jur_cap <- as.integer(jur_yaml$age_cap_years)
        age_cap_years <- if (is.null(age_cap_years)) jur_cap else min(age_cap_years, jur_cap)
      }

      # Zip prefix digits: minimum non-null wins
      if (!is.null(jur_yaml$zip_prefix_digits)) {
        jur_zip <- as.integer(jur_yaml$zip_prefix_digits)
        zip_prefix_digits <- if (is.null(zip_prefix_digits)) jur_zip else min(zip_prefix_digits, jur_zip)
      }

      # Regex scrubbers: union cleanly
      if (!is.null(jur_yaml$regex_scrubbers)) {
        regex_scrubbers <- unique(c(regex_scrubbers, as.character(unlist(jur_yaml$regex_scrubbers))))
      }

      # Flags
      if (!is.null(jur_yaml$flags)) {
        for (f_nm in names(jur_yaml$flags)) {
          flags[[f_nm]] <- jur_yaml$flags[[f_nm]]
        }
      }

      # Tag overrides: monotonic strictest wins along K < C < U < D < Z < X
      overrides <- if (!is.null(jur_yaml$tag_overrides)) jur_yaml$tag_overrides else jur_yaml$overrides
      if (!is.null(overrides) && length(overrides) > 0L) {
        for (tg in names(overrides)) {
          tg_upper <- toupper(tg)
          jur_act <- resolve_ps315_action(as.character(overrides[[tg]]))
          if (!is.null(compiled_tags[[tg_upper]])) {
            cur_act <- compiled_tags[[tg_upper]]$action
            # Monotonic lattice: update only if jurisdiction action is strictly greater in rank
            if (ranks[jur_act] > ranks[cur_act]) {
              compiled_tags[[tg_upper]]$action <- jur_act
            }
          } else {
            compiled_tags[[tg_upper]] <- list(
              tag = tg_upper,
              action = jur_act,
              name = "",
              keyword = "",
              vr = "",
              original_action = as.character(overrides[[tg]])
            )
          }
        }
      }
    }
  }

  # Apply user-specified override_tags (explicit caller intent takes final precedence)
  if (length(override_tags) > 0L) {
    for (tg in names(override_tags)) {
      tg_upper <- toupper(tg)
      user_act <- resolve_ps315_action(as.character(override_tags[[tg]]))
      if (!is.null(compiled_tags[[tg_upper]])) {
        compiled_tags[[tg_upper]]$action <- user_act
      } else {
        compiled_tags[[tg_upper]] <- list(
          tag = tg_upper,
          action = user_act,
          name = "",
          keyword = "",
          vr = "",
          original_action = as.character(override_tags[[tg]])
        )
      }
    }
  }

  # Build tags data frame
  if (length(compiled_tags) > 0L) {
    tags_df <- data.frame(
      tag = vapply(compiled_tags, function(x) x$tag, character(1L)),
      action = vapply(compiled_tags, function(x) x$action, character(1L)),
      name = vapply(compiled_tags, function(x) x$name, character(1L)),
      keyword = vapply(compiled_tags, function(x) x$keyword, character(1L)),
      vr = vapply(compiled_tags, function(x) x$vr, character(1L)),
      stringsAsFactors = FALSE,
      row.names = NULL
    )
  } else {
    tags_df <- data.frame(
      tag = character(0),
      action = character(0),
      name = character(0),
      keyword = character(0),
      vr = character(0),
      stringsAsFactors = FALSE
    )
  }

  structure(
    list(
      profile = prof_name,
      description = prof_desc,
      cid7050_codes = cid7050_codes,
      date_policy = date_policy,
      age_cap_years = age_cap_years,
      zip_prefix_digits = zip_prefix_digits,
      regex_scrubbers = regex_scrubbers,
      disclaimers = disclaimers,
      flags = flags,
      options = options,
      jurisdictions = jurisdictions,
      safe_private = safe_private,
      tags = tags_df
    ),
    class = "dicom_deid_profile"
  )
}

#' Format Method for dicom_deid_profile
#'
#' Formats a summary of a compiled DICOM de-identification profile as character lines.
#'
#' @param x An object of class \code{"dicom_deid_profile"}.
#' @param ... Additional arguments (unused).
#' @return A character vector of formatted lines.
#' @export
format.dicom_deid_profile <- function(x, ...) {
  lines <- c(
    sprintf("=== dicom_deid_profile: %s ===", x$profile),
    sprintf("Description: %s", x$description),
    ""
  )

  if (length(x$cid7050_codes) > 0L) {
    lines <- c(lines, "CID 7050 Codes:")
    for (i in seq_along(x$cid7050_codes)) {
      cd <- names(x$cid7050_codes)[i]
      nm <- x$cid7050_codes[[i]]
      lines <- c(lines, sprintf("  * [%s] %s", cd, nm))
    }
    lines <- c(lines, "")
  }

  lines <- c(lines, "Configuration & Policies:")
  lines <- c(lines, sprintf("  * Date Policy: %s", x$date_policy))
  lines <- c(lines, sprintf("  * Age Cap: %s", if (is.null(x$age_cap_years)) "None" else sprintf("%d years", x$age_cap_years)))
  lines <- c(lines, sprintf("  * Zip Prefix: %s", if (is.null(x$zip_prefix_digits)) "None" else sprintf("%d digits", x$zip_prefix_digits)))
  lines <- c(lines, sprintf("  * Options (%d): %s", length(x$options), if (length(x$options) == 0L) "none" else paste(x$options, collapse = ", ")))
  lines <- c(lines, sprintf("  * Jurisdictions (%d): %s", length(x$jurisdictions), if (length(x$jurisdictions) == 0L) "none" else paste(x$jurisdictions, collapse = ", ")))
  lines <- c(lines, sprintf("  * Safe Private Creators: %d allowlisted", length(x$safe_private)))
  lines <- c(lines, sprintf("  * Regex Text Scrubbers: %d active", length(x$regex_scrubbers)))

  if (nrow(x$tags) > 0L) {
    act_counts <- table(x$tags$action)
    counts_str <- paste(sprintf("%s: %d", names(act_counts), as.integer(act_counts)), collapse = " | ")
    lines <- c(lines, "", sprintf("Tag Action Breakdown (%d tags):", nrow(x$tags)))
    lines <- c(lines, sprintf("  %s", counts_str))
  }

  if (length(x$disclaimers) > 0L) {
    lines <- c(lines, "")
    for (disc in x$disclaimers) {
      lines <- c(lines, sprintf("Disclaimer: %s", disc))
    }
  }

  lines
}

#' Print Method for dicom_deid_profile
#'
#' Formats and prints a human-readable summary of a compiled DICOM de-identification profile.
#'
#' @param x An object of class \code{"dicom_deid_profile"}.
#' @param ... Additional arguments passed to print methods (unused).
#' @return The object \code{x}, invisibly.
#' @export
print.dicom_deid_profile <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}
