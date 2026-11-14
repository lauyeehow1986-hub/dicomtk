# Stitch an Arbitrary Rectangular Region Across WSI Tile Boundaries

Stitch an Arbitrary Rectangular Region Across WSI Tile Boundaries

## Usage

``` r
wsi_stitch_region(
  pyramid,
  level = 1L,
  x = 1L,
  y = 1L,
  width = 32L,
  height = 32L
)
```

## Arguments

- pyramid:

  A `"dicom_wsi_pyramid"` from
  [`read_dicom_wsi_pyramid()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_wsi_pyramid.md).

- level:

  1-based pyramid level.

- x:

  1-based starting column coordinate.

- y:

  1-based starting row coordinate.

- width:

  Region width in pixels.

- height:

  Region height in pixels.

## Value

A 2D numeric matrix of dimensions `height x width`.
