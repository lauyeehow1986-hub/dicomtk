# Convert DICOM Processing Provenance to W3C PROV-JSON

Convert DICOM Processing Provenance to W3C PROV-JSON

## Usage

``` r
as_w3c_prov(x, agent_name = "dicomtk")
```

## Arguments

- x:

  A result from
  [`dicom_deid()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid.md)
  or a `dicom_volume` object.

- agent_name:

  Software agent identifier.

## Value

A named list conforming to W3C PROV-JSON (`entity`, `activity`,
`agent`).
