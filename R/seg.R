#' DICOM Segmentation S3 Class
#'
#' Constructs a `dicom_seg` spatial segmentation object inheriting from
#' [dicom_volume].
#'
#' @param mask A 3D integer array (`[rows, cols, slices]`) or 4D array (`[rows, cols, slices, segments]`).
#' @param ref_volume Reference [dicom_volume] object providing geometry, spatial
#'   affine matrix, and slice spacing.
#' @param segments A data frame or tibble with segment metadata containing at
#'   minimum `segment_id` and `label`.
#'
#' @return A `dicom_seg` object inheriting from `dicom_volume`.
#' @export
#' @examples
#' synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 4L))
#' vol <- read_dicom_volume(synth$files[1L])
#' m <- array(0L, dim = c(32L, 32L, 4L))
#' m[10:20, 10:20, 2:3] <- 1L
#' seg_meta <- tibble::tibble(segment_id = 1L, label = "Liver")
#' seg <- dicom_seg(m, vol, seg_meta)
#' print(seg)
dicom_seg <- function(mask, ref_volume, segments = NULL) {
  if (!inherits(ref_volume, "dicom_volume")) {
    rlang::abort("`ref_volume` must be a `dicom_volume` object.")
  }
  if (!is.array(mask) || length(dim(mask)) < 3L) {
    rlang::abort("`mask` must be an array with at least 3 dimensions.")
  }

  if (is.null(segments)) {
    segments <- tibble::tibble(
      segment_id = 1L,
      label = "Segment_1",
      category = "Anatomy",
      type = "binary",
      algorithm_type = "MANUAL",
      anatomic_region = "Unknown",
      property_category = "Tissue"
    )
  }

  # Construct using new_dicom_volume and subclass as dicom_seg
  vol <- new_dicom_volume(
    voxels = mask,
    affine = ref_volume$affine,
    coord_system = ref_volume$coord_system %||% "LPS",
    spacing = ref_volume$spacing,
    direction = ref_volume$direction,
    frame_meta = ref_volume$frame_meta,
    uids = ref_volume$uids,
    modality = "SEG",
    units = "binary"
  )

  vol$array <- mask
  vol$mask <- mask
  vol$segments <- tibble::as_tibble(segments)
  vol$source_volume_uid <- ref_volume$uids$series_instance_uid %||%
                           ref_volume$header$SeriesInstanceUID[[1L]] %||%
                           "1.2.826.0.1.3680043.9.1"

  class(vol) <- c("dicom_seg", class(vol))
  vol
}

#' Convert a Multi-Segment `dicom_seg` to a 3D Integer Label-Map
#'
#' Flattens a 4D multi-segment [dicom_seg] (`[rows, cols, slices, segments]`) or
#' 3D binary/labelmap [dicom_seg] into a single 3D integer label-map volume where
#' each voxel holds the integer `segment_id` (`0L` for background). When segments
#' overlap, higher `segment_id` values take precedence by default (`conflict = "last"`),
#' or lower `segment_id` values when `conflict = "first"`.
#'
#' @param seg A [dicom_seg] object.
#' @param conflict Conflict resolution policy for overlapping segments:
#'   `"last"` (default) or `"first"`.
#'
#' @return A 3D integer [dicom_seg] object with `type = "labelmap"`.
#' @export
#' @examples
#' synth <- dicom_synthesize(modality = "CT", dims = c(16L, 16L, 4L))
#' vol <- read_dicom_volume(synth[["out_dir"]])
#' m4 <- array(0L, dim = c(16L, 16L, 4L, 2L))
#' m4[3:7, 3:7, 2L, 1L] <- 1L
#' m4[10:14, 10:14, 2L, 2L] <- 1L
#' seg4 <- dicom_seg(m4, vol, tibble::tibble(segment_id = 1:2, label = c("Left", "Right")))
#' lmap <- as_labelmap(seg4)
#' dim(lmap)
as_labelmap <- function(seg, conflict = c("last", "first")) {
  if (!inherits(seg, "dicom_seg")) {
    rlang::abort("`seg` must be a `dicom_seg` object.")
  }
  conflict <- match.arg(conflict)
  vox <- seg$voxels %||% seg$array
  d <- dim(vox)

  if (length(d) == 3L) {
    out_arr <- array(as.integer(vox), dim = d)
  } else if (length(d) == 4L) {
    out_arr <- array(0L, dim = d[1:3])
    n_seg <- d[4L]
    seg_ids <- if (!is.null(seg$segments) && nrow(seg$segments) == n_seg) {
      as.integer(seg$segments$segment_id)
    } else {
      seq_len(n_seg)
    }
    idx_order <- if (identical(conflict, "last")) seq_len(n_seg) else rev(seq_len(n_seg))
    for (k in idx_order) {
      layer <- vox[, , , k] > 0
      out_arr[layer] <- seg_ids[k]
    }
  } else {
    rlang::abort("`seg` array must have 3 or 4 dimensions.")
  }

  seg_meta <- seg$segments
  if (!is.null(seg_meta) && nrow(seg_meta) > 0L) {
    seg_meta$type <- "labelmap"
  }
  dicom_seg(mask = out_arr, ref_volume = seg, segments = seg_meta)
}

