# DICOM Segmentation S3 Class

Constructs a `dicom_seg` spatial segmentation object inheriting from
[dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md).

## Usage

``` r
dicom_seg(mask, ref_volume, segments = NULL)
```

## Arguments

- mask:

  A 3D integer array (`[rows, cols, slices]`) or 4D array
  (`[rows, cols, slices, segments]`).

- ref_volume:

  Reference
  [dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  object providing geometry, spatial affine matrix, and slice spacing.

- segments:

  A data frame or tibble with segment metadata containing at minimum
  `segment_id` and `label`.

## Value

A `dicom_seg` object inheriting from `dicom_volume`.

## Examples

``` r
synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 4L))
vol <- read_dicom_volume(synth$files[1L])
m <- array(0L, dim = c(32L, 32L, 4L))
m[10:20, 10:20, 2:3] <- 1L
seg_meta <- tibble::tibble(segment_id = 1L, label = "Liver")
seg <- dicom_seg(m, vol, seg_meta)
print(seg)
#> ℹ DICOM Segmentation Object (Segment rows: 1, Mask dims: 32x32x4)
```
