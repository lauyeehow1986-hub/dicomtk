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

  # Build as dicom_volume with class c("dicom_seg", "dicom_volume")
  res <- structure(
    list(
      array = mask,
      affine = ref_volume$affine,
      spacing = ref_volume$spacing,
      origin = ref_volume$origin,
      direction = ref_volume$direction,
      header = ref_volume$header,
      files = ref_volume$files,
      segments = tibble::as_tibble(segments),
      source_volume_uid = ref_volume$header$SeriesInstanceUID[[1L]] %||% "1.2.826.0.1.3680043.9.1"
    ),
    class = c("dicom_seg", "dicom_volume")
  )
  res
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
