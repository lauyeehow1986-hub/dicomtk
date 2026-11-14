# Convert a 3D Segmentation Mask (`dicom_seg`) to `RTSTRUCT` Contours

Traces closed 2D planar polygon contours slice-by-slice from a
[dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
mask and transforms pixel indices to LPS world coordinates using
`ref_volume$affine`, producing an `RTSTRUCT` object (see
[`read_dicom_rt()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_rt.md)).

## Usage

``` r
seg_to_rtstruct(seg, ref_volume, roi_name = NULL, roi_color = "255\\0\\0")
```

## Arguments

- seg:

  A
  [dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
  object.

- ref_volume:

  Reference
  [dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  providing spatial geometry.

- roi_name:

  Name for the exported ROI (defaults to segment label).

- roi_color:

  Color string (e.g. `"255\\0\\0"`).

## Value

A `dicom_rt` object of modality `"RTSTRUCT"`.

## Examples

``` r
synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 5L))
vol <- read_dicom_volume(synth[["out_dir"]])
m <- array(0L, dim = c(32L, 32L, 5L))
m[5:15, 5:15, 2:3] <- 1L
seg <- dicom_seg(m, vol)
rt <- seg_to_rtstruct(seg, vol)
rt$modality
#> [1] "RTSTRUCT"
```
