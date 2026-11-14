# Trace Contours from 2D Binary Mask

Extracts ordered planar polygon vertices from a 2D binary mask using
marching squares.

## Usage

``` r
trace_contours_2d(mask)
```

## Arguments

- mask:

  A 2D logical matrix.

## Value

A list of 2-column numeric matrices representing closed contour loops.

## Examples

``` r
m <- matrix(FALSE, 20L, 20L)
m[5:15, 5:15] <- TRUE
polys <- trace_contours_2d(m)
length(polys)
#> [1] 1
```
