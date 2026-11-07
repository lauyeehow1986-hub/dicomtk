# Task 7: External CI fixture downloader & dcm2niix affine/voxel parity suite

as_mat44 <- function(m) matrix(as.double(m), nrow = 4L, ncol = 4L)

test_that("helper-fixtures exposes cache path, manifest, and dcm2niix locator safely", {
  default_dir <- dicomtk_fixture_dir()
  expect_type(default_dir, "character")
  expect_length(default_dir, 1L)
  expect_true(nzchar(default_dir))
  # Must NEVER live inside the package source / installed tree (CRAN tarball hygiene)
  pkg_root <- normalizePath(system.file(package = "dicomtk"), winslash = "/", mustWork = FALSE)
  if (nzchar(pkg_root)) {
    expect_false(startsWith(normalizePath(default_dir, winslash = "/", mustWork = FALSE), pkg_root))
  }

  custom <- file.path(tempdir(), "custom_dicomtk_fixtures")
  withr::with_envvar(c(DICOMTK_FIXTURE_DIR = custom), {
    expect_equal(
      normalizePath(dicomtk_fixture_dir(), winslash = "/", mustWork = FALSE),
      normalizePath(custom, winslash = "/", mustWork = FALSE)
    )
  })

  manifest <- dicomtk_fixture_manifest()
  expect_s3_class(manifest, "data.frame")
  expect_true(all(c("id", "modality", "subdir", "url", "filename", "license") %in% names(manifest)))
  expect_gte(nrow(manifest), 7L)
  expect_true(all(c("CT", "ENHCT", "MR", "ENHMR", "US", "CR") %in% manifest$modality))
  expect_true(all(startsWith(manifest$url, "https://")))

  cmd <- find_dcm2niix_cmd()
  expect_true(is.null(cmd) || (is.list(cmd) && cmd$mode %in% c("cli", "docker")))
})

test_that("analytical dcm2niix parity holds across orientations, reversed disk order, and multi-modality phantoms", {
  skip_if_not_installed("RNifti")

  cases <- list(
    list(modality = "CT",    orientation = "axial",    rev = FALSE, dims = c(12L, 10L, 5L), sp = c(0.8, 0.9, 2.5)),
    list(modality = "CT",    orientation = "coronal",  rev = FALSE, dims = c(12L, 10L, 5L), sp = c(0.8, 0.9, 2.5)),
    list(modality = "CT",    orientation = "sagittal", rev = FALSE, dims = c(12L, 10L, 5L), sp = c(0.8, 0.9, 2.5)),
    list(modality = "CT",    orientation = "oblique",  rev = FALSE, dims = c(12L, 10L, 5L), sp = c(0.7, 0.85, 2.0)),
    list(modality = "CT",    orientation = "axial",    rev = TRUE,  dims = c(10L, 12L, 6L), sp = c(0.75, 0.75, 3.0)),
    list(modality = "MR",    orientation = "oblique",  rev = TRUE,  dims = c(10L, 11L, 5L), sp = c(0.9, 0.9, 2.2)),
    list(modality = "ENHCT", orientation = "oblique",  rev = TRUE,  dims = c(10L, 10L, 4L), sp = c(0.8, 0.8, 2.5)),
    list(modality = "ENHMR", orientation = "coronal",  rev = FALSE, dims = c(10L, 12L, 4L), sp = c(1.0, 1.0, 2.0)),
    list(modality = "PT",    orientation = "axial",    rev = FALSE, dims = c(10L, 10L, 4L), sp = c(2.0, 2.0, 3.0)),
    list(modality = "MG",    orientation = "axial",    rev = FALSE, dims = c(12L, 10L, 1L), sp = c(0.1, 0.1, 1.0))
  )

  for (tc in cases) {
    lbl <- sprintf("%s/%s/rev=%s", tc$modality, tc$orientation, tc$rev)
    in_dir <- tempfile("parity_in_")
    nii_file <- tempfile(fileext = ".nii")
    on.exit(unlink(c(in_dir, nii_file, sub("\\.nii$", ".json", nii_file)), recursive = TRUE), add = TRUE)

    ph <- dicom_synthesize(
      out_dir = in_dir,
      modality = tc$modality,
      dims = tc$dims,
      spacing = tc$sp,
      origin = c(-25.0, -18.0, 12.5),
      orientation = tc$orientation,
      reverse_order = tc$rev,
      phi = FALSE
    )

    vol <- read_dicom_volume(in_dir, warn = FALSE)
    write_nifti(vol, nii_file, json_sidecar = TRUE, backend = "builtin")

    nii <- RNifti::readNifti(nii_file)
    sf <- as_mat44(RNifti::xform(nii, useQuaternionFirst = FALSE))
    qf <- as_mat44(RNifti::xform(nii, useQuaternionFirst = TRUE))
    oracle <- dicomtk_analytic_dcm2niix_sform(ph)

    expect_lt(max(abs(sf - oracle)), 1e-4, label = paste("sform vs dcm2niix oracle:", lbl))
    expect_lt(max(abs(qf - oracle)), 1e-4, label = paste("qform vs dcm2niix oracle:", lbl))

    expected_nii_vox <- aperm(ph$truth_voxels[tc$dims[1L]:1L, , , drop = FALSE], c(2L, 1L, 3L))
    if (tc$dims[3L] == 1L) {
      expect_equal(as.numeric(as.array(nii)), as.numeric(expected_nii_vox), tolerance = 1e-4, info = lbl)
    } else {
      expect_equal(as.array(nii), expected_nii_vox, tolerance = 1e-4, ignore_attr = TRUE, info = lbl)
    }
  }
})

