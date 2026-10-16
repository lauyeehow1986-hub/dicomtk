# Apply VOI LUT Window/Level Transformation to DICOM Pixels

Applies linear window/level (Window Center and Window Width)
transformation to a DICOM pixel matrix or array, normalizing output
values to `[0, 1]`. Supports standard clinical CT window presets
(`"brain"`, `"lung"`, `"bone"`, `"abdomen"`, `"mediastinum"`, `"liver"`,
`"stroke"`, `"subdural"`, `"angio"`), embedded DICOM
`WindowCenter`/`WindowWidth` tags (`"auto"`), or custom numeric `center`
and `width`.

## Usage

``` r
dicom_window(x, center = NULL, width = NULL, preset = "auto", invert = NULL)
```

## Arguments

- x:

  A `"dicom_pixels"` array/matrix or a file path to a DICOM file.

- center:

  Numeric window center (level). Overrides `preset` if both `center` and
  `width` are provided.

- width:

  Numeric window width (must be `> 0`).

- preset:

  Character preset name (`"auto"`, `"brain"`, `"stroke"`, `"subdural"`,
  `"lung"`, `"mediastinum"`, `"abdomen"`, `"liver"`, `"bone"`,
  `"angio"`) or numeric vector `c(center, width)`. Default is `"auto"`.

- invert:

  Optional logical to invert grayscale intensities. By default,
  automatically inverts if `PhotometricInterpretation == "MONOCHROME1"`.

## Value

A numeric matrix/array of the same dimensions as `x` with values scaled
to `[0, 1]`.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
px <- read_dicom_pixels(dcm_file)
win_auto <- dicom_window(px, preset = "auto")
range(win_auto)
#> [1] 0 1
```
