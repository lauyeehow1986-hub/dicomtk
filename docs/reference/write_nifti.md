# Write a DICOM Volume to NIfTI-1 With dcm2niix-Compatible Geometry

Exports a
[`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md),
`"dicom_series"`, or DICOM path to a NIfTI-1 file (`.nii` or `.nii.gz`)
whose voxel layout and world-space orientation match `dcm2niix`: voxel
`(i, j, k)` is `(column, flipped row, slice)` and both an exact RAS
`sform` (preserving any gantry-tilt shear) and an orthogonalized
quaternion `qform` (via the NIfTI-1 `nifti_mat44_to_quatern` algorithm)
are written with codes `1`.

## Usage

``` r
write_nifti(
  x,
  out_path = NULL,
  json_sidecar = TRUE,
  backend = c("auto", "rnifti", "builtin")
)
```

## Arguments

- x:

  A
  [`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md),
  a `"dicom_series"` object, or a path to a DICOM file, directory, or
  vector of files.

- out_path:

  Output `.nii` / `.nii.gz` path. Defaults to a temporary `.nii` file.
  `".nii"` is appended when the path has neither extension.

- json_sidecar:

  Logical. When `TRUE` (default) writes a BIDS-style `<stem>.json`
  sidecar (`Modality`, `ImageOrientationPatientDICOM`, `SliceThickness`
  (nominal DICOM value), `SpacingBetweenSlices`, `RepetitionTime`,
  `EchoTime`, `PixelSpacing`, `ConversionSoftware`, ...) next to the
  image.

- backend:

  Writer backend: `"auto"` (default; `RNifti` when installed, otherwise
  the built-in dependency-free writer), `"rnifti"`, or `"builtin"`.

## Value

Invisibly returns `out_path`.

## Examples

``` r
out_dir <- tempfile("nifti_demo_")
dicom_synthesize(out_dir = out_dir, modality = "CT", dims = c(16L, 16L, 4L))
vol <- read_dicom_volume(out_dir)
nii <- write_nifti(vol, tempfile(fileext = ".nii"), backend = "builtin")
file.exists(nii)
#> [1] TRUE
unlink(c(out_dir, nii, sub("\\.nii$", ".json", nii)), recursive = TRUE)
```
