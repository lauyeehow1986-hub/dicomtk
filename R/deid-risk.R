#' Re-Identification Risk Scoring and K-Anonymity Assessment
#'
#' Evaluates re-identification risk metrics across a cohort of DICOM studies
#' by grouping subjects into quasi-identifier equivalence classes. Computes
#' \eqn{k}-anonymity, \eqn{\ell}-diversity, maximum prosecutor risk, journalist
#' risk, and marketer risk in compliance with HIPAA Expert Determination and
#' privacy engineering standards.
#'
#' @param path Character vector of DICOM file paths, or a directory path.
#' @param quasi_ids Character vector of DICOM keywords or attributes acting as
#'   quasi-identifiers (e.g. \code{c("PatientSex", "PatientAge", "Modality", "StudyYear")}).
#' @param sensitive_attr Character string specifying the sensitive clinical attribute
#'   used for \eqn{\ell}-diversity calculation (default is \code{"BodyPartExamined"}).
#' @param k_threshold Integer minimum acceptable cell size \eqn{k} (default is \code{5L}).
#'   Equivalence classes with \eqn{k < k\_threshold} are flagged.
#'
#' @return An S3 object of class \code{"dicom_deid_risk"} containing:
#'   \item{k_min}{Integer minimum equivalence class size (\eqn{k}-anonymity).}
#'   \item{l_min}{Integer minimum number of distinct sensitive values (\eqn{\ell}-diversity).}
#'   \item{max_prosecutor_risk}{Numeric maximum prosecutor re-identification risk (\eqn{1 / k_{min}}).}
#'   \item{journalist_risk}{Numeric journalist risk (proportion of singleton subjects with \eqn{k = 1}).}
#'   \item{marketer_risk}{Numeric marketer risk (average re-identification probability across cohort).}
#'   \item{k_threshold}{Integer threshold applied.}
#'   \item{n_subjects}{Total number of unique subjects in the cohort.}
#'   \item{n_equivalence_classes}{Total number of distinct equivalence classes.}
#'   \item{equivalence_classes}{Tibble detailing each equivalence class, its \eqn{k} size, \eqn{\ell} diversity, and member subjects.}
#'   \item{flagged_subjects}{Character vector of subject IDs belonging to under-protected equivalence classes (\eqn{k < k\_threshold}).}
#'   \item{flagged_patients}{Alias for \code{flagged_subjects}.}
#'   \item{quasi_ids}{Character vector of active quasi-identifiers.}
#'   \item{sensitive_attr}{Active sensitive attribute.}
#' @export
#'
#' @examples
#' \dontrun{
#' rk <- dicom_deid_risk("path/to/cohort", k_threshold = 5L)
#' print(rk)
#' if (rk$k_min < 5L) {
#'   message("Cohort requires generalization for: ", paste(rk$flagged_subjects, collapse = ", "))
#' }
#' }
dicom_deid_risk <- function(path,
                            quasi_ids = c("PatientSex", "PatientAge", "Modality", "StudyYear"),
                            sensitive_attr = "BodyPartExamined",
                            k_threshold = 5L) {
  files <- resolve_dicom_paths(path, recursive = TRUE)
  if (length(files) == 0L) {
    cli::cli_abort("No valid DICOM files found in `path`.")
  }

  meta <- read_dicom(files, wide = TRUE)

  # Derive StudyYear if requested and StudyDate is present
  if ("StudyYear" %in% quasi_ids && !"StudyYear" %in% names(meta)) {
    if ("StudyDate" %in% names(meta)) {
      meta$StudyYear <- substr(gsub("[^0-9]", "", as.character(meta$StudyDate)), 1L, 4L)
    } else {
      meta$StudyYear <- ""
    }
  }

  # Ensure all quasi_ids and sensitive_attr exist in meta
  for (q in c(quasi_ids, sensitive_attr)) {
    if (!q %in% names(meta)) {
      meta[[q]] <- ""
    }
  }

  pid_col <- if ("PatientID" %in% names(meta)) {
    "PatientID"
  } else if ("(0010,0020)" %in% names(meta)) {
    "(0010,0020)"
  } else {
    "file"
  }

  meta$SubjectID <- as.character(meta[[pid_col]])
  meta$SubjectID[is.na(meta$SubjectID) | !nzchar(meta$SubjectID)] <- basename(meta$file[is.na(meta$SubjectID) | !nzchar(meta$SubjectID)])

  # Aggregate by SubjectID
  sub_list <- split(meta, meta$SubjectID)
  subject_rows <- lapply(sub_list, function(df) {
    res <- list(SubjectID = df$SubjectID[1L])
    for (q in quasi_ids) {
      vals <- df[[q]]
      val_clean <- vals[!is.na(vals) & nzchar(as.character(vals))]
      res[[q]] <- if (length(val_clean) > 0L) as.character(val_clean[1L]) else ""
    }
    sens_vals <- df[[sensitive_attr]]
    sens_clean <- unique(sens_vals[!is.na(sens_vals) & nzchar(as.character(sens_vals))])
    res[["sens_values"]] <- list(sens_clean)
    tibble::as_tibble(res)
  })

  subjects_df <- dplyr::bind_rows(subject_rows)

  # Group by quasi-identifiers to form Equivalence Classes
  class_keys <- apply(subjects_df[, quasi_ids, drop = FALSE], 1L, paste, collapse = " | ")
  split_classes <- split(subjects_df, class_keys)

  eq_list <- lapply(split_classes, function(cdf) {
    k_size <- nrow(cdf)
    subjs <- sort(cdf$SubjectID)
    sens_all <- unique(unlist(cdf$sens_values))
    l_size <- length(sens_all)

    out <- as.list(cdf[1L, quasi_ids, drop = FALSE])
    out$k <- as.integer(k_size)
    out$l <- as.integer(l_size)
    out$flagged <- k_size < as.integer(k_threshold)
    out$subjects <- list(subjs)
    out$sensitive_values <- list(sens_all)
    tibble::as_tibble(out)
  })

  equiv_df <- dplyr::bind_rows(eq_list)

  n_subj <- nrow(subjects_df)
  n_classes <- nrow(equiv_df)

  k_min <- if (n_classes > 0L) min(equiv_df$k) else 0L
  l_min <- if (n_classes > 0L) min(equiv_df$l) else 0L

  max_prosecutor <- if (k_min > 0L) 1.0 / k_min else 0.0
  journalist <- if (n_subj > 0L) sum(equiv_df$k[equiv_df$k == 1L]) / n_subj else 0.0
  marketer <- if (n_subj > 0L) n_classes / n_subj else 0.0

  flagged_subjs <- if (n_classes > 0L) {
    sort(unique(unlist(equiv_df$subjects[equiv_df$k < as.integer(k_threshold)])))
  } else {
    character(0L)
  }
  if (is.null(flagged_subjs)) flagged_subjs <- character(0L)

  structure(
    list(
      k_min = as.integer(k_min),
      l_min = as.integer(l_min),
      max_prosecutor_risk = round(max_prosecutor, 4L),
      journalist_risk = round(journalist, 4L),
      marketer_risk = round(marketer, 4L),
      k_threshold = as.integer(k_threshold),
      n_subjects = as.integer(n_subj),
      n_equivalence_classes = as.integer(n_classes),
      equivalence_classes = equiv_df,
      flagged_subjects = flagged_subjs,
      flagged_patients = flagged_subjs,
      quasi_ids = quasi_ids,
      sensitive_attr = sensitive_attr
    ),
    class = "dicom_deid_risk"
  )
}

