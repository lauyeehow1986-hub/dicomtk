# Internal 3D right-handed cross product
vol_cross3 <- function(a, b) {
  c(
    a[2L] * b[3L] - a[3L] * b[2L],
    a[3L] * b[1L] - a[1L] * b[3L],
    a[1L] * b[2L] - a[2L] * b[1L]
  )
}

# Internal helper: derive spacing = c(dr, dc, dz) and direction = list(d_row, d_col, normal)
# from a 4x4 affine where col1 = d_col * dr, col2 = d_row * dc, col3 = s_step.
derive_geometry_from_affine <- function(affine) {
  col1 <- as.double(affine[1:3, 1L])
  col2 <- as.double(affine[1:3, 2L])
  col3 <- as.double(affine[1:3, 3L])

  dr <- sqrt(sum(col1^2))
  dc <- sqrt(sum(col2^2))
  dz <- sqrt(sum(col3^2))

  d_col <- if (dr > 1e-12) col1 / dr else c(0.0, 1.0, 0.0)
  d_row <- if (dc > 1e-12) col2 / dc else c(1.0, 0.0, 0.0)
  d_col[abs(d_col) < 1e-15] <- 0.0
  d_row[abs(d_row) < 1e-15] <- 0.0

  n_raw <- vol_cross3(d_row, d_col)
  n_len <- sqrt(sum(n_raw^2))
  normal <- if (n_len > 1e-12) {
    n_raw / n_len
  } else if (dz > 1e-12) {
    col3 / dz
  } else {
    c(0.0, 0.0, 1.0)
  }
  normal[abs(normal) < 1e-15] <- 0.0

  list(
    spacing = c(dr, dc, dz),
    direction = list(
      d_row = unname(d_row),
      d_col = unname(d_col),
      normal = unname(normal)
    )
  )
}

# Internal helper: create a timestamped provenance record
make_provenance_entry <- function(action, params = list()) {
  if (!is.character(action) || length(action) != 1L || is.na(action) || !nzchar(action)) {
    cli::cli_abort("{.arg action} must be a single non-empty character string.")
  }
  if (!is.list(params) || is.data.frame(params)) {
    cli::cli_abort("{.arg params} must be a {.cls list}.")
  }
  pkg_ver <- tryCatch(
    as.character(utils::packageVersion("dicomtk")),
    error = function(e) "0.2.0"
  )
  list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    package_version = pkg_ver,
    action = action,
    params = params
  )
}

# Internal helper: append a provenance record to a dicom_volume or provenance list
append_provenance <- function(x, action, params = list()) {
  entry <- if (is.list(action) && !is.data.frame(action)) {
    action
  } else {
    make_provenance_entry(action = action, params = params)
  }

  if (is_dicom_volume(x)) {
    x$provenance <- c(x$provenance, list(entry))
    return(x)
  }
  if (is.list(x) && !is.data.frame(x)) {
    return(c(x, list(entry)))
  }
  cli::cli_abort("{.arg x} must be a {.cls dicom_volume} object or a provenance {.cls list}.")
}

