#' Render a 3D DICOM Volume (Orthogonal MPR, MIP, or Interactive rgl 3D)
#'
#' Visualizes a 3D DICOM series (`"dicom_series"` or 3D numeric array) using:
#' - `"mpr"`: 3-plane Orthogonal Multi-Planar Reconstruction (Axial, Coronal,
#'   Sagittal slices) via `ggplot2`.
#' - `"mip"`: Maximum Intensity Projection across Axial, Coronal, and Sagittal
#'   orientations via `ggplot2`.
#' - `"rgl"`: Interactive 3D voxel rendering using the `rgl` package (falls back
#'   to `"mip"` if `rgl` is not installed).
#'
#' @param x A `"dicom_series"` object (from [read_dicom_series()]), a 3D numeric
#'   array `[rows, cols, slices]`, or a directory/vector of DICOM file paths.
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
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' series <- read_dicom_series(c(dcm_file, dcm_file, dcm_file))
#' render_volume(series, method = "mpr")
#' render_volume(series, method = "mip")
render_volume <- function(x,
                          method = c("mpr", "mip", "rgl"),
                          window = "auto",
                          threshold = 0.5,
                          palette = c("gray", "viridis", "inferno", "magma", "plasma")) {
  method <- match.arg(method)
  palette <- match.arg(palette)

  vol <- if (inherits(x, "dicom_series")) {
    x$volume
  } else if (is.character(x)) {
    read_dicom_series(x)$volume
  } else if (is.numeric(x) && length(dim(x)) == 3L) {
    x
  } else if (is.numeric(x) && length(dim(x)) == 2L) {
    array(x, dim = c(dim(x), 1L))
  } else {
    rlang::abort("`x` must be a `dicom_series` object, 3D numeric array, or path to DICOM files.")
  }

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
      id <- rgl::points3d(idx[, 2L], rows - idx[, 1L] + 1L, idx[, 3L],
                          color = cols_hex, size = 3)
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

    axial <- win_vol[, , mid_s]
    coronal <- matrix(win_vol[mid_r, , ], nrow = cols, ncol = slices)
    sagittal <- matrix(win_vol[, mid_c, ], nrow = rows, ncol = slices)
    views <- list(
      Axial = axial,
      Coronal = t(coronal),
      Sagittal = t(sagittal)
    )
    title_str <- "3-Plane Orthogonal Multi-Planar Reconstruction (MPR)"
  } else {
    # Maximum Intensity Projection (MIP)
    axial <- apply(win_vol, c(1L, 2L), max, na.rm = TRUE)
    coronal <- t(apply(win_vol, c(2L, 3L), max, na.rm = TRUE))
    sagittal <- t(apply(win_vol, c(1L, 3L), max, na.rm = TRUE))
    views <- list(
      "Axial MIP" = axial,
      "Coronal MIP" = coronal,
      "Sagittal MIP" = sagittal
    )
    title_str <- "3-Plane Maximum Intensity Projection (MIP)"
  }

  dfs <- lapply(names(views), function(vname) {
    m <- views[[vname]]
    nr <- nrow(m)
    nc <- ncol(m)
    g <- expand.grid(r = seq_len(nr), c = seq_len(nc))
    g$x <- (g$c - 0.5) / max(1, nc)
    g$y <- (nr - g$r + 0.5) / max(1, nr)
    g$w <- 1.0 / max(1, nc)
    g$h <- 1.0 / max(1, nr)
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
