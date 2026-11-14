# Apply VOI LUT (Window/Level or Sigmoidal Transfer Function) to DICOM Volume

Applies DICOM PS3.3 Section C.11.2.1 Value of Interest (VOI)
transformations (`"LINEAR"`, `"LINEAR_EXACT"`, or `"SIGMOID"`) to a
[`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md),
scaling output voxels to `[0, 1]` and optionally inverting
`PhotometricInterpretation == "MONOCHROME1"` so higher attenuation
appears brighter.

## Usage

``` r
dicom_apply_voi_lut(
  x,
  window_center = NULL,
  window_width = NULL,
  function_type = c("auto", "LINEAR", "LINEAR_EXACT", "SIGMOID"),
  index = 1L,
  invert_monochrome1 = TRUE
)
```

## Arguments

- x:

  A
  [`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  or path to DICOM files.

- window_center:

  Optional numeric window center override.

- window_width:

  Optional numeric window width override.

- function_type:

  VOI LUT function type: `"auto"` (reads `VOILUTFunction` from metadata,
  defaulting to `"LINEAR"`), `"LINEAR"`, `"LINEAR_EXACT"`, or
  `"SIGMOID"`.

- index:

  1-based integer index selecting which `(WindowCenter, WindowWidth)`
  preset to apply when multi-valued presets (e.g. `"40\\400"`) are
  stored in the DICOM header. Default is `1L`.

- invert_monochrome1:

  Logical. When `TRUE` (default) and
  `PhotometricInterpretation == "MONOCHROME1"`, inverts normalized
  intensities (`1 - y`) for standard presentation polarity.

## Value

A
[`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
with voxels scaled to `[0, 1]` and `units = "normalized"`.

## Examples

``` r
out_dir <- tempfile("mg_demo_")
dicom_synthesize(out_dir = out_dir, modality = "MG", dims = c(16L, 16L, 1L))
vol <- read_dicom_volume(out_dir)
voi_vol <- dicom_apply_voi_lut(vol)
range(voi_vol$voxels)
#> [1] 0.3392436 0.8779687
unlink(out_dir, recursive = TRUE)
```
