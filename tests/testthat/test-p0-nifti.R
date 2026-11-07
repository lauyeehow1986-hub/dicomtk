# Task 6: write_nifti() with dcm2niix-compatible qform/sform + BIDS JSON sidecar

# Independent analytical dcm2niix-style RAS sform derived ONLY from the phantom
# ground truth (never from write_nifti() / read_dicom_volume() internals).
# NIfTI voxel (i = c, j = rows - 1 - r, k = s), all 0-based.
analytic_sform_ras <- function(truth_affine_lps, rows) {
  a_ras <- diag(c(-1, -1, 1, 1)) %*% truth_affine_lps
  s <- matrix(0, 4L, 4L)
  s[, 1L] <- a_ras[, 2L]                                   # i step = c step
  s[, 2L] <- -a_ras[, 1L]                                  # j step = -(r step)
  s[, 3L] <- a_ras[, 3L]                                   # k step = s step
  s[1:3, 4L] <- a_ras[1:3, 4L] + (rows - 1) * a_ras[1:3, 1L]
  s[4L, ] <- c(0, 0, 0, 1)
  s
}

as_plain_matrix <- function(m) matrix(as.double(m), nrow = 4L, ncol = 4L)

# Reconstruct a 3x3 rotation matrix from NIfTI quaternion params (b, c, d) and qfac
quatern_to_rot <- function(b, c, d, qfac) {
  a <- sqrt(max(0, 1 - (b * b + c * c + d * d)))
  r <- matrix(c(
    a * a + b * b - c * c - d * d, 2 * b * c - 2 * a * d,         2 * b * d + 2 * a * c,
    2 * b * c + 2 * a * d,         a * a + c * c - b * b - d * d, 2 * c * d - 2 * a * b,
    2 * b * d - 2 * a * c,         2 * c * d + 2 * a * b,         a * a + d * d - c * c - b * b
  ), nrow = 3L, byrow = TRUE)
  if (qfac < 0) r[, 3L] <- -r[, 3L]
  r
}

test_that("mat44_to_nifti_quatern recovers rotation, pixdim, offsets, and qfac", {
  # Identity
  q <- dicomtk:::mat44_to_nifti_quatern(diag(4L))
  expect_equal(c(q$quatern_b, q$quatern_c, q$quatern_d), c(0, 0, 0))
  expect_equal(q$qfac, 1)

  # 90 deg about z, scaled, with offset
  rz <- matrix(c(0, -1, 0, 1, 0, 0, 0, 0, 1), 3L, byrow = TRUE)
  m <- diag(4L)
  m[1:3, 1:3] <- rz %*% diag(c(2, 3, 4))
  m[1:3, 4L] <- c(10, -20, 30)
  q <- dicomtk:::mat44_to_nifti_quatern(m)
  expect_equal(c(q$dx, q$dy, q$dz), c(2, 3, 4), tolerance = 1e-12)
  expect_equal(c(q$qoffset_x, q$qoffset_y, q$qoffset_z), c(10, -20, 30))
  expect_equal(q$qfac, 1)
  expect_equal(
    quatern_to_rot(q$quatern_b, q$quatern_c, q$quatern_d, q$qfac), rz,
    tolerance = 1e-10
  )

  # Reflections (det < 0 -> qfac = -1) and a general rotation, round-tripped
  th <- 0.7
  rx <- matrix(c(1, 0, 0, 0, cos(th), -sin(th), 0, sin(th), cos(th)), 3L, byrow = TRUE)
  ry <- matrix(c(cos(0.4), 0, sin(0.4), 0, 1, 0, -sin(0.4), 0, cos(0.4)), 3L, byrow = TRUE)
  rot <- rx %*% ry
  cases <- list(
    rot,
    rot %*% diag(c(1, -1, 1)),
    diag(c(1, -1, 1)),
    diag(c(-1, 1, 1)),
    diag(c(1, 1, -1)),
    matrix(c(0, 1, 0, 1, 0, 0, 0, 0, 1), 3L, byrow = TRUE),   # swap axes, det -1
    matrix(c(0, 0, 1, 1, 0, 0, 0, 1, 0), 3L, byrow = TRUE),   # cyclic, det +1
    matrix(c(0, 0, -1, 0, -1, 0, -1, 0, 0), 3L, byrow = TRUE) # trace < 0 branch
  )
  for (r in cases) {
    mm <- diag(4L)
    mm[1:3, 1:3] <- r
    q <- dicomtk:::mat44_to_nifti_quatern(mm)
    expect_equal(q$qfac, if (det(r) < 0) -1 else 1)
    # quatern_a >= 0 always holds by construction: b^2 + c^2 + d^2 <= 1
    expect_lte(q$quatern_b^2 + q$quatern_c^2 + q$quatern_d^2, 1 + 1e-12)
    expect_equal(
      quatern_to_rot(q$quatern_b, q$quatern_c, q$quatern_d, q$qfac), r,
      tolerance = 1e-10
    )
  }
})

