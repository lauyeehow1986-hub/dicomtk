# Build a Normalized 3-Table DICOM Archive Index (DuckDB / Parquet / Tibble)

Scans a DICOM directory (or header tibble) and constructs normalized
`studies`, `series`, and `instances` tables backed by `duckdb` (with
optional Parquet export) or a pure-R `tibble` fallback.

## Usage

``` r
dicom_index_build(
  path,
  db_path = ":memory:",
  parquet_dir = NULL,
  engine = c("auto", "duckdb", "tibble")
)
```

## Arguments

- path:

  Directory containing `.dcm` files, or a data frame from
  [`read_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom.md).

- db_path:

  Path to a DuckDB database file or `":memory:"`.

- parquet_dir:

  Optional directory where `studies.parquet`, `series.parquet`, and
  `instances.parquet` are written when `duckdb` is used.

- engine:

  Backend engine: `"auto"` (uses `duckdb` if installed, otherwise
  `"tibble"`), `"duckdb"`, or `"tibble"`.

## Value

A `"dicom_archive_index"` S3 object.
