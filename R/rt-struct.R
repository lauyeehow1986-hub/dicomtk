#' Convert RTSTRUCT Contours to a 3D Segmentation Mask (`dicom_seg`)
#'
#' Maps planar polygonal contours in LPS world coordinates (from an `RTSTRUCT`
#' DICOM object) into the in-plane voxel pixel grid of `ref_volume` and rasterizes
#' each slice into a 3D [dicom_seg] mask.
#'
#' @param rt An object of class `dicom_rt` with modality `"RTSTRUCT"`, or a path to an `RTSTRUCT` DICOM file.
#' @param ref_volume A reference [dicom_volume] object providing geometry and spatial affine.
#' @param roi_numbers Optional integer vector of specific ROI numbers to rasterize. If `NULL`, all ROIs are rasterized.
#'
#' @return A [dicom_seg] object spatially registered with `ref_volume`.
#' @export
#' @examples
#' synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 5L))
#' vol <- read_dicom_volume(synth[["out_dir"]])
#' # See vignette for full RTSTRUCT workflow
rtstruct_to_seg <- function(rt, ref_volume, roi_numbers = NULL) {
  if (is.character(rt) && length(rt) == 1L && file.exists(rt)) {
    rt <- read_dicom_rt(rt)
  }
  if (!inherits(ref_volume, "dicom_volume")) {
    rlang::abort("`ref_volume` must be a `dicom_volume` object.")
  }

  dims <- dim(ref_volume)
  h <- dims[1L]
  w <- dims[2L]
  n_slices <- dims[3L]

  # Parse ROIs and contours
  rois <- rt$rois %||% tibble::tibble(roi_number = 1L, roi_name = "ROI_1")
  contours <- rt$contours %||% tibble::tibble()

  mask_arr <- array(0L, dim = c(h, w, n_slices))

  if (nrow(contours) > 0L) {
    if (!is.null(roi_numbers)) {
      contours <- contours[contours$roi_number %in% roi_numbers, , drop = FALSE]
    }

    for (i in seq_len(nrow(contours))) {
      cdata <- contours$contour_data[[i]]
      if (length(cdata) < 9L) next # Need at least 3 points (9 numbers)

      # Reshape into Nx3 matrix of [x, y, z] points in LPS mm
      pts_lps <- matrix(cdata, ncol = 3L, byrow = TRUE)

      # Use world_to_voxel(..., index_base = 1L) to convert LPS world mm to 1-based voxel indices (r, c, s)
      vox_pts <- world_to_voxel(ref_volume, pts_lps, index_base = 1L)

      # Find slice index s
      mean_s <- mean(vox_pts[, 3L])
      slice_idx <- as.integer(round(mean_s))

      if (slice_idx >= 1L && slice_idx <= n_slices) {
        # Extract 2D polygon in pixel coordinates (row, col)
        poly_2d <- vox_pts[, 1:2, drop = FALSE]

        slice_mask <- rasterize_polygon_2d(poly_2d, width = w, height = h)
        r_num <- as.integer(contours$roi_number[i] %||% 1L)
        if (is.na(r_num) || r_num <= 0L) r_num <- 1L
        cur_slice <- mask_arr[, , slice_idx]
        cur_slice[slice_mask] <- r_num
        mask_arr[, , slice_idx] <- cur_slice
      }
    }
  }

  # Build segment metadata from ROIs
  seg_meta <- tibble::tibble(
    segment_id = rois$roi_number,
    label = rois$roi_name,
    category = "Anatomy",
    type = "binary"
  )

  dicom_seg(mask = mask_arr, ref_volume = ref_volume, segments = seg_meta)
}