#' Construct and Validate a `dicom_volume` Object
#'
#' Low-level S3 constructor and validator for 3D (`[rows, cols, slices]`) and
#' 4D (`[rows, cols, slices, frames]`) medical imaging volumes paired with an
#' exact 4x4 homogeneous voxel-to-world affine matrix in DICOM `"LPS"` or
#' NIfTI `"RAS"` physical coordinates (millimeters).
#'
#' By convention, 0-based voxel indices `(r, c, s)` map to physical world
#' coordinates via `affine %*% c(r, c, s, 1)`, where:
#' - Column 1 (`r` step along rows) is `d_col * dr`
#' - Column 2 (`c` step along columns) is `d_row * dc`
#' - Column 3 (`s` step across slices) is the inter-slice step vector
#' - Column 4 is the physical origin of voxel `(r = 0, c = 0, s = 0)` (`[1, 1, 1]` 1-based)
#'
#' @param voxels Numeric 2D matrix `[rows, cols]` (automatically promoted to
#'   `[rows, cols, 1L]`), 3D array `[rows, cols, slices]`, or 4D array
#'   `[rows, cols, slices, frames]`.
#' @param affine 4x4 finite numeric homogeneous voxel-to-world affine matrix
#'   whose bottom row is `c(0, 0, 0, 1)`. Defaults to `diag(4L)`.
#' @param coord_system World coordinate convention: `"LPS"` (DICOM Patient
#'   Coordinate System: Left-Posterior-Superior, default) or `"RAS"`
#'   (Right-Anterior-Superior).
#' @param spacing Optional length-3 non-negative numeric vector `c(dr, dc, dz)`
#'   in millimeters. Automatically derived from the Euclidean norms of columns
#'   1..3 of `affine` when `NULL`.
#' @param direction Optional named list with length-3 numeric direction cosine
#'   vectors `d_row`, `d_col`, and `normal`. Automatically derived from
#'   `affine` when `NULL`.
#' @param frame_meta Optional [tibble::tibble] (or `data.frame`, coerced to a
#'   tibble) storing per-slice or per-frame DICOM header metadata. Defaults to
#'   an empty tibble.
#' @param uids Named `list` of DICOM study/series/frame-of-reference UIDs.
#' @param modality Single character string (e.g. `"CT"`, `"MR"`, `"PT"`) or
#'   `NA_character_`.
#' @param units Single character string giving voxel physical units (e.g.
#'   `"HU"`, `"BQML"`, `"g/mL"`) or `NA_character_`.
#' @param diagnostics Named `list` of geometry diagnostics (e.g.
#'   `irregular_spacing`, `gantry_tilt_deg`).
#' @param provenance `list` of chronological provenance entries recording
#'   transformations applied to the volume.
#'
#' @return A validated S3 object of class `"dicom_volume"`.
#' @export
#' @examples
#' vox <- array(seq_len(8 * 8 * 4), dim = c(8L, 8L, 4L))
#' aff <- diag(c(0.8, 0.8, 2.5, 1.0))
#' aff[1:3, 4] <- c(-10, -10, 0)
#' vol <- new_dicom_volume(vox, affine = aff, modality = "CT", units = "HU")
#' vol
#' is_dicom_volume(vol)
new_dicom_volume <- function(voxels,
                             affine = diag(4L),
                             coord_system = c("LPS", "RAS"),
                             spacing = NULL,
                             direction = NULL,
                             frame_meta = NULL,
                             uids = list(),
                             modality = NA_character_,
                             units = NA_character_,
                             diagnostics = list(),
                             provenance = list()) {
  if (missing(voxels) || is.null(voxels) || is.factor(voxels) || !is.numeric(voxels)) {
    cli::cli_abort("{.arg voxels} must be a non-empty numeric 2D matrix, 3D array, or 4D array.")
  }
  d <- dim(voxels)
  if (is.null(d) || !(length(d) %in% c(2L, 3L, 4L))) {
    cli::cli_abort(
      "{.arg voxels} must have 2, 3, or 4 dimensions ({.code [rows, cols, slices[, frames]]})."
    )
  }
  if (length(voxels) == 0L || any(is.na(d)) || any(d < 1L)) {
    cli::cli_abort("{.arg voxels} must be non-empty with strictly positive dimensions.")
  }

  dn <- dimnames(voxels)
  target_dim <- if (length(d) == 2L) c(as.integer(d), 1L) else as.integer(d)
  target_dn <- if (!is.null(dn) && length(d) == 2L) c(dn, list(NULL)) else dn
  clean_voxels <- array(as.vector(voxels), dim = target_dim, dimnames = target_dn)

  if (!is.matrix(affine) || !is.numeric(affine) || !identical(dim(affine), c(4L, 4L))) {
    cli::cli_abort("{.arg affine} must be a 4x4 numeric matrix.")
  }
  if (any(!is.finite(affine))) {
    cli::cli_abort(
      "{.arg affine} must contain only finite numeric values (no {.val NA}, {.val NaN}, or {.val Inf})."
    )
  }
  if (max(abs(as.double(affine[4L, ]) - c(0.0, 0.0, 0.0, 1.0))) > 1e-12) {
    cli::cli_abort("Bottom row of {.arg affine} must equal {.code c(0, 0, 0, 1)}.")
  }
  clean_affine <- matrix(as.double(affine), nrow = 4L, ncol = 4L)
  clean_affine[4L, ] <- c(0.0, 0.0, 0.0, 1.0)

  if (missing(coord_system) || identical(coord_system, c("LPS", "RAS"))) {
    coord_system <- "LPS"
  }
  if (!is.character(coord_system) || length(coord_system) != 1L ||
      is.na(coord_system) || !(coord_system %in% c("LPS", "RAS"))) {
    cli::cli_abort("{.arg coord_system} must be either {.val LPS} or {.val RAS}.")
  }

  derived <- derive_geometry_from_affine(clean_affine)

  if (is.null(spacing)) {
    clean_spacing <- derived$spacing
  } else {
    if (!is.numeric(spacing) || length(spacing) != 3L ||
        any(!is.finite(spacing)) || any(spacing < 0)) {
      cli::cli_abort(
        "{.arg spacing} must be a finite non-negative numeric vector of length 3 ({.code c(dr, dc, dz)})."
      )
    }
    clean_spacing <- as.double(unname(spacing))
  }

  if (is.null(direction)) {
    clean_direction <- derived$direction
  } else {
    req_dir <- c("d_row", "d_col", "normal")
    if (!is.list(direction) || is.data.frame(direction) || !all(req_dir %in% names(direction))) {
      cli::cli_abort(
        "{.arg direction} must be a named list containing {.field d_row}, {.field d_col}, and {.field normal}."
      )
    }
    for (nm in req_dir) {
      vec <- direction[[nm]]
      if (!is.numeric(vec) || length(vec) != 3L || any(!is.finite(vec))) {
        cli::cli_abort("{.arg direction}${nm} must be a finite numeric vector of length 3.")
      }
    }
    clean_direction <- list(
      d_row = as.double(unname(direction$d_row)),
      d_col = as.double(unname(direction$d_col)),
      normal = as.double(unname(direction$normal))
    )
  }

  if (is.null(frame_meta)) {
    clean_frame_meta <- tibble::tibble()
  } else if (inherits(frame_meta, "data.frame")) {
    clean_frame_meta <- tibble::as_tibble(frame_meta)
  } else {
    cli::cli_abort("{.arg frame_meta} must be a {.cls tbl_df} or {.cls data.frame}.")
  }

  if (!is.list(uids) || is.data.frame(uids)) {
    cli::cli_abort("{.arg uids} must be a {.cls list}.")
  }

  if (is.null(modality)) modality <- NA_character_
  if (!is.character(modality) || length(modality) != 1L) {
    cli::cli_abort("{.arg modality} must be a single character string or {.val NA_character_}.")
  }

  if (is.null(units)) units <- NA_character_
  if (!is.character(units) || length(units) != 1L) {
    cli::cli_abort("{.arg units} must be a single character string or {.val NA_character_}.")
  }

  if (!is.list(diagnostics) || is.data.frame(diagnostics)) {
    cli::cli_abort("{.arg diagnostics} must be a {.cls list}.")
  }

  if (!is.list(provenance) || is.data.frame(provenance)) {
    cli::cli_abort("{.arg provenance} must be a {.cls list}.")
  }

  structure(
    list(
      voxels = clean_voxels,
      affine = clean_affine,
      coord_system = coord_system,
      spacing = clean_spacing,
      direction = clean_direction,
      frame_meta = clean_frame_meta,
      uids = uids,
      modality = modality,
      units = units,
      diagnostics = diagnostics,
      provenance = provenance
    ),
    class = "dicom_volume"
  )
}

