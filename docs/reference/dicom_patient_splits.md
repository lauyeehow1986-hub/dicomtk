# Generate Leakage-Free Patient-Level Train / Validation / Test Splits

Partitions a cohort manifest `data.frame` or
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
into `"train"`, `"val"`, and `"test"` splits strictly grouped by
`patient_col` so that all series and studies belonging to a patient
remain in the same fold.

## Usage

``` r
dicom_patient_splits(
  cohort,
  patient_col = "patient_id",
  val_frac = 0.15,
  test_frac = 0.15,
  seed = NULL
)
```

## Arguments

- cohort:

  A `data.frame` or
  [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
  with one row per scan/series.

- patient_col:

  Name of the patient identifier column. Default is `"patient_id"`.

- val_frac:

  Fraction of patients assigned to validation. Default is `0.15`.

- test_frac:

  Fraction of patients assigned to test. Default is `0.15`.

- seed:

  Optional integer random seed for reproducible splitting.

## Value

The input `cohort` tibble with an added `split` character column
(`"train"`, `"val"`, or `"test"`).

## Examples

``` r
df <- tibble::tibble(
  patient_id = rep(paste0("P", 1:10), each = 2L),
  series = seq_len(20L)
)
dicom_patient_splits(df, val_frac = 0.2, test_frac = 0.2, seed = 42L)
#> # A tibble: 20 × 3
#>    patient_id series split
#>    <chr>       <int> <chr>
#>  1 P1              1 val  
#>  2 P1              2 val  
#>  3 P2              3 train
#>  4 P2              4 train
#>  5 P3              5 train
#>  6 P3              6 train
#>  7 P4              7 train
#>  8 P4              8 train
#>  9 P5              9 val  
#> 10 P5             10 val  
#> 11 P6             11 train
#> 12 P6             12 train
#> 13 P7             13 train
#> 14 P7             14 train
#> 15 P8             15 test 
#> 16 P8             16 test 
#> 17 P9             17 train
#> 18 P9             18 train
#> 19 P10            19 test 
#> 20 P10            20 test 
```
