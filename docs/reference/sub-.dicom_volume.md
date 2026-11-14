# Subset a `dicom_volume` While Preserving World Geometry

Extracts a sub-volume from a 3D or 4D `dicom_volume`, automatically
shifting the physical origin `affine[1:3, 4]` to the world coordinate of
the new first voxel, scaling/flipping affine columns and `direction` /
`spacing` for strided or reversed index sequences, slicing `frame_meta`,
and flagging irregular spacing if non-uniform indices are supplied.

## Usage

``` r
# S3 method for class 'dicom_volume'
x[..., drop = FALSE]
```

## Arguments

- x:

  A `dicom_volume` object.

- ...:

  Row, column, slice (and optional 4th-dimension frame) subscripts.

- drop:

  Logical. Defaults to `FALSE`, preserving the `"dicom_volume"`
  container and 4x4 affine even when subsetting selects a single slice
  (`vol[, , 2]`) or crops a single-slice 2D modality
  (`dx_vol[2:8, 3:10, ]`). If `TRUE` and subsetting reduces any spatial
  dimension to length 1, returns the dropped base R matrix or vector;
  when subsetting a single temporal frame from a 4D volume
  (`vol[, , , 2, drop = TRUE]`) with all 3 spatial dimensions `> 1`,
  drops the 4th dimension and returns a 3D `dicom_volume`.

## Value

A `dicom_volume` object (always when `drop = FALSE`, or when 3-4
spatial/temporal dimensions remain under `drop = TRUE`), or a base R
array/matrix/vector when `drop = TRUE` reduces spatial dimensions `< 3`.

## Examples

``` r
vox <- array(seq_len(10 * 12 * 6), dim = c(10L, 12L, 6L))
aff <- diag(c(0.5, 0.5, 2.0, 1.0))
vol <- new_dicom_volume(vox, affine = aff, modality = "CT")
sub <- vol[2:8, 3:10, 2:5]
dim(sub)
#> [1] 7 8 4
single <- vol[, , 2]
dim(single)
#> [1] 10 12  1
```
