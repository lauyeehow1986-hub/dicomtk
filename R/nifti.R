# NIfTI-1 export with dcm2niix-compatible qform/sform and BIDS-style JSON sidecar

# Internal: NIfTI-1 `nifti_mat44_to_quatern` port.
#
# Decomposes the upper-left 3x3 of a 4x4 affine into pixel sizes (column
# norms), the nearest proper rotation (polar decomposition via SVD), the
# handedness flag `qfac` (-1 when the rotation block has a negative
# determinant, in which case the 3rd rotation column is negated), and the
# unit quaternion parameters (b, c, d) with a >= 0 enforced.
mat44_to_nifti_quatern <- function(m) {
  if (!is.matrix(m) || !identical(dim(m), c(4L, 4L)) || any(!is.finite(m))) {
    cli::cli_abort("{.arg m} must be a finite 4x4 numeric matrix.")
  }
  r <- m[1:3, 1:3, drop = FALSE]

  # Pixel sizes = column norms; fall back to unit axes for degenerate columns
  norms <- sqrt(colSums(r^2))
  for (j in 1:3) {
    if (norms[j] < 1e-12) {
      r[, j] <- 0
      r[j, j] <- 1
      norms[j] <- 1
    }
  }
  r <- sweep(r, 2L, norms, "/")

  # Nearest orthogonal matrix (orthogonalizes any shear, e.g. gantry tilt)
  sv <- svd(r)
  q <- sv$u %*% t(sv$v)

  qfac <- 1
  if (det(q) < 0) {
    q[, 3L] <- -q[, 3L]
    qfac <- -1
  }

  r11 <- q[1L, 1L]; r12 <- q[1L, 2L]; r13 <- q[1L, 3L]
  r21 <- q[2L, 1L]; r22 <- q[2L, 2L]; r23 <- q[2L, 3L]
  r31 <- q[3L, 1L]; r32 <- q[3L, 2L]; r33 <- q[3L, 3L]

  a <- r11 + r22 + r33 + 1
  if (a > 0.5) {
    a <- 0.5 * sqrt(a)
    b <- 0.25 * (r32 - r23) / a
    c <- 0.25 * (r13 - r31) / a
    d <- 0.25 * (r21 - r12) / a
  } else {
    xd <- 1 + r11 - (r22 + r33)
    yd <- 1 + r22 - (r11 + r33)
    zd <- 1 + r33 - (r11 + r22)
    if (xd > 1) {
      b <- 0.5 * sqrt(xd)
      c <- 0.25 * (r12 + r21) / b
      d <- 0.25 * (r13 + r31) / b
      a <- 0.25 * (r32 - r23) / b
    } else if (yd > 1) {
      c <- 0.5 * sqrt(yd)
      b <- 0.25 * (r12 + r21) / c
      d <- 0.25 * (r23 + r32) / c
      a <- 0.25 * (r13 - r31) / c
    } else {
      d <- 0.5 * sqrt(zd)
      b <- 0.25 * (r13 + r31) / d
      c <- 0.25 * (r23 + r32) / d
      a <- 0.25 * (r21 - r12) / d
    }
    if (a < 0) {
      a <- -a
      b <- -b
      c <- -c
      d <- -d
    }
  }

  list(
    quatern_b = b, quatern_c = c, quatern_d = d,
    qoffset_x = m[1L, 4L], qoffset_y = m[2L, 4L], qoffset_z = m[3L, 4L],
    dx = norms[1L], dy = norms[2L], dz = norms[3L],
    qfac = qfac,
    rotation = q
  )
}

# Internal: exact RAS sform for the NIfTI voxel layout (i = c, j = rows-1-r, k = s)
nifti_sform_from_ras_affine <- function(a_ras, rows) {
  s <- matrix(0, 4L, 4L)
  s[, 1L] <- a_ras[, 2L]
  s[, 2L] <- -a_ras[, 1L]
  s[, 3L] <- a_ras[, 3L]
  s[1:3, 4L] <- a_ras[1:3, 4L] + (rows - 1) * a_ras[1:3, 1L]
  s[4L, ] <- c(0, 0, 0, 1)
  s
}