#' Write DICOM Segmentation Object (`dcmseg`)
#'
#' Writes a [dicom_seg] object to a standard DICOM Segmentation file (PS3.3 C.8.20).
#'
#' @param seg A [dicom_seg] object.
#' @param file Path to the output DICOM file.
#'
#' @return Character path to the written DICOM file (invisibly).
#' @export
#' @examples
#' synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 4L))
#' vol <- read_dicom_volume(synth$files[1L])
#' m <- array(0L, dim = c(32L, 32L, 4L))
#' m[5:15, 5:15, 2L] <- 1L
#' seg <- dicom_seg(m, vol)
#' tmp_f <- file.path(tempdir(), "test_write_seg.dcm")
#' on.exit(unlink(tmp_f))
#' write_dicom_seg(seg, tmp_f)
write_dicom_seg <- function(seg, file) {
  if (!inherits(seg, "dicom_seg")) {
    rlang::abort("`seg` must be a `dicom_seg` object.")
  }

  dims <- dim(seg$array)
  h <- dims[1L]
  w <- dims[2L]
  n_slices <- dims[3L]

  # Write multi-frame segmentation pixel data
  # For binary SEG: each slice is packed to 1-bit binary frame
  raw_frames <- vector("list", n_slices)
  for (k in seq_len(n_slices)) {
    slice_mat <- as.matrix(seg$array[, , k])
    raw_frames[[k]] <- cpp_pack_binary_frame(slice_mat)
  }

  all_pixel_bytes <- unlist(raw_frames)

  # Synthesize a base DICOM file to receive the pixel and SEG tags
  temp_base <- tempfile(fileext = ".dcm")
  on.exit(unlink(temp_base), add = TRUE)

  # Generate template DICOM using MR/CT base then re-tagging as SEG
  synth_res <- dicom_synthesize(
    modality = "MR",
    dims = c(w, h, 1L),
    out_dir = dirname(temp_base),
    extra_tags = list(
      Modality = "SEG",
      SOPClassUID = "1.2.840.10008.5.1.4.1.1.66.4", # Segmentation Storage
      BitsAllocated = 1L,
      BitsStored = 1L,
      HighBit = 0L,
      PixelRepresentation = 0L,
      SamplesPerPixel = 1L,
      NumberOfFrames = as.character(n_slices),
      Rows = as.integer(h),
      Columns = as.integer(w),
      SegmentationType = "BINARY",
      ContentLabel = seg$segments$label[1L] %||% "DICOMTK_SEG"
    )
  )

  # Move synthesized file to target
  synth_file <- synth_res$files[1L]
  if (!file.exists(synth_file)) {
    # Direct fallback: write standard binary payload
    synth_file <- seg$files[1L]
  }

  # Overwrite pixel data tag (7FE0,0010) and SEG header elements using cpp_write_dicom_raw_pixels
  cpp_write_dicom_raw_pixels(
    in_dcm_path = normalizePath(synth_file, mustWork = TRUE),
    out_dcm_path = normalizePath(file, mustWork = FALSE),
    raw_pixel_bytes = all_pixel_bytes,
    bits_allocated = 1L,
    bits_stored = 1L,
    high_bit = 0L,
    pixel_representation = 0L,
    samples_per_pixel = 1L,
    number_of_frames = n_slices
  )

  invisible(file)
}
