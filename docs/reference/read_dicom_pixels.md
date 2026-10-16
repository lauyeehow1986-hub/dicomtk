# Extract Pixel Data from a DICOM File

Reads and decodes 8-bit, 16-bit, or 32-bit monochrome or RGB pixel data
(including RLE-compressed frames) directly into an R matrix or array,
applying Modality LUT (`RescaleSlope` and `RescaleIntercept`) when
`rescale = TRUE`.

## Usage

``` r
read_dicom_pixels(path, frame = 0L, rescale = TRUE)
```

## Arguments

- path:

  Path to a single DICOM file.

- frame:

  Integer frame number (1-indexed). Use `0` (default) to read all
  frames.

- rescale:

  Logical. Apply `RescaleSlope` and `RescaleIntercept` to convert stored
  pixel values to modality units (e.g., Hounsfield Units for CT).
  Default is `TRUE`.

## Value

A numeric matrix `[rows, cols]` (for single-frame monochrome) or 3D/4D
array `[rows, cols, frames/channels]` with class `"dicom_pixels"` and
DICOM imaging metadata attached as attributes.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
px <- read_dicom_pixels(dcm_file)
dim(px)
#> [1] 512 512
```
