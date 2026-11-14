# Rasterize Multiple 2D Polygons

Rasterizes multiple 2D planar polygons (e.g. outer contour and inner
holes) using either `"evenodd"` or `"nonzero"` winding fill rules.

## Usage

``` r
rasterize_polygons_2d(polygons, width, height, rule = c("evenodd", "nonzero"))
```

## Arguments

- polygons:

  A list of 2-column numeric matrices.

- width:

  Grid width.

- height:

  Grid height.

- rule:

  Fill rule: `"evenodd"` (default) or `"nonzero"`.

## Value

A logical matrix of dimension `height x width`.

## Examples

``` r
p1 <- matrix(c(2, 2, 18, 2, 18, 18, 2, 18), ncol = 2, byrow = TRUE)
p2 <- matrix(c(6, 6, 14, 6, 14, 14, 6, 14), ncol = 2, byrow = TRUE)
m <- rasterize_polygons_2d(list(p1, p2), 20L, 20L, rule = "evenodd")
sum(m)
#> [1] 216
```
