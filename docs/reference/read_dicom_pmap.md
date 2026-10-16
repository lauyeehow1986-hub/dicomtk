# Read DICOM Parametric Map Objects (`dcmpmap`)

Reads a DICOM Parametric Map (`PMAP`) dataset and applies
`RealWorldValueSlope` and `RealWorldValueIntercept` transformations.

## Usage

``` r
read_dicom_pmap(path)
```

## Arguments

- path:

  Path to a DICOM Parametric Map file.

## Value

A list of class `"dicom_pmap"` containing `values` (real-world mapped
numeric array) and `metadata` (tibble of header tags).

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
pmap <- read_dicom_pmap(dcm_file)
dim(pmap$values)
#> [1] 512 512
```
