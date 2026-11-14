# Export Volumes and Segmentations in MONAI Datalist Format

Writes NIfTI image/label pairs and a MONAI-compatible `datalist.json`
grouped by split (`training`, `validation`, `testing`, etc.).

## Usage

``` r
export_monai(
  volumes,
  segmentations,
  splits = NULL,
  out_dir,
  dataset_name = "dicomtk_monai",
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

- splits:

  Character vector of split names matching `volumes` (default all
  `"training"`).

- out_dir:

  Output directory for images, labels, and `datalist.json`.

- dataset_name:

  Optional dataset name stored in the return object.

- file_ending:

  NIfTI file extension (`".nii.gz"` or `".nii"`).

## Value

Invisibly returns a list with `out_dir`, `datalist_json`, and
`dataset_name`.
