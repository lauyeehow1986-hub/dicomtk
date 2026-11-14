# Convert RTSTRUCT Contours to a 3D Segmentation Mask (`dicom_seg`)

Maps planar polygonal contours in LPS world coordinates (from an
`RTSTRUCT` DICOM object) into the in-plane voxel pixel grid of
`ref_volume` and rasterizes each slice into a 3D
[dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
mask.

## Usage

``` r
rtstruct_to_seg(rt, ref_volume, roi_numbers = NULL)
```

## Arguments

- rt:

  An object of class `dicom_rt` with modality `"RTSTRUCT"`, or a path to
  an `RTSTRUCT` DICOM file.

- ref_volume:

  A reference
  [dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  object providing geometry and spatial affine.

- roi_numbers:

  Optional integer vector of specific ROI numbers to rasterize. If
  `NULL`, all ROIs are rasterized.

## Value

A
[dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
object spatially registered with `ref_volume`.

## Examples

``` r
synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 5L))
vol <- read_dicom_volume(synth[["out_dir"]])
# See vignette for full RTSTRUCT workflow
```
