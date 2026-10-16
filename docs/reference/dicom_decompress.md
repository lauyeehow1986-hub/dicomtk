# Decompress an Encapsulated DICOM File

Decompresses RLE-compressed (or encapsulated) DICOM files into standard
Explicit VR Little Endian (`1.2.840.10008.1.2.1`) uncompressed DICOM
format.

## Usage

``` r
dicom_decompress(path, out_path = tempfile(fileext = ".dcm"))
```

## Arguments

- path:

  Input compressed DICOM file path.

- out_path:

  Output uncompressed DICOM file path. Defaults to a temporary `.dcm`
  file.

## Value

Invisibly returns `out_path`.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
rle_file <- dicom_compress(dcm_file)
dec_file <- dicom_decompress(rle_file)
is_dicom(dec_file)
#> [1] TRUE
```
