# Test helpers for external reference DICOM fixtures & dcm2niix parity checks

dicomtk_fixture_dir <- function() {
  override <- trimws(Sys.getenv("DICOMTK_FIXTURE_DIR", unset = ""))
  if (nzchar(override)) {
    return(override)
  }
  file.path(tools::R_user_dir("dicomtk", which = "cache"), "fixtures")
}

dicomtk_fixture_manifest <- function() {
  pydicom_core <- "https://raw.githubusercontent.com/pydicom/pydicom/main/src/pydicom/data/test_files"
  pydicom_data <- "https://raw.githubusercontent.com/pydicom/pydicom-data/master/data_store/data"
  dcmqa_ct     <- "https://raw.githubusercontent.com/neurolabusc/dcm_qa_ct/master/In/GE"
  dcmqa_nih    <- "https://raw.githubusercontent.com/neurolabusc/dcm_qa_nih/master/In/20180918GE/mr_0004"

  data.frame(
    id = c(
      "pydicom_ct_small",
      "dcmqa_ge_ct", "dcmqa_ge_ct", "dcmqa_ge_ct",
      "pydicom_ect",
      "dcmqa_nih_mr", "dcmqa_nih_mr", "dcmqa_nih_mr",
      "pydicom_emri",
      "pydicom_us",
      "pydicom_rg"
    ),
    modality = c(
      "CT",
      "CT", "CT", "CT",
      "ENHCT",
      "MR", "MR", "MR",
      "ENHMR",
      "US",
      "CR"
    ),
    subdir = c(
      "ct_pydicom_small",
      "ct_dcmqa_ge", "ct_dcmqa_ge", "ct_dcmqa_ge",
      "enhct_pydicom",
      "mr_dcmqa_nih", "mr_dcmqa_nih", "mr_dcmqa_nih",
      "enhmr_pydicom",
      "us_pydicom",
      "cr_pydicom"
    ),
    filename = c(
      "CT_small.dcm",
      "01.dcm", "02.dcm", "03.dcm",
      "eCT_Supplemental.dcm",
      "axial_epi_fmri_space-00001.dcm",
      "axial_epi_fmri_space-00002.dcm",
      "axial_epi_fmri_space-00003.dcm",
      "emri_small.dcm",
      "US1_UNCI.dcm",
      "RG1_UNCI.dcm"
    ),
    url = c(
      paste0(pydicom_core, "/CT_small.dcm"),
      paste0(dcmqa_ct, "/01.dcm"),
      paste0(dcmqa_ct, "/02.dcm"),
      paste0(dcmqa_ct, "/03.dcm"),
      paste0(pydicom_data, "/eCT_Supplemental.dcm"),
      paste0(dcmqa_nih, "/axial_epi_fmri_interleaved_i_to_s-00001.dcm"),
      paste0(dcmqa_nih, "/axial_epi_fmri_interleaved_i_to_s-00002.dcm"),
      paste0(dcmqa_nih, "/axial_epi_fmri_interleaved_i_to_s-00003.dcm"),
      paste0(pydicom_data, "/emri_small.dcm"),
      paste0(pydicom_data, "/US1_UNCI.dcm"),
      paste0(pydicom_data, "/RG1_UNCI.dcm")
    ),
    license = c(
      "MIT (pydicom)",
      "BSD-2-Clause (neurolabusc/dcm_qa_ct)",
      "BSD-2-Clause (neurolabusc/dcm_qa_ct)",
      "BSD-2-Clause (neurolabusc/dcm_qa_ct)",
      "MIT (pydicom-data)",
      "BSD-2-Clause (neurolabusc/dcm_qa_nih)",
      "BSD-2-Clause (neurolabusc/dcm_qa_nih)",
      "BSD-2-Clause (neurolabusc/dcm_qa_nih)",
      "MIT (pydicom-data)",
      "MIT (pydicom-data)",
      "MIT (pydicom-data)"
    ),
    stringsAsFactors = FALSE
  )
}

dicomtk_cached_fixtures <- function(root = dicomtk_fixture_dir()) {
  empty_df <- data.frame(
    id = character(0),
    modality = character(0),
    path = character(0),
    n_files = integer(0),
    stringsAsFactors = FALSE
  )
  if (!dir.exists(root)) {
    return(empty_df)
  }
  mf <- dicomtk_fixture_manifest()
  ids <- unique(mf$id)
  rows <- vector("list", length(ids))
  n_ok <- 0L
  for (fx_id in ids) {
    sub <- mf[mf$id == fx_id, , drop = FALSE]
    dir_path <- file.path(root, sub$subdir[1L])
    expected_files <- file.path(dir_path, sub$filename)
    if (all(file.exists(expected_files)) && all(file.info(expected_files)$size > 128)) {
      n_ok <- n_ok + 1L
      rows[[n_ok]] <- data.frame(
        id = fx_id,
        modality = sub$modality[1L],
        path = normalizePath(dir_path, winslash = "/", mustWork = TRUE),
        n_files = nrow(sub),
        stringsAsFactors = FALSE
      )
    }
  }
  if (n_ok == 0L) {
    return(empty_df)
  }
  do.call(rbind, rows[seq_len(n_ok)])
}

