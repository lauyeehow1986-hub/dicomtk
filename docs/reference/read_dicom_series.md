# Read a Multi-Slice DICOM Series into a 3D Volume

Scans a directory (or vector of DICOM file paths), reads slice headers
and pixel data, orders slices spatially by `InstanceNumber` or
`ImagePositionPatient`, and assembles a 3D numeric array
`[rows, cols, slices]` alongside a wide metadata tibble.

## Usage

``` r
read_dicom_series(path, recursive = TRUE, rescale = TRUE)
```

## Arguments

- path:

  Directory path or character vector of DICOM file paths.

- recursive:

  Logical. Search subdirectories recursively. Default is `TRUE`.

- rescale:

  Logical. Apply `RescaleSlope` and `RescaleIntercept`. Default is
  `TRUE`.

## Value

An object of class `"dicom_series"` (a named list with elements `volume`
(`[rows, cols, slices]` numeric array), `metadata` (wide tibble of slice
headers), and `dims` (integer vector)).

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
series <- read_dicom_series(c(dcm_file, dcm_file))
dim(series$volume)
#> [1] 512 512   2
```
