# Export RO-Crate 1.1 Dataset Metadata

Generates an RO-Crate 1.1 compliant `ro-crate-metadata.json` file in
`out_dir`.

## Usage

``` r
export_rocrate(out_dir, name, description, files = NULL, license = "CC-BY-4.0")
```

## Arguments

- out_dir:

  Directory where `ro-crate-metadata.json` will be written.

- name:

  Dataset title.

- description:

  Dataset description.

- files:

  Optional character vector of relative file paths to include in the
  crate graph.

- license:

  SPDX license identifier (default `"CC-BY-4.0"`).

## Value

Invisibly returns the path to `ro-crate-metadata.json`.
