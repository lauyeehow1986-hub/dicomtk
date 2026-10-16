# Convert a DICOM File to JSON (DICOM JSON Model PS3.18)

Exports the DICOM header and dataset elements to standard DICOMWeb JSON
format (PS3.18).

## Usage

``` r
dcm2json(file, out_path = NULL)
```

## Arguments

- file:

  Path to input DICOM file.

- out_path:

  Optional output `.json` file path. If `NULL` (default), returns the
  JSON string directly.

## Value

Character string of DICOM JSON (or invisibly `out_path` if written to a
file).

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
json_txt <- dcm2json(dcm_file)
substr(json_txt, 1, 200)
#> [1] "{\n  \"00020001\": {\n    \"vr\": \"OB\",\n    \"Value\": [\"00\", \"01\"]\n  },\n  \"00020002\": {\n    \"vr\": \"UI\",\n    \"Value\": [\"1.2.840.10008.5.1.4.1.1.2\"]\n  },\n  \"00020003\": {\n    \"vr\": \"UI\",\n    \"Value\": [\"1.3.6.1."
```
