# Export a Portable JSON Cohort Specification

Export a Portable JSON Cohort Specification

## Usage

``` r
export_cohort_spec(cohort, name = "cohort_spec", out_path = NULL)
```

## Arguments

- cohort:

  A `"dicom_cohort_query"` object from
  [`dicom_cohort_nl()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_cohort_nl.md).

- name:

  Cohort identifier string.

- out_path:

  Optional file path to write the JSON specification.

## Value

A portable cohort specification list (invisibly if written to disk).
