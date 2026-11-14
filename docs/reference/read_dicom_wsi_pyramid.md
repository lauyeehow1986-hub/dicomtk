# Read a Multi-Resolution DICOM WSI Pyramid Index

Reads a Whole Slide Imaging (WSI) directory containing
`wsi_pyramid.json` or tiled DICOM `SM` / `DX` files, organizing pyramid
levels from highest resolution (Level 1) to lowest resolution overview.

## Usage

``` r
read_dicom_wsi_pyramid(path)
```

## Arguments

- path:

  Directory path containing the WSI pyramid.

## Value

An S3 `"dicom_wsi_pyramid"` object with `levels` (tibble) and
`tile_index` (per-level tile lookup).