test_that("live dcm2niix binary/Docker cross-check matches sform and voxels within 1e-4", {
  skip_if_not_installed("RNifti")
  cmd <- find_dcm2niix_cmd()
  skip_if(is.null(cmd), "dcm2niix CLI / Docker image not available on this machine")

  configs <- list(
    list(orientation = "axial",    rev = FALSE),
    list(orientation = "coronal",  rev = FALSE),
    list(orientation = "sagittal", rev = FALSE),
    list(orientation = "oblique",  rev = FALSE),
    list(orientation = "oblique",  rev = TRUE)
  )

  for (cfg in configs) {
    lbl <- sprintf("live-%s-rev=%s", cfg$orientation, cfg$rev)
    dcm_dir <- tempfile("dcm2niix_src_")
    ref_dir <- tempfile("dcm2niix_ref_")
    our_nii <- tempfile(fileext = ".nii")
    dir.create(ref_dir, recursive = TRUE)
    on.exit(unlink(c(dcm_dir, ref_dir, our_nii, sub("\\.nii$", ".json", our_nii)), recursive = TRUE), add = TRUE)

    dicom_synthesize(
      out_dir = dcm_dir,
      modality = "CT",
      dims = c(12L, 10L, 5L),
      spacing = c(0.8, 0.9, 2.5),
      origin = c(-20, -15, 10),
      orientation = cfg$orientation,
      reverse_order = cfg$rev,
      phi = FALSE
    )

    ref_nii <- run_dcm2niix_convert(dcm_dir, ref_dir, cmd = cmd)
    expect_true(file.exists(ref_nii), info = lbl)

    vol <- read_dicom_volume(dcm_dir, warn = FALSE)
    write_nifti(vol, our_nii, json_sidecar = FALSE)

    nii_ours <- RNifti::readNifti(our_nii)
    nii_ref <- RNifti::readNifti(ref_nii)

    sf_ours <- as_mat44(RNifti::xform(nii_ours, useQuaternionFirst = FALSE))
    sf_ref <- as_mat44(RNifti::xform(nii_ref, useQuaternionFirst = FALSE))

    expect_lt(max(abs(sf_ours - sf_ref)), 1e-4, label = paste("sform:", lbl))
    expect_lt(max(abs(as.array(nii_ours) - as.array(nii_ref))), 1e-4, label = paste("voxels:", lbl))
  }
})

test_that("cached external reference DICOM fixtures load with valid non-singular geometry and NIfTI export", {
  skip_if_not_installed("RNifti")
  fixtures <- dicomtk_cached_fixtures()
  skip_if(nrow(fixtures) == 0L, "No cached external DICOM fixtures; run `Rscript tools/download_fixtures.R` to populate.")

  for (i in seq_len(nrow(fixtures))) {
    fx <- fixtures[i, , drop = FALSE]
    lbl <- paste0(fx$id, " (", fx$modality, ")")
    vol <- read_dicom_volume(fx$path, warn = FALSE)
    expect_true(is_dicom_volume(vol), info = lbl)
    expect_true(all(dim(vol) >= 1L), info = lbl)
    expect_true(all(is.finite(vol$voxels)), info = lbl)
    expect_gt(abs(det(vol$affine[1:3, 1:3])), 1e-8, label = paste("non-singular affine:", lbl))

    nii_path <- tempfile(fileext = ".nii")
    on.exit(unlink(c(nii_path, sub("\\.nii$", ".json", nii_path))), add = TRUE)
    has_warn <- isTRUE(vol$diagnostics$has_gantry_tilt) || isTRUE(vol$diagnostics$irregular_spacing)
    if (has_warn) {
      expect_warning(write_nifti(vol, nii_path, json_sidecar = TRUE, backend = "builtin"))
    } else {
      expect_no_warning(write_nifti(vol, nii_path, json_sidecar = TRUE, backend = "builtin"))
    }
    nii <- RNifti::readNifti(nii_path)
    expect_equal(unname(dim(nii)[1:2]), dim(vol)[c(2L, 1L)], info = lbl)
    sf <- as_mat44(RNifti::xform(nii, useQuaternionFirst = FALSE))
    expect_gt(abs(det(sf[1:3, 1:3])), 1e-8, label = paste("NIfTI sform det:", lbl))
  }
})