# Internal: orthogonalized qform matrix [R_q * diag(dx, dy, dz) | offset]
nifti_qform_matrix <- function(qp) {
  rot <- qp$rotation
  if (qp$qfac < 0) rot[, 3L] <- -rot[, 3L]
  m <- diag(4L)
  m[1:3, 1:3] <- rot %*% diag(c(qp$dx, qp$dy, qp$dz))
  m[1:3, 4L] <- c(qp$qoffset_x, qp$qoffset_y, qp$qoffset_z)
  m
}

# Internal: permute R `[rows, cols, slices(, frames)]` into NIfTI `[i, j, k(, t)]`
nifti_permute_voxels <- function(voxels) {
  d <- dim(voxels)
  if (length(d) == 4L) {
    aperm(voxels[d[1L]:1L, , , , drop = FALSE], c(2L, 1L, 3L, 4L))
  } else {
    aperm(voxels[d[1L]:1L, , , drop = FALSE], c(2L, 1L, 3L))
  }
}

# Internal: little-endian field writers into a raw header buffer (0-based offsets)
nifti_put_num <- function(buf, off, x, size, integer = FALSE) {
  bytes <- if (integer) {
    writeBin(as.integer(x), raw(), size = size, endian = "little")
  } else {
    writeBin(as.double(x), raw(), size = size, endian = "little")
  }
  buf[off + seq_along(bytes)] <- bytes
  buf
}

nifti_put_chr <- function(buf, off, txt, maxlen) {
  bytes <- charToRaw(txt)
  bytes <- bytes[seq_len(min(length(bytes), maxlen))]
  buf[off + seq_along(bytes)] <- bytes
  buf
}

# Internal: dependency-free NIfTI-1 (single-file `n+1`) float32 writer
nifti_write_builtin <- function(arr, sform, qp, out_path) {
  d <- dim(arr)
  ndim <- length(d)
  dim_vec <- c(ndim, d, rep(1L, 7L - ndim))

  buf <- raw(352L)
  buf <- nifti_put_num(buf, 0L, 348L, 4L, TRUE)                       # sizeof_hdr
  buf <- nifti_put_chr(buf, 38L, "r", 1L)                             # regular
  buf <- nifti_put_num(buf, 40L, dim_vec, 2L, TRUE)                   # dim[8]
  buf <- nifti_put_num(buf, 70L, 16L, 2L, TRUE)                       # datatype = FLOAT32
  buf <- nifti_put_num(buf, 72L, 32L, 2L, TRUE)                       # bitpix
  pixdim <- c(qp$qfac, qp$dx, qp$dy, qp$dz, rep(1, 4L))
  if (ndim == 3L) pixdim[5L] <- 0
  buf <- nifti_put_num(buf, 76L, pixdim, 4L)                          # pixdim[8]
  buf <- nifti_put_num(buf, 108L, 352, 4L)                            # vox_offset
  buf <- nifti_put_num(buf, 112L, 1, 4L)                              # scl_slope
  buf <- nifti_put_num(buf, 116L, 0, 4L)                              # scl_inter
  buf <- nifti_put_num(buf, 123L, 2L, 1L, TRUE)                       # xyzt_units = mm
  fin <- arr[is.finite(arr)]
  if (length(fin) > 0L) {
    buf <- nifti_put_num(buf, 124L, max(fin), 4L)                     # cal_max
    buf <- nifti_put_num(buf, 128L, min(fin), 4L)                     # cal_min
  }
  buf <- nifti_put_chr(buf, 148L, "Created by dicomtk", 79L)          # descrip
  buf <- nifti_put_num(buf, 252L, 1L, 2L, TRUE)                       # qform_code = SCANNER_ANAT
  buf <- nifti_put_num(buf, 254L, 1L, 2L, TRUE)                       # sform_code = SCANNER_ANAT
  buf <- nifti_put_num(buf, 256L, c(qp$quatern_b, qp$quatern_c, qp$quatern_d), 4L)
  buf <- nifti_put_num(buf, 268L, c(qp$qoffset_x, qp$qoffset_y, qp$qoffset_z), 4L)
  buf <- nifti_put_num(buf, 280L, sform[1L, ], 4L)                    # srow_x
  buf <- nifti_put_num(buf, 296L, sform[2L, ], 4L)                    # srow_y
  buf <- nifti_put_num(buf, 312L, sform[3L, ], 4L)                    # srow_z
  buf <- nifti_put_chr(buf, 344L, "n+1", 3L)                          # magic "n+1\0"
  # bytes 348..351 = extender (all zero)

  con <- if (grepl("\\.gz$", out_path, ignore.case = TRUE)) {
    gzfile(out_path, "wb")
  } else {
    file(out_path, "wb")
  }
  on.exit(close(con), add = TRUE)
  writeBin(buf, con)
  writeBin(as.double(arr), con, size = 4L, endian = "little")
  invisible(out_path)
}

