# Read Radiation Therapy (RT) DICOM Objects (`dcmrt`)

Reads DICOM Radiation Therapy objects (`RTPLAN`, `RTDOSE`, `RTSTRUCT`,
`RTIMAGE`), extracting group `0x3002`, `0x3004`, `0x3006`, `0x3008`,
`0x300A`, and `0x300C` elements and nested sequences into a tidy
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html),
along with dose grids if pixel data is present (`RTDOSE`).

## Usage

``` r
read_dicom_rt(path)
```

## Arguments

- path:

  Path to a DICOM RT file.

## Value

A list of class `"dicom_rt"` containing `modality`, `summary` (tidy
tibble of top-level RT attributes), `rt_elements` (full hierarchical RT
sequence tibble), and `dose_grid` (3D dose array if
`Modality == "RTDOSE"`).

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
rt_info <- read_dicom_rt(dcm_file)
rt_info$modality
#> [1] "CT"
```
