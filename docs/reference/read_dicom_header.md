# Read DICOM Header Metadata

Reads the header elements of one or more DICOM files into a tidy tibble.
Compatible with both `dicomtk` tidy pipelines and legacy
[`dcmtk::read_dicom_header()`](https://rdrr.io/pkg/dcmtk/man/read_dicom_header.html)
arguments.

## Usage

``` r
read_dicom_header(
  file,
  replace_names = FALSE,
  add_opts = NULL,
  verbose = FALSE,
  wide = FALSE,
  ...
)
```

## Arguments

- file:

  Character vector of DICOM file paths or directory paths.

- replace_names:

  Logical. Kept for compatibility with legacy `dcmtk`; tag names are
  automatically resolved against the built-in DCMTK 3.7.1 dictionary.

- add_opts:

  Character vector of options (ignored in native C++ mode, kept for
  backward compatibility).

- verbose:

  Logical. Print progress information. Default is `FALSE`.

- wide:

  Logical. Return wide format (1 row per file). Default is `FALSE`.

- ...:

  Additional arguments passed to
  [`read_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom.md).

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
containing the parsed DICOM header elements.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
read_dicom_header(dcm_file)
#> # A tibble: 190 × 12
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
#> # ℹ 180 more rows
#> # ℹ 1 more variable: sequence_path <chr>
```
