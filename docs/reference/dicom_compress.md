# Compress a DICOM File (Lossless RLE)

Compresses native uncompressed pixel data into DICOM Lossless RLE
transfer syntax (`1.2.840.10008.1.2.5`, per DICOM PS3.5 Annex G).

## Usage

``` r
dicom_compress(path, out_path = tempfile(fileext = ".dcm"), method = c("rle"))
```

## Arguments

- path:

  Input DICOM file path.

- out_path:

  Output compressed DICOM file path. Defaults to a temporary `.dcm`
  file.

- method:

  Compression method (`"rle"`).

## Value

Invisibly returns `out_path`.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
rle_file <- dicom_compress(dcm_file)
file.exists(rle_file)
#> [1] TRUE
```
