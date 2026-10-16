# Read DICOM Segmentation Objects (`dcmseg`)

Reads a DICOM Segmentation (`SEG`) dataset, extracting segment
descriptions (`SegmentSequence (0062,0002)`) and the binary/fractional
3D segmentation mask array.

## Usage

``` r
read_dicom_seg(path)
```

## Arguments

- path:

  Path to a DICOM Segmentation file.

## Value

A list of class `"dicom_seg"` containing `segments` (tibble of segment
metadata) and `mask` (pixel/voxel mask array).

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
seg <- read_dicom_seg(dcm_file)
dim(seg$mask)
#> [1] 512 512
```
