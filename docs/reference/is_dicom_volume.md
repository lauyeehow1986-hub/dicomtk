# Test Whether an Object Is a `dicom_volume`

Test Whether an Object Is a `dicom_volume`

## Usage

``` r
is_dicom_volume(x)
```

## Arguments

- x:

  An R object.

## Value

`TRUE` if `x` inherits from `"dicom_volume"`, otherwise `FALSE`.

## Examples

``` r
vol <- new_dicom_volume(array(0, dim = c(4L, 4L, 2L)))
is_dicom_volume(vol)
#> [1] TRUE
is_dicom_volume(array(0, dim = c(4L, 4L, 2L)))
#> [1] FALSE
```
