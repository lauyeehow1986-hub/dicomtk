# Render a 3D DICOM Volume (Orthogonal MPR, MIP, or Interactive rgl 3D)

Visualizes a 3D DICOM series (`"dicom_series"` or 3D numeric array)
using:

- `"mpr"`: 3-plane Orthogonal Multi-Planar Reconstruction (Axial,
  Coronal, Sagittal slices) via `ggplot2`.

- `"mip"`: Maximum Intensity Projection across Axial, Coronal, and
  Sagittal orientations via `ggplot2`.

- `"rgl"`: Interactive 3D voxel rendering using the `rgl` package (falls
  back to `"mip"` if `rgl` is not installed).

## Usage

``` r
render_volume(
  x,
  method = c("mpr", "mip", "rgl"),
  window = "auto",
  threshold = 0.5,
  palette = c("gray", "viridis", "inferno", "magma", "plasma")
)
```

## Arguments

- x:

  A `"dicom_series"` object (from
  [`read_dicom_series()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_series.md)),
  a 3D numeric array `[rows, cols, slices]`, or a directory/vector of
  DICOM file paths.

- method:

  Visualization mode: `"mpr"` (default), `"mip"`, or `"rgl"`.

- window:

  Window preset (`"auto"`, `"brain"`, `"lung"`, `"bone"`, etc.) or
  `c(center, width)`. Default is `"auto"`.

- threshold:

  Optional intensity threshold in `[0, 1]` for 3D `"rgl"` point-cloud /
  surface rendering. Default is `0.5`.

- palette:

  Color palette (`"gray"`, `"viridis"`, `"inferno"`, `"magma"`,
  `"plasma"`). Default is `"gray"`.

## Value

A [ggplot2::ggplot](https://ggplot2.tidyverse.org/reference/ggplot.html)
object (for `"mpr"` and `"mip"`) or invisibly the `rgl` scene ID (for
`"rgl"`).

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
series <- read_dicom_series(c(dcm_file, dcm_file, dcm_file))
render_volume(series, method = "mpr")

render_volume(series, method = "mip")
```
