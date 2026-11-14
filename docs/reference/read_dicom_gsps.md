# Read a DICOM Grayscale Softcopy Presentation State (GSPS) Object

Parses a DICOM Grayscale Softcopy Presentation State (`PR`) file and
extracts vector graphic objects (`GraphicObjectSequence (0070,0009)`),
text labels (`TextObjectSequence (0070,0008)`), and VOI LUT windowing
parameters into tidy tibbles.

## Usage

``` r
read_dicom_gsps(path)
```

## Arguments

- path:

  Path to a DICOM GSPS `.dcm` file.

## Value

An S3 object of class `c("dicom_gsps", "dicom_pstate")` containing:

- graphics:

  A tibble with columns `layer`, `graphic_type`, `n_points`, `coords`
  (list of numeric vectors), and `units`.

- texts:

  A tibble with columns `layer`, `text`, `anchor_col`, and `anchor_row`.

- window_center:

  Numeric `WindowCenter` (or `NA_real_`).

- window_width:

  Numeric `WindowWidth` (or `NA_real_`).

- annotations:

  Raw group `0x0070` header rows.

- voi_lut:

  Raw VOI LUT header rows.

- header:

  Top-level DICOM header tibble.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
gsps <- read_dicom_gsps(dcm_file)
gsps$graphics
#> # A tibble: 0 × 5
#> # ℹ 5 variables: layer <chr>, graphic_type <chr>, n_points <int>,
#> #   coords <list>, units <chr>
```
