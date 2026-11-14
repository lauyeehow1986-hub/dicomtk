# Convert PS3.18 DICOM JSON Model to a Tidy Header Tibble

Convert PS3.18 DICOM JSON Model to a Tidy Header Tibble

## Usage

``` r
from_dicom_json(dj)
```

## Arguments

- dj:

  A named list (one DICOM JSON dataset) from
  [`as_dicom_json()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_dicom_json.md)
  or a QIDO-RS/WADO-RS metadata response.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `tag`, `vr`, and `value`.

## Examples

``` r
dj <- list("00080060" = list(vr = "CS", Value = list("CT")))
from_dicom_json(dj)
#> # A tibble: 1 × 3
#>   tag         vr    value
#>   <chr>       <chr> <chr>
#> 1 (0008,0060) CS    CT   
```
