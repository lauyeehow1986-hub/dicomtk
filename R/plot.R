# Clinical CT Window Center / Window Width presets (Hounsfield Units)
dicom_window_presets <- list(
  brain       = c(center = 40,   width = 80),
  stroke      = c(center = 32,   width = 8),
  subdural    = c(center = 75,   width = 215),
  lung        = c(center = -600, width = 1500),
  mediastinum = c(center = 50,   width = 350),
  abdomen     = c(center = 40,   width = 400),
  liver       = c(center = 60,   width = 150),
  bone        = c(center = 400,  width = 1800),
  angio       = c(center = 300,  width = 600)
)

#' Apply VOI LUT Window/Level Transformation to DICOM Pixels
#'
#' Applies linear window/level (Window Center and Window Width) transformation
#' to a DICOM pixel matrix or array, normalizing output values to `[0, 1]`.
#' Supports standard clinical CT window presets (`"brain"`, `"lung"`, `"bone"`,
#' `"abdomen"`, `"mediastinum"`, `"liver"`, `"stroke"`, `"subdural"`, `"angio"`),
#' embedded DICOM `WindowCenter`/`WindowWidth` tags (`"auto"`), or custom
#' numeric `center` and `width`.
#'
#' @param x A `"dicom_pixels"` array/matrix or a file path to a DICOM file.
#' @param center Numeric window center (level). Overrides `preset` if both
#'   `center` and `width` are provided.
#' @param width Numeric window width (must be `> 0`).
#' @param preset Character preset name (`"auto"`, `"brain"`, `"stroke"`,
#'   `"subdural"`, `"lung"`, `"mediastinum"`, `"abdomen"`, `"liver"`, `"bone"`,
#'   `"angio"`) or numeric vector `c(center, width)`. Default is `"auto"`.
#' @param invert Optional logical to invert grayscale intensities. By default,
#'   automatically inverts if `PhotometricInterpretation == "MONOCHROME1"`.
#'
#' @return A numeric matrix/array of the same dimensions as `x` with values
#'   scaled to `[0, 1]`.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' px <- read_dicom_pixels(dcm_file)
#' win_auto <- dicom_window(px, preset = "auto")
#' range(win_auto)
dicom_window <- function(x,
                         center = NULL,
                         width = NULL,
                         preset = "auto",
                         invert = NULL) {
  if (is.character(x)) {
    x <- read_dicom_pixels(x)
  }

  if (is.numeric(preset) && length(preset) == 2L) {
    center <- preset[1L]
    width <- preset[2L]
  } else if (is.null(center) || is.null(width)) {
    preset_nm <- tolower(as.character(preset)[1L])
    if (preset_nm %in% names(dicom_window_presets)) {
      p <- dicom_window_presets[[preset_nm]]
      center <- p[["center"]]
      width <- p[["width"]]
    } else {
      # "auto": use DICOM attributes if present and valid, else robust quantiles
      wc <- attr(x, "window_center")
      ww <- attr(x, "window_width")
      if (!is.null(wc) && !is.null(ww) && !is.na(wc) && !is.na(ww) && ww > 0) {
        center <- wc
        width <- ww
      } else {
        qs <- stats::quantile(x, probs = c(0.01, 0.99), na.rm = TRUE)
        if (qs[2L] <= qs[1L]) {
          qs <- range(x, na.rm = TRUE)
        }
        center <- mean(qs)
        width <- max(1e-6, diff(qs))
      }
    }
  }

  width <- max(1e-6, as.double(width))
  center <- as.double(center)

  low <- center - width / 2.0
  high <- center + width / 2.0

  res <- (x - low) / (high - low)
  res[res < 0.0] <- 0.0
  res[res > 1.0] <- 1.0

  if (is.null(invert)) {
    photometric <- attr(x, "photometric")
    invert <- identical(toupper(as.character(photometric)), "MONOCHROME1")
  }
  if (isTRUE(invert)) {
    res <- 1.0 - res
  }

  attr(res, "window_center") <- center
  attr(res, "window_width") <- width
  attr(res, "photometric") <- attr(x, "photometric")
  attr(res, "modality") <- attr(x, "modality")
  attr(res, "pixel_spacing") <- attr(x, "pixel_spacing")
  res
}