test_that("write_nifti sform/qform and fiducial world coordinates match dcm2niix RAS across orientations and backends", {
  skip_if_not_installed("RNifti")

  for (orient in c("axial", "coronal", "sagittal", "oblique")) {
    for (backend in c("rnifti", "builtin")) {
      out_dir <- tempfile(paste0("nii_", orient, "_"))
      nii_path <- tempfile(fileext = ".nii")
      on.exit(unlink(c(out_dir, nii_path, sub("\\.nii$", ".json", nii_path)), recursive = TRUE), add = TRUE)

      dims <- c(12L, 10L, 5L)
      ph <- dicom_synthesize(
        out_dir = out_dir, modality = "CT", dims = dims,
        spacing = c(0.8, 0.9, 2.5), origin = c(-16, -12, 5), orientation = orient
      )
      vol <- read_dicom_volume(out_dir)
      res <- write_nifti(vol, nii_path, json_sidecar = TRUE, backend = backend)
      expect_identical(normalizePath(res, winslash = "/"), normalizePath(nii_path, winslash = "/"))
      expect_true(file.exists(nii_path), info = paste(orient, backend))

      nii <- RNifti::readNifti(nii_path)
      expect_equal(unname(dim(nii)), dims[c(2L, 1L, 3L)], info = paste(orient, backend))

      target <- analytic_sform_ras(ph$truth_affine_lps, rows = dims[1L])
      sf <- as_plain_matrix(RNifti::xform(nii, useQuaternionFirst = FALSE))
      qf <- as_plain_matrix(RNifti::xform(nii, useQuaternionFirst = TRUE))
      expect_lt(max(abs(sf - target)), 1e-4, label = paste("sform", orient, backend))
      expect_lt(max(abs(qf - sf)), 1e-4, label = paste("qform==sform", orient, backend))

      hdr <- RNifti::niftiHeader(nii)
      expect_equal(hdr$qform_code, 1L)
      expect_equal(hdr$sform_code, 1L)

      # Every fiducial voxel lands on the exact RAS coordinate of its LPS point.
      tv <- ph$truth_voxels
      fids <- list(
        c(1L, 1L, 1L), c(dims[1L], 1L, 1L), c(1L, dims[2L], 1L),
        c(1L, 1L, dims[3L]), c(1L, dims[2L], dims[3L])
      )
      for (f in fids) {
        # NIfTI 1-based (i, j, k) = (c, rows - r + 1, s)
        ijk <- c(f[2L], dims[1L] - f[1L] + 1L, f[3L])
        expect_equal(
          as.numeric(nii[ijk[1L], ijk[2L], ijk[3L]]), tv[f[1L], f[2L], f[3L]],
          tolerance = 1e-4, info = paste("voxel", orient, backend, toString(f))
        )
        p_lps <- as.numeric(ph$truth_affine_lps %*% c(f[1L] - 1, f[2L] - 1, f[3L] - 1, 1))[1:3]
        w <- as.numeric(RNifti::voxelToWorld(ijk, nii))
        expect_equal(w, c(-p_lps[1L], -p_lps[2L], p_lps[3L]), tolerance = 1e-4,
                     info = paste("world", orient, backend, toString(f)))
      }
    }
  }
})

