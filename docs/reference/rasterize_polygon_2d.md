# 2D Polygon Rasterization

Rasterizes a 2D planar polygon into a binary mask of dimensions
`height x width`.

## Usage

``` r
rasterize_polygon_2d(coords, width, height)
```

## Arguments

- coords:

  A 2-column numeric matrix of (x, y) vertex coordinates.

- width:

  Grid width (number of columns).

- height:

  Grid height (number of rows).

## Value

A logical matrix of dimension `height x width`.

## Examples

``` r
poly <- matrix(c(5, 5, 15, 5, 15, 15, 5, 15), ncol = 2, byrow = TRUE)
m <- rasterize_polygon_2d(poly, 20L, 20L)
sum(m)
#> [1] 110
```
