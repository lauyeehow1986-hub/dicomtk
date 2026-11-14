# Compute Per-Patient Date Shift

Computes a deterministic integer day shift for a given patient
identifier, bounded within `date_range`.

## Usage

``` r
deid_patient_shift(key_provider, patient_id, date_range = c(-3650L, -30L))
```

## Arguments

- key_provider:

  A `dicom_key_provider` object.

- patient_id:

  Character vector of patient identifiers.

- date_range:

  Integer vector of length 2 giving `c(min_days, max_days)`. Defaults to
  `c(-3650L, -30L)`.

## Value

Integer vector of day shift values.

## Examples

``` r
kp <- dicom_key_provider(passphrase = "secret", salt = "salt")
deid_patient_shift(kp, "PAT001", c(-3650L, -30L))
#> [1] -537
```
