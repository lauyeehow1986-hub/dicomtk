# Parse an HL7 FHIR `ImagingStudy` Resource Into a Tidy Tibble

Parse an HL7 FHIR `ImagingStudy` Resource Into a Tidy Tibble

## Usage

``` r
from_fhir_imaging_study(study)
```

## Arguments

- study:

  A FHIR `ImagingStudy` list or JSON string.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with one row per series (`study_uid`, `series_uid`, `modality`,
`number_of_instances`, `patient_ref`).

## Examples

``` r
st <- list(
  resourceType = "ImagingStudy",
  identifier = list(list(value = "urn:dicom:uid:1.2.3")),
  subject = list(reference = "Patient/p1"),
  series = list(list(uid = "1.2.3.1", modality = list(code = "CT"), numberOfInstances = 10L))
)
from_fhir_imaging_study(st)
#> # A tibble: 1 × 5
#>   study_uid series_uid modality number_of_instances patient_ref
#>   <chr>     <chr>      <chr>                  <int> <chr>      
#> 1 1.2.3     1.2.3.1    CT                        10 Patient/p1 
```