#' Test Whether an Object Is a `dicom_volume`
#'
#' @param x An R object.
#' @return `TRUE` if `x` inherits from `"dicom_volume"`, otherwise `FALSE`.
#' @export
#' @examples
#' vol <- new_dicom_volume(array(0, dim = c(4L, 4L, 2L)))
#' is_dicom_volume(vol)
#' is_dicom_volume(array(0, dim = c(4L, 4L, 2L)))
is_dicom_volume <- function(x) {
  inherits(x, "dicom_volume")
}

#' @rdname new_dicom_volume
#' @param x A `dicom_volume` object.
#' @param ... Additional arguments passed to or from methods.
#' @export
dim.dicom_volume <- function(x) {
  dim(x$voxels)
}

#' @rdname new_dicom_volume
#' @export
as.array.dicom_volume <- function(x, ...) {
  array(x$voxels, dim = dim(x$voxels), dimnames = dimnames(x$voxels))
}

#' @rdname new_dicom_volume
#' @export
print.dicom_volume <- function(x, ...) {
  d <- dim(x$voxels)
  dim_str <- paste(d, collapse = "x")
  mod_str <- if (!is.na(x$modality) && nzchar(x$modality)) x$modality else "DICOM"
  unit_str <- if (!is.na(x$units) && nzchar(x$units)) sprintf(" | units=%s", x$units) else ""
  orig <- x$affine[1:3, 4L]
  sp <- x$spacing

  cat(sprintf(
    "<dicom_volume [%s] %s | coord=%s%s>\n",
    mod_str, dim_str, x$coord_system, unit_str
  ))
  cat(sprintf(
    "  spacing: (%.4g, %.4g, %.4g) mm | origin: (%.4g, %.4g, %.4g) mm\n",
    sp[1L], sp[2L], sp[3L], orig[1L], orig[2L], orig[3L]
  ))
  cat(sprintf(
    "  frame_meta: %d row(s) | provenance: %d step(s)\n",
    nrow(x$frame_meta), length(x$provenance)
  ))
  if (isTRUE(x$diagnostics$irregular_spacing)) {
    cat("  diagnostics: irregular slice/voxel spacing detected\n")
  }
  invisible(x)
}

# Internal helper: resolve a single dimension subscript into positive 1-based integers
resolve_axis_subscript <- function(quo, axis_len, axis_num, axis_names = NULL) {
  if (rlang::quo_is_missing(quo)) {
    return(seq_len(axis_len))
  }
  idx <- rlang::eval_tidy(quo)
  if (is.null(idx)) {
    return(integer(0))
  }
  if (is.logical(idx)) {
    if (anyNA(idx)) {
      cli::cli_abort("Subscript along dimension {axis_num} contains {.val NA} values.")
    }
    if (length(idx) == 1L) {
      idx <- rep(idx, axis_len)
    } else if (length(idx) != axis_len) {
      cli::cli_abort(
        "Logical subscript along dimension {axis_num} must have length 1 or {axis_len}, not {length(idx)}."
      )
    }
    return(which(idx))
  }
  if (is.character(idx)) {
    if (is.null(axis_names)) {
      cli::cli_abort("Dimension {axis_num} has no names for character subsetting.")
    }
    pos <- match(idx, axis_names)
    if (anyNA(pos)) {
      cli::cli_abort("Character subscript out of bounds along dimension {axis_num}.")
    }
    return(as.integer(pos))
  }
  if (!is.numeric(idx)) {
    cli::cli_abort("Invalid subscript type {.cls {class(idx)}} along dimension {axis_num}.")
  }
  if (any(!is.finite(idx))) {
    cli::cli_abort("Subscript along dimension {axis_num} contains non-finite or {.val NA} values.")
  }
  if (any(idx < 0) && any(idx > 0)) {
    cli::cli_abort("Cannot mix positive and negative subscripts along dimension {axis_num}.")
  }
  if (any(abs(idx) > axis_len)) {
    cli::cli_abort(
      "Subscript out of bounds along dimension {axis_num} (valid range: 1..{axis_len})."
    )
  }
  idx <- as.integer(idx)
  seq_len(axis_len)[idx]
}

