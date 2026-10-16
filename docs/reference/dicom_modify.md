# Modify, Insert, or Delete DICOM Header Tags

Updates, inserts, or deletes specified tags in a DICOM file using the
native C++ engine and writes the modified dataset to `out_path`.

## Usage

``` r
dicom_modify(
  path,
  tags = list(),
  out_path = path,
  delete_tags = character(),
  erase_private = FALSE,
  regenerate_uids = FALSE
)
```

## Arguments

- path:

  Input DICOM file path.

- tags:

  Named list or named character vector of tags (by `"(GGGG,EEEE)"` or
  keyword such as `"PatientName"`) and their new string values.

- out_path:

  Output DICOM file path. Defaults to modifying `path` in-place.

- delete_tags:

  Character vector of tags or keywords to remove.

- erase_private:

  Logical. Remove all odd-group private tags. Default is `FALSE`.

- regenerate_uids:

  Logical. Generate fresh `SOPInstanceUID`, `StudyInstanceUID`, and
  `SeriesInstanceUID`. Default is `FALSE`.

## Value

Invisibly returns `out_path`.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
tmp <- tempfile(fileext = ".dcm")
dicom_modify(dcm_file, tags = list(PatientName = "ANON^PATIENT"), out_path = tmp)
dicom_tag_value(tmp, "PatientName")
#>    PatientName 
#> "ANON^PATIENT" 
```