# Internal: RNifti-backed writer
nifti_write_rnifti <- function(arr, sform, qp, out_path) {
  nii <- RNifti::asNifti(
    array(as.double(arr), dim = dim(arr)),
    internal = FALSE
  )
  RNifti::pixdim(nii) <- c(qp$dx, qp$dy, qp$dz)
  RNifti::sform(nii) <- structure(sform, code = 1L)
  RNifti::qform(nii) <- structure(nifti_qform_matrix(qp), code = 1L)
  RNifti::writeNifti(nii, out_path, datatype = "float")
  invisible(out_path)
}

# Internal: coerce supported inputs to a dicom_volume
nifti_as_volume <- function(x) {
  if (is_dicom_volume(x)) {
    return(x)
  }
  if (inherits(x, "dicom_series")) {
    vox <- array(as.double(x$volume), dim = dim(x$volume))
    mod <- attr(x$volume, "modality")
    return(new_dicom_volume(
      voxels = vox,
      affine = x$affine,
      coord_system = "LPS",
      frame_meta = x$metadata,
      modality = if (is.null(mod)) NA_character_ else as.character(mod)
    ))
  }
  if (is.character(x) && length(x) >= 1L && !anyNA(x)) {
    return(read_dicom_volume(x, warn = FALSE))
  }
  cli::cli_abort(
    "{.arg x} must be a {.cls dicom_volume}, a {.cls dicom_series}, or a DICOM file/directory path."
  )
}

# Internal: slice-step shear angle (degrees) relative to the slice normal
nifti_shear_deg <- function(vol_ras) {
  col3 <- vol_ras$affine[1:3, 3L]
  len <- sqrt(sum(col3^2))
  if (len < 1e-12) return(0)
  nrm <- vol_ras$direction$normal
  cs <- min(1, abs(sum(col3 * nrm)) / len)
  acos(cs) * 180 / pi
}

# Internal: BIDS-style JSON sidecar
nifti_write_sidecar <- function(vol, out_path) {
  vol_lps <- to_lps(vol)
  stem <- sub("\\.nii(\\.gz)?$", "", out_path, ignore.case = TRUE)
  ver <- tryCatch(as.character(utils::packageVersion("dicomtk")), error = function(e) "0.2.0")
  side <- list(
    ConversionSoftware = "dicomtk",
    ConversionSoftwareVersion = ver,
    SliceThickness = as.double(vol$spacing[3L]),
    ImageOrientationPatientDICOM = as.double(c(vol_lps$direction$d_row, vol_lps$direction$d_col)),
    PixelSpacing = as.double(vol$spacing[1:2])
  )
  if (!is.na(vol$modality) && nzchar(vol$modality)) side$Modality <- vol$modality
  if (!is.na(vol$units) && nzchar(vol$units)) side$Units <- vol$units
  jsonlite::write_json(side, paste0(stem, ".json"), auto_unbox = TRUE, digits = NA, pretty = TRUE)
  invisible(paste0(stem, ".json"))
}