#' Subset a `dicom_volume` While Preserving World Geometry
#'
#' Extracts a sub-volume from a 3D or 4D `dicom_volume`, automatically
#' shifting the physical origin `affine[1:3, 4]` to the world coordinate of
#' the new first voxel, scaling/flipping affine columns and `direction` /
#' `spacing` for strided or reversed index sequences, slicing `frame_meta`,
#' and flagging irregular spacing if non-uniform indices are supplied.
#'
#' @param x A `dicom_volume` object.
#' @param ... Row, column, slice (and optional 4th-dimension frame) subscripts.
#' @param drop Logical. Defaults to `FALSE`, preserving the `"dicom_volume"`
#'   container and 4x4 affine even when subsetting selects a single slice
#'   (`vol[, , 2]`) or crops a single-slice 2D modality (`dx_vol[2:8, 3:10, ]`).
#'   If `TRUE` and subsetting reduces any spatial dimension to length 1, returns
#'   the dropped base R matrix or vector; when subsetting a single temporal
#'   frame from a 4D volume (`vol[, , , 2, drop = TRUE]`) with all 3 spatial
#'   dimensions `> 1`, drops the 4th dimension and returns a 3D `dicom_volume`.
#'
#' @return A `dicom_volume` object (always when `drop = FALSE`, or when 3–4
#'   spatial/temporal dimensions remain under `drop = TRUE`), or a base R
#'   array/matrix/vector when `drop = TRUE` reduces spatial dimensions `< 3`.
#' @export
#' @examples
#' vox <- array(seq_len(10 * 12 * 6), dim = c(10L, 12L, 6L))
#' aff <- diag(c(0.5, 0.5, 2.0, 1.0))
#' vol <- new_dicom_volume(vox, affine = aff, modality = "CT")
#' sub <- vol[2:8, 3:10, 2:5]
#' dim(sub)
#' single <- vol[, , 2]
#' dim(single)
`[.dicom_volume` <- function(x, ..., drop = FALSE) {
  quos <- rlang::enquos(..., .ignore_empty = "none")
  dims <- dim(x$voxels)
  nd <- length(dims)

  # Empty bracket vol[] -> return volume unchanged
  if (length(quos) == 1L && rlang::quo_is_missing(quos[[1L]])) {
    return(x)
  }

  # Single linear 1D subscript vol[idx] -> delegate to underlying array
  if (length(quos) == 1L && !rlang::quo_is_missing(quos[[1L]])) {
    idx1 <- rlang::eval_tidy(quos[[1L]])
    return(x$voxels[idx1])
  }

  if (length(quos) != nd) {
    cli::cli_abort(
      "Incorrect number of dimensions for {.cls dicom_volume}: expected {nd} subscripts, got {length(quos)}."
    )
  }

  dn <- dimnames(x$voxels)
  pos_list <- lapply(seq_len(nd), function(m) {
    axis_nm <- if (!is.null(dn)) dn[[m]] else NULL
    resolve_axis_subscript(quos[[m]], dims[m], m, axis_nm)
  })

  if (any(lengths(pos_list) == 0L)) {
    if (isTRUE(drop)) {
      if (nd == 3L) {
        return(x$voxels[pos_list[[1L]], pos_list[[2L]], pos_list[[3L]], drop = TRUE])
      }
      return(x$voxels[pos_list[[1L]], pos_list[[2L]], pos_list[[3L]], pos_list[[4L]], drop = TRUE])
    }
    cli::cli_abort("Subsetting produced an empty dimension; a {.cls dicom_volume} must be non-empty.")
  }

  if (nd == 3L) {
    sub_vox <- x$voxels[pos_list[[1L]], pos_list[[2L]], pos_list[[3L]], drop = FALSE]
  } else {
    sub_vox <- x$voxels[pos_list[[1L]], pos_list[[2L]], pos_list[[3L]], pos_list[[4L]], drop = FALSE]
  }

  sub_dims <- dim(sub_vox)
  if (isTRUE(drop)) {
    # If any of the 3 spatial dimensions collapses to 1, spatial dimensionality < 3
    if (any(sub_dims[1:3] == 1L)) {
      if (nd == 3L) {
        return(x$voxels[pos_list[[1L]], pos_list[[2L]], pos_list[[3L]], drop = TRUE])
      }
      return(x$voxels[pos_list[[1L]], pos_list[[2L]], pos_list[[3L]], pos_list[[4L]], drop = TRUE])
    }
    # For 4D volumes where spatial dims > 1 and frame dim == 1, collapse to 3D dicom_volume
    if (nd == 4L && sub_dims[4L] == 1L) {
      sub_dn <- dimnames(sub_vox)
      sub_vox <- array(
        sub_vox,
        dim = sub_dims[1:3],
        dimnames = if (!is.null(sub_dn)) sub_dn[1:3] else NULL
      )
    }
  }

  # Compute spatial origin and per-axis strides for axes 1..3
  pos1 <- pos_list[[1L]]
  pos2 <- pos_list[[2L]]
  pos3 <- pos_list[[3L]]

  new_origin <- unname(as.double(
    voxel_to_world(x, c(pos1[1L], pos2[1L], pos3[1L]), index_base = 1L)
  ))

  axis_step_info <- function(pos) {
    n <- length(pos)
    if (n <= 1L) {
      return(list(stride = 1.0, uniform = TRUE))
    }
    diffs <- diff(pos)
    if (all(diffs == diffs[1L]) && diffs[1L] != 0L) {
      list(stride = as.double(diffs[1L]), uniform = TRUE)
    } else {
      list(
        stride = as.double(pos[n] - pos[1L]) / (n - 1.0),
        uniform = FALSE
      )
    }
  }

  st1 <- axis_step_info(pos1)
  st2 <- axis_step_info(pos2)
  st3 <- axis_step_info(pos3)

  new_diag <- x$diagnostics
  if (!st1$uniform || !st2$uniform || !st3$uniform) {
    new_diag$irregular_spacing <- TRUE
    cli::cli_warn(
      "Non-uniform subsetting indices break regular voxel spacing; setting {.code diagnostics$irregular_spacing = TRUE}."
    )
  }

  new_affine <- x$affine
  new_affine[1:3, 1L] <- x$affine[1:3, 1L] * st1$stride + 0.0
  new_affine[1:3, 2L] <- x$affine[1:3, 2L] * st2$stride + 0.0
  new_affine[1:3, 3L] <- x$affine[1:3, 3L] * st3$stride + 0.0
  new_affine[1:3, 4L] <- new_origin + 0.0
  new_affine[4L, ] <- c(0.0, 0.0, 0.0, 1.0)

  new_spacing <- c(
    x$spacing[1L] * abs(st1$stride),
    x$spacing[2L] * abs(st2$stride),
    x$spacing[3L] * abs(st3$stride)
  )

  sign1 <- if (st1$stride < 0) -1.0 else 1.0
  sign2 <- if (st2$stride < 0) -1.0 else 1.0
  new_d_col <- x$direction$d_col * sign1 + 0.0
  new_d_row <- x$direction$d_row * sign2 + 0.0
  n_raw <- vol_cross3(new_d_row, new_d_col)
  n_len <- sqrt(sum(n_raw^2))
  new_normal <- if (n_len > 1e-12) {
    n_raw / n_len + 0.0
  } else {
    x$direction$normal * (sign1 * sign2) + 0.0
  }
  new_direction <- list(
    d_row = unname(new_d_row),
    d_col = unname(new_d_col),
    normal = unname(new_normal)
  )

  # Subset frame_meta consistently
  n_meta <- nrow(x$frame_meta)
  if (nd == 3L) {
    new_frame_meta <- if (n_meta == dims[3L]) {
      x$frame_meta[pos3, , drop = FALSE]
    } else {
      x$frame_meta
    }
  } else {
    pos4 <- pos_list[[4L]]
    if (n_meta == dims[3L] * dims[4L]) {
      grid_idx <- as.vector(outer(pos3, (pos4 - 1L) * dims[3L], "+"))
      new_frame_meta <- x$frame_meta[grid_idx, , drop = FALSE]
    } else if (n_meta == dims[3L]) {
      new_frame_meta <- x$frame_meta[pos3, , drop = FALSE]
    } else if (n_meta == dims[4L]) {
      new_frame_meta <- x$frame_meta[pos4, , drop = FALSE]
    } else {
      new_frame_meta <- x$frame_meta
    }
  }

  new_prov <- append_provenance(
    x$provenance,
    action = "subset",
    params = list(dims_before = dims, dims_after = dim(sub_vox))
  )

  new_dicom_volume(
    voxels = sub_vox,
    affine = new_affine,
    coord_system = x$coord_system,
    spacing = new_spacing,
    direction = new_direction,
    frame_meta = new_frame_meta,
    uids = x$uids,
    modality = x$modality,
    units = x$units,
    diagnostics = new_diag,
    provenance = new_prov
  )
}

