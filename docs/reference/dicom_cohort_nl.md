# Build and Execute a Guardrailed Natural-Language Cohort Query

Translates a natural-language cohort description into a validated
read-only `SELECT` SQL query against a `dicom_archive_index` (using
deterministic clinical parsing offline, or an `llm` chat session when
online).

## Usage

``` r
dicom_cohort_nl(index, prompt, llm = dicom_llm("offline"), execute = TRUE)
```

## Arguments

- index:

  A `"dicom_archive_index"` object from
  [`dicom_index_build()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_index_build.md).

- prompt:

  Natural-language cohort description (e.g.,
  `"CT chest series with at least 2 instances"`).

- llm:

  Optional `dicom_llm` object (default `dicom_llm("offline")`).

- execute:

  Logical. Execute the validated SQL query immediately (`TRUE`).

## Value

A list of class `"dicom_cohort_query"` with `prompt`, `sql`, `criteria`,
and `results`.
