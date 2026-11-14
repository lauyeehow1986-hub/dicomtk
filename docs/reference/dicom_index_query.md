# Execute a Read-Only SQL Query Against a `dicom_archive_index`

Execute a Read-Only SQL Query Against a `dicom_archive_index`

## Usage

``` r
dicom_index_query(index, sql)
```

## Arguments

- index:

  A `"dicom_archive_index"` object from
  [`dicom_index_build()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_index_build.md).

- sql:

  A read-only `SELECT` (or `WITH ... SELECT`) SQL query string.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
of query results.
