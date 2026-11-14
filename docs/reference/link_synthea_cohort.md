# Link Synthea FHIR Clinical Bundles With Local DICOM Studies

Reads Synthea FHIR `Bundle` JSON files from `fhir_dir` (`Patient`,
`Condition`, and `ImagingStudy` resources) and joins them with DICOM
series metadata from `dicom_source` by `StudyInstanceUID` or
`PatientID`.

## Usage

``` r
link_synthea_cohort(dicom_source, fhir_dir)
```

## Arguments

- dicom_source:

  A DICOM directory path or header data frame from
  [`read_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom.md).

- fhir_dir:

  Directory containing Synthea FHIR `.json` bundle files.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
joining clinical patient/condition fields with DICOM study/series
metadata.
