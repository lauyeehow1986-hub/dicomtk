# Build an HL7 FHIR R5 `ImagingSelection` Resource From a Segmentation or GSPS

Build an HL7 FHIR R5 `ImagingSelection` Resource From a Segmentation or
GSPS

## Usage

``` r
as_fhir_imaging_selection(x, study_ref = "ImagingStudy/unknown")
```

## Arguments

- x:

  A `dicom_seg` or `dicom_gsps` object.

- study_ref:

  FHIR `ImagingStudy` reference string.

## Value

A named list representing a FHIR `ImagingSelection` resource.
