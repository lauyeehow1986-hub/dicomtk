# Read a 3D or 4D DICOM Volume with Exact Patient-Space Geometry

Reconstructs a 3D (`[rows, cols, slices]`) or 4D
(`[rows, cols, slices, frames]`)
[`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
object from classical multi-file DICOM series, single-file Enhanced
Multi-Frame IODs (`SharedFunctionalGroupsSequence` /
`PerFrameFunctionalGroupsSequence`), stationary cine loops (`XA`, `US`),
or dynamic multi-timepoint stacks.

## Usage

``` r
read_dicom_volume(
  path,
  series_uid = NULL,
  subseries = NULL,
  rescale = TRUE,
  split = FALSE,
  recursive = TRUE,
  warn = TRUE
)
```

## Arguments

- path:

  Directory path or character vector of DICOM file/directory paths.

- series_uid:

  Optional `SeriesInstanceUID` string to select a specific DICOM series
  when `path` contains multiple series.

- subseries:

  Optional 1-based integer index selecting which homogeneous sub-series
  from
  [`dicom_split_series()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_split_series.md)
  to read when `split = FALSE`. When `NULL` (default), reads primary
  sub-series `1L` and emits a warning if multiple sub-series (e.g. a
  localizer scout or multiple echoes) were detected.

- rescale:

  Logical. Apply per-frame or top-level `RescaleSlope` and
  `RescaleIntercept` to convert stored integers to physical modality
  units (e.g. `"HU"` for CT, `"BQML"` for PET). Default is `TRUE`.

- split:

  Logical. If `TRUE`, returns a `list` of `dicom_volume` objects, one
  for every homogeneous sub-series discovered by
  [`dicom_split_series()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_split_series.md).
  Default is `FALSE`.

- recursive:

  Logical. When `path` contains directories, search subdirectories
  recursively. Default is `TRUE`.

- warn:

  Logical. Emit informative
  [`cli::cli_warn()`](https://cli.r-lib.org/reference/cli_abort.html)
  diagnostics when multiple sub-series, irregular slice spacing, gantry
  tilt shear, or duplicate slice positions are encountered. Default is
  `TRUE`.

## Value

A
[`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
object when `split = FALSE`, or a `list` of `dicom_volume` objects when
`split = TRUE`.

## Details

Slices are ordered strictly by projecting
`ImagePositionPatient (0020,0032)` onto the right-handed slice normal
`cross(d_row, d_col)` derived from `ImageOrientationPatient (0020,0037)`
(never trusting `InstanceNumber` when spatial positions are present).
Computes the exact 4x4 DICOM LPS voxel-to-world affine matrix (including
gantry/detector tilt shear when present) and records geometry
diagnostics for irregular spacing, slice gaps/overlaps, gantry tilt, and
duplicate positions.

## Examples

``` r
out_dir <- tempfile("vol_read_demo_")
dicom_synthesize(
  out_dir = out_dir,
  modality = "CT",
  dims = c(16L, 16L, 4L),
  orientation = "oblique",
  reverse_order = TRUE
)
vol <- read_dicom_volume(out_dir)
vol
#> <dicom_volume [CT] 16x16x4 | coord=LPS | units=HU>
#>   spacing: (1, 1, 2.5) mm | origin: (-16, -16, 0) mm
#>   frame_meta: 4 row(s) | provenance: 1 step(s)
unlink(out_dir, recursive = TRUE)
```
