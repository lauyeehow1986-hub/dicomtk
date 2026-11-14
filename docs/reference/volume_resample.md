# Resample a 3D `dicom_volume` or `dicom_seg` to Target Voxel Spacing

Resamples a 3D
[dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
or
[dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
object to `target_spacing` (in millimeters) using high-speed C++17
trilinear interpolation (for continuous imaging intensities) or
nearest-neighbor interpolation (for discrete segmentation masks and
label-maps), updating the 4x4 spatial affine matrix and spacing metadata
while preserving the physical origin.

## Usage

``` r
volume_resample(
  vol,
  target_spacing = c(1, 1, 1),
  method = c("trilinear", "nearest")
)
```

## Arguments

- vol:

  A
  [dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  or
  [dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
  object.

- target_spacing:

  Numeric vector of length 3 giving target spacing `c(dr, dc, dz)` in
  millimeters. Default is `c(1, 1, 1)`.

- method:

  Interpolation method: `"trilinear"` (default for images) or
  `"nearest"` (default automatically when `vol` is a `dicom_seg` if not
  explicitly overridden).

## Value

A resampled
[dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
(or
[dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md))
object with updated `voxels`, `affine`, and `spacing`.

## Examples

``` r
synth <- dicom_synthesize(modality = "CT", dims = c(16L, 16L, 4L))
vol <- read_dicom_volume(synth[["out_dir"]])
vol_iso <- volume_resample(vol, target_spacing = c(1, 1, 1))
dim(vol_iso)
#> [1] 16 16 10
unlink(synth[["out_dir"]], recursive = TRUE)
```
