#' 3D Coordinate-Aware Head CT/MR Defacing
#'
#' Removes recognizable facial features (nose, jaw, facial profile) from 3D
#' cranial CT and MR volumes using orientation-invariant physical RAS coordinates,
#' while guaranteeing that deep intracranial brain parenchyma remains completely
#' untouched.
#'
#' The defacing algorithm operates in physical RAS world coordinates derived via
#' \code{\link{to_ras}(vol)$affine}, ensuring that facial geometry is computed
#' consistently regardless of whether the volume was acquired axially, sagittally,
#' or coronally. The algorithm defines an anterior-inferior facial bevel half-space
#' bounded by the nasion and tragus planes, restricted to superficial tissue within
#' \code{surface_depth_mm} of the anterior air-skin boundary.
#'
#' @param x A \code{\link{dicom_volume}} object, or a character string / vector
#'   specifying a DICOM directory or slice file paths.
#' @param out_dir Optional directory path where defaced DICOM slice files will be written.
#'   If \code{NULL} (default), no files are written.
#' @param fill Method or numeric scalar to fill masked facial voxels:
#'   \code{"auto"} (-1000 HU for CT, 0 for MR), \code{"air"} (-1000), \code{"zero"} (0),
#'   or a numeric scalar value.
#' @param surface_depth_mm Numeric scalar. Maximum superficial depth (in millimeters)
#'   from the anterior air-skin surface to mask. Tissue deeper than this limit is
#'   guaranteed untouched. Default is 35 mm.
#' @param nasion_fraction Numeric scalar between 0 and 1. Fraction of the head's
#'   inferior-to-superior span defining the superior boundary of facial defacing (nasion plane).
#'   Default is 0.55.
#' @param tragus_fraction Numeric scalar between 0 and 1. Fraction of the head's
#'   anterior-to-posterior span defining the posterior boundary of the facial bevel (tragus plane).
#'   Default is 0.50.
#' @param ... Additional arguments passed to internal methods.
#'
#' @return A modified \code{\link{dicom_volume}} object with facial voxels replaced
#'   by the fill value, and a provenance record appended. When \code{out_dir} is provided,
#'   written DICOM slice files carry:
#'   \itemize{
#'     \item \code{RecognizableVisualFeatures (0028,0302) == "NO"}
#'     \item \code{ImageType (0008,0008)} starting with \code{"DERIVED\\SECONDARY"}
#'     \item Fresh \code{SOPInstanceUID (0008,0018)} and \code{MediaStorageSOPInstanceUID (0002,0003)}
#'     \item CID 7050 code \code{"113102"} (\emph{Clean Recognizable Visual Features Option})
#'           stamped in \code{DeidentificationMethodCodeSequence (0012,0064)}.
#'   }
#' @export
#' @examples
#' \dontrun{
#' vol <- read_dicom_volume("path/to/head_ct")
#' defaced <- dicom_deface(vol, out_dir = "path/to/defaced_ct")
#' }
dicom_deface <- function(x,
                         out_dir = NULL,
                         fill = c("auto", "air", "zero"),
                         surface_depth_mm = 35,
                         nasion_fraction = 0.55,
                         tragus_fraction = 0.50,
                         ...) {
  # 1. Resolve input to dicom_volume
  if (is.character(x)) {
    vol <- read_dicom_volume(x)
  } else if (is_dicom_volume(x)) {
    vol <- x
  } else {
    cli::cli_abort("{.arg x} must be a {.cls dicom_volume} or path to DICOM files.")
  }

  dims <- dim(vol$voxels)[1:3]
  nx <- dims[1L]
  ny <- dims[2L]
  nz <- dims[3L]
  nvox <- nx * ny * nz

  # 2. Resolve fill value
  fill_choice <- if (is.numeric(fill)) {
    as.double(fill[[1L]])
  } else {
    match.arg(fill, c("auto", "air", "zero"))
  }

  modality <- toupper(vol$modality %||% "CT")
  fill_val <- if (is.numeric(fill_choice)) {
    fill_choice
  } else if (fill_choice == "air") {
    -1000.0
  } else if (fill_choice == "zero") {
    0.0
  } else {
    # auto
    if (modality == "CT") -1000.0 else 0.0
  }

  # 3. Map voxel grid coordinates to physical RAS coordinates
  vol_ras <- to_ras(vol)
  aff_ras <- vol_ras$affine

  grid_i <- rep(seq_len(nx) - 1L, times = ny * nz)
  grid_j <- rep(rep(seq_len(ny) - 1L, each = nx), times = nz)
  grid_k <- rep(seq_len(nz) - 1L, each = nx * ny)

  X_R <- aff_ras[1L, 1L] * grid_i + aff_ras[1L, 2L] * grid_j + aff_ras[1L, 3L] * grid_k + aff_ras[1L, 4L]
  Y_A <- aff_ras[2L, 1L] * grid_i + aff_ras[2L, 2L] * grid_j + aff_ras[2L, 3L] * grid_k + aff_ras[2L, 4L]
  Z_S <- aff_ras[3L, 1L] * grid_i + aff_ras[3L, 2L] * grid_j + aff_ras[3L, 3L] * grid_k + aff_ras[3L, 4L]

  # 4. Foreground segmentation
  vox_flat <- as.double(vol$voxels[seq_len(nvox)])
  if (modality == "CT") {
    fg_mask <- vox_flat > -500.0
  } else {
    pos_vox <- vox_flat[vox_flat > 0.0]
    if (length(pos_vox) > 0L) {
      thresh <- stats::quantile(pos_vox, 0.15)
      fg_mask <- vox_flat >= thresh & vox_flat > 0.0
    } else {
      thresh <- stats::quantile(vox_flat, 0.15)
      fg_mask <- vox_flat > thresh
    }
  }

  deface_mask <- rep(FALSE, nvox)

  if (any(fg_mask)) {
    fg_idx <- which(fg_mask)
    y_fg <- Y_A[fg_idx]
    z_fg <- Z_S[fg_idx]

    y_min <- min(y_fg)
    y_max <- max(y_fg)
    z_min <- min(z_fg)
    z_max <- max(z_fg)

    y_span <- y_max - y_min
    z_span <- z_max - z_min

    z_nasion <- z_min + nasion_fraction * z_span
    y_tragus <- y_min + tragus_fraction * y_span
    y_nasion <- y_min + 0.65 * y_span

    # Facial bevel plane: separates face from skull base / cranium
    y_bevel <- y_tragus + (y_nasion - y_tragus) * (Z_S - z_min) / max(1e-6, (z_nasion - z_min))
    in_bevel <- (Z_S <= z_nasion) & (Y_A >= y_bevel)

    # 5. Superficial depth restriction from anterior air-skin boundary
    bin_size <- max(1.0, min(vol$spacing[1:2]))
    x_bin <- round(X_R / bin_size)
    z_bin <- round(Z_S / bin_size)

    fg_face_idx <- fg_idx[Y_A[fg_idx] >= y_tragus & Z_S[fg_idx] <= z_nasion]
    if (length(fg_face_idx) == 0L) {
      fg_face_idx <- fg_idx
    }

    fg_keys <- paste0(x_bin[fg_face_idx], ":", z_bin[fg_face_idx])
    surf_max <- tapply(Y_A[fg_face_idx], fg_keys, max)

    vox_keys <- paste0(x_bin, ":", z_bin)
    surf_y <- surf_max[vox_keys]
    surf_y[is.na(surf_y)] <- -Inf

    in_surface_depth <- (Y_A >= (surf_y - surface_depth_mm))

    deface_mask <- fg_mask & in_bevel & in_surface_depth
  }

  # 6. Apply defacing mask
  vol_out <- vol
  if (length(dim(vol_out$voxels)) == 3L) {
    vol_out$voxels[deface_mask] <- fill_val
  } else if (length(dim(vol_out$voxels)) == 4L) {
    for (f in seq_len(dim(vol_out$voxels)[4L])) {
      f_slice <- vol_out$voxels[, , , f]
      f_slice[deface_mask] <- fill_val
      vol_out$voxels[, , , f] <- f_slice
    }
  }

  # 7. Append provenance record
  vol_out <- append_provenance(
    vol_out,
    action = "dicom_deface",
    params = list(
      fill = fill_val,
      surface_depth_mm = surface_depth_mm,
      masked_voxels = sum(deface_mask),
      total_voxels = nvox
    )
  )

  # 8. Write DICOM slice files if out_dir is provided
  if (!is.null(out_dir)) {
    if (length(dim(vol$voxels)) > 3L) {
      cli::cli_abort("Exporting 4D volumes with {.arg out_dir} is not supported.")
    }
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

    nslices <- dims[3L]
    new_series_uid <- synth_next_uid(sub_id = 113102L)

    cid_sq <- list(
      "(0012,0064)" = list(
        list(
          CodeValue = "113102",
          CodingSchemeDesignator = "DCM",
          CodeMeaning = "Clean Recognizable Visual Features Option"
        )
      )
    )

    for (s in seq_len(nslices)) {
      slice_pixels <- vol_out$voxels[, , s]
      new_sop_uid <- synth_next_uid(sub_id = s)

      has_source <- !is.null(vol$frame_meta) &&
                    "file" %in% names(vol$frame_meta) &&
                    s <= nrow(vol$frame_meta) &&
                    file.exists(vol$frame_meta$file[s])

      out_fname <- if (has_source) basename(vol$frame_meta$file[s]) else sprintf("slice_%04d.dcm", s)
      out_path <- file.path(out_dir, out_fname)

      if (has_source) {
        in_file <- vol$frame_meta$file[s]
        hdr_raw <- read_dicom(in_file, include_sequences = FALSE)

        skip_tags <- c(
          "(0008,0018)", "(0002,0003)", "(0020,000E)", "(0028,0302)",
          "(0008,0008)", "(0012,0062)", "(0012,0063)", "(0012,0064)",
          "(7FE0,0010)"
        )
        sub_hdr <- subset(hdr_raw, !tag %in% skip_tags & depth == 0L)
        sub_vals <- sub_hdr$value
        sub_vals[is.na(sub_vals)] <- ""

        orig_img_type <- subset(hdr_raw, tag == "(0008,0008)")$value
        new_img_type <- "DERIVED\\SECONDARY"
        if (length(orig_img_type) > 0L && !is.na(orig_img_type[1L]) && nzchar(orig_img_type[1L])) {
          parts <- strsplit(orig_img_type[1L], "\\\\")[[1L]]
          if (length(parts) > 2L) {
            new_img_type <- paste(c("DERIVED", "SECONDARY", parts[3:length(parts)]), collapse = "\\")
          }
        }

        meta_tags <- c(
          sub_hdr$tag,
          "(0008,0018)", "(0002,0003)", "(0020,000E)",
          "(0028,0302)", "(0008,0008)", "(0012,0062)", "(0012,0063)"
        )
        meta_vals <- c(
          sub_vals,
          new_sop_uid, new_sop_uid, new_series_uid,
          "NO", new_img_type, "YES", "DEFACE"
        )
      } else {
        vol_lps <- to_lps(vol)
        ipp_s <- vol_lps$affine[1:3, 4L] + vol_lps$affine[1:3, 3L] * (s - 1L)
        iop_lps <- paste(round(c(vol_lps$direction$d_row, vol_lps$direction$d_col), 6L), collapse = "\\")

        meta_tags <- c(
          "Modality", "ImageType", "RecognizableVisualFeatures",
          "SOPInstanceUID", "MediaStorageSOPInstanceUID", "SeriesInstanceUID",
          "PatientIdentityRemoved", "DeidentificationMethod",
          "ImagePositionPatient", "ImageOrientationPatient", "PixelSpacing"
        )
        meta_vals <- c(
          modality,
          "DERIVED\\SECONDARY",
          "NO",
          new_sop_uid, new_sop_uid, new_series_uid,
          "YES", "DEFACE",
          paste(round(ipp_s, 4L), collapse = "\\"),
          iop_lps,
          paste(round(vol$spacing[1:2], 4L), collapse = "\\")
        )
      }

      cpp_write_dicom_multiframe(
        pixels = as.double(slice_pixels),
        dims = c(dims[1L], dims[2L], 1L),
        out_path = out_path,
        meta_tags = meta_tags,
        meta_values = meta_vals,
        extra_sequences = cid_sq
      )
    }
  }

  vol_out
}
