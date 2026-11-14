# Retrieve DICOMweb Study/Series Metadata (WADO-RS Metadata)

Retrieve DICOMweb Study/Series Metadata (WADO-RS Metadata)

## Usage

``` r
dicomweb_metadata(conn, study_uid, series_uid = NULL)
```

## Arguments

- conn:

  A `"dicom_connection"` object.

- study_uid:

  `StudyInstanceUID` string.

- series_uid:

  Optional `SeriesInstanceUID` string.

## Value

A list of PS3.18 DICOM JSON objects (one per instance).
