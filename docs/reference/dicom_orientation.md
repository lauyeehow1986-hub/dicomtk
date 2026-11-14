# Query Anatomical Orientation of a DICOM Volume

Determines the standard 3-letter patient anatomical orientation code
(e.g., `"LPS"` for axial, `"LIP"` for coronal, `"PIR"` for sagittal)
giving the physical patient direction (`L`/`R`, `P`/`A`, `S`/`I`) of
increasing image columns (`d_row`), rows (`d_col`), and slices (`normal`
/ slice step).

## Usage

``` r
dicom_orientation(vol, coord_system = c("LPS", "RAS"))
```

## Arguments

- vol:

  A `dicom_volume` object, or a finite numeric `3x3` / `4x4`
  `dicom_volume`-style affine matrix (column 1 = row step, column 2 =
  column step, column 3 = slice step).

- coord_system:

  World coordinate convention (`"LPS"` or `"RAS"`) used when `vol` is a
  raw numeric matrix. Ignored when `vol` is a `dicom_volume` (whose
  `vol$coord_system` is used automatically).

## Value

A length-1 3-character string naming the anatomical orientation (e.g.,
`"LPS"`, `"LIP"`, `"PIR"`).

## Examples

``` r
aff <- diag(4L)
aff[1:3, 1:3] <- matrix(c(0, 0.8, 0, 0.8, 0, 0, 0, 0, 2.5), nrow = 3L)
vol <- new_dicom_volume(array(0, dim = c(8L, 8L, 4L)), affine = aff, coord_system = "LPS")
dicom_orientation(vol)
#> [1] "LPS"
```
