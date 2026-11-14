# Write DICOM Segmentation Object (`dcmseg`)

Writes a
[dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
object to a standard DICOM Segmentation file (PS3.3 C.8.20).

## Usage

``` r
write_dicom_seg(seg, file)
```

## Arguments

- seg:

  A
  [dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
  object.

- file:

  Path to the output DICOM file.

## Value

Character path to the written DICOM file (invisibly).

## Examples

``` r
synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 4L))
vol <- read_dicom_volume(synth$files[1L])
m <- array(0L, dim = c(32L, 32L, 4L))
m[5:15, 5:15, 2L] <- 1L
seg <- dicom_seg(m, vol)
tmp_f <- file.path(tempdir(), "test_write_seg.dcm")
on.exit(unlink(tmp_f))
write_dicom_seg(seg, tmp_f)
```
