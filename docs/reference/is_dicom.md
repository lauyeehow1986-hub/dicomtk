# Check Whether File(s) Are Valid DICOM Files

Inspects the file header for the standard 128-byte preamble + `"DICM"`
magic bytes or valid initial DICOM group/element tags.

## Usage

``` r
is_dicom(path)
```

## Arguments

- path:

  Character vector of file paths.

## Value

A logical vector of the same length as `path`.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
is_dicom(dcm_file)
#> [1] TRUE
```
