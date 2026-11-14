#' Export Volumes and Segmentations in nnU-Net v2 Format
#'
#' Writes a cohort of [`dicom_volume`][new_dicom_volume] and
#' [`dicom_seg`] objects into an nnU-Net v2 directory tree
#' (`Dataset<id>_<name>/imagesTr`, `labelsTr`, and `dataset.json`).
#'
#' @param volumes Named list of [`dicom_volume`][new_dicom_volume] objects.
#' @param segmentations Named list of [`dicom_seg`] objects matching `volumes`.
#' @param out_dir Root output directory where the nnU-Net dataset folder will
#'   be created.
#' @param dataset_name Short dataset name (alphanumeric/underscores).
#' @param dataset_id Integer dataset ID (e.g., `101L`).
#' @param channel_names Named list mapping zero-indexed channel strings to
#'   modality names (default `list("0" = "CT")`).
#' @param file_ending NIfTI file extension (`".nii.gz"` or `".nii"`).
#'
#' @return Invisibly returns a list with `dataset_dir`, `dataset_json`,
#'   `images_dir`, and `labels_dir`.
#' @export
export_nnunet <- function(volumes,
                          segmentations,
                          out_dir,
                          dataset_name,
                          dataset_id = 101L,
                          channel_names = list("0" = "CT"),
                          file_ending = ".nii.gz") {
  if (!is.list(volumes) || length(volumes) == 0L || is.null(names(volumes))) {
    cli::cli_abort("{.arg volumes} must be a non-empty named list.")
  }
  if (!is.list(segmentations) || length(segmentations) != length(volumes)) {
    cli::cli_abort("{.arg segmentations} must be a list matching {.arg volumes}.")
  }
  if (!is.character(out_dir) || length(out_dir) != 1L || !nzchar(out_dir)) {
    cli::cli_abort("{.arg out_dir} must be a single non-empty directory path.")
  }
  if (!is.character(dataset_name) || length(dataset_name) != 1L || !nzchar(dataset_name)) {
    cli::cli_abort("{.arg dataset_name} must be a non-empty string.")
  }

  ds_folder <- sprintf("Dataset%03d_%s", as.integer(dataset_id), dataset_name)
  dataset_dir <- file.path(out_dir, ds_folder)
  images_dir <- file.path(dataset_dir, "imagesTr")
  labels_dir <- file.path(dataset_dir, "labelsTr")
  dir.create(images_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(labels_dir, recursive = TRUE, showWarnings = FALSE)

  labels <- list(background = 0L)
  case_ids <- names(volumes)

  for (i in seq_along(case_ids)) {
    cid <- case_ids[i]
    vol <- volumes[[cid]]
    seg <- if (!is.null(names(segmentations)) && cid %in% names(segmentations)) {
      segmentations[[cid]]
    } else {
      segmentations[[i]]
    }

    img_path <- file.path(images_dir, paste0(cid, "_0000", file_ending))
    lbl_path <- file.path(labels_dir, paste0(cid, file_ending))
    write_nifti(vol, img_path, json_sidecar = FALSE)
    write_nifti(seg, lbl_path, json_sidecar = FALSE)

    if (inherits(seg, "dicom_seg") && !is.null(seg$segments) && nrow(seg$segments) > 0L) {
      for (r in seq_len(nrow(seg$segments))) {
        lbl_name <- as.character(seg$segments$label[r])
        seg_id <- as.integer(seg$segments$segment_id[r])
        if (nzchar(lbl_name) && !(lbl_name %in% names(labels))) {
          labels[[lbl_name]] <- seg_id
        }
      }
    }
  }

  dataset_meta <- list(
    channel_names = channel_names,
    labels = labels,
    numTraining = as.integer(length(case_ids)),
    file_ending = file_ending
  )
  dataset_json <- file.path(dataset_dir, "dataset.json")
  jsonlite::write_json(dataset_meta, dataset_json, auto_unbox = TRUE, pretty = TRUE)

  invisible(list(
    dataset_dir = dataset_dir,
    dataset_json = dataset_json,
    images_dir = images_dir,
    labels_dir = labels_dir
  ))
}

#' Export Volumes and Segmentations in MONAI Datalist Format
#'
#' Writes NIfTI image/label pairs and a MONAI-compatible `datalist.json`
#' grouped by split (`training`, `validation`, `testing`, etc.).
#'
#' @param volumes Named list of [`dicom_volume`][new_dicom_volume] objects.
#' @param segmentations Named list of [`dicom_seg`] objects matching `volumes`.
#' @param splits Character vector of split names matching `volumes` (default
#'   all `"training"`).
#' @param out_dir Output directory for images, labels, and `datalist.json`.
#' @param dataset_name Optional dataset name stored in the return object.
#' @param file_ending NIfTI file extension (`".nii.gz"` or `".nii"`).
#'
#' @return Invisibly returns a list with `out_dir`, `datalist_json`, and
#'   `dataset_name`.
#' @export
export_monai <- function(volumes,
                         segmentations,
                         splits = NULL,
                         out_dir,
                         dataset_name = "dicomtk_monai",
                         file_ending = ".nii.gz") {
  if (!is.list(volumes) || length(volumes) == 0L) {
    cli::cli_abort("{.arg volumes} must be a non-empty list.")
  }
  if (!is.list(segmentations) || length(segmentations) != length(volumes)) {
    cli::cli_abort("{.arg segmentations} must be a list matching {.arg volumes}.")
  }
  if (is.null(splits)) {
    splits <- rep("training", length(volumes))
  }
  if (!is.character(splits) || length(splits) != length(volumes)) {
    cli::cli_abort("{.arg splits} must be a character vector matching {.arg volumes}.")
  }
  if (!is.character(out_dir) || length(out_dir) != 1L || !nzchar(out_dir)) {
    cli::cli_abort("{.arg out_dir} must be a single non-empty directory path.")
  }

  images_dir <- file.path(out_dir, "images")
  labels_dir <- file.path(out_dir, "labels")
  dir.create(images_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(labels_dir, recursive = TRUE, showWarnings = FALSE)

  case_ids <- names(volumes)
  if (is.null(case_ids)) {
    case_ids <- sprintf("case_%03d", seq_along(volumes))
  }

  datalist <- list()
  for (i in seq_along(case_ids)) {
    cid <- case_ids[i]
    sp <- splits[i]
    img_rel <- file.path("images", paste0(cid, file_ending))
    lbl_rel <- file.path("labels", paste0(cid, file_ending))

    write_nifti(volumes[[i]], file.path(out_dir, img_rel), json_sidecar = FALSE)
    write_nifti(segmentations[[i]], file.path(out_dir, lbl_rel), json_sidecar = FALSE)

    if (is.null(datalist[[sp]])) {
      datalist[[sp]] <- list()
    }
    datalist[[sp]][[length(datalist[[sp]]) + 1L]] <- list(
      image = img_rel,
      label = lbl_rel
    )
  }

  datalist_json <- file.path(out_dir, "datalist.json")
  jsonlite::write_json(datalist, datalist_json, auto_unbox = TRUE, pretty = TRUE)

  invisible(list(
    out_dir = out_dir,
    datalist_json = datalist_json,
    dataset_name = dataset_name
  ))
}

#' Export RO-Crate 1.1 Dataset Metadata
#'
#' Generates an RO-Crate 1.1 compliant `ro-crate-metadata.json` file in
#' `out_dir`.
#'
#' @param out_dir Directory where `ro-crate-metadata.json` will be written.
#' @param name Dataset title.
#' @param description Dataset description.
#' @param files Optional character vector of relative file paths to include in
#'   the crate graph.
#' @param license SPDX license identifier (default `"CC-BY-4.0"`).
#'
#' @return Invisibly returns the path to `ro-crate-metadata.json`.
#' @export
export_rocrate <- function(out_dir,
                           name,
                           description,
                           files = NULL,
                           license = "CC-BY-4.0") {
  if (!is.character(out_dir) || length(out_dir) != 1L || !nzchar(out_dir)) {
    cli::cli_abort("{.arg out_dir} must be a single non-empty directory path.")
  }
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  parts <- if (!is.null(files) && length(files) > 0L) {
    lapply(as.character(files), function(f) list(`@id` = f))
  } else {
    list()
  }

  graph <- list(
    list(
      `@type` = "CreativeWork",
      `@id` = "ro-crate-metadata.json",
      conformsTo = list(`@id` = "https://w3id.org/ro/crate/1.1"),
      about = list(`@id` = "./")
    ),
    list(
      `@id` = "./",
      `@type` = "Dataset",
      name = as.character(name)[1L],
      description = as.character(description)[1L],
      license = as.character(license)[1L],
      hasPart = parts
    )
  )

  if (!is.null(files) && length(files) > 0L) {
    for (f in as.character(files)) {
      graph[[length(graph) + 1L]] <- list(`@id` = f, `@type` = "File")
    }
  }

  payload <- list(
    `@context` = "https://w3id.org/ro/crate/1.1/context",
    `@graph` = graph
  )

  rc_path <- file.path(out_dir, "ro-crate-metadata.json")
  jsonlite::write_json(payload, rc_path, auto_unbox = TRUE, pretty = TRUE)
  invisible(rc_path)
}

#' Export MLCommons Croissant 1.0 Dataset Metadata
#'
#' Generates an MLCommons Croissant 1.0 compliant `croissant.json` file in
#' `out_dir`.
#'
#' @param out_dir Directory where `croissant.json` will be written.
#' @param name Dataset title.
#' @param description Dataset description.
#' @param num_records Optional integer count of records in the dataset.
#' @param license SPDX license identifier (default `"CC-BY-4.0"`).
#'
#' @return Invisibly returns the path to `croissant.json`.
#' @export
export_croissant <- function(out_dir,
                             name,
                             description,
                             num_records = NULL,
                             license = "CC-BY-4.0") {
  if (!is.character(out_dir) || length(out_dir) != 1L || !nzchar(out_dir)) {
    cli::cli_abort("{.arg out_dir} must be a single non-empty directory path.")
  }
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  payload <- list(
    `@context` = "https://schema.org/",
    `@type` = "Dataset",
    conformsTo = "http://mlcommons.org/croissant/1.0",
    name = as.character(name)[1L],
    description = as.character(description)[1L],
    license = as.character(license)[1L]
  )

  if (!is.null(num_records)) {
    payload$recordSet <- list(
      list(
        `@type` = "cr:RecordSet",
        name = "cases",
        description = sprintf("Dataset cases (%d records)", as.integer(num_records)[1L])
      )
    )
  }

  cr_path <- file.path(out_dir, "croissant.json")
  jsonlite::write_json(payload, cr_path, auto_unbox = TRUE, pretty = TRUE)
  invisible(cr_path)
}
