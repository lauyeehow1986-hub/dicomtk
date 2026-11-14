# Internal helper: Bresenham line rasterizer on a 2D numeric matrix
burn_line_2d <- function(mat, r0, c0, r1, c1, val) {
  nr <- nrow(mat)
  nc <- ncol(mat)
  r0 <- as.integer(round(r0))
  c0 <- as.integer(round(c0))
  r1 <- as.integer(round(r1))
  c1 <- as.integer(round(c1))

  dr <- abs(r1 - r0)
  dc <- abs(c1 - c0)
  sr <- if (r0 < r1) 1L else -1L
  sc <- if (c0 < c1) 1L else -1L
  err <- dr - dc

  repeat {
    if (r0 >= 1L && r0 <= nr && c0 >= 1L && c0 <= nc) {
      mat[r0, c0] <- val
    }
    if (r0 == r1 && c0 == c1) break
    e2 <- 2L * err
    if (e2 > -dc) {
      err <- err - dc
      r0 <- r0 + sr
    }
    if (e2 < dr) {
      err <- err + dr
      c0 <- c0 + sc
    }
  }
  mat
}

# Internal helper: rasterize a 2D circle perimeter given center (r0, c0) and edge point (r1, c1)
burn_circle_2d <- function(mat, r0, c0, r1, c1, val) {
  rad <- sqrt((r1 - r0)^2 + (c1 - c0)^2)
  if (rad < 0.5) {
    rr <- as.integer(round(r0))
    cc <- as.integer(round(c0))
    if (rr >= 1L && rr <= nrow(mat) && cc >= 1L && cc <= ncol(mat)) {
      mat[rr, cc] <- val
    }
    return(mat)
  }
  n_seg <- max(24L, as.integer(ceiling(2 * pi * rad)))
  theta <- seq(0, 2 * pi, length.out = n_seg + 1L)
  rs <- r0 + rad * sin(theta)
  cs <- c0 + rad * cos(theta)
  for (k in seq_len(n_seg)) {
    mat <- burn_line_2d(mat, rs[k], cs[k], rs[k + 1L], cs[k + 1L], val)
  }
  mat
}

# Internal helper: burn a single annotation row onto a 2D slice matrix
burn_annotation_row <- function(mat, g_type, coords, val) {
  if (length(coords) < 2L) return(mat)
  g_type <- toupper(as.character(g_type)[1L])

  if (g_type == "POINT") {
    rr <- as.integer(round(coords[1L]))
    cc <- as.integer(round(coords[2L]))
    for (dr in -1:1) {
      for (dc in -1:1) {
        r_i <- rr + dr
        c_i <- cc + dc
        if (r_i >= 1L && r_i <= nrow(mat) && c_i >= 1L && c_i <= ncol(mat)) {
          mat[r_i, c_i] <- val
        }
      }
    }
    return(mat)
  }

  if (g_type == "CIRCLE" && length(coords) >= 4L) {
    return(burn_circle_2d(mat, coords[1L], coords[2L], coords[3L], coords[4L], val))
  }

  # POLYLINE / INTERPOLATED / ELLIPSE fallback: connect consecutive (r, c) pairs
  n_pts <- length(coords) %/% 2L
  if (n_pts >= 2L) {
    for (i in seq_len(n_pts - 1L)) {
      r0 <- coords[2L * i - 1L]
      c0 <- coords[2L * i]
      r1 <- coords[2L * i + 1L]
      c1 <- coords[2L * i + 2L]
      mat <- burn_line_2d(mat, r0, c0, r1, c1, val)
    }
  }
  mat
}

