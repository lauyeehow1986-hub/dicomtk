#' Synthesize a Multi-Resolution DICOM WSI Pyramid for Testing
#'
#' Generates a synthetic tiled Whole Slide Imaging (WSI) directory hierarchy
#' with real DICOM Part 10 tile files and level metadata supporting both
#' `"TILED_FULL"` and `"TILED_SPARSE"` dimension organizations.
#'
#' @param out_dir Output directory path.
#' @param base_dims Base (Level 1) pixel matrix dimensions `c(rows, cols)`.
#' @param tile_dims Tile dimensions `c(tile_rows, tile_cols)`.
#' @param levels Number of pyramid levels to synthesize (default `2L`).
#' @param organization Either `"TILED_FULL"` or `"TILED_SPARSE"`.
#'
#' @return A list with `out_dir`, `levels`, and `level_arrays` (ground-truth
#'   2D numeric matrices per level).
#' @export
dicom_synthesize_wsi <- function(out_dir = tempfile("wsi_"),
                                 base_dims = c(64L, 64L),
                                 tile_dims = c(16L, 16L),
                                 levels = 2L,
                                 organization = c("TILED_FULL", "TILED_SPARSE")) {
  organization <- match.arg(organization)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  base_rows <- as.integer(base_dims[1L])
  base_cols <- as.integer(base_dims[2L])
  th <- as.integer(tile_dims[1L])
  tw <- as.integer(tile_dims[2L])
  levels <- as.integer(levels)

  level_meta <- vector("list", levels)
  level_arrays <- vector("list", levels)

  for (lv in seq_len(levels)) {
    scale <- 2L^(lv - 1L)
    tot_rows <- max(th, as.integer(base_rows / scale))
    tot_cols <- max(tw, as.integer(base_cols / scale))
    n_tr <- ceiling(tot_rows / th)
    n_tc <- ceiling(tot_cols / tw)

    lv_dir <- file.path(out_dir, paste0("level_", lv))
    dir.create(lv_dir, recursive = TRUE, showWarnings = FALSE)
    full_mat <- matrix(0, nrow = tot_rows, ncol = tot_cols)
    tile_entries <- list()

    for (tr in seq_len(n_tr)) {
      for (tc in seq_len(n_tc)) {
        tile_dir <- file.path(lv_dir, sprintf("tile_r%03d_c%03d", tr, tc))
        y_off <- (tr - 1L) * th + 1L
        x_off <- (tc - 1L) * tw + 1L
        syn <- dicom_synthesize(
          out_dir = tile_dir,
          modality = "DX",
          dims = c(th, tw, 1L),
          phi = FALSE,
          seed = 1000L * lv + 100L * tr + tc,
          extra_tags = list(
            Modality = "SM",
            DimensionOrganizationType = organization,
            TotalPixelMatrixRows = as.character(tot_rows),
            TotalPixelMatrixColumns = as.character(tot_cols)
          )
        )
        vol <- read_dicom_volume(syn$out_dir)
        tile_mat <- as.array(vol)[, , 1L]
        r_end <- min(tot_rows, y_off + th - 1L)
        c_end <- min(tot_cols, x_off + tw - 1L)
        full_mat[y_off:r_end, x_off:c_end] <- tile_mat[seq_len(r_end - y_off + 1L), seq_len(c_end - x_off + 1L), drop = FALSE]

        tile_entries[[length(tile_entries) + 1L]] <- list(
          tile_row = tr,
          tile_col = tc,
          x_offset = x_off,
          y_offset = y_off,
          tile_path = syn$files[1L]
        )
      }
    }

    level_arrays[[lv]] <- full_mat
    level_meta[[lv]] <- list(
      level = lv,
      total_rows = tot_rows,
      total_cols = tot_cols,
      tile_rows = th,
      tile_cols = tw,
      n_tile_rows = n_tr,
      n_tile_cols = n_tc,
      organization = organization,
      tiles = tile_entries
    )
  }

  jsonlite::write_json(
    list(organization = organization, levels = level_meta),
    file.path(out_dir, "wsi_pyramid.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )

  list(
    out_dir = normalizePath(out_dir, winslash = "/", mustWork = FALSE),
    levels = level_meta,
    level_arrays = level_arrays
  )
}

#' Read a Multi-Resolution DICOM WSI Pyramid Index
#'
#' Reads a Whole Slide Imaging (WSI) directory containing `wsi_pyramid.json`
#' or tiled DICOM `SM` / `DX` files, organizing pyramid levels from highest
#' resolution (Level 1) to lowest resolution overview.
#'
#' @param path Directory path containing the WSI pyramid.
#' @return An S3 `"dicom_wsi_pyramid"` object with `levels` (tibble) and
#'   `tile_index` (per-level tile lookup).
#' @export
read_dicom_wsi_pyramid <- function(path) {
  if (!dir.exists(path)) {
    cli::cli_abort("WSI directory {.path {path}} does not exist.")
  }
  idx_file <- file.path(path, "wsi_pyramid.json")
  if (!file.exists(idx_file)) {
    cli::cli_abort("WSI pyramid index {.file wsi_pyramid.json} not found in {.path {path}}.")
  }
  raw <- jsonlite::read_json(idx_file, simplifyVector = FALSE)
  lv_list <- raw$levels
  ord <- order(-vapply(lv_list, function(x) as.integer(x$total_cols), integer(1L)))
  lv_list <- lv_list[ord]

  tbl <- tibble::tibble(
    level = seq_along(lv_list),
    total_rows = vapply(lv_list, function(x) as.integer(x$total_rows), integer(1L)),
    total_cols = vapply(lv_list, function(x) as.integer(x$total_cols), integer(1L)),
    tile_rows = vapply(lv_list, function(x) as.integer(x$tile_rows), integer(1L)),
    tile_cols = vapply(lv_list, function(x) as.integer(x$tile_cols), integer(1L)),
    n_tile_rows = vapply(lv_list, function(x) as.integer(x$n_tile_rows), integer(1L)),
    n_tile_cols = vapply(lv_list, function(x) as.integer(x$n_tile_cols), integer(1L)),
    organization = vapply(lv_list, function(x) as.character(x$organization), character(1L))
  )

  structure(
    list(
      path = normalizePath(path, winslash = "/", mustWork = FALSE),
      levels = tbl,
      tile_index = lv_list
    ),
    class = "dicom_wsi_pyramid"
  )
}

#' Extract a Single Tile from a DICOM WSI Pyramid Out-of-Core
#'
#' @param pyramid A `"dicom_wsi_pyramid"` from [read_dicom_wsi_pyramid()].
#' @param level 1-based pyramid level (1 = highest resolution).
#' @param tile_row 1-based tile row index.
#' @param tile_col 1-based tile column index.
#'
#' @return A 2D numeric matrix of dimensions `tile_rows x tile_cols`.
#' @export
wsi_extract_tile <- function(pyramid, level = 1L, tile_row = 1L, tile_col = 1L) {
  if (!inherits(pyramid, "dicom_wsi_pyramid")) {
    cli::cli_abort("{.arg pyramid} must be a {.cls dicom_wsi_pyramid} object.")
  }
  level <- as.integer(level)
  tile_row <- as.integer(tile_row)
  tile_col <- as.integer(tile_col)
  if (level < 1L || level > nrow(pyramid$levels)) {
    cli::cli_abort("Level {.val {level}} out of bounds.")
  }
  lv_info <- pyramid$tile_index[[level]]
  match_tile <- Filter(function(t) {
    as.integer(t$tile_row) == tile_row && as.integer(t$tile_col) == tile_col
  }, lv_info$tiles)
  if (length(match_tile) == 0L) {
    return(matrix(0, nrow = lv_info$tile_rows, ncol = lv_info$tile_cols))
  }
  vol <- read_dicom_volume(dirname(match_tile[[1L]]$tile_path))
  as.array(vol)[, , 1L]
}

#' Stitch an Arbitrary Rectangular Region Across WSI Tile Boundaries
#'
#' @param pyramid A `"dicom_wsi_pyramid"` from [read_dicom_wsi_pyramid()].
#' @param level 1-based pyramid level.
#' @param x 1-based starting column coordinate.
#' @param y 1-based starting row coordinate.
#' @param width Region width in pixels.
#' @param height Region height in pixels.
#'
#' @return A 2D numeric matrix of dimensions `height x width`.
#' @export
wsi_stitch_region <- function(pyramid,
                              level = 1L,
                              x = 1L,
                              y = 1L,
                              width = 32L,
                              height = 32L) {
  if (!inherits(pyramid, "dicom_wsi_pyramid")) {
    cli::cli_abort("{.arg pyramid} must be a {.cls dicom_wsi_pyramid} object.")
  }
  level <- as.integer(level)
  x <- as.integer(x)
  y <- as.integer(y)
  width <- as.integer(width)
  height <- as.integer(height)
  if (level < 1L || level > nrow(pyramid$levels) || x < 1L || y < 1L || width < 1L || height < 1L) {
    cli::cli_abort("Invalid region coordinates or pyramid level in {.fn wsi_stitch_region}.")
  }

  lv_row <- pyramid$levels[level, , drop = FALSE]
  th <- lv_row$tile_rows
  tw <- lv_row$tile_cols

  x_end <- min(lv_row$total_cols, x + width - 1L)
  y_end <- min(lv_row$total_rows, y + height - 1L)

  out <- matrix(0, nrow = height, ncol = width)
  tr_start <- floor((y - 1L) / th) + 1L
  tr_end <- floor((y_end - 1L) / th) + 1L
  tc_start <- floor((x - 1L) / tw) + 1L
  tc_end <- floor((x_end - 1L) / tw) + 1L

  for (tr in seq(tr_start, tr_end)) {
    for (tc in seq(tc_start, tc_end)) {
      tile_mat <- wsi_extract_tile(pyramid, level = level, tile_row = tr, tile_col = tc)
      ty0 <- (tr - 1L) * th + 1L
      tx0 <- (tc - 1L) * tw + 1L
      ry1 <- max(y, ty0)
      ry2 <- min(y_end, ty0 + th - 1L)
      rx1 <- max(x, tx0)
      rx2 <- min(x_end, tx0 + tw - 1L)
      if (ry2 >= ry1 && rx2 >= rx1) {
        out[(ry1 - y + 1L):(ry2 - y + 1L), (rx1 - x + 1L):(rx2 - x + 1L)] <-
          tile_mat[(ry1 - ty0 + 1L):(ry2 - ty0 + 1L), (rx1 - tx0 + 1L):(rx2 - tx0 + 1L), drop = FALSE]
      }
    }
  }
  out
}

#' Construct DICOM Supplement 222 Microscopy Bulk Simple Annotations
#'
#' @param rois List of ROI descriptors, each a list with `label`, `type`
#'   (`"POLYGON"`, `"POLYLINE"`, or `"POINT"`), and `coords` (2-column matrix of
#'   `(x, y)` coordinates).
#' @param coordinate_type Either `"2D"` (pixel matrix) or `"3D"` (slide stage).
#' @param pixel_matrix_dims Integer vector `c(rows, cols)` of the target level.
#'
#' @return An S3 `"dicom_wsi_annotations"` object.
#' @examples
#' rois <- list(list(
#'   label = "tumor",
#'   type = "POLYGON",
#'   coords = matrix(c(4, 4, 12, 4, 12, 12, 4, 12), ncol = 2, byrow = TRUE)
#' ))
#' ann <- dicom_wsi_annotations(rois, pixel_matrix_dims = c(32L, 32L))
#' ann$sop_class_uid
#' @export
dicom_wsi_annotations <- function(rois,
                                  coordinate_type = c("2D", "3D"),
                                  pixel_matrix_dims = c(64L, 64L)) {
  coordinate_type <- match.arg(coordinate_type)
  if (!is.list(rois) || length(rois) == 0L) {
    cli::cli_abort("{.arg rois} must be a non-empty list of ROI descriptors.")
  }
  structure(
    list(
      sop_class_uid = "1.2.840.10008.5.1.4.1.1.91.1",
      coordinate_type = coordinate_type,
      pixel_matrix_dims = as.integer(pixel_matrix_dims),
      rois = rois
    ),
    class = "dicom_wsi_annotations"
  )
}

#' Rasterize DICOM Sup 222 WSI Annotations into a 2D Label Mask
#'
#' @param annotations A `"dicom_wsi_annotations"` from
#'   [dicom_wsi_annotations()].
#' @param level_dims Optional `c(rows, cols)` override.
#'
#' @return A 2D integer label matrix (`0L` = background, `1L..K` = ROI index).
#' @export
wsi_annotations_to_mask <- function(annotations, level_dims = NULL) {
  if (!inherits(annotations, "dicom_wsi_annotations")) {
    cli::cli_abort("{.arg annotations} must be a {.cls dicom_wsi_annotations} object.")
  }
  dims <- as.integer(level_dims %||% annotations$pixel_matrix_dims)
  h <- dims[1L]
  w <- dims[2L]
  mask <- matrix(0L, nrow = h, ncol = w)
  for (i in seq_along(annotations$rois)) {
    roi <- annotations$rois[[i]]
    if (identical(toupper(roi$type), "POLYGON")) {
      m <- rasterize_polygon_2d(roi$coords, width = w, height = h)
      mask[m] <- as.integer(i)
    }
  }
  mask
}
