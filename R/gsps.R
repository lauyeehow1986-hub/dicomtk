#' Write a DICOM Grayscale Softcopy Presentation State (GSPS) Object
#'
#' Creates a standard DICOM Grayscale Softcopy Presentation State Storage
#' (`1.2.840.10008.5.1.4.1.1.11.1`, `Modality = "PR"`) file containing vector
#' graphic annotations (`GraphicObjectSequence (0070,0009)`), text labels
#' (`TextObjectSequence (0070,0008)`), graphic layers (`GraphicLayerSequence (0070,0060)`),
#' and softcopy VOI LUT windowing parameters without altering the underlying
#' image pixel data.
#'
#' @param annotations A `data.frame` or [tibble::tibble] with columns:
#'   \itemize{
#'     \item `slice`: 1-based slice index (optional, default `1L`).
#'     \item `layer`: Graphic layer name (optional, default `"LAYER_1"`).
#'     \item `graphic_type`: One of `"POINT"`, `"POLYLINE"`, `"INTERPOLATED"`, `"CIRCLE"`, or `"ELLIPSE"`.
#'     \item `coords`: A list-column of numeric vectors `c(x1, y1, x2, y2, ...)` giving 2D pixel coordinates.
#'     \item `text`: Optional character column with text annotation labels (`NA` or `""` for no text).
#'   }
#' @param out_path Path to the output `.dcm` presentation state file.
#' @param ref_volume Optional reference [dicom_volume] to link Study/Series UIDs.
#' @param window_center Optional numeric VOI LUT `WindowCenter (0028,1050)`.
#' @param window_width Optional numeric VOI LUT `WindowWidth (0028,1051)`.
#' @param content_label Presentation state `ContentLabel (0070,0080)`. Default is `"GSPS_ANNOTATIONS"`.
#'
#' @return Normalized path to `out_path` (invisibly).
#' @export
#' @examples
#' ann <- tibble::tibble(
#'   slice = 1L,
#'   layer = "ROI_LAYER",
#'   graphic_type = "POLYLINE",
#'   coords = list(c(10, 10, 20, 10, 20, 20, 10, 20, 10, 10)),
#'   text = "Target ROI"
#' )
#' tmp_pr <- tempfile(fileext = ".dcm")
#' write_dicom_gsps(ann, tmp_pr, window_center = 40, window_width = 400)
#' ps <- read_dicom_gsps(tmp_pr)
#' ps$graphics
#' unlink(tmp_pr)
write_dicom_gsps <- function(annotations,
                             out_path,
                             ref_volume = NULL,
                             window_center = NULL,
                             window_width = NULL,
                             content_label = "GSPS_ANNOTATIONS") {
  if (!inherits(annotations, "data.frame")) {
    rlang::abort("`annotations` must be a data.frame or tibble.")
  }
  n_ann <- nrow(annotations)

  layers <- if ("layer" %in% names(annotations)) {
    as.character(annotations$layer)
  } else {
    rep("LAYER_1", n_ann)
  }
  slices <- if ("slice" %in% names(annotations)) {
    as.integer(annotations$slice)
  } else {
    rep(1L, n_ann)
  }

  ann_items <- vector("list", n_ann)
  for (i in seq_len(n_ann)) {
    lyr <- layers[i]
    g_type <- if ("graphic_type" %in% names(annotations)) {
      toupper(as.character(annotations$graphic_type[i]))
    } else {
      "POLYLINE"
    }
    pts <- as.double(annotations$coords[[i]])
    n_pts <- length(pts) %/% 2L
    pts_str <- paste(format(round(pts, 4), scientific = FALSE, trim = TRUE), collapse = "\\")

    g_obj <- list(list(
      `(0070,0005)` = "PIXEL",                    # GraphicAnnotationUnits
      `(0070,0020)` = "2",                        # GraphicDimensions
      `(0070,0021)` = as.character(n_pts),        # NumberOfGraphicPoints
      `(0070,0022)` = pts_str,                    # GraphicData
      `(0070,0023)` = g_type,                     # GraphicType
      `(0070,0024)` = "N"                         # GraphicFilled
    ))

    item_i <- list(
      `(0070,0002)` = lyr,                        # GraphicLayer
      `(0070,0009)` = g_obj                       # GraphicObjectSequence
    )

    if ("text" %in% names(annotations)) {
      txt_val <- as.character(annotations$text[i])
      if (!is.na(txt_val) && nzchar(txt_val)) {
        anchor_pt <- if (length(pts) >= 2L) {
          paste(format(round(pts[1:2], 4), scientific = FALSE, trim = TRUE), collapse = "\\")
        } else {
          "1\\1"
        }
        item_i[["(0070,0008)"]] <- list(list(
          `(0070,0004)` = "PIXEL",                # AnchorPointAnnotationUnits
          `(0070,0006)` = txt_val,                # UnformattedTextValue
          `(0070,0014)` = anchor_pt,              # AnchorPoint
          `(0070,0015)` = "Y"                     # AnchorPointVisibility
        ))
      }
    }

    ann_items[[i]] <- item_i
  }

  unique_layers <- unique(layers)
  layer_items <- lapply(seq_along(unique_layers), function(idx) {
    list(
      `(0070,0002)` = unique_layers[idx],
      `(0070,0062)` = as.character(idx)
    )
  })

  meta_tags <- c(
    "SOPClassUID",
    "Modality",
    "ContentLabel",
    "ContentDescription",
    "InstanceNumber"
  )
  meta_vals <- c(
    "1.2.840.10008.5.1.4.1.1.11.1", # Grayscale Softcopy Presentation State Storage
    "PR",
    toupper(gsub("[^A-Z0-9_]", "_", as.character(content_label)[1L])),
    "DICOMTK Grayscale Softcopy Presentation State",
    "1"
  )

  if (!is.null(ref_volume) && inherits(ref_volume, "dicom_volume")) {
    st_uid <- ref_volume$uids$study_instance_uid %||% ""
    if (nzchar(st_uid)) {
      meta_tags <- c(meta_tags, "StudyInstanceUID")
      meta_vals <- c(meta_vals, as.character(st_uid)[1L])
    }
  }

  if (!is.null(window_center) && is.finite(window_center)) {
    meta_tags <- c(meta_tags, "WindowCenter")
    meta_vals <- c(meta_vals, format(as.double(window_center)[1L], scientific = FALSE, trim = TRUE))
  }
  if (!is.null(window_width) && is.finite(window_width)) {
    meta_tags <- c(meta_tags, "WindowWidth")
    meta_vals <- c(meta_vals, format(as.double(window_width)[1L], scientific = FALSE, trim = TRUE))
  }

  extra_sq <- list(
    `(0070,0001)` = ann_items,
    `(0070,0060)` = layer_items
  )

  ok <- cpp_write_dicom_dataset(
    out_path = out_path,
    meta_tags = meta_tags,
    meta_values = meta_vals,
    extra_sequences = extra_sq
  )
  if (!isTRUE(ok)) {
    rlang::abort(paste0("Failed to write DICOM GSPS file: ", out_path))
  }

  invisible(normalizePath(out_path, mustWork = FALSE))
}

