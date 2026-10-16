# Retrieve DICOM Files from PACS Connection (C-GET / C-MOVE / Local PACS)

Copies or downloads matching DICOM files from a `"dicom_connection"` or
query result tibble into `output_dir`.

## Usage

``` r
dicom_get(x, output_dir = tempfile("dicom_get_"), ...)
```

## Arguments

- x:

  A `"dicom_connection"` object or a
  [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
  returned by
  [`dicom_find()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_find.md).

- output_dir:

  Destination directory for retrieved `.dcm` files. Defaults to a
  temporary directory.

- ...:

  Optional filter criteria if `x` is a `"dicom_connection"`.

## Value

Character vector of retrieved file paths in `output_dir`.

## Examples

``` r
ext_dir <- system.file("extdata", package = "dicomtk")
conn <- dicom_connect(local_dir = ext_dir)
files <- conn |> dicom_find() |> dicom_get()
length(files)
#> [1] 2
```
