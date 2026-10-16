# Create a ggplot2 DICOM Image Object

Alias for
[`plot_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/plot_dicom.md)
designed for composable `ggplot2` pipelines.

## Usage

``` r
ggdicom(x, frame = 1L, window = "auto", ...)
```

## Arguments

- x:

  Path to a DICOM file, a `"dicom_pixels"` matrix/array, or a
  `"dicom_series"` object.

- frame:

  Integer slice/frame index (1-based) when `x` is multi-frame or a
  `"dicom_series"`. Default is `1L`.

- window:

  Window preset (`"auto"`, `"brain"`, `"lung"`, `"bone"`, `"abdomen"`,
  etc.) or `c(center, width)`. Default is `"auto"`.

- ...:

  Additional arguments passed to
  [`plot_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/plot_dicom.md).

## Value

A [ggplot2::ggplot](https://ggplot2.tidyverse.org/reference/ggplot.html)
object.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
ggdicom(dcm_file, palette = "viridis")
```
