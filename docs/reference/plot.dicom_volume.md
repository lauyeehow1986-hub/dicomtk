# Plot a `dicom_volume` Object

Visualizes a 3D/4D `dicom_volume` as a 3-plane orthogonal Multi-Planar
Reconstruction (`method = "mpr"`) or Maximum Intensity Projection
(`method = "mip"`) via
[`render_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/render_volume.md),
or renders a single 2D slice via
[`ggdicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/ggdicom.md)
when `dim(x)[3] == 1` or `slice` is specified.

## Usage

``` r
# S3 method for class 'dicom_volume'
plot(
  x,
  y = NULL,
  ...,
  slice = NULL,
  method = c("mpr", "mip", "rgl"),
  window = "auto",
  threshold = 0.5,
  palette = c("gray", "viridis", "inferno", "magma", "plasma"),
  frame = 1L
)
```

## Arguments

- x:

  A `dicom_volume` object.

- y:

  Unused (included for S3 generic compatibility with
  [`base::plot()`](https://rdrr.io/r/base/plot.html)). If supplied as a
  single numeric value while `slice` is `NULL`, treated as `slice`.

- ...:

  Additional arguments passed to
  [`ggdicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/ggdicom.md)
  for single-slice rendering (e.g. `center`, `width`, `annotate`,
  `title`).

- slice:

  Optional 1-based integer slice index to plot a single 2D slice.

- method:

  Volume rendering mode when plotting 3D volumes: `"mpr"` (default),
  `"mip"`, or `"rgl"`.

- window:

  Window preset (`"auto"`, `"brain"`, `"lung"`, `"bone"`, etc.) or
  `c(center, width)`. Default is `"auto"`.

- threshold:

  Intensity threshold in `[0, 1]` when `method = "rgl"`. Default is
  `0.5`.

- palette:

  Color palette (`"gray"`, `"viridis"`, `"inferno"`, `"magma"`,
  `"plasma"`). Default is `"gray"`.

- frame:

  1-based temporal frame index when `x` is a 4D volume. Default is `1L`.

## Value

A [ggplot2::ggplot](https://ggplot2.tidyverse.org/reference/ggplot.html)
object (or invisibly the `rgl` scene ID when `method = "rgl"` and `rgl`
is installed).

## Examples

``` r
vox <- array(seq_len(12 * 12 * 4), dim = c(12L, 12L, 4L))
vol <- new_dicom_volume(vox, affine = diag(c(0.8, 0.8, 2.5, 1.0)), modality = "CT")
plot(vol, method = "mpr")

plot(vol, slice = 2L)
```