# Independent Chris Rorden dcm2niix RAS sform oracle computed directly from
# DICOM IOP (d_row, d_col), PixelSpacing (dr, dc), slice positions (LPS), and Rows.
dicomtk_analytic_dcm2niix_sform <- function(phantom) {
  rows <- phantom$dims[1L]
  nslices <- phantom$dims[3L]
  dr <- phantom$spacing[1L]
  dc <- phantom$spacing[2L]
  dz <- phantom$spacing[3L]

  d_row_lps <- phantom$direction$d_row
  d_col_lps <- phantom$direction$d_col
  nrm_lps   <- phantom$direction$normal

  ipp_first_lps <- as.double(phantom$slice_positions_lps[1L, ])
  s_step_lps <- if (nslices > 1L) {
    (as.double(phantom$slice_positions_lps[nslices, ]) - ipp_first_lps) / (nslices - 1.0)
  } else {
    nrm_lps * dz
  }

  lps_to_ras3 <- function(v) c(-v[1L], -v[2L], v[3L])
  d_row_ras <- lps_to_ras3(d_row_lps)
  d_col_ras <- lps_to_ras3(d_col_lps)
  s_step_ras <- lps_to_ras3(s_step_lps)
  ipp_first_ras <- lps_to_ras3(ipp_first_lps)

  s <- matrix(0.0, nrow = 4L, ncol = 4L)
  s[1:3, 1L] <- d_row_ras * dc
  s[1:3, 2L] <- -d_col_ras * dr
  s[1:3, 3L] <- s_step_ras
  s[1:3, 4L] <- ipp_first_ras + (rows - 1.0) * d_col_ras * dr
  s[4L, ] <- c(0.0, 0.0, 0.0, 1.0)
  s
}

find_dcm2niix_cmd <- function() {
  bin <- Sys.which("dcm2niix")
  if (nzchar(bin)) {
    rc <- tryCatch(
      suppressWarnings(system2(bin, "-h", stdout = FALSE, stderr = FALSE)),
      error = function(e) 127L
    )
    if (as.integer(rc) %in% c(0L, 1L, 2L, 3L)) {
      return(list(mode = "cli", bin = unname(bin)))
    }
  }

  if (identical(tolower(Sys.getenv("DICOMTK_DOCKER_DCM2NIIX", unset = "")), "true")) {
    dk <- Sys.which("docker")
    if (nzchar(dk)) {
      rc <- tryCatch(
        suppressWarnings(system2(dk, "info", stdout = FALSE, stderr = FALSE)),
        error = function(e) 127L
      )
      if (identical(as.integer(rc), 0L)) {
        img <- Sys.getenv("DICOMTK_DCM2NIIX_IMAGE", unset = "vnmd/dcm2niix_20240202:latest")
        return(list(mode = "docker", bin = unname(dk), image = img))
      }
    }
  }

  NULL
}

docker_mount_path <- function(p) {
  norm <- normalizePath(p, winslash = "/", mustWork = TRUE)
  if (.Platform$OS.type == "windows") {
    norm <- sub("^([A-Za-z]):", "/\\L\\1", norm, perl = TRUE)
  }
  norm
}

run_dcm2niix_convert <- function(in_dir, out_dir, cmd = find_dcm2niix_cmd()) {
  if (is.null(cmd)) {
    stop("dcm2niix command is not available.", call. = FALSE)
  }
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  in_norm <- normalizePath(in_dir, winslash = "/", mustWork = TRUE)
  out_norm <- normalizePath(out_dir, winslash = "/", mustWork = TRUE)

  if (identical(cmd$mode, "cli")) {
    args <- c("-z", "n", "-b", "n", "-f", "ref", "-o", out_norm, in_norm)
    rc <- system2(cmd$bin, args, stdout = FALSE, stderr = FALSE)
  } else {
    args <- c(
      "run", "--rm",
      "-v", paste0(docker_mount_path(in_dir), ":/in:ro"),
      "-v", paste0(docker_mount_path(out_dir), ":/out"),
      cmd$image,
      "dcm2niix", "-z", "n", "-b", "n", "-f", "ref", "-o", "/out", "/in"
    )
    rc <- system2(cmd$bin, args, stdout = FALSE, stderr = FALSE)
  }

  niis <- list.files(out_norm, pattern = "\\.nii(\\.gz)?$", full.names = TRUE)
  if (length(niis) == 0L) {
    stop(sprintf("dcm2niix exited with status %s and produced no .nii output.", as.character(rc)), call. = FALSE)
  }
  niis[1L]
}
