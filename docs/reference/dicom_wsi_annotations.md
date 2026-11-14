# Construct DICOM Supplement 222 Microscopy Bulk Simple Annotations

Construct DICOM Supplement 222 Microscopy Bulk Simple Annotations

## Usage

``` r
dicom_wsi_annotations(
  rois,
  coordinate_type = c("2D", "3D"),
  pixel_matrix_dims = c(64L, 64L)
)
```

## Arguments

- rois:

  List of ROI descriptors, each a list with `label`, `type`
  (`"POLYGON"`, `"POLYLINE"`, or `"POINT"`), and `coords` (2-column
  matrix of `(x, y)` coordinates).

- coordinate_type:

  Either `"2D"` (pixel matrix) or `"3D"` (slide stage).

- pixel_matrix_dims:

  Integer vector `c(rows, cols)` of the target level.

## Value

An S3 `"dicom_wsi_annotations"` object.

## Examples

``` r
rois <- list(list(
  label = "tumor",
  type = "POLYGON",
  coords = matrix(c(4, 4, 12, 4, 12, 12, 4, 12), ncol = 2, byrow = TRUE)
))
ann <- dicom_wsi_annotations(rois, pixel_matrix_dims = c(32L, 32L))
ann$sop_class_uid
#> [1] "1.2.840.10008.5.1.4.1.1.91.1"
```
