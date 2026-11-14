# Check or Synchronize with Upstream OFFIS DCMTK Repository

Checks the official upstream DCMTK GitHub mirror
(`https://github.com/DCMTK/dcmtk`) for new commits, dictionary releases,
or C++ module header updates, and optionally synchronizes a local
`dicomtk` source checkout by running `tools/bundle_dcmtk.R`.

## Usage

``` r
dicom_sync_upstream(pkg_dir = ".", apply = FALSE, repo = "DCMTK/dcmtk")
```

## Arguments

- pkg_dir:

  Optional path to a local `dicomtk` package source directory when
  `apply = TRUE`. Defaults to `"."`.

- apply:

  Logical; if `TRUE`, clones the latest `DCMTK/dcmtk` `master` branch
  and executes `tools/bundle_dcmtk.R` inside `pkg_dir`. Default is
  `FALSE` (check-only mode).

- repo:

  GitHub repository slug. Default is `"DCMTK/dcmtk"`.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
summarizing the bundled DCMTK version/commit, the latest upstream commit
SHA/date/message from GitHub, and whether the bundle is up to date.

## Examples

``` r
# \donttest{
dicom_sync_upstream(apply = FALSE)
#> # A tibble: 1 × 6
#>   bundled_version bundled_commit upstream_commit upstream_date  upstream_message
#>   <chr>           <chr>          <chr>           <chr>          <chr>           
#> 1 3.7.1           108acdae424d   a435c17e0fb4    2026-11-12T20… Try fixing rema…
#> # ℹ 1 more variable: up_to_date <lgl>
# }
```
