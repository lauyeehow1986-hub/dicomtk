# Build an HL7 FHIR `Provenance` Resource From De-Identification or Volume Provenance

Build an HL7 FHIR `Provenance` Resource From De-Identification or Volume
Provenance

## Usage

``` r
as_fhir_provenance(
  x,
  target_ref = "ImagingStudy/unknown",
  agent_name = "dicomtk"
)
```

## Arguments

- x:

  A result from
  [`dicom_deid()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid.md)
  or a `dicom_volume` object.

- target_ref:

  FHIR target resource reference.

- agent_name:

  Software/pipeline agent identifier.

## Value

A named list representing a FHIR `Provenance` resource.