#' Print Method for DICOM De-Identification Risk
#'
#' @param x A \code{dicom_deid_risk} object.
#' @param ... Additional arguments ignored.
#' @return Invisibly returns \code{x}.
#' @export
print.dicom_deid_risk <- function(x, ...) {
  cli::cli_h1("DICOM Cohort Re-Identification Risk Assessment")
  cli::cli_bullets(c(
    "*" = paste0("Cohort Size: ", x$n_subjects, " subjects across ", x$n_equivalence_classes, " equivalence classes"),
    "*" = paste0("Quasi-Identifiers: ", paste(x$quasi_ids, collapse = ", ")),
    "*" = paste0("Sensitive Attribute: ", x$sensitive_attr),
    "*" = paste0("k-Threshold: ", x$k_threshold)
  ))

  k_status <- if (x$k_min >= x$k_threshold) cli::col_green(paste0("k_min = ", x$k_min)) else cli::col_red(paste0("k_min = ", x$k_min, " (BELOW THRESHOLD ", x$k_threshold, ")"))
  cli::cli_h2("Privacy & Risk Metrics")
  cli::cli_bullets(c(
    "*" = paste0("k-Anonymity: ", k_status),
    "*" = paste0("l-Diversity: l_min = ", x$l_min),
    "*" = paste0("Max Prosecutor Risk (1 / k_min): ", format(x$max_prosecutor_risk, nsmall = 4L)),
    "*" = paste0("Journalist Risk (Singletons / N): ", format(x$journalist_risk, nsmall = 4L)),
    "*" = paste0("Marketer Risk (Classes / N): ", format(x$marketer_risk, nsmall = 4L))
  ))

  if (length(x$flagged_subjects) > 0L) {
    cli::cli_alert_danger("{length(x$flagged_subjects)} subject(s) in high-risk cells (k < {x$k_threshold}):")
    cli::cli_text(paste(head(x$flagged_subjects, 10L), collapse = ", "))
    if (length(x$flagged_subjects) > 10L) {
      cli::cli_text("... and {length(x$flagged_subjects) - 10L} more")
    }
  } else {
    cli::cli_alert_success("All equivalence classes satisfy k >= {x$k_threshold}.")
  }

  invisible(x)
}
