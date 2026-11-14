# Derive Patient Shift Days from Key or Provider

Convenience helper for date shifting given either a raw 32-byte key or a
`dicom_key_provider`.

## Usage

``` r
derive_patient_shift_days(key, patient_id, date_range = c(-3650L, -30L))
```

## Arguments

- key:

  A 32-byte raw vector or a `dicom_key_provider`.

- patient_id:

  Character string of patient identifier.

- date_range:

  Integer vector of length 2 giving `c(min_days, max_days)`.

## Value

Integer day shift.