#' Export Derived Burned-In Annotation Secondary Capture DICOMs
#'
#' Renders graphic annotations (polylines, circles, points, or GSPS objects)
#' directly into a **new derived Secondary Capture series**
#' (`SOPClassUID = 1.2.840.10008.5.1.4.1.1.7`, `ImageType = "DERIVED\\SECONDARY"`,
#' `BurnedInAnnotation = "YES"`) for teaching files and presentations.
#' Source DICOM files are never modified, and writing into the source directory
#' is strictly prohibited.
#'
#' @param volume A [dicom_volume] object.
#' @param annotations A `data.frame` / [tibble::tibble] (same schema as
#'   [write_dicom_gsps()]) with columns `slice`, `graphic_type`, `coords`, and
#'   optional `text`, or a `dicom_gsps` object.
#' @param out_dir Output directory path where derived `.dcm` files will be written.
#'   Must not match any directory containing source files of `volume`.
#' @param slices Optional integer vector of 1-based slice indices to export.
#'   Defaults to all slices referenced in `annotations` (or all slices if none).
#' @param burn_value Optional numeric intensity for burned-in overlays. Defaults
#'   to the slice maximum plus a bright margin (clamped to unsigned 16-bit range).
#'
#' @return An S3 object of class `"dicom_burned_export"` containing `files`,
#'   `out_dir`, `series_uid`, `slices`, and `n_annotations`.
#' @export
#' @examples
#' synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 3L))
#' vol <- read_dicom_volume(synth[["out_dir"]])
#' ann <- tibble::tibble(
#'   slice = 2L,
#'   graphic_type = "POLYLINE",
#'   coords = list(c(8, 8, 22, 8, 22, 22, 8, 22, 8, 8)),
#'   text = "Lesion"
#' )
#' out_dir <- file.path(tempdir(), "burned_ex")
#' res <- dicom_burn_annotations(vol, ann, out_dir)
#' unlink(out_dir, recursive = TRUE)
dicom_burn_annotations <- function(volume,
                                   annotations,
                                   out_dir,
                                   slices = NULL,
                                   burn_value = NULL) {
  if (!inherits(volume, "dicom_volume")) {
    rlang::abort("`volume` must be a `dicom_volume` object.")
  }
  if (!is.character(out_dir) || length(out_dir) != 1L || !nzchar(out_dir)) {
    rlang::abort("`out_dir` must be a single non-empty directory path.")
  }

  # Guard-rail: refuse to write into the source directory
  norm_out <- normalizePath(out_dir, winslash = "/", mustWork = FALSE)
  if (!is.null(volume$frame_meta) && "file" %in% names(volume$frame_meta) && nrow(volume$frame_meta) > 0L) {
    src_dirs <- unique(normalizePath(dirname(volume$frame_meta$file), winslash = "/", mustWork = FALSE))
    if (norm_out %in% src_dirs) {
      rlang::abort("Refusing to write derived burned-in annotations into the source DICOM directory.")
    }
  }

  if (inherits(annotations, "dicom_gsps")) {
    ann_df <- annotations$graphics
    ann_df$slice <- 1L
  } else if (inherits(annotations, "data.frame")) {
    ann_df <- annotations
  } else {
    rlang::abort("`annotations` must be a data.frame, tibble, or `dicom_gsps` object.")
  }

  if (!dir.exists(out_dir)) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  }

  d <- dim(volume$voxels)
  n_slices <- d[3L]
  if (!("slice" %in% names(ann_df))) {
    ann_df$slice <- 1L
  }

  target_slices <- if (!is.null(slices)) {
    as.integer(slices)
  } else if (nrow(ann_df) > 0L) {
    sort(unique(as.integer(ann_df$slice)))
  } else {
    seq_len(n_slices)
  }
  target_slices <- target_slices[target_slices >= 1L & target_slices <= n_slices]
  if (length(target_slices) == 0L) {
    rlang::abort("No valid target slice indices to export.")
  }

  series_uid <- paste0("2.25.", format(Sys.time(), "%Y%m%d%H%M%S"), ".", sample.int(1e7, 1L))
  study_uid <- volume$uids$study_instance_uid %||% paste0("2.25.", sample.int(1e9, 1L))

  written_files <- character(length(target_slices))
  for (idx in seq_along(target_slices)) {
    s_k <- target_slices[idx]
    slice_mat <- matrix(as.double(volume$voxels[, , s_k]), nrow = d[1L], ncol = d[2L])

    # Shift negative HU values if any so Secondary Capture 16-bit display is clean, or burn bright value
    val_burn <- if (!is.null(burn_value) && is.finite(burn_value)) {
      as.double(burn_value)[1L]
    } else {
      rng_max <- max(slice_mat, na.rm = TRUE)
      min(65535.0, max(rng_max + 500.0, 2000.0))
    }

    ann_k <- ann_df[as.integer(ann_df$slice) == s_k, , drop = FALSE]
    if (nrow(ann_k) > 0L) {
      for (r_i in seq_len(nrow(ann_k))) {
        g_t <- if ("graphic_type" %in% names(ann_k)) ann_k$graphic_type[r_i] else "POLYLINE"
        pts <- as.double(ann_k$coords[[r_i]])
        slice_mat <- burn_annotation_row(slice_mat, g_t, pts, val_burn)
      }
    }

    out_file <- file.path(out_dir, sprintf("derived_slice_%04d.dcm", s_k))
    meta_tags <- c(
      "SOPClassUID",
      "Modality",
      "ImageType",
      "BurnedInAnnotation",
      "DerivationDescription",
      "StudyInstanceUID",
      "SeriesInstanceUID",
      "InstanceNumber",
      "SeriesDescription"
    )
    meta_vals <- c(
      "1.2.840.10008.5.1.4.1.1.7", # Secondary Capture Image Storage
      "OT",
      "DERIVED\\SECONDARY",
      "YES",
      "DICOMTK Derived Teaching Capture with Burned-In Annotations",
      as.character(study_uid)[1L],
      series_uid,
      as.character(idx),
      "Derived Burned-In Annotation Series"
    )

    ok <- cpp_write_dicom_matrix(
      pixels = slice_mat,
      out_path = normalizePath(out_file, mustWork = FALSE),
      meta_tags = meta_tags,
      meta_values = meta_vals
    )
    if (!isTRUE(ok)) {
      rlang::abort(paste0("Failed to write derived Secondary Capture DICOM: ", out_file))
    }
    written_files[idx] <- normalizePath(out_file, mustWork = TRUE)
  }

  structure(
    list(
      files = written_files,
      out_dir = normalizePath(out_dir, mustWork = TRUE),
      series_uid = series_uid,
      slices = target_slices,
      n_annotations = nrow(ann_df)
    ),
    class = "dicom_burned_export"
  )
}

#' @keywords internal
#' @export
print.dicom_burned_export <- function(x, ...) {
  cat("<dicom_burned_export [", length(x$files), " derived slice(s), ",
      x$n_annotations, " annotation(s)]>\n", sep = "")
  invisible(x)
}
