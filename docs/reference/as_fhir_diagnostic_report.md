# Build an HL7 FHIR `DiagnosticReport` Resource From a DICOM SR / TID 1500 Report

Build an HL7 FHIR `DiagnosticReport` Resource From a DICOM SR / TID 1500
Report

## Usage

``` r
as_fhir_diagnostic_report(
  sr,
  patient_ref = "Patient/unknown",
  imaging_study_ref = NULL
)
```

## Arguments

- sr:

  A structured report object from
  [`read_sr_tid1500()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_sr_tid1500.md)
  or
  [`read_dicom_sr()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_sr.md).

- patient_ref:

  FHIR Patient reference string.

- imaging_study_ref:

  Optional FHIR `ImagingStudy` reference string.

## Value

A named list representing a FHIR `DiagnosticReport` with `contained`
`Observation` resources.
