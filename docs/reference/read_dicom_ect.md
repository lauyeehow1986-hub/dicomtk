# Read DICOM Tractography Results (`dcmtract`) and Enhanced Multi-Frame IODs (`dcmect` / `dcmfg`)

Extracts functional groups
(`SharedFunctionalGroupsSequence (5200,9229)`,
`PerFrameFunctionalGroupsSequence (5200,9230)`) and tractography
sequences (`TrackSetSequence (0066,0101)`) into a tidy
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html).

## Usage

``` r
read_dicom_ect(path)
```

## Arguments

- path:

  Path to a DICOM Enhanced CT or Tractography file.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
of functional group and tractography elements.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
read_dicom_ect(dcm_file)
#> # A tibble: 201 × 12
#>    file         tag   group element vr    length vm    keyword name  value depth
#>    <chr>        <chr> <chr> <chr>   <chr>  <int> <chr> <chr>   <chr> <chr> <int>
#>  1 "C:\\Users\… (000… 0002  0000    UL         4 1     FileMe… File… "192"     0
#>  2 "C:\\Users\… (000… 0002  0001    OB         2 1     FileMe… File… "00\…     0
#>  3 "C:\\Users\… (000… 0002  0002    UI        26 1     MediaS… Medi… "1.2…     0
#>  4 "C:\\Users\… (000… 0002  0003    UI        48 1     MediaS… Medi… "1.3…     0
#>  5 "C:\\Users\… (000… 0002  0010    UI        20 1     Transf… Tran… "1.2…     0
#>  6 "C:\\Users\… (000… 0002  0012    UI        18 1     Implem… Impl… "1.3…     0
#>  7 "C:\\Users\… (000… 0002  0013    SH        10 1     Implem… Impl… "DCT…     0
#>  8 "C:\\Users\… (000… 0002  0016    AE         8 1     Source… Sour… "CLU…     0
#>  9 "C:\\Users\… (000… 0008  0005    CS        10 1-n   Specif… Spec… "ISO…     0
#> 10 "C:\\Users\… (000… 0008  0008    CS        22 2-n   ImageT… Imag… "ORI…     0
#> # ℹ 191 more rows
#> # ℹ 1 more variable: sequence_path <chr>
```
