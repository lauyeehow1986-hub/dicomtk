# Read a Multi-Slice DICOM Series into a 3D Volume

**\[deprecated\]**

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
(`[rows, cols, slices]` numeric array), `metadata` (wide tibble of
sorted slice headers), `files` (sorted file paths), `dims` (named
integer vector), and `affine` (4x4 DICOM LPS voxel-to-world matrix)).

## Details

`read_dicom_series()` was soft-deprecated in `dicomtk` 0.2.0 in favor of
[`read_dicom_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md),
which returns a geometry-aware
[`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
object with full multi-frame and 4D support. `read_dicom_series()` now
delegates slice ordering and patient-space affine reconstruction to
[`read_dicom_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md)
so reversed or oblique slices are ordered accurately by
`ImagePositionPatient` projected onto the slice normal.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
series <- read_dicom_series(c(dcm_file, dcm_file))
#> Warning: `read_dicom_series()` was deprecated in dicomtk 0.2.0.
#> ℹ Please use `read_dicom_volume()` instead.
dim(series$volume)
#> [1] 512 512   2
```