#' Write a DICOM Volume to NIfTI-1 With dcm2niix-Compatible Geometry
#'
#' Exports a [`dicom_volume`][new_dicom_volume], `"dicom_series"`, or DICOM
#' path to a NIfTI-1 file (`.nii` or `.nii.gz`) whose voxel layout and
#' world-space orientation match `dcm2niix`: voxel `(i, j, k)` is
#' `(column, flipped row, slice)` and both an exact RAS `sform` (preserving any
#' gantry-tilt shear) and an orthogonalized quaternion `qform` (via the NIfTI-1
#' `nifti_mat44_to_quatern` algorithm) are written with codes `1`.
#'
#' @param x A [`dicom_volume`][new_dicom_volume], a `"dicom_series"` object, or
#'   a path to a DICOM file, directory, or vector of files.
#' @param out_path Output `.nii` / `.nii.gz` path. Defaults to a temporary
#'   `.nii` file.
#' @param json_sidecar Logical. When `TRUE` (default) writes a BIDS-style
#'   `<stem>.json` sidecar (`Modality`, `ImageOrientationPatientDICOM`,
#'   `SliceThickness`, `PixelSpacing`, `ConversionSoftware`, ...) next to the
#'   image.
#' @param backend Writer backend: `"auto"` (default; `RNifti` when installed,
#'   otherwise the built-in dependency-free writer), `"rnifti"`, or
#'   `"builtin"`.
#'
#' @return Invisibly returns `out_path`.
#' @export
#' @examples
#' out_dir <- tempfile("nifti_demo_")
#' dicom_synthesize(out_dir = out_dir, modality = "CT", dims = c(16L, 16L, 4L))
#' vol <- read_dicom_volume(out_dir)
#' nii <- write_nifti(vol, tempfile(fileext = ".nii"), backend = "builtin")
#' file.exists(nii)
#' unlink(out_dir, recursive = TRUE)
write_nifti <- function(x,
                        out_path = NULL,
                        json_sidecar = TRUE,
                        backend = c("auto", "rnifti", "builtin")) {
  backend <- match.arg(backend)
  vol <- nifti_as_volume(x)

  if (!is.logical(json_sidecar) || length(json_sidecar) != 1L || is.na(json_sidecar)) {
    cli::cli_abort("{.arg json_sidecar} must be {.val TRUE} or {.val FALSE}.")
  }
  if (is.null(out_path)) out_path <- tempfile(fileext = ".nii")
  if (!is.character(out_path) || length(out_path) != 1L || is.na(out_path) || !nzchar(out_path)) {
    cli::cli_abort("{.arg out_path} must be a single non-empty file path.")
  }

  if (identical(backend, "auto")) {
    backend <- if (requireNamespace("RNifti", quietly = TRUE)) "rnifti" else "builtin"
  } else if (identical(backend, "rnifti") && !requireNamespace("RNifti", quietly = TRUE)) {
    cli::cli_abort("Backend {.val rnifti} requires the {.pkg RNifti} package.")
  }

  vol_ras <- to_ras(vol)
  rows <- dim(vol_ras$voxels)[1L]
  sform <- nifti_sform_from_ras_affine(vol_ras$affine, rows)
  qp <- mat44_to_nifti_quatern(sform)

  shear <- nifti_shear_deg(vol_ras)
  if (shear > 0.05) {
    cli::cli_warn(c(
      "Gantry/detector tilt of {round(shear, 2)} deg detected.",
      "i" = "The quaternion {.field qform} orthogonalizes this shear; the {.field sform} preserves the exact sheared geometry."
    ))
  }

  arr <- nifti_permute_voxels(vol_ras$voxels)
  if (identical(backend, "rnifti")) {
    nifti_write_rnifti(arr, sform, qp, out_path)
  } else {
    nifti_write_builtin(arr, sform, qp, out_path)
  }

  if (isTRUE(json_sidecar)) nifti_write_sidecar(vol, out_path)
  invisible(out_path)
}
