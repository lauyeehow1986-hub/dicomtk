# Extract a Single Tile from a DICOM WSI Pyramid Out-of-Core

Extract a Single Tile from a DICOM WSI Pyramid Out-of-Core

## Usage

``` r
wsi_extract_tile(pyramid, level = 1L, tile_row = 1L, tile_col = 1L)
```

## Arguments

- pyramid:

  A `"dicom_wsi_pyramid"` from
  [`read_dicom_wsi_pyramid()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_wsi_pyramid.md).

- level:

  1-based pyramid level (1 = highest resolution).

- tile_row:

  1-based tile row index.

- tile_col:

  1-based tile column index.

## Value

A 2D numeric matrix of dimensions `tile_rows x tile_cols`.
