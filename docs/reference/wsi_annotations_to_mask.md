# Rasterize DICOM Sup 222 WSI Annotations into a 2D Label Mask

Rasterize DICOM Sup 222 WSI Annotations into a 2D Label Mask

## Usage

``` r
wsi_annotations_to_mask(annotations, level_dims = NULL)
```

## Arguments

- annotations:

  A `"dicom_wsi_annotations"` from
  [`dicom_wsi_annotations()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_wsi_annotations.md).

- level_dims:

  Optional `c(rows, cols)` override.

## Value

A 2D integer label matrix (`0L` = background, `1L..K` = ROI index).