test_that("write_nifti output is identical across backends and supports .nii.gz", {
  skip_if_not_installed("RNifti")

  out_dir <- tempfile("nii_bk_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)
  dicom_synthesize(out_dir = out_dir, modality = "CT", dims = c(8L, 9L, 4L), orientation = "oblique")
  vol <- read_dicom_volume(out_dir)

  p_r <- tempfile(fileext = ".nii")
  p_b <- tempfile(fileext = ".nii.gz")
  on.exit(unlink(c(p_r, p_b, sub("\\.nii$", ".json", p_r), sub("\\.nii\\.gz$", ".json", p_b))), add = TRUE)
  write_nifti(vol, p_r, json_sidecar = FALSE, backend = "rnifti")
  write_nifti(vol, p_b, json_sidecar = TRUE, backend = "builtin")

  expect_true(file.exists(sub("\\.nii\\.gz$", ".json", p_b)))
  expect_false(file.exists(sub("\\.nii$", ".json", p_r)))

  a <- RNifti::readNifti(p_r)
  b <- RNifti::readNifti(p_b)
  expect_equal(as.array(a), as.array(b), tolerance = 1e-4, ignore_attr = TRUE)
  expect_lt(
    max(abs(as_plain_matrix(RNifti::xform(a)) - as_plain_matrix(RNifti::xform(b)))), 1e-4
  )
})

test_that("gantry-tilted CT warns that qform orthogonalizes shear but sform stays exact", {
  skip_if_not_installed("RNifti")

  out_dir <- tempfile("nii_tilt_")
  nii_path <- tempfile(fileext = ".nii")
  on.exit(unlink(c(out_dir, nii_path, sub("\\.nii$", ".json", nii_path)), recursive = TRUE), add = TRUE)

  dims <- c(10L, 10L, 6L)
  ph <- dicom_synthesize(
    out_dir = out_dir, modality = "CT", dims = dims, spacing = c(0.8, 0.8, 2.5),
    gantry_tilt_deg = 15
  )
  vol <- suppressWarnings(read_dicom_volume(out_dir))
  expect_gt(abs(vol$diagnostics$gantry_tilt_deg), 10)

  expect_warning(
    write_nifti(vol, nii_path, json_sidecar = TRUE, backend = "builtin"),
    "qform|shear|tilt"
  )

  nii <- RNifti::readNifti(nii_path)
  target <- analytic_sform_ras(ph$truth_affine_lps, rows = dims[1L])
  sf <- as_plain_matrix(RNifti::xform(nii, useQuaternionFirst = FALSE))
  expect_lt(max(abs(sf - target)), 1e-4)

  # Fiducial on the last slice maps to the exact tilted RAS coordinate via the
  # sform (RNifti::voxelToWorld() prefers the orthogonalized qform, which by
  # design cannot represent the shear, so apply the sform explicitly).
  f <- c(1L, dims[2L], dims[3L])
  ijk <- c(f[2L], dims[1L] - f[1L] + 1L, f[3L])
  p_lps <- as.numeric(ph$truth_affine_lps %*% c(f[1L] - 1, f[2L] - 1, f[3L] - 1, 1))[1:3]
  w_sform <- as.numeric(sf %*% c(ijk - 1, 1))[1:3]
  expect_equal(w_sform, c(-p_lps[1L], -p_lps[2L], p_lps[3L]), tolerance = 1e-4)

  # ...and the qform differs from the sform (shear was orthogonalized).
  qf <- as_plain_matrix(RNifti::xform(nii, useQuaternionFirst = TRUE))
  expect_gt(max(abs(qf - sf)), 1e-3)
})

test_that("write_nifti writes a BIDS-style JSON sidecar", {
  out_dir <- tempfile("nii_json_")
  nii_path <- tempfile(fileext = ".nii.gz")
  json_path <- sub("\\.nii\\.gz$", ".json", nii_path)
  on.exit(unlink(c(out_dir, nii_path, json_path), recursive = TRUE), add = TRUE)

  dicom_synthesize(out_dir = out_dir, modality = "CT", dims = c(8L, 8L, 3L), spacing = c(1, 1, 3))
  vol <- read_dicom_volume(out_dir)
  write_nifti(vol, nii_path, json_sidecar = TRUE, backend = "builtin")

  expect_true(file.exists(json_path))
  js <- jsonlite::fromJSON(json_path, simplifyVector = TRUE)
  expect_equal(js$Modality, "CT")
  expect_equal(js$ConversionSoftware, "dicomtk")
  expect_equal(as.numeric(js$SliceThickness), 3)
  expect_equal(length(js$ImageOrientationPatientDICOM), 6L)
  expect_equal(
    as.numeric(js$ImageOrientationPatientDICOM),
    c(vol$direction$d_row, vol$direction$d_col), tolerance = 1e-6
  )
})

test_that("write_nifti handles 4D volumes, dicom_series, and directory paths", {
  skip_if_not_installed("RNifti")

  vox4 <- array(as.numeric(seq_len(6 * 5 * 3 * 2)), dim = c(6L, 5L, 3L, 2L))
  aff <- diag(c(0.5, 0.5, 2, 1))
  aff[1:3, 4L] <- c(-5, -6, 7)
  vol4 <- new_dicom_volume(vox4, affine = aff, modality = "MR")
  p4 <- tempfile(fileext = ".nii")
  on.exit(unlink(c(p4, sub("\\.nii$", ".json", p4))), add = TRUE)
  write_nifti(vol4, p4, json_sidecar = FALSE, backend = "builtin")
  n4 <- RNifti::readNifti(p4)
  expect_equal(unname(dim(n4)), c(5L, 6L, 3L, 2L))
  # frame 2, voxel (r=1, c=1, s=1) -> nii (i=1, j=rows, k=1, t=2)
  expect_equal(as.numeric(n4[1, 6, 1, 2]), vox4[1, 1, 1, 2], tolerance = 1e-4)

  # directory path + dicom_series input
  out_dir <- tempfile("nii_in_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)
  dicom_synthesize(out_dir = out_dir, modality = "CT", dims = c(8L, 8L, 3L))
  pd <- tempfile(fileext = ".nii")
  ps <- tempfile(fileext = ".nii")
  on.exit(unlink(c(pd, ps)), add = TRUE)
  write_nifti(out_dir, pd, json_sidecar = FALSE)
  series <- withr::with_options(
    list(lifecycle_verbosity = "quiet"), read_dicom_series(out_dir)
  )
  write_nifti(series, ps, json_sidecar = FALSE)
  expect_lt(
    max(abs(as_plain_matrix(RNifti::xform(RNifti::readNifti(pd))) -
              as_plain_matrix(RNifti::xform(RNifti::readNifti(ps))))), 1e-4
  )
})

test_that("write_nifti validates inputs and defaults out_path", {
  expect_error(write_nifti(42), "dicom_volume|path")
  vol <- new_dicom_volume(array(0, dim = c(4L, 4L, 2L)))
  expect_error(write_nifti(vol, backend = "nope"))
  p <- write_nifti(vol, json_sidecar = FALSE, backend = "builtin")
  on.exit(unlink(p), add = TRUE)
  expect_true(file.exists(p))
  expect_match(p, "\\.nii$")
})

test_that("dicom_to_nifti delegates to write_nifti with matching geometry", {
  skip_if_not_installed("RNifti")

  out_dir <- tempfile("nii_legacy_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)
  ph <- dicom_synthesize(out_dir = out_dir, modality = "CT", dims = c(8L, 9L, 4L), orientation = "oblique")

  legacy <- dicom_to_nifti(out_dir)
  on.exit(unlink(legacy), add = TRUE)
  expect_false(file.exists(sub("\\.nii$", ".json", legacy)))
  nii <- RNifti::readNifti(legacy)
  target <- analytic_sform_ras(ph$truth_affine_lps, rows = 8L)
  expect_lt(max(abs(as_plain_matrix(RNifti::xform(nii)) - target)), 1e-4)
})

test_that("write_nifti warns when slice spacing is irregular (uniform NIfTI grid is approximate)", {
  out_dir <- tempfile("nii_irr_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)
  dicom_synthesize(out_dir = out_dir, modality = "CT", dims = c(8L, 8L, 6L), irregular_z = TRUE)
  vol <- suppressWarnings(read_dicom_volume(out_dir))
  expect_true(isTRUE(vol$diagnostics$irregular_spacing))

  p <- tempfile(fileext = ".nii")
  on.exit(unlink(p), add = TRUE)
  expect_warning(
    write_nifti(vol, p, json_sidecar = FALSE, backend = "builtin"),
    "[Ii]rregular"
  )

  # Regular series must stay silent
  reg_dir <- tempfile("nii_reg_")
  on.exit(unlink(reg_dir, recursive = TRUE), add = TRUE)
  dicom_synthesize(out_dir = reg_dir, modality = "CT", dims = c(8L, 8L, 4L))
  p2 <- tempfile(fileext = ".nii")
  on.exit(unlink(p2), add = TRUE)
  expect_no_warning(write_nifti(read_dicom_volume(reg_dir), p2, json_sidecar = FALSE, backend = "builtin"))
})

test_that("write_nifti accepts legacy v0.1.0 dicom_series objects without $affine", {
  skip_if_not_installed("RNifti")
  legacy <- structure(
    list(
      volume = structure(array(as.double(1:32), dim = c(4L, 4L, 2L)),
                         pixel_spacing = c(0.5, 0.75), slice_thickness = 2),
      metadata = tibble::tibble(), files = character(0),
      dims = c(rows = 4L, cols = 4L, slices = 2L)
    ),
    class = "dicom_series"
  )
  p <- tempfile(fileext = ".nii")
  on.exit(unlink(p), add = TRUE)
  expect_no_error(write_nifti(legacy, p, json_sidecar = FALSE, backend = "builtin"))
  nii <- RNifti::readNifti(p)
  expect_equal(unname(dim(nii)), c(4L, 4L, 2L))
  # column spacing (0.75) on i, row spacing (0.5) on j, slice thickness on k
  sf <- as_plain_matrix(RNifti::xform(nii))
  expect_equal(sqrt(colSums(sf[1:3, 1:3]^2)), c(0.75, 0.5, 2), tolerance = 1e-6)
})

test_that("write_nifti appends .nii to extensionless paths and returns the real file for every backend", {
  skip_if_not_installed("RNifti")
  vol <- new_dicom_volume(array(1, dim = c(4L, 4L, 2L)))
  for (bk in c("rnifti", "builtin")) {
    stem <- tempfile(paste0("noext_", bk, "_"))
    on.exit(unlink(paste0(stem, c("", ".nii"))), add = TRUE)
    ret <- write_nifti(vol, stem, json_sidecar = FALSE, backend = bk)
    expect_equal(ret, paste0(stem, ".nii"), info = bk)
    expect_true(file.exists(ret), info = bk)
    expect_false(file.exists(stem), info = bk)
  }
})

test_that("rnifti backend writes 4D volumes identically to the builtin writer", {
  skip_if_not_installed("RNifti")
  vox4 <- array(as.numeric(seq_len(6 * 5 * 3 * 2)), dim = c(6L, 5L, 3L, 2L))
  aff <- diag(c(0.5, 0.5, 2, 1))
  aff[1:3, 4L] <- c(-5, -6, 7)
  vol4 <- new_dicom_volume(vox4, affine = aff, modality = "MR")
  pr <- tempfile(fileext = ".nii")
  pb <- tempfile(fileext = ".nii")
  on.exit(unlink(c(pr, pb)), add = TRUE)
  write_nifti(vol4, pr, json_sidecar = FALSE, backend = "rnifti")
  write_nifti(vol4, pb, json_sidecar = FALSE, backend = "builtin")
  a <- RNifti::readNifti(pr)
  b <- RNifti::readNifti(pb)
  expect_equal(unname(dim(a)), c(5L, 6L, 3L, 2L))
  expect_equal(as.array(a), as.array(b), ignore_attr = TRUE)
  expect_lt(max(abs(as_plain_matrix(RNifti::xform(a)) - as_plain_matrix(RNifti::xform(b)))), 1e-6)
})

test_that("BIDS sidecar SliceThickness follows the DICOM tag; step goes to SpacingBetweenSlices", {
  # Overlapping recon: 5 mm thick slices reconstructed every 2.5 mm
  aff <- diag(c(0.8, 0.8, 2.5, 1))
  vol <- new_dicom_volume(
    array(0, dim = c(4L, 4L, 3L)), affine = aff, modality = "CT",
    frame_meta = tibble::tibble(SliceThickness = rep("5", 3L))
  )
  p <- tempfile(fileext = ".nii")
  json <- sub("\\.nii$", ".json", p)
  on.exit(unlink(c(p, json)), add = TRUE)
  write_nifti(vol, p, json_sidecar = TRUE, backend = "builtin")
  js <- jsonlite::fromJSON(json)
  expect_equal(as.numeric(js$SliceThickness), 5)
  expect_equal(as.numeric(js$SpacingBetweenSlices), 2.5)

  # No tag -> SliceThickness falls back to the geometric step
  vol2 <- new_dicom_volume(array(0, dim = c(4L, 4L, 3L)), affine = aff)
  write_nifti(vol2, p, json_sidecar = TRUE, backend = "builtin")
  expect_equal(as.numeric(jsonlite::fromJSON(json)$SliceThickness), 2.5)
})

test_that("rnifti backend records millimetre spatial units like the builtin writer", {
  skip_if_not_installed("RNifti")
  vol <- new_dicom_volume(array(1, dim = c(4L, 4L, 2L)))
  for (bk in c("rnifti", "builtin")) {
    p <- tempfile(fileext = ".nii")
    on.exit(unlink(p), add = TRUE)
    write_nifti(vol, p, json_sidecar = FALSE, backend = bk)
    expect_equal(bitwAnd(RNifti::niftiHeader(RNifti::readNifti(p))$xyzt_units, 7L), 2L, info = bk)
  }
})

test_that("BIDS sidecar extracts RepetitionTime/EchoTime in seconds and 4D NIfTI writes temporal pixdim[5] + sec units", {
  skip_if_not_installed("RNifti")

  aff <- diag(c(2.0, 2.0, 3.0, 1.0))
  meta4 <- tibble::tibble(
    SliceThickness = rep("3.0", 6L),
    RepetitionTime = rep("2000", 6L),
    EchoTime = rep("30", 6L)
  )
  vol4 <- new_dicom_volume(
    array(runif(4 * 4 * 3 * 2), dim = c(4L, 4L, 3L, 2L)),
    affine = aff,
    frame_meta = meta4,
    modality = "MR"
  )

  for (bk in c("builtin", "rnifti")) {
    p <- tempfile(fileext = ".nii")
    js_path <- sub("\\.nii$", ".json", p)
    on.exit(unlink(c(p, js_path)), add = TRUE)
    write_nifti(vol4, p, json_sidecar = TRUE, backend = bk)

    js <- jsonlite::fromJSON(js_path)
    expect_equal(as.numeric(js$RepetitionTime), 2.0, tolerance = 1e-6, info = bk)
    expect_equal(as.numeric(js$EchoTime), 0.03, tolerance = 1e-6, info = bk)

    hdr <- RNifti::niftiHeader(RNifti::readNifti(p))
    expect_equal(as.numeric(hdr$pixdim[5L]), 2.0, tolerance = 1e-5, info = bk)
    expect_equal(bitwAnd(hdr$xyzt_units, 7L), 2L, info = bk)
    expect_equal(bitwAnd(hdr$xyzt_units, 56L), 8L, info = bk)
  }
})