#' Plot a DICOM Image Using ggplot2
#'
#' Renders a 2D slice of a DICOM image as a [ggplot2::ggplot] object with
#' clinical window/level scaling, proper pixel aspect ratio, and optional
#' radiological metadata overlay.
#'
#' @param x Path to a DICOM file, a `"dicom_pixels"` matrix/array, or a
#'   `"dicom_series"` object.
#' @param frame Integer slice/frame index (1-based) when `x` is multi-frame or
#'   a `"dicom_series"`. Default is `1L`.
#' @param window Window preset (`"auto"`, `"brain"`, `"lung"`, `"bone"`,
#'   `"abdomen"`, etc.) or `c(center, width)`. Default is `"auto"`.
#' @param center,width Optional explicit window center and width.
#' @param palette Color palette: `"gray"` (default radiological grayscale),
#'   `"viridis"`, `"inferno"`, `"magma"`, or `"plasma"`.
#' @param annotate Logical. Display clinical overlay text (modality, dimensions,
#'   window center/width). Default is `TRUE`.
#' @param title Optional plot title.
#'
#' @return A [ggplot2::ggplot] object.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' p <- plot_dicom(dcm_file)
#' p
plot_dicom <- function(x,
                       frame = 1L,
                       window = "auto",
                       center = NULL,
                       width = NULL,
                       palette = c("gray", "viridis", "inferno", "magma", "plasma"),
                       annotate = TRUE,
                       title = NULL) {
  palette <- match.arg(palette)

  px <- if (is.character(x)) {
    read_dicom_pixels(x, frame = frame, rescale = TRUE)
  } else if (inherits(x, "dicom_series")) {
    vol <- x$volume
    ns <- dim(vol)[3L]
    idx <- max(1L, min(as.integer(frame), ns))
    slice <- vol[, , idx]
    for (nm in c("modality", "photometric", "window_center", "window_width", "pixel_spacing")) {
      attr(slice, nm) <- attr(vol, nm)
    }
    slice
  } else {
    x
  }

  win <- dicom_window(px, center = center, width = width, preset = window)
  dims <- dim(win)
  rows <- dims[1L]
  cols <- dims[2L]

  # Extract 2D slice if 3D monochrome
  if (length(dims) == 3L && dims[3L] != 3L) {
    idx <- max(1L, min(as.integer(frame), dims[3L]))
    mat <- win[, , idx]
  } else if (length(dims) == 3L && dims[3L] == 3L) {
    # Convert RGB to luminance for tidy raster or use raster annotation
    mat <- 0.299 * win[, , 1L] + 0.587 * win[, , 2L] + 0.114 * win[, , 3L]
  } else {
    mat <- win
  }

  grid_df <- expand.grid(
    row = seq_len(rows),
    col = seq_len(cols)
  )
  grid_df$intensity <- as.double(mat)
  grid_df$y <- rows - grid_df$row + 1L

  spacing <- attr(win, "pixel_spacing")
  aspect <- if (!is.null(spacing) && length(spacing) >= 2L &&
                all(!is.na(spacing[1:2])) && spacing[2L] > 0) {
    spacing[1L] / spacing[2L]
  } else {
    1.0
  }

  p <- ggplot2::ggplot(grid_df, ggplot2::aes(x = .data$col, y = .data$y, fill = .data$intensity)) +
    ggplot2::geom_raster(interpolate = FALSE) +
    ggplot2::coord_fixed(ratio = aspect, expand = FALSE) +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.background = ggplot2::element_rect(fill = "black", color = NA),
      panel.background = ggplot2::element_rect(fill = "black", color = NA),
      plot.title = ggplot2::element_text(color = "white", hjust = 0.5, size = 11,
                                         margin = ggplot2::margin(t = 6, b = 4)),
      plot.subtitle = ggplot2::element_text(color = "grey80", hjust = 0.5, size = 9,
                                            margin = ggplot2::margin(b = 4)),
      legend.position = "none"
    )

  if (palette == "gray") {
    p <- p + ggplot2::scale_fill_gradient(low = "black", high = "white", limits = c(0, 1))
  } else {
    p <- p + ggplot2::scale_fill_viridis_c(option = palette, limits = c(0, 1))
  }

  wc <- round(attr(win, "window_center"), 1)
  ww <- round(attr(win, "window_width"), 1)
  mod <- attr(win, "modality")
  if (is.null(mod) || !nzchar(mod)) mod <- "DICOM"

  if (isTRUE(annotate)) {
    sub_txt <- sprintf("%s | %dx%d | WL: %s WW: %s", mod, cols, rows, wc, ww)
    p <- p + ggplot2::labs(title = title, subtitle = sub_txt)
  } else if (!is.null(title)) {
    p <- p + ggplot2::labs(title = title)
  }

  p
}

#' Create a ggplot2 DICOM Image Object
#'
#' Alias for [plot_dicom()] designed for composable `ggplot2` pipelines.
#'
#' @inheritParams plot_dicom
#' @param ... Additional arguments passed to [plot_dicom()].
#' @return A [ggplot2::ggplot] object.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' ggdicom(dcm_file, palette = "viridis")
ggdicom <- function(x, frame = 1L, window = "auto", ...) {
  plot_dicom(x = x, frame = frame, window = window, ...)
}
