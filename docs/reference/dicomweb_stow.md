# Store DICOM Instances via STOW-RS

Store DICOM Instances via STOW-RS

## Usage

``` r
dicomweb_stow(conn, files, study_uid = NULL)
```

## Arguments

- conn:

  A `"dicom_connection"` object.

- files:

  Character vector of `.dcm` file paths to upload.

- study_uid:

  Optional target `StudyInstanceUID` path suffix.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
summarizing per-file store status.