#' Plot a `dicom_volume` Object
#'
#' Visualizes a 3D/4D `dicom_volume` as a 3-plane orthogonal Multi-Planar
#' Reconstruction (`method = "mpr"`) or Maximum Intensity Projection
#' (`method = "mip"`) via [render_volume()], or renders a single 2D slice via
#' [ggdicom()] when `dim(x)[3] == 1` or `slice` is specified.
#'
#' @param x A `dicom_volume` object.
#' @param y Unused (included for S3 generic compatibility with [base::plot()]).
#'   If supplied as a single numeric value while `slice` is `NULL`, treated as
#'   `slice`.
#' @param ... Additional arguments passed to [ggdicom()] for single-slice
#'   rendering (e.g. `center`, `width`, `annotate`, `title`).
#' @param slice Optional 1-based integer slice index to plot a single 2D slice.
#' @param method Volume rendering mode when plotting 3D volumes: `"mpr"`
#'   (default), `"mip"`, or `"rgl"`.
#' @param window Window preset (`"auto"`, `"brain"`, `"lung"`, `"bone"`, etc.)
#'   or `c(center, width)`. Default is `"auto"`.
#' @param threshold Intensity threshold in `[0, 1]` when `method = "rgl"`.
#'   Default is `0.5`.
#' @param palette Color palette (`"gray"`, `"viridis"`, `"inferno"`, `"magma"`,
#'   `"plasma"`). Default is `"gray"`.
#' @param frame 1-based temporal frame index when `x` is a 4D volume. Default
#'   is `1L`.
#'
#' @return A [ggplot2::ggplot] object (or invisibly the `rgl` scene ID when
#'   `method = "rgl"` and `rgl` is installed).
#' @export
#' @examples
#' vox <- array(seq_len(12 * 12 * 4), dim = c(12L, 12L, 4L))
#' vol <- new_dicom_volume(vox, affine = diag(c(0.8, 0.8, 2.5, 1.0)), modality = "CT")
#' plot(vol, method = "mpr")
#' plot(vol, slice = 2L)
plot.dicom_volume <- function(x,
                              y = NULL,
                              ...,
                              slice = NULL,
                              method = c("mpr", "mip", "rgl"),
                              window = "auto",
                              threshold = 0.5,
                              palette = c("gray", "viridis", "inferno", "magma", "plasma"),
                              frame = 1L) {
  method <- match.arg(method)
  palette <- match.arg(palette)

  if (!is.null(y) && is.null(slice) && is.numeric(y) && length(y) == 1L) {
    slice <- y
  }

  d <- dim(x$voxels)
  f_idx <- 1L
  if (length(d) == 4L) {
    if (!is.numeric(frame) || length(frame) != 1L || !is.finite(frame) ||
        frame < 1 || frame > d[4L]) {
      cli::cli_abort("{.arg frame} must be an integer between 1 and {d[4L]}.")
    }
    f_idx <- as.integer(frame)
    arr3 <- array(x$voxels[, , , f_idx], dim = d[1:3])
  } else {
    arr3 <- x$voxels
  }

  use_single_slice <- !is.null(slice) || d[3L] == 1L
  s_idx <- 1L
  if (!is.null(slice)) {
    if (!is.numeric(slice) || length(slice) != 1L || !is.finite(slice) ||
        slice < 1 || slice > d[3L]) {
      cli::cli_abort("{.arg slice} must be a single integer between 1 and {d[3L]}.")
    }
    s_idx <- as.integer(slice)
  }

  mod_val <- if (!is.na(x$modality) && nzchar(x$modality)) x$modality else NULL
  attr(arr3, "modality") <- mod_val
  attr(arr3, "pixel_spacing") <- x$spacing[1:2]

  n_meta <- nrow(x$frame_meta)
  if (n_meta > 0L) {
    meta_row <- if (use_single_slice && n_meta == d[3L]) {
      s_idx
    } else if (use_single_slice && length(d) == 4L && n_meta == d[3L] * d[4L]) {
      s_idx + (f_idx - 1L) * d[3L]
    } else {
      1L
    }
    if ("PhotometricInterpretation" %in% names(x$frame_meta)) {
      attr(arr3, "photometric") <- as.character(x$frame_meta$PhotometricInterpretation[meta_row])
    }
    if ("WindowCenter" %in% names(x$frame_meta)) {
      wc_raw <- strsplit(as.character(x$frame_meta$WindowCenter[meta_row]), "\\\\", fixed = FALSE)[[1L]][1L]
      wc_num <- suppressWarnings(as.numeric(wc_raw))
      if (is.finite(wc_num)) attr(arr3, "window_center") <- wc_num
    }
    if ("WindowWidth" %in% names(x$frame_meta)) {
      ww_raw <- strsplit(as.character(x$frame_meta$WindowWidth[meta_row]), "\\\\", fixed = FALSE)[[1L]][1L]
      ww_num <- suppressWarnings(as.numeric(ww_raw))
      if (is.finite(ww_num) && ww_num > 0) attr(arr3, "window_width") <- ww_num
    }
  }

  if (use_single_slice) {
    mat <- matrix(arr3[, , s_idx], nrow = d[1L], ncol = d[2L])
    for (nm in c("modality", "pixel_spacing", "photometric", "window_center", "window_width")) {
      attr(mat, nm) <- attr(arr3, nm)
    }
    return(ggdicom(mat, window = window, palette = palette, ...))
  }

  render_volume(
    arr3,
    method = method,
    window = window,
    threshold = threshold,
    palette = palette
  )
}

