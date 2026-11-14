# Execute a Portable JSON Cohort Specification Against an Archive Index

Execute a Portable JSON Cohort Specification Against an Archive Index

## Usage

``` r
run_cohort_spec(index, spec_or_path)
```

## Arguments

- index:

  A `"dicom_archive_index"` object from
  [`dicom_index_build()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_index_build.md).

- spec_or_path:

  A cohort spec list from
  [`export_cohort_spec()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/export_cohort_spec.md)
  or a `.json` file path.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
of matching cohort records.