#' Convert a 3D Segmentation Mask (`dicom_seg`) to `RTSTRUCT` Contours
#'
#' Traces closed 2D planar polygon contours slice-by-slice from a [dicom_seg]
#' mask and transforms pixel indices to LPS world coordinates using `ref_volume$affine`,
#' producing an `RTSTRUCT` object (see [read_dicom_rt()]).
#'
#' @param seg A [dicom_seg] object.
#' @param ref_volume Reference [dicom_volume] providing spatial geometry.
#' @param roi_name Name for the exported ROI (defaults to segment label).
#' @param roi_color Color string (e.g. `"255\\0\\0"`).
#'
#' @return A `dicom_rt` object of modality `"RTSTRUCT"`.
#' @export
#' @examples
#' synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 5L))
#' vol <- read_dicom_volume(synth[["out_dir"]])
#' m <- array(0L, dim = c(32L, 32L, 5L))
#' m[5:15, 5:15, 2:3] <- 1L
#' seg <- dicom_seg(m, vol)
#' rt <- seg_to_rtstruct(seg, vol)
#' rt$modality
seg_to_rtstruct <- function(seg, ref_volume, roi_name = NULL, roi_color = "255\\0\\0") {
  if (!inherits(seg, "dicom_seg") && !inherits(seg, "dicom_volume")) {
    rlang::abort("`seg` must be a `dicom_seg` or `dicom_volume` object.")
  }
  if (!inherits(ref_volume, "dicom_volume")) {
    rlang::abort("`ref_volume` must be a `dicom_volume` object.")
  }

  dims <- dim(seg)
  h <- dims[1L]
  w <- dims[2L]
  n_slices <- dims[3L]

  mask_data <- seg$voxels %||% seg$array

  seg_tbl <- seg$segments
  if (is.null(seg_tbl) || nrow(seg_tbl) == 0L) {
    seg_tbl <- tibble::tibble(
      segment_id = 1L,
      label = roi_name %||% "ROI_1"
    )
  } else if (!is.null(roi_name) && length(roi_name) == nrow(seg_tbl)) {
    seg_tbl$label <- as.character(roi_name)
  }

  contour_rows <- list()

  for (r_idx in seq_len(nrow(seg_tbl))) {
    s_id <- as.integer(seg_tbl$segment_id[r_idx])
    for (k in seq_len(n_slices)) {
      slice_mat <- if (nrow(seg_tbl) == 1L && s_id == 1L) {
        as.matrix(mask_data[, , k] > 0)
      } else {
        as.matrix(mask_data[, , k] == s_id)
      }
      if (!any(slice_mat)) next

      # Trace 2D contours on this slice
      polys <- trace_contours_2d(slice_mat)

      for (poly in polys) {
        if (nrow(poly) < 3L) next

        # Convert 2D pixel coordinates (row, col) with slice k into 1-based voxel indices (r, c, s)
        n_pts <- nrow(poly)
        rcs_mat <- cbind(
          poly[, 1L],
          poly[, 2L],
          rep(as.double(k), n_pts)
        )

        # Convert to world coordinates via voxel_to_world
        lps_pts <- voxel_to_world(ref_volume, rcs_mat, index_base = 1L)

        # Flatten into x1, y1, z1, x2, y2, z2, ...
        xyz_flat <- as.numeric(t(lps_pts))

        contour_rows[[length(contour_rows) + 1L]] <- list(
          roi_number = s_id,
          geometric_type = "CLOSED_PLANAR",
          n_points = n_pts,
          contour_data = xyz_flat
        )
      }
    }
  }

  contours_tbl <- if (length(contour_rows) > 0L) {
    tibble::tibble(
      roi_number = vapply(contour_rows, `[[`, integer(1L), "roi_number"),
      geometric_type = vapply(contour_rows, `[[`, character(1L), "geometric_type"),
      n_points = vapply(contour_rows, `[[`, integer(1L), "n_points"),
      contour_data = lapply(contour_rows, `[[`, "contour_data")
    )
  } else {
    tibble::tibble(
      roi_number = integer(),
      geometric_type = character(),
      n_points = integer(),
      contour_data = list()
    )
  }

  rois_tbl <- tibble::tibble(
    roi_number = as.integer(seg_tbl$segment_id),
    roi_name = as.character(seg_tbl$label),
    roi_color = rep(roi_color, length.out = nrow(seg_tbl))
  )

  structure(
    list(
      modality = "RTSTRUCT",
      rois = rois_tbl,
      contours = contours_tbl,
      ref_volume_uid = ref_volume$uids$series_instance_uid %||%
                       ref_volume$header$SeriesInstanceUID[[1L]] %||%
                       "1.2.826.0.1.3680043.9.1"
    ),
    class = "dicom_rt"
  )
}
