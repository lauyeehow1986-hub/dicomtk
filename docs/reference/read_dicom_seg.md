# Read DICOM Segmentation Objects (`dcmseg`)

Reads a DICOM Segmentation (`SEG`) dataset, extracting segment
descriptions (`SegmentSequence (0062,0002)`) and the binary/fractional
3D segmentation mask array, optionally constructing a unified
[dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
object if a reference
[dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
is supplied.

## Usage

``` r
read_dicom_seg(path, ref_volume = NULL)
```

## Arguments

- path:

  Path to a DICOM Segmentation file.

- ref_volume:

  Optional reference
  [dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  providing spatial geometry.

## Value

An object of class
[dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
(if `ref_volume` is provided or can be derived) or a list of class
`"dicom_seg"`.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
seg <- read_dicom_seg(dcm_file)
seg$modality
#> NULL
```
