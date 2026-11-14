# Query a DICOMweb Endpoint Using QIDO-RS

Query a DICOMweb Endpoint Using QIDO-RS

## Usage

``` r
dicomweb_qido(
  conn,
  level = c("studies", "series", "instances"),
  study_uid = NULL,
  series_uid = NULL,
  ...
)
```

## Arguments

- conn:

  A `"dicom_connection"` object with `dicomweb_url` (or `local_dir`).

- level:

  Query resource level: `"studies"`, `"series"`, or `"instances"`.

- study_uid:

  Optional `StudyInstanceUID` when querying `"series"` or `"instances"`.

- series_uid:

  Optional `SeriesInstanceUID` when querying `"instances"`.

- ...:

  Optional query parameters (e.g., `Modality = "CT"`,
  `PatientID = "123"`).

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
of matching records.
