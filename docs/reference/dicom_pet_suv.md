# Calculate Standardized Uptake Value (SUV) for PET Volumes

Computes SUV body weight (`"bw"`), lean body mass (`"lbm"`,
Janmahasatian 2005), or body surface area (`"bsa"`, DuBois & DuBois)
from a PET
[`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
or path.

## Usage

``` r
dicom_pet_suv(
  x,
  method = c("bw", "lbm", "bsa"),
  decay_correct = c("auto", "none", "force")
)
```

## Arguments

- x:

  A
  [`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  object or path to DICOM PET files.

- method:

  SUV normalization method: `"bw"` (body weight, default), `"lbm"` (lean
  body mass), or `"bsa"` (body surface area).

- decay_correct:

  Decay correction handling: `"auto"` (default, uses `SeriesTime` or
  `AcquisitionTime` with radiopharmaceutical start time if
  `CorrectedImage` indicates decay correction), `"none"`, or `"force"`.

## Value

A
[`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
object with voxel values converted to SUV (units `"g/ml"` for `"bw"` and
`"lbm"`, or `"cm2/ml"` for `"bsa"`), updated metadata, and appended
provenance.

## Examples

``` r
out_dir <- tempfile("pet_demo_")
dicom_synthesize(out_dir = out_dir, modality = "PT", dims = c(16L, 16L, 2L))
vol <- read_dicom_volume(out_dir)
suv_vol <- dicom_pet_suv(vol, method = "bw")
suv_vol
#> <dicom_volume [PT] 16x16x2 | coord=LPS | units=g/ml>
#>   spacing: (1, 1, 2.5) mm | origin: (-16, -16, 0) mm
#>   frame_meta: 2 row(s) | provenance: 2 step(s)
unlink(out_dir, recursive = TRUE)
```
