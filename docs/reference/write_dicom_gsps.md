# Write a DICOM Grayscale Softcopy Presentation State (GSPS) Object

Creates a standard DICOM Grayscale Softcopy Presentation State Storage
(`1.2.840.10008.5.1.4.1.1.11.1`, `Modality = "PR"`) file containing
vector graphic annotations (`GraphicObjectSequence (0070,0009)`), text
labels (`TextObjectSequence (0070,0008)`), graphic layers
(`GraphicLayerSequence (0070,0060)`), and softcopy VOI LUT windowing
parameters without altering the underlying image pixel data.

## Usage

``` r
write_dicom_gsps(
  annotations,
  out_path,
  ref_volume = NULL,
  window_center = NULL,
  window_width = NULL,
  content_label = "GSPS_ANNOTATIONS"
)
```

## Arguments

- annotations:

  A `data.frame` or
  [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
  with columns:

  - `slice`: 1-based slice index (optional, default `1L`).

  - `layer`: Graphic layer name (optional, default `"LAYER_1"`).

  - `graphic_type`: One of `"POINT"`, `"POLYLINE"`, `"INTERPOLATED"`,
    `"CIRCLE"`, or `"ELLIPSE"`.

  - `coords`: A list-column of numeric vectors `c(x1, y1, x2, y2, ...)`
    giving 2D pixel coordinates.

  - `text`: Optional character column with text annotation labels (`NA`
    or `""` for no text).

- out_path:

  Path to the output `.dcm` presentation state file.

- ref_volume:

  Optional reference
  [dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  to link Study/Series UIDs.

- window_center:

  Optional numeric VOI LUT `WindowCenter (0028,1050)`.

- window_width:

  Optional numeric VOI LUT `WindowWidth (0028,1051)`.

- content_label:

  Presentation state `ContentLabel (0070,0080)`. Default is
  `"GSPS_ANNOTATIONS"`.

## Value

Normalized path to `out_path` (invisibly).

## Examples

``` r
ann <- tibble::tibble(
  slice = 1L,
  layer = "ROI_LAYER",
  graphic_type = "POLYLINE",
  coords = list(c(10, 10, 20, 10, 20, 20, 10, 20, 10, 10)),
  text = "Target ROI"
)
tmp_pr <- tempfile(fileext = ".dcm")
write_dicom_gsps(ann, tmp_pr, window_center = 40, window_width = 400)
ps <- read_dicom_gsps(tmp_pr)
ps$graphics
#> # A tibble: 1 × 5
#>   layer     graphic_type n_points coords     units
#>   <chr>     <chr>           <int> <list>     <chr>
#> 1 ROI_LAYER POLYLINE            5 <dbl [10]> PIXEL
unlink(tmp_pr)
```
