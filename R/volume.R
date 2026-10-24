#' Render a 3D DICOM Volume (Orthogonal MPR, MIP, or Interactive rgl 3D)
#'
#' Visualizes a 3D DICOM volume ([`dicom_volume`][new_dicom_volume],
#' `"dicom_series"`, 3D numeric array, or file/directory path) with true
#' physical millimeter aspect ratios using:
#' - `"mpr"`: 3-plane Orthogonal Multi-Planar Reconstruction (Axial, Coronal,
#'   Sagittal slices) via `ggplot2`.
#' - `"mip"`: Maximum Intensity Projection across Axial, Coronal, and Sagittal
#'   orientations via `ggplot2`.
#' - `"rgl"`: Interactive 3D voxel rendering using the `rgl` package (falls back
#'   to `"mip"` if `rgl` is not installed).
#'
#' @param x A [`dicom_volume`][new_dicom_volume] object (from
#'   [read_dicom_volume()]), a `"dicom_series"` object, a 2D/3D numeric array,
#'   or a directory/vector of DICOM file paths.
#' @param method Visualization mode: `"mpr"` (default), `"mip"`, or `"rgl"`.
#' @param window Window preset (`"auto"`, `"brain"`, `"lung"`, `"bone"`, etc.) or
#'   `c(center, width)`. Default is `"auto"`.
#' @param threshold Optional intensity threshold in `[0, 1]` for 3D `"rgl"`
#'   point-cloud / surface rendering. Default is `0.5`.
#' @param palette Color palette (`"gray"`, `"viridis"`, `"inferno"`, `"magma"`,
#'   `"plasma"`). Default is `"gray"`.
#'
#' @return A [ggplot2::ggplot] object (for `"mpr"` and `"mip"`) or invisibly the
#'   `rgl` scene ID (for `"rgl"`).
#' @export
#' @examples
#' out_dir <- tempfile("render_vol_")
#' dicom_synthesize(out_dir = out_dir, modality = "CT", dims = c(16L, 16L, 4L))
#' vol <- read_dicom_volume(out_dir)
#' render_volume(vol, method = "mpr")
#' render_volume(vol, method = "mip")
#' unlink(out_dir, recursive = TRUE)
render_volume <- function(x,
                          method = c("mpr", "mip", "rgl"),
                          window = "auto",
                          threshold = 0.5,
                          palette = c("gray", "viridis", "inferno", "magma", "plasma")) {
  method <- match.arg(method)
  palette <- match.arg(palette)

  extract_from_dicom_volume <- function(dv) {
    d <- dim(dv$voxels)
    arr <- if (length(d) == 4L) {
      array(dv$voxels[, , , 1L], dim = d[1:3])
    } else {
      dv$voxels
    }
    if (!is.na(dv$modality) && nzchar(dv$modality)) {
      attr(arr, "modality") <- dv$modality
    }
    attr(arr, "pixel_spacing") <- dv$spacing[1:2]
    attr(arr, "slice_thickness") <- dv$spacing[3L]
    meta <- dv$frame_meta
    if (nrow(meta) > 0L) {
      if ("PhotometricInterpretation" %in% names(meta)) {
        attr(arr, "photometric") <- as.character(meta$PhotometricInterpretation[1L])
      }
      if ("WindowCenter" %in% names(meta)) {
        wc <- vol_parse_ds(meta$WindowCenter[1L], expected_len = 1L)
        if (!is.null(wc)) attr(arr, "window_center") <- wc
      }
      if ("WindowWidth" %in% names(meta)) {
        ww <- vol_parse_ds(meta$WindowWidth[1L], expected_len = 1L)
        if (!is.null(ww) && ww > 0) attr(arr, "window_width") <- ww
      }
    }
    list(vol = arr, spacing = dv$spacing)
  }

  sp3 <- c(1.0, 1.0, 1.0)
  if (is_dicom_volume(x)) {
    info <- extract_from_dicom_volume(x)
    vol <- info$vol
    sp3 <- info$spacing
  } else if (inherits(x, "dicom_series")) {
    vol <- x$volume
    if (!is.null(x$affine) && is.matrix(x$affine) && identical(dim(x$affine), c(4L, 4L))) {
      sp3 <- derive_geometry_from_affine(x$affine)$spacing
    } else {
      ps <- attr(vol, "pixel_spacing")
      st <- attr(vol, "slice_thickness")
      if (is.numeric(ps) && length(ps) >= 2L && all(is.finite(ps[1:2])) && all(ps[1:2] > 0)) {
        sp3[1:2] <- ps[1:2]
      }
      if (is.numeric(st) && length(st) >= 1L && is.finite(st[1L]) && st[1L] > 0) {
        sp3[3L] <- st[1L]
      }
    }
  } else if (is.character(x)) {
    dv <- read_dicom_volume(x, warn = FALSE)
    info <- extract_from_dicom_volume(dv)
    vol <- info$vol
    sp3 <- info$spacing
  } else if (is.numeric(x) && length(dim(x)) %in% c(2L, 3L)) {
    vol <- if (length(dim(x)) == 2L) {
      res <- array(x, dim = c(dim(x), 1L))
      for (nm in c("modality", "photometric", "window_center", "window_width", "pixel_spacing", "slice_thickness", "spacing")) {
        attr(res, nm) <- attr(x, nm)
      }
      res
    } else {
      x
    }
    sp_attr <- attr(vol, "spacing")
    ps <- attr(vol, "pixel_spacing")
    st <- attr(vol, "slice_thickness")
    if (is.numeric(sp_attr) && length(sp_attr) == 3L && all(is.finite(sp_attr)) && all(sp_attr > 0)) {
      sp3 <- as.double(sp_attr)
    } else {
      if (is.numeric(ps) && length(ps) >= 2L && all(is.finite(ps[1:2])) && all(ps[1:2] > 0)) {
        sp3[1:2] <- as.double(ps[1:2])
      }
      if (is.numeric(st) && length(st) >= 1L && is.finite(st[1L]) && st[1L] > 0) {
        sp3[3L] <- as.double(st[1L])
      }
    }
  } else {
    rlang::abort("`x` must be a `dicom_volume`, `dicom_series`, 3D numeric array, or path to DICOM files.")
  }

  sp3[!is.finite(sp3) | sp3 <= 0] <- 1.0
  dr <- sp3[1L]
  dc <- sp3[2L]
  dz <- sp3[3L]

  win_vol <- dicom_window(vol, preset = window)
  dims <- dim(win_vol)
  rows <- dims[1L]
  cols <- dims[2L]
  slices <- dims[3L]

  if (method == "rgl") {
    if (requireNamespace("rgl", quietly = TRUE)) {
      idx <- which(win_vol >= threshold, arr.ind = TRUE)
      if (nrow(idx) > 25000L) {
        keep <- sample.int(nrow(idx), 25000L)
        idx <- idx[keep, , drop = FALSE]
      }
      vals <- win_vol[idx]
      cols_hex <- grDevices::gray(vals)
      rgl::open3d()
      rgl::bg3d("black")
      id <- rgl::points3d(
        (idx[, 2L] - 0.5) * dc,
        (rows - idx[, 1L] + 0.5) * dr,
        (idx[, 3L] - 0.5) * dz,
        color = cols_hex,
        size = 3
      )
      return(invisible(id))
    } else {
      cli::cli_alert_warning("Package `rgl` not installed; falling back to `method = 'mip'`.")
      method <- "mip"
    }
  }

  if (method == "mpr") {
    mid_r <- max(1L, as.integer(ceiling(rows / 2)))
    mid_c <- max(1L, as.integer(ceiling(cols / 2)))
    mid_s <- max(1L, as.integer(ceiling(slices / 2)))

    axial <- matrix(win_vol[, , mid_s], nrow = rows, ncol = cols)
    coronal <- matrix(win_vol[mid_r, , ], nrow = cols, ncol = slices)
    sagittal <- matrix(win_vol[, mid_c, ], nrow = rows, ncol = slices)
    views <- list(
      Axial = list(mat = axial, step_r = dr, step_c = dc),
      Coronal = list(mat = t(coronal), step_r = dz, step_c = dc),
      Sagittal = list(mat = t(sagittal), step_r = dz, step_c = dr)
    )
    title_str <- "3-Plane Orthogonal Multi-Planar Reconstruction (MPR)"
  } else {
    # Maximum Intensity Projection (MIP)
    axial <- matrix(apply(win_vol, c(1L, 2L), max, na.rm = TRUE), nrow = rows, ncol = cols)
    coronal <- matrix(t(apply(win_vol, c(2L, 3L), max, na.rm = TRUE)), nrow = slices, ncol = cols)
    sagittal <- matrix(t(apply(win_vol, c(1L, 3L), max, na.rm = TRUE)), nrow = slices, ncol = rows)
    views <- list(
      "Axial MIP" = list(mat = axial, step_r = dr, step_c = dc),
      "Coronal MIP" = list(mat = coronal, step_r = dz, step_c = dc),
      "Sagittal MIP" = list(mat = sagittal, step_r = dz, step_c = dr)
    )
    title_str <- "3-Plane Maximum Intensity Projection (MIP)"
  }

  dfs <- lapply(names(views), function(vname) {
    v_item <- views[[vname]]
    m <- v_item$mat
    nr <- nrow(m)
    nc <- ncol(m)
    phys_h <- max(1e-9, nr * v_item$step_r)
    phys_w <- max(1e-9, nc * v_item$step_c)
    scale_max <- max(phys_w, phys_h)
    tile_w <- v_item$step_c / scale_max
    tile_h <- v_item$step_r / scale_max
    x_off <- (1.0 - nc * tile_w) / 2.0
    y_off <- (1.0 - nr * tile_h) / 2.0

    g <- expand.grid(r = seq_len(nr), c = seq_len(nc))
    g$x <- x_off + (g$c - 0.5) * tile_w
    g$y <- y_off + (nr - g$r + 0.5) * tile_h
    g$w <- tile_w
    g$h <- tile_h
    g$intensity <- as.double(m)
    g$plane <- factor(vname, levels = names(views))
    g
  })
  plot_df <- dplyr::bind_rows(dfs)

  p <- ggplot2::ggplot(plot_df, ggplot2::aes(
    x = .data$x,
    y = .data$y,
    width = .data$w,
    height = .data$h,
    fill = .data$intensity
  )) +
    ggplot2::geom_tile() +
    ggplot2::facet_wrap(~ plane, nrow = 1L) +
    ggplot2::coord_fixed(ratio = 1.0, expand = FALSE) +
    ggplot2::labs(title = title_str) +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.background = ggplot2::element_rect(fill = "black", color = NA),
      panel.background = ggplot2::element_rect(fill = "black", color = NA),
      strip.text = ggplot2::element_text(color = "white", size = 10,
                                         margin = ggplot2::margin(t = 4, b = 4)),
      plot.title = ggplot2::element_text(color = "white", hjust = 0.5, size = 11,
                                         margin = ggplot2::margin(t = 6, b = 6)),
      legend.position = "none"
    )

  if (palette == "gray") {
    p <- p + ggplot2::scale_fill_gradient(low = "black", high = "white", limits = c(0, 1))
  } else {
    p <- p + ggplot2::scale_fill_viridis_c(option = palette, limits = c(0, 1))
  }
  p
}
