# Synthesize Multi-Modality DICOM Phantoms with Exact Ground-Truth Geometry

Generates standards-compliant synthetic DICOM Part 10 datasets across
classical multi-file 3D series (`"CT"`, `"MR"`, `"PT"`, `"DX"`, `"MG"`,
`"US"`, `"XA"`), single-file Enhanced Multi-Frame IODs (`"ENHCT"`,
`"ENHMR"`, `"DBT"`), and cine multi-frame sequences (`"XA_CINE"`,
`"US_CINE"`). Returns the analytical 4x4 DICOM LPS voxel-to-world
affine, rescaled ground-truth voxel array with asymmetric corner
fiducials, and planted synthetic PHI metadata for deterministic
validation of geometry, quantitative transforms, de-identification, and
NIfTI export.

## Usage

``` r
dicom_synthesize(
  out_dir = tempfile("dicom_synth_"),
  modality = c("CT", "MR", "PT", "DX", "MG", "US", "XA", "ENHCT", "ENHMR", "DBT",
    "XA_CINE", "US_CINE"),
  dims = c(32L, 32L, 8L),
  spacing = c(1, 1, 2.5),
  origin = c(-16, -16, 0),
  orientation = c("axial", "coronal", "sagittal", "oblique"),
  oblique_angles_deg = c(15, -10, 5),
  gantry_tilt_deg = 0,
  irregular_z = FALSE,
  reverse_order = FALSE,
  mixed_series = FALSE,
  phi = TRUE,
  pet_params = list(),
  voi_params = list(),
  extra_tags = list(),
  seed = 42L,
  inject_phi = NULL,
  phi_profile = c("basic", "midi_b")
)

# S3 method for class 'dicom_phantom'
print(x, ...)
```

## Arguments

- out_dir:

  Output directory where synthesized `.dcm` file(s) will be written.
  Created automatically if it does not exist. Defaults to a new
  temporary directory.

- modality:

  Imaging modality / IOD preset. One of `"CT"`, `"MR"`, `"PT"`, `"DX"`,
  `"MG"`, `"US"`, `"XA"`, `"ENHCT"`, `"ENHMR"`, `"DBT"`, `"XA_CINE"`, or
  `"US_CINE"`.

- dims:

  Integer vector `c(rows, cols, slices)` (or `c(rows, cols)` for a
  single slice). Default is `c(32L, 32L, 8L)`.

- spacing:

  Numeric vector `c(dr, dc, dz)` in millimeters, where `dr` is row
  spacing (along `d_col`), `dc` is column spacing (along `d_row`), and
  `dz` is nominal slice step. Default is `c(1.0, 1.0, 2.5)`.

- origin:

  Numeric vector `c(x, y, z)` in DICOM LPS millimeters for voxel
  `(r = 0, c = 0, s = 0)` (`[1, 1, 1]` 1-based). Default is
  `c(-16.0, -16.0, 0.0)`.

- orientation:

  Anatomical acquisition plane: `"axial"`, `"coronal"`, `"sagittal"`, or
  `"oblique"`.

- oblique_angles_deg:

  Numeric vector of 3 ZYX Euler angles in degrees applied when
  `orientation = "oblique"`. Default is `c(15, -10, 5)`.

- gantry_tilt_deg:

  Numeric gantry/detector tilt angle in degrees rotating the slice step
  direction in the `(normal, d_col)` plane. Default is `0`.

- irregular_z:

  Logical. If `TRUE` (and `slices >= 2`), introduces a deterministic
  `2 * dz` slice gap after slice `floor(slices / 2)`. Default is
  `FALSE`.

- reverse_order:

  Logical. If `TRUE`, writes slices/frames on disk in reverse spatial
  order (`slices:1`) while keeping `truth_affine_lps` and `truth_voxels`
  in canonical ascending `IPP . normal` order. Default is `FALSE`.

