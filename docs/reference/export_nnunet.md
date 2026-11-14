# Export Volumes and Segmentations in nnU-Net v2 Format

Writes a cohort of
[`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
and
[`dicom_seg`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
objects into an nnU-Net v2 directory tree
(`Dataset<id>_<name>/imagesTr`, `labelsTr`, and `dataset.json`).

## Usage

``` r
export_nnunet(
  volumes,
  segmentations,
  out_dir,
  dataset_name,
  dataset_id = 101L,
  channel_names = list(`0` = "CT"),
  file_ending = ".nii.gz"
)
```

## Arguments

- volumes:

  Named list of
  [`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  objects.

- segmentations:

  Named list of
  [`dicom_seg`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
  objects matching `volumes`.

- out_dir:

  Root output directory where the nnU-Net dataset folder will be
  created.

- dataset_name:

  Short dataset name (alphanumeric/underscores).

- dataset_id:

  Integer dataset ID (e.g., `101L`).

- channel_names:

  Named list mapping zero-indexed channel strings to modality names
  (default `list("0" = "CT")`).

- file_ending:

  NIfTI file extension (`".nii.gz"` or `".nii"`).

## Value

Invisibly returns a list with `dataset_dir`, `dataset_json`,
`images_dir`, and `labels_dir`.
