# Map DICOM Studies and Series to OHDSI OMOP `IMAGE_OCCURRENCE`

Converts a
[`dicom_index_build()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_index_build.md)
index, DICOM directory path, or header tibble into a standard OHDSI
Medical Imaging CDM (`MI-CDM`) `image_occurrence` table using the
bundled
[omop_imaging_concepts](https://lauyeehow1986-hub.github.io/dicomtk/reference/omop_imaging_concepts.md)
crosswalk.

## Usage

``` r
to_omop_image_occurrence(source, person_map = NULL, wadors_base = NULL)
```

## Arguments

- source:

  A `dicom_archive_index`, DICOM directory path, or header data frame
  from
  [`read_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom.md).

- person_map:

  Optional named integer vector mapping `PatientID` strings to integer
  OMOP `person_id` values.

- wadors_base:

  Optional base DICOMweb WADO-RS URL for constructing `wadors_uri`
  values.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
conforming to OHDSI `image_occurrence`.
