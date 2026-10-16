# Read DICOM Tractography Results (`dcmtract`)

Reads a DICOM Tractography Results (`1.2.840.10008.5.1.4.1.1.66.6`)
dataset, extracting `TrackSetSequence (0066,0101)` and streamline
metadata into a tidy
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html).

## Usage

``` r
read_dicom_tract(path)
```

## Arguments

- path:

  Path to a DICOM Tractography file.

## Value

A list of class `"dicom_tract"` containing `track_sets` (tibble of group
`0x0066` elements) and `header` (top-level metadata tibble).

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
tr <- read_dicom_tract(dcm_file)
tr
#> ℹ DICOM Tractography Object (Track Set elements: 0)
```
