#!/usr/bin/env Rscript
# Download small open-license reference DICOM fixtures into the user cache
# (`tools::R_user_dir("dicomtk", "cache")/fixtures` or `DICOMTK_FIXTURE_DIR`).
# Never writes inside the package tree so CRAN tarballs stay clean.

local({
  args <- commandArgs(trailingOnly = TRUE)
  force_dl <- "--force" %in% args
  quiet_dl <- "--quiet" %in% args

  # Locate helper-fixtures.R relative to the repo root or working directory
  candidates <- c(
    file.path(getwd(), "tests", "testthat", "helper-fixtures.R"),
    local({
      f_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
      if (length(f_arg) > 0L) {
        script_dir <- dirname(normalizePath(sub("^--file=", "", f_arg[1L]), winslash = "/", mustWork = FALSE))
        file.path(dirname(script_dir), "tests", "testthat", "helper-fixtures.R")
      } else {
        ""
      }
    })
  )
  helper_path <- candidates[nzchar(candidates) & file.exists(candidates)][1L]
  if (is.na(helper_path)) {
    stop("Could not locate tests/testthat/helper-fixtures.R. Run from package root.", call. = FALSE)
  }

  env <- new.env(parent = globalenv())
  sys.source(helper_path, envir = env)

  dest_root <- env$dicomtk_fixture_dir()
  manifest <- env$dicomtk_fixture_manifest()
  dir.create(dest_root, recursive = TRUE, showWarnings = FALSE)

  if (!quiet_dl) {
    message(sprintf("Caching %d reference DICOM file(s) in: %s", nrow(manifest), dest_root))
  }

  n_downloaded <- 0L
  n_cached <- 0L
  failures <- character(0)

  old_timeout <- getOption("timeout")
  on.exit(options(timeout = old_timeout), add = TRUE)
  options(timeout = max(120L, as.integer(if (is.null(old_timeout)) 60L else old_timeout)))

  for (i in seq_len(nrow(manifest))) {
    row <- manifest[i, , drop = FALSE]
    sub_dir <- file.path(dest_root, row$subdir)
    dir.create(sub_dir, recursive = TRUE, showWarnings = FALSE)
    target <- file.path(sub_dir, row$filename)

    if (!force_dl && file.exists(target) && isTRUE(file.info(target)$size > 128)) {
      n_cached <- n_cached + 1L
      next
    }

    tmp <- paste0(target, ".part")
    ok <- FALSE
    for (attempt in 1:3) {
      status <- tryCatch(
        utils::download.file(row$url, destfile = tmp, mode = "wb", quiet = TRUE),
        error = function(e) 1L
      )
      if (identical(as.integer(status), 0L) && file.exists(tmp) && isTRUE(file.info(tmp)$size > 128)) {
        file.rename(tmp, target)
        ok <- TRUE
        break
      }
      unlink(tmp)
      Sys.sleep(0.5 * attempt)
    }

    if (ok) {
      n_downloaded <- n_downloaded + 1L
      if (!quiet_dl) {
        message(sprintf("  [OK] %s/%s (%s)", row$subdir, row$filename, row$modality))
      }
    } else {
      failures <- c(failures, sprintf("%s (%s)", row$filename, row$url))
      warning(sprintf("Failed to download %s from %s", row$filename, row$url), call. = FALSE)
    }
  }

  if (!quiet_dl) {
    message(sprintf(
      "Fixture sync complete: %d downloaded, %d already cached, %d failed.",
      n_downloaded, n_cached, length(failures)
    ))
  }

  if (length(failures) > 0L) {
    quit(save = "no", status = 1L)
  }
})
