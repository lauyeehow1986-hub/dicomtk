# Discover and Split Homogeneous DICOM Sub-Series

Scans a directory or vector of DICOM file paths and partitions image
files into homogeneous volumetric sub-series grouped by
`SeriesInstanceUID`, `Modality`, `SOPClassUID`, matrix dimensions
(`Rows`, `Columns`), rounded `ImageOrientationPatient` direction
cosines, `EchoNumbers`, and localizer status (`LOCALIZER` / `SCOUT`).
Primary 3D volumetric stacks are ordered ahead of scout/localizer
slices, and multi-echo acquisitions are ordered by ascending echo
number.

## Usage

``` r
dicom_split_series(path, recursive = TRUE)
```

## Arguments

- path:

  Directory path or character vector of DICOM file/directory paths.

- recursive:

  Logical. When `path` includes directories, search subdirectories
  recursively. Default is `TRUE`.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with one row per discovered homogeneous sub-series and columns
`series_uid`, `subseries_id`, `modality`, `rows`, `cols`, `n_files`,
`n_frames`, `orientation_key`, `echo_number`, `is_localizer`, and
`files` (list-column of normalized file path vectors).

## Examples

``` r
out_dir <- tempfile("split_demo_")
dicom_synthesize(out_dir = out_dir, modality = "CT", dims = c(16L, 16L, 4L), mixed_series = TRUE)
dicom_split_series(out_dir)
#> # A tibble: 2 × 11
#>   series_uid  subseries_id modality  rows  cols n_files n_frames orientation_key
#>   <chr>              <int> <chr>    <int> <int>   <int>    <int> <chr>          
#> 1 2.25.17946…            1 CT          16    16       4        4 "1.000\\0.000\…
#> 2 2.25.17946…            2 CT          24    24       1        1 "0.000\\1.000\…
#> # ℹ 3 more variables: echo_number <chr>, is_localizer <lgl>, files <list>
unlink(out_dir, recursive = TRUE)
```
