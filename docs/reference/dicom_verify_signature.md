# Inspect Digital Signatures in a DICOM File (`dcmsign`)

Checks whether a DICOM dataset contains digital signatures in
`DigitalSignaturesSequence (FFFA,FFFA)` or
`MACParametersSequence (4FFE,0001)` and returns a tidy summary tibble.

## Usage

``` r
dicom_verify_signature(path)
```

## Arguments

- path:

  Path to a DICOM file.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
of signature elements (0 rows if unsigned).

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
dicom_verify_signature(dcm_file)
#> # A tibble: 0 × 12
#> # ℹ 12 variables: file <chr>, tag <chr>, group <chr>, element <chr>, vr <chr>,
#> #   length <int>, vm <chr>, keyword <chr>, name <chr>, value <chr>,
#> #   depth <int>, sequence_path <chr>
```
