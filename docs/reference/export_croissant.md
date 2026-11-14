# Export MLCommons Croissant 1.0 Dataset Metadata

Generates an MLCommons Croissant 1.0 compliant `croissant.json` file in
`out_dir`.

## Usage

``` r
export_croissant(
  out_dir,
  name,
  description,
  num_records = NULL,
  license = "CC-BY-4.0"
)
```

## Arguments

- out_dir:

  Directory where `croissant.json` will be written.

- name:

  Dataset title.

- description:

  Dataset description.

- num_records:

  Optional integer count of records in the dataset.

- license:

  SPDX license identifier (default `"CC-BY-4.0"`).

## Value

Invisibly returns the path to `croissant.json`.