- mixed_series:

  Logical. If `TRUE`, writes an additional scout/localizer DICOM slice
  with distinct orientation and matrix dimensions into `out_dir`
  (recorded in `phantom$extra_files`) sharing the same
  `SeriesInstanceUID`. Default is `FALSE`.

- phi:

  Logical. If `TRUE` (default), plants synthetic fictitious PHI tags
  (and burned-in top-row pixels for `"US"` / `"US_CINE"`). If `FALSE`,
  writes clean de-identified tags.

- pet_params:

  Optional named list configuring quantitative PET (`"PT"`) attributes
  (`patient_weight`, `patient_size`, `patient_sex`, `series_time`,
  `acquisition_time`, `total_dose`, `half_life`, `start_time`, `units`,
  `corrected_image`, `decay_correction`, `activity_bqml`,
  `rescale_slope`, `rescale_intercept`).

- voi_params:

  Optional named list configuring `"MG"` / `"DX"` / `"DBT"` VOI LUT and
  presentation attributes (`presentation_intent`, `photometric`,
  `voi_lut_function`, `window_center`, `window_width`).

- extra_tags:

  Optional named list of additional top-level DICOM tags or private tags
  (e.g. `list("(2005,100D)" = "0", "(2005,100E)" = "2.5")`) to embed in
  every written file.

- seed:

  Optional integer seed reserved for deterministic phantom extensions
  without mutating the caller's `.Random.seed`. Default is `42L`.

- inject_phi:

  Optional logical alias for `phi`. If provided, overrides `phi`.

- phi_profile:

  Character string specifying the synthetic PHI profile:

  - `"basic"` (default): Plants core identity tags (name, ID, birthdate,
    institution).

  - `"midi_b"`: Plants comprehensive HIPAA Safe Harbor, PS3.15, and
    SG/MY/EU canaries across headers, sequences
    (`ReferencedSOPSequence`), safe/unsafe private blocks, and burned-in
    pixel annotation banners.

- x:

  A `"dicom_phantom"` object returned by `dicom_synthesize()`.

- ...:

  Additional arguments (unused).

## Value

Invisibly returns an S3 object of class `"dicom_phantom"` containing:

- `files`: character vector of primary `.dcm` file paths

- `extra_files`: character vector of extra `.dcm` files when
  `mixed_series = TRUE`

- `out_dir`: normalized output directory path

- `modality`: requested modality string

- `dims`: integer vector `c(rows, cols, slices)`

- `orientation`: canonical orientation string (`"axial"`, `"coronal"`,
  `"sagittal"`, or `"oblique"`)

- `truth_affine_lps`: 4x4 numeric LPS voxel-to-world affine matrix
  (0-based `[r, c, s, 1]`)

- `truth_voxels`: `[rows, cols, slices]` numeric array in rescaled units

- `direction`: list with `d_row`, `d_col`, and `normal` unit vectors in
  LPS

- `spacing`: numeric vector `c(dr, dc, dz)`

- `slice_positions_lps`: `nslices x 3` numeric matrix of canonical slice
  origins in LPS

- `planted_phi`: named list of planted synthetic PHI tags (empty
  [`list()`](https://rdrr.io/r/base/list.html) when `phi = FALSE`)

- `phi_manifest`: tibble of planted PHI canaries with columns `tag`,
  `keyword`, `sequence_path`, `value`, `expected_action`, and `category`

- `phi_profile`: character string identifying the active PHI profile

- `uids`: list with `study_uid`, `series_uid`, and
  `frame_of_reference_uid`

## Examples

``` r
out_dir <- tempfile("ct_phantom_")
phantom <- dicom_synthesize(
  out_dir = out_dir,
  modality = "CT",
  dims = c(16L, 16L, 4L),
  spacing = c(0.8, 0.8, 2.5),
  orientation = "oblique"
)
phantom
#> <dicom_phantom [CT] 16x16x4 | spacing=(0.8, 0.8, 2.5) mm | orientation=oblique | files=4 | phi=planted>
unlink(out_dir, recursive = TRUE)
```
