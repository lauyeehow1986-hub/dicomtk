# Validate That a SQL String Is Strictly Read-Only and Free of File-Access Functions

Enforces an unbypassable read-only SQL policy for natural-language
cohort queries against a
[`dicom_index_build()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_index_build.md)
index. Rejects SQL comments, multi-statement semicolons, DDL/DML/admin
statements, and DuckDB host-file reader functions.

## Usage

``` r
validate_readonly_sql(sql)
```

## Arguments

- sql:

  Character SQL string to validate.

## Value

Invisibly returns `TRUE` if valid; otherwise aborts via
[`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html).

## Examples

``` r
validate_readonly_sql("SELECT StudyInstanceUID, Modality FROM series WHERE Modality = 'CT'")
```