#' Read a DICOM Grayscale Softcopy Presentation State (GSPS) Object
#'
#' Parses a DICOM Grayscale Softcopy Presentation State (`PR`) file and extracts
#' vector graphic objects (`GraphicObjectSequence (0070,0009)`), text labels
#' (`TextObjectSequence (0070,0008)`), and VOI LUT windowing parameters into
#' tidy tibbles.
#'
#' @param path Path to a DICOM GSPS `.dcm` file.
#'
#' @return An S3 object of class `c("dicom_gsps", "dicom_pstate")` containing:
#'   \item{graphics}{A tibble with columns `layer`, `graphic_type`, `n_points`, `coords` (list of numeric vectors), and `units`.}
#'   \item{texts}{A tibble with columns `layer`, `text`, `anchor_col`, and `anchor_row`.}
#'   \item{window_center}{Numeric `WindowCenter` (or `NA_real_`).}
#'   \item{window_width}{Numeric `WindowWidth` (or `NA_real_`).}
#'   \item{annotations}{Raw group `0x0070` header rows.}
#'   \item{voi_lut}{Raw VOI LUT header rows.}
#'   \item{header}{Top-level DICOM header tibble.}
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' gsps <- read_dicom_gsps(dcm_file)
#' gsps$graphics
read_dicom_gsps <- function(path) {
  if (length(path) != 1L || !file.exists(path)) {
    rlang::abort("`path` must be a single existing DICOM file path.")
  }
  hdr <- read_dicom(path, include_sequences = TRUE)

  # Parse GraphicObjectSequence (0070,0009) items
  gtype_rows <- which(hdr$tag == "(0070,0023)")
  graphics_list <- list()

  for (r_idx in gtype_rows) {
    sp <- hdr$sequence_path[r_idx]
    ann_prefix <- sub("/?\\(0070,0009\\)\\[[0-9]+\\].*$", "", sp)

    g_rows <- which(startsWith(hdr$sequence_path, sp))
    g_type <- hdr$value[r_idx]
    units_val <- hdr$value[g_rows[hdr$tag[g_rows] == "(0070,0005)"]][1L] %||% "PIXEL"
    n_pts_val <- suppressWarnings(as.integer(hdr$value[g_rows[hdr$tag[g_rows] == "(0070,0021)"]][1L]))
    raw_data <- hdr$value[g_rows[hdr$tag[g_rows] == "(0070,0022)"]][1L] %||% ""
    coords_num <- if (nzchar(raw_data)) {
      suppressWarnings(as.double(strsplit(raw_data, "\\\\", fixed = FALSE)[[1L]]))
    } else {
      numeric(0)
    }

    lyr_rows <- which(startsWith(hdr$sequence_path, ann_prefix) & hdr$tag == "(0070,0002)")
    lyr_val <- if (length(lyr_rows) > 0L) hdr$value[lyr_rows[1L]] else "LAYER_1"

    graphics_list[[length(graphics_list) + 1L]] <- tibble::tibble(
      layer = lyr_val,
      graphic_type = g_type,
      n_points = if (!is.na(n_pts_val)) n_pts_val else length(coords_num) %/% 2L,
      coords = list(coords_num),
      units = units_val
    )
  }

  # Parse TextObjectSequence (0070,0008) items
  txt_rows <- which(hdr$tag == "(0070,0006)")
  texts_list <- list()

  for (r_idx in txt_rows) {
    sp <- hdr$sequence_path[r_idx]
    ann_prefix <- sub("/?\\(0070,0008\\)\\[[0-9]+\\].*$", "", sp)

    t_rows <- which(startsWith(hdr$sequence_path, sp))
    txt_val <- hdr$value[r_idx]
    anc_raw <- hdr$value[t_rows[hdr$tag[t_rows] == "(0070,0014)"]][1L] %||% ""
    anc_num <- if (nzchar(anc_raw)) {
      suppressWarnings(as.double(strsplit(anc_raw, "\\\\", fixed = FALSE)[[1L]]))
    } else {
      c(NA_real_, NA_real_)
    }

    lyr_rows <- which(startsWith(hdr$sequence_path, ann_prefix) & hdr$tag == "(0070,0002)")
    lyr_val <- if (length(lyr_rows) > 0L) hdr$value[lyr_rows[1L]] else "LAYER_1"

    texts_list[[length(texts_list) + 1L]] <- tibble::tibble(
      layer = lyr_val,
      text = txt_val,
      anchor_col = anc_num[1L],
      anchor_row = anc_num[2L]
    )
  }

  graphics_df <- if (length(graphics_list) > 0L) {
    dplyr::bind_rows(graphics_list)
  } else {
    tibble::tibble(
      layer = character(),
      graphic_type = character(),
      n_points = integer(),
      coords = list(),
      units = character()
    )
  }

  texts_df <- if (length(texts_list) > 0L) {
    dplyr::bind_rows(texts_list)
  } else {
    tibble::tibble(
      layer = character(),
      text = character(),
      anchor_col = numeric(),
      anchor_row = numeric()
    )
  }

  wc_rows <- which(hdr$tag == "(0028,1050)")
  ww_rows <- which(hdr$tag == "(0028,1051)")
  wc_val <- if (length(wc_rows) > 0L) suppressWarnings(as.double(hdr$value[wc_rows[1L]])) else NA_real_
  ww_val <- if (length(ww_rows) > 0L) suppressWarnings(as.double(hdr$value[ww_rows[1L]])) else NA_real_

  structure(
    list(
      graphics = graphics_df,
      texts = texts_df,
      window_center = wc_val,
      window_width = ww_val,
      annotations = hdr[hdr$group == "0070", , drop = FALSE],
      voi_lut = hdr[hdr$tag %in% c("(0028,1050)", "(0028,1051)", "(0028,1052)", "(0028,1053)", "(0028,3010)"), , drop = FALSE],
      header = hdr[hdr$depth == 0L, , drop = FALSE]
    ),
    class = c("dicom_gsps", "dicom_pstate")
  )
}
