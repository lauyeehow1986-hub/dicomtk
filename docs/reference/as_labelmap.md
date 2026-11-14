# Convert a Multi-Segment `dicom_seg` to a 3D Integer Label-Map

Flattens a 4D multi-segment
[dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
(`[rows, cols, slices, segments]`) or 3D binary/labelmap
[dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
into a single 3D integer label-map volume where each voxel holds the
integer `segment_id` (`0L` for background). When segments overlap,
higher `segment_id` values take precedence by default
(`conflict = "last"`), or lower `segment_id` values when
`conflict = "first"`.

## Usage

``` r
as_labelmap(seg, conflict = c("last", "first"))
```

## Arguments

- seg:

  A
  [dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
  object.

- conflict:

  Conflict resolution policy for overlapping segments: `"last"`
  (default) or `"first"`.

## Value

A 3D integer
[dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
object with `type = "labelmap"`.

## Examples

``` r
synth <- dicom_synthesize(modality = "CT", dims = c(16L, 16L, 4L))
vol <- read_dicom_volume(synth[["out_dir"]])
m4 <- array(0L, dim = c(16L, 16L, 4L, 2L))
m4[3:7, 3:7, 2L, 1L] <- 1L
m4[10:14, 10:14, 2L, 2L] <- 1L
seg4 <- dicom_seg(m4, vol, tibble::tibble(segment_id = 1:2, label = c("Left", "Right")))
lmap <- as_labelmap(seg4)
dim(lmap)
#> [1] 16 16  4
```