#' Convert a `dicom_volume` Between DICOM LPS and NIfTI RAS World Coordinates
#'
#' Transforms the 4x4 physical world affine and direction cosines of a
#' `dicom_volume` between the DICOM Patient Coordinate System (`"LPS"`:
#' Left-Posterior-Superior) and the neuroimaging NIfTI standard (`"RAS"`:
#' Right-Anterior-Superior) via `diag(c(-1, -1, 1, 1)) %*% affine`.
#'
#' Because `det(diag(-1, -1, 1)) == +1` (a 180-degree rotation around the
#' Superior `z` axis), right-handedness of `(d_row, d_col, normal)` is strictly
#' preserved without permuting in-memory voxel indices. Both functions are
#' idempotent when `vol` is already in the target coordinate system.
#'
#' @param vol A `dicom_volume` object.
#'
#' @return A `dicom_volume` object in the target coordinate system (`"RAS"` for
#'   `to_ras()`, `"LPS"` for `to_lps()`).
#' @export
#' @examples
#' aff <- diag(c(0.8, 0.8, 2.5, 1.0))
#' aff[1:3, 4] <- c(-100, -120, 50)
#' vol <- new_dicom_volume(array(0, dim = c(8L, 8L, 4L)), affine = aff, coord_system = "LPS")
#' vol_ras <- to_ras(vol)
#' vol_ras$affine[1:3, 4]
#' vol_lps <- to_lps(vol_ras)
#' all.equal(vol_lps$affine, vol$affine)
to_ras <- function(vol) {
  if (!is_dicom_volume(vol)) {
    cli::cli_abort("{.arg vol} must be a {.cls dicom_volume} object.")
  }
  if (identical(vol$coord_system, "RAS")) {
    return(vol)
  }

  m_flip <- diag(c(-1.0, -1.0, 1.0, 1.0))
  new_affine <- m_flip %*% vol$affine + 0.0
  new_affine[4L, ] <- c(0.0, 0.0, 0.0, 1.0)

  flip3 <- c(-1.0, -1.0, 1.0)
  new_direction <- list(
    d_row = unname(vol$direction$d_row * flip3 + 0.0),
    d_col = unname(vol$direction$d_col * flip3 + 0.0),
    normal = unname(vol$direction$normal * flip3 + 0.0)
  )

  vol$affine <- new_affine
  vol$direction <- new_direction
  vol$coord_system <- "RAS"
  append_provenance(vol, action = "to_ras", params = list(from = "LPS", to = "RAS"))
}

