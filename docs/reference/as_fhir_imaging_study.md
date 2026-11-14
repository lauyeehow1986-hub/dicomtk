# Build an HL7 FHIR R4/R5 `ImagingStudy` Resource

Converts a `dicom_volume`, DICOM directory path, or header summary
tibble into an HL7 FHIR `ImagingStudy` resource list.

## Usage

``` r
as_fhir_imaging_study(x, patient_ref = "Patient/unknown", endpoint_ref = NULL)
```

## Arguments

- x:

  A `dicom_volume` object, a directory/file path, or a data frame from
  [`read_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom.md).

- patient_ref:

  FHIR Patient reference (e.g., `"Patient/p-001"`).

- endpoint_ref:

  Optional FHIR Endpoint reference.

## Value

A named list representing a FHIR `ImagingStudy` resource.

## Examples

``` r
synth <- dicom_synthesize(modality = "CT", dims = c(8L, 8L, 2L))
on.exit(unlink(synth$out_dir, recursive = TRUE), add = TRUE)
vol <- read_dicom_volume(synth$out_dir)
#> Error in resolve_dicom_paths(path, recursive = recursive): Path does not exist: C:/Users/lauye/AppData/Local/Temp/RtmpENsyff/dicom_synth_26c87be2540c
as_fhir_imaging_study(vol, patient_ref = "Patient/p-001")$resourceType
#> Error: object 'vol' not found
```
