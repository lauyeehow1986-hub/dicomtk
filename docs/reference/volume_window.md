# Apply Intensity Windowing and Normalization to a `dicom_volume`

Clips voxel intensities to `[center - width / 2, center + width / 2]`
and optionally normalizes to `[0, 1]` (`"minmax"`) or zero-mean
unit-variance (`"zscore"`).

## Usage

``` r
volume_window(
  vol,
  center = NULL,
  width = NULL,
  normalize = c("none", "minmax", "zscore")
)
```

## Arguments

- vol:

  A
  [dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  object.

- center:

  Numeric window center (level). If `NULL`, no clipping is applied.

- width:

  Numeric window width (must be positive if `center` is supplied).

- normalize:

  Normalization mode: `"none"` (default, clip only), `"minmax"` (rescale
  to `[0, 1]`), or `"zscore"` (standardize to mean 0, SD 1).

## Value

A
[dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
object with transformed voxel intensities.

## Examples

``` r
vox <- array(c(-1000, 0, 40, 200, 1000, 2000, 3000, 4000), dim = c(2L, 2L, 2L))
vol <- new_dicom_volume(vox, modality = "CT", units = "HU")
w <- volume_window(vol, center = 40, width = 400, normalize = "minmax")
range(w$voxels)
#> [1] 0 1
```
