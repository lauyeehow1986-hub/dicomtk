# Read DICOM Grayscale Softcopy Presentation State (`dcmpstat`)

Extracts display shutter, VOI LUT, graphic annotation (`0x0070`), and
spatial transformation parameters from a DICOM Presentation State (`PR`)
object.

## Usage

``` r
read_dicom_pstate(path)
```

## Arguments

- path:

  Path to a DICOM Presentation State file.

## Value

A list of class `"dicom_pstate"` containing `annotations` (group
`0x0070` elements), `voi_lut` (window/LUT attributes), and `header`.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
ps <- read_dicom_pstate(dcm_file)
ps
#> ℹ DICOM Presentation State (Annotations: 0, VOI LUT entries: 4)
```
