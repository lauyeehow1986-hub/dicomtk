# Construct and Validate a `dicom_volume` Object

Low-level S3 constructor and validator for 3D (`[rows, cols, slices]`)
and 4D (`[rows, cols, slices, frames]`) medical imaging volumes paired
with an exact 4x4 homogeneous voxel-to-world affine matrix in DICOM
`"LPS"` or NIfTI `"RAS"` physical coordinates (millimeters).

## Usage

``` r
new_dicom_volume(
  voxels,
  affine = diag(4L),
  coord_system = c("LPS", "RAS"),
  spacing = NULL,
  direction = NULL,
  frame_meta = NULL,
  uids = list(),
  modality = NA_character_,
  units = NA_character_,
  diagnostics = list(),
  provenance = list()
)

# S3 method for class 'dicom_volume'
dim(x)

# S3 method for class 'dicom_volume'
as.array(x, ...)

# S3 method for class 'dicom_volume'
print(x, ...)
```

## Arguments

- voxels:

  Numeric 2D matrix `[rows, cols]` (automatically promoted to
  `[rows, cols, 1L]`), 3D array `[rows, cols, slices]`, or 4D array
  `[rows, cols, slices, frames]`.

- affine:

  4x4 finite numeric homogeneous voxel-to-world affine matrix whose
  bottom row is `c(0, 0, 0, 1)`. Defaults to `diag(4L)`.

- coord_system:

  World coordinate convention: `"LPS"` (DICOM Patient Coordinate System:
  Left-Posterior-Superior, default) or `"RAS"`
  (Right-Anterior-Superior).

- spacing:

  Optional length-3 non-negative numeric vector `c(dr, dc, dz)` in
  millimeters. Automatically derived from the Euclidean norms of columns
  1..3 of `affine` when `NULL`.

- direction:

  Optional named list with length-3 numeric direction cosine vectors
  `d_row`, `d_col`, and `normal`. Automatically derived from `affine`
  when `NULL`.

- frame_meta:

  Optional
  [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
  (or `data.frame`, coerced to a tibble) storing per-slice or per-frame
  DICOM header metadata. Defaults to an empty tibble.

- uids:

  Named `list` of DICOM study/series/frame-of-reference UIDs.

- modality:

  Single character string (e.g. `"CT"`, `"MR"`, `"PT"`) or
  `NA_character_`.

- units:

  Single character string giving voxel physical units (e.g. `"HU"`,
  `"BQML"`, `"g/mL"`) or `NA_character_`.

- diagnostics:

  Named `list` of geometry diagnostics (e.g. `irregular_spacing`,
  `gantry_tilt_deg`).

- provenance:

  `list` of chronological provenance entries recording transformations
  applied to the volume.

- x:

  A `dicom_volume` object.

- ...:

  Additional arguments passed to or from methods.

## Value

A validated S3 object of class `"dicom_volume"`.

## Details

By convention, 0-based voxel indices `(r, c, s)` map to physical world
coordinates via `affine %*% c(r, c, s, 1)`, where:

- Column 1 (`r` step along rows) is `d_col * dr`

- Column 2 (`c` step along columns) is `d_row * dc`

- Column 3 (`s` step across slices) is the inter-slice step vector

- Column 4 is the physical origin of voxel `(r = 0, c = 0, s = 0)`
  (`[1, 1, 1]` 1-based)

## Examples

``` r
vox <- array(seq_len(8 * 8 * 4), dim = c(8L, 8L, 4L))
aff <- diag(c(0.8, 0.8, 2.5, 1.0))
aff[1:3, 4] <- c(-10, -10, 0)
vol <- new_dicom_volume(vox, affine = aff, modality = "CT", units = "HU")
vol
#> <dicom_volume [CT] 8x8x4 | coord=LPS | units=HU>
#>   spacing: (0.8, 0.8, 2.5) mm | origin: (-10, -10, 0) mm
#>   frame_meta: 0 row(s) | provenance: 0 step(s)
is_dicom_volume(vol)
#> [1] TRUE
```
