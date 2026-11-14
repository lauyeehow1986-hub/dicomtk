# Synthesize a Multi-Resolution DICOM WSI Pyramid for Testing

Generates a synthetic tiled Whole Slide Imaging (WSI) directory
hierarchy with real DICOM Part 10 tile files and level metadata
supporting both `"TILED_FULL"` and `"TILED_SPARSE"` dimension
organizations.

## Usage

``` r
dicom_synthesize_wsi(
  out_dir = tempfile("wsi_"),
  base_dims = c(64L, 64L),
  tile_dims = c(16L, 16L),
  levels = 2L,
  organization = c("TILED_FULL", "TILED_SPARSE")
)
```

## Arguments

- out_dir:

  Output directory path.

- base_dims:

  Base (Level 1) pixel matrix dimensions `c(rows, cols)`.

- tile_dims:

  Tile dimensions `c(tile_rows, tile_cols)`.

- levels:

  Number of pyramid levels to synthesize (default `2L`).

- organization:

  Either `"TILED_FULL"` or `"TILED_SPARSE"`.

## Value

A list with `out_dir`, `levels`, and `level_arrays` (ground-truth 2D
numeric matrices per level).
