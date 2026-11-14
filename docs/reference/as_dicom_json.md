# Convert DICOM Header Tibble to PS3.18 DICOM JSON Model

Serializes a tidy header tibble from
[`read_dicom_header()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_header.md)
into a DICOM PS3.18 JSON Model list
(`{"gggggggg": {"vr": ..., "Value": [...]}}`).

## Usage

``` r
as_dicom_json(hdr)
```

## Arguments

- hdr:

  A data frame returned by
  [`read_dicom_header()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_header.md).

## Value

A named list conforming to the DICOM PS3.18 JSON Model.

## Examples

``` r
dcm <- system.file("extdata", "example.dcm", package = "dicomtk")
if (nzchar(dcm)) {
  dj <- as_dicom_json(read_dicom_header(dcm))
  names(dj)[1:3]
}
#> [1] "00020001" "00020002" "00020003"
```