#' @rdname to_ras
#' @export
to_lps <- function(vol) {
  if (!is_dicom_volume(vol)) {
    cli::cli_abort("{.arg vol} must be a {.cls dicom_volume} object.")
  }
  if (identical(vol$coord_system, "LPS")) {
    return(vol)
  }

  m_flip <- diag(c(-1.0, -1.0, 1.0, 1.0))
  new_affine <- m_flip %*% vol$affine + 0.0
  new_affine[4L, ] <- c(0.0, 0.0, 0.0, 1.0)

  flip3 <- c(-1.0, -1.0, 1.0)
  new_direction <- list(
    d_row = unname(vol$direction$d_row * flip3 + 0.0),
    d_col = unname(vol$direction$d_col * flip3 + 0.0),
    normal = unname(vol$direction$normal * flip3 + 0.0)
  )

  vol$affine <- new_affine
  vol$direction <- new_direction
  vol$coord_system <- "LPS"
  append_provenance(vol, action = "to_lps", params = list(from = "RAS", to = "LPS"))
}

#' @rdname to_ras
#' @export
dicom_to_ras <- to_ras

#' @rdname to_ras
#' @export
dicom_to_lps <- to_lps

#' Query Anatomical Orientation of a DICOM Volume
#'
#' Determines the standard 3-letter anatomical coordinate orientation
#' (e.g., `"LPS"`, `"RAS"`) of a `dicom_volume` or orientation matrix.
#'
#' @param vol A `dicom_volume` object, or a 4x4 / 3x3 numeric affine/direction matrix.
#' @return A length-1 character string naming the coordinate orientation (e.g. `"LPS"`, `"RAS"`).
#' @export
#' @examples
#' aff <- diag(c(0.8, 0.8, 2.5, 1.0))
#' vol <- new_dicom_volume(array(0, dim = c(8L, 8L, 4L)), affine = aff, coord_system = "LPS")
#' dicom_orientation(vol)
dicom_orientation <- function(vol) {
  if (is_dicom_volume(vol)) {
    if (!is.null(vol$coord_system) && nzchar(vol$coord_system)) {
      return(as.character(vol$coord_system))
    }
  } else if (!is.matrix(vol)) {
    cli::cli_abort("{.arg vol} must be a {.cls dicom_volume} or numeric matrix.")
  }
  "LPS"
}

