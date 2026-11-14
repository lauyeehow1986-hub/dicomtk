# Convert a `dicom_volume` Between DICOM LPS and NIfTI RAS World Coordinates

Transforms the 4x4 physical world affine and direction cosines of a
`dicom_volume` between the DICOM Patient Coordinate System (`"LPS"`:
Left-Posterior-Superior) and the neuroimaging NIfTI standard (`"RAS"`:
Right-Anterior-Superior) via `diag(c(-1, -1, 1, 1)) %*% affine`.

## Usage

``` r
to_ras(vol)

to_lps(vol)

dicom_to_ras(vol)

dicom_to_lps(vol)
```

## Arguments

- vol:

  A `dicom_volume` object.

## Value

A `dicom_volume` object in the target coordinate system (`"RAS"` for
`to_ras()`, `"LPS"` for `to_lps()`).

## Details

Because `det(diag(-1, -1, 1)) == +1` (a 180-degree rotation around the
Superior `z` axis), right-handedness of `(d_row, d_col, normal)` is
strictly preserved without permuting in-memory voxel indices. Both
functions are idempotent when `vol` is already in the target coordinate
system.

## Examples

``` r
aff <- diag(c(0.8, 0.8, 2.5, 1.0))
aff[1:3, 4] <- c(-100, -120, 50)
vol <- new_dicom_volume(array(0, dim = c(8L, 8L, 4L)), affine = aff, coord_system = "LPS")
vol_ras <- to_ras(vol)
vol_ras$affine[1:3, 4]
#> [1] 100 120  50
vol_lps <- to_lps(vol_ras)
all.equal(vol_lps$affine, vol$affine)
#> [1] TRUE
```
