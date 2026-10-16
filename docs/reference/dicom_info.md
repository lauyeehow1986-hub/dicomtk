# Inspect Bundled DCMTK Configuration and Version Info

Returns a tidy tibble describing the bundled DCMTK version, data
dictionary edition, number of standard tags, and active C++ backend.

## Usage

``` r
dicom_info()
```

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with DCMTK configuration details.

## Examples

``` r
dicom_info()
#> # A tibble: 1 × 5
#>   dcmtk_version dictionary_standard dictionary_entries backend codecs_registered
#>   <chr>         <chr>                            <int> <chr>   <lgl>            
#> 1 3.7.1         PS 3.6-2026d / PS …               5277 Bundle… TRUE             
```