#' Map Between Voxel Indices and Physical World Coordinates
#'
#' Maps 3D voxel coordinates `(r, c, s)` to physical world coordinates
#' `(x, y, z)` in millimeters (in `vol$coord_system`, `"LPS"` or `"RAS"`) and
#' vice versa using `vol$affine`, supporting both R's 1-based indexing
#' (`index_base = 1L`) and DICOM/C/NIfTI 0-based indexing (`index_base = 0L`).
#'
#' @param vol A `dicom_volume` object.
#' @param ijk Numeric vector of length 3 (`c(r, c, s)`) or `N x 3` numeric
#'   matrix of voxel indices.
#' @param xyz Numeric vector of length 3 (`c(x, y, z)`) or `N x 3` numeric
#'   matrix of physical world coordinates in millimeters.
#' @param index_base Integer indexing base: `1L` (default, R 1-based where
#'   `c(1, 1, 1)` maps to `vol$affine[1:3, 4]`) or `0L` (0-based where
#'   `c(0, 0, 0)` maps to `vol$affine[1:3, 4]`).
#'
#' @return For a length-3 vector input, a named length-3 numeric vector
#'   (`c(x = ..., y = ..., z = ...)` for `voxel_to_world()`,
#'   `c(r = ..., c = ..., s = ...)` for `world_to_voxel()`). For an `N x 3`
#'   matrix input, an `N x 3` numeric matrix.
#' @export
#' @examples
#' aff <- diag(c(0.8, 0.8, 2.5, 1.0))
#' aff[1:3, 4] <- c(-16, -16, 0)
#' vol <- new_dicom_volume(array(0, dim = c(32L, 32L, 8L)), affine = aff)
#' w <- voxel_to_world(vol, c(1, 1, 1), index_base = 1L)
#' w
#' world_to_voxel(vol, w, index_base = 1L)
voxel_to_world <- function(vol, ijk, index_base = 1L) {
  if (!is_dicom_volume(vol)) {
    cli::cli_abort("{.arg vol} must be a {.cls dicom_volume} object.")
  }
  if (!is.numeric(index_base) || length(index_base) != 1L ||
      is.na(index_base) || !(index_base %in% c(0, 1))) {
    cli::cli_abort("{.arg index_base} must be {.val {0L}} or {.val {1L}}.")
  }
  if (!is.numeric(ijk) || any(!is.finite(ijk))) {
    cli::cli_abort("{.arg ijk} must be a finite numeric length-3 vector or N x 3 matrix.")
  }

  base_offset <- as.double(index_base)
  m33 <- vol$affine[1:3, 1:3, drop = FALSE]
  t_vec <- vol$affine[1:3, 4L]

  if (is.null(dim(ijk))) {
    if (length(ijk) != 3L) {
      cli::cli_abort("{.arg ijk} vector must have length 3 ({.code c(r, c, s)}), not {length(ijk)}.")
    }
    v0 <- as.double(ijk) - base_offset
    out <- as.double(m33 %*% v0 + t_vec)
    names(out) <- c("x", "y", "z")
    return(out)
  }

  if (!is.matrix(ijk) || ncol(ijk) != 3L) {
    cli::cli_abort("{.arg ijk} matrix must be a 2D numeric matrix with 3 columns.")
  }
  n_pts <- nrow(ijk)
  if (n_pts == 0L) {
    return(matrix(numeric(0), nrow = 0L, ncol = 3L))
  }
  mat0 <- matrix(as.double(ijk) - base_offset, nrow = n_pts, ncol = 3L)
  out <- mat0 %*% t(m33) + matrix(t_vec, nrow = n_pts, ncol = 3L, byrow = TRUE)
  dimnames(out) <- NULL
  out
}

#' @rdname voxel_to_world
#' @export
world_to_voxel <- function(vol, xyz, index_base = 1L) {
  if (!is_dicom_volume(vol)) {
    cli::cli_abort("{.arg vol} must be a {.cls dicom_volume} object.")
  }
  if (!is.numeric(index_base) || length(index_base) != 1L ||
      is.na(index_base) || !(index_base %in% c(0, 1))) {
    cli::cli_abort("{.arg index_base} must be {.val {0L}} or {.val {1L}}.")
  }
  if (!is.numeric(xyz) || any(!is.finite(xyz))) {
    cli::cli_abort("{.arg xyz} must be a finite numeric length-3 vector or N x 3 matrix.")
  }

  base_offset <- as.double(index_base)
  m33 <- vol$affine[1:3, 1:3, drop = FALSE]
  t_vec <- vol$affine[1:3, 4L]

  det_val <- det(m33)
  if (!is.finite(det_val) || det_val == 0 || rcond(m33) < 1e-14) {
    cli::cli_abort(
      "Cannot invert singular {.field affine} matrix in {.fn world_to_voxel} (determinant = {signif(det_val, 4)})."
    )
  }

  solve_safe <- function(rhs) {
    tryCatch(
      solve(m33, rhs),
      error = function(e) {
        cli::cli_abort(
          "Cannot invert singular {.field affine} matrix in {.fn world_to_voxel}: {conditionMessage(e)}"
        )
      }
    )
  }

  if (is.null(dim(xyz))) {
    if (length(xyz) != 3L) {
      cli::cli_abort("{.arg xyz} vector must have length 3 ({.code c(x, y, z)}), not {length(xyz)}.")
    }
    v0 <- as.double(solve_safe(as.double(xyz) - t_vec))
    out <- v0 + base_offset
    names(out) <- c("r", "c", "s")
    return(out)
  }

  if (!is.matrix(xyz) || ncol(xyz) != 3L) {
    cli::cli_abort("{.arg xyz} matrix must be a 2D numeric matrix with 3 columns.")
  }
  n_pts <- nrow(xyz)
  if (n_pts == 0L) {
    return(matrix(numeric(0), nrow = 0L, ncol = 3L))
  }
  mat_w <- matrix(as.double(xyz), nrow = n_pts, ncol = 3L)
  shifted <- sweep(mat_w, 2L, t_vec, FUN = "-")
  v0 <- t(solve_safe(t(shifted)))
  out <- matrix(as.double(v0) + base_offset, nrow = n_pts, ncol = 3L)
  out
}
