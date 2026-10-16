# Export a DICOM Image Slice to PNG

Renders a DICOM slice with window/level transformation to a PNG image
file.

## Usage

``` r
dicom_to_png(
  path,
  out_path = tempfile(fileext = ".png"),
  frame = 1L,
  window = "auto",
  width = NULL,
  height = NULL
)
```

## Arguments

- path:

  Path to a DICOM file, or a `"dicom_pixels"` matrix/array.

- out_path:

  Output PNG file path. Defaults to a temporary `.png` file.

- frame:

  Integer frame/slice index (1-based). Default is `1L`.

- window:

  Window preset name (e.g., `"auto"`, `"brain"`, `"lung"`, `"bone"`,
  `"abdomen"`) or numeric `c(center, width)`. Default is `"auto"`.

- width, height:

  Output PNG dimensions in pixels. Defaults to the native DICOM image
  dimensions.

## Value

Invisibly returns `out_path`.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
png_file <- dicom_to_png(dcm_file)
file.exists(png_file)
#> [1] TRUE
```
