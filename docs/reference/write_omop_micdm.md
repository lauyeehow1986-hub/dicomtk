# Write and Validate OHDSI OMOP MI-CDM Tables in a DBI / DuckDB Database

Write and Validate OHDSI OMOP MI-CDM Tables in a DBI / DuckDB Database

## Usage

``` r
write_omop_micdm(con, occurrence_df, feature_df)
```

## Arguments

- con:

  An active `DBI` connection (e.g., DuckDB or PostgreSQL).

- occurrence_df:

  Data frame from
  [`to_omop_image_occurrence()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_omop_image_occurrence.md).

- feature_df:

  Data frame from
  [`to_omop_image_feature()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_omop_image_feature.md).

## Value

A list with `valid_fk`, `n_occurrences`, and `n_features`.
