# Map Between Voxel Indices and Physical World Coordinates

Maps 3D voxel coordinates `(r, c, s)` to physical world coordinates
`(x, y, z)` in millimeters (in `vol$coord_system`, `"LPS"` or `"RAS"`)
and vice versa using `vol$affine`, supporting both R's 1-based indexing
(`index_base = 1L`) and DICOM/C/NIfTI 0-based indexing
(`index_base = 0L`).

## Usage

``` r
voxel_to_world(vol, ijk, index_base = 1L)

world_to_voxel(vol, xyz, index_base = 1L)
```

## Arguments

- vol:

  A `dicom_volume` object.

- ijk:

  Numeric vector of length 3 (`c(r, c, s)`) or `N x 3` numeric matrix of
  voxel indices.

- index_base:

  Integer indexing base: `1L` (default, R 1-based where `c(1, 1, 1)`
  maps to `vol$affine[1:3, 4]`) or `0L` (0-based where `c(0, 0, 0)` maps
  to `vol$affine[1:3, 4]`).

- xyz:

  Numeric vector of length 3 (`c(x, y, z)`) or `N x 3` numeric matrix of
  physical world coordinates in millimeters.

## Value

For a length-3 vector input, a named length-3 numeric vector
(`c(x = ..., y = ..., z = ...)` for `voxel_to_world()`,
`c(r = ..., c = ..., s = ...)` for `world_to_voxel()`). For an `N x 3`
matrix input, an `N x 3` numeric matrix.

## Examples

``` r
aff <- diag(c(0.8, 0.8, 2.5, 1.0))
aff[1:3, 4] <- c(-16, -16, 0)
vol <- new_dicom_volume(array(0, dim = c(32L, 32L, 8L)), affine = aff)
w <- voxel_to_world(vol, c(1, 1, 1), index_base = 1L)
w
#>   x   y   z 
#> -16 -16   0 
world_to_voxel(vol, w, index_base = 1L)
#> r c s 
#> 1 1 1 
```
