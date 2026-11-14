# Retrieve DICOM Instances via WADO-RS

Retrieve DICOM Instances via WADO-RS

## Usage

``` r
dicomweb_wado(
  conn,
  study_uid,
  series_uid = NULL,
  out_dir = tempfile("dw_wado_")
)
```

## Arguments

- conn:

  A `"dicom_connection"` object.

- study_uid:

  `StudyInstanceUID` string.

- series_uid:

  Optional `SeriesInstanceUID` string.

- out_dir:

  Output directory for retrieved `.dcm` files.

## Value

Character vector of retrieved file paths.
