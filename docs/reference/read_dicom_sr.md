# Read a DICOM Structured Report (SR) or Advanced IOD

Parses a DICOM Structured Report (`dcmsr`) or hierarchical DICOM dataset
(including RT Plan/Dose/Structure Set, Segmentation, Parametric Map, and
Tractography objects) into a tidy
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
preserving sequence hierarchy (`depth` and `sequence_path`).

## Usage

``` r
read_dicom_sr(path)
```

## Arguments

- path:

  Path to a DICOM Structured Report (`.dcm`) file.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `depth`, `sequence_path`, `tag`, `keyword`, `vr`, and
`value`.

## Examples

``` r
sr_file <- tempfile(fileext = ".dcm")
create_dicom_sr(
  sr_file,
  title = "Chest CT Report",
  text = "No acute cardiopulmonary abnormality."
)
read_dicom_sr(sr_file)
#> # A tibble: 14 × 6
#>    depth sequence_path tag         keyword              vr    value             
#>    <int> <chr>         <chr>       <chr>                <chr> <chr>             
#>  1     0 ""            (0008,0005) SpecificCharacterSet CS    ISO_IR 192        
#>  2     0 ""            (0008,0016) SOPClassUID          UI    1.2.840.10008.5.1…
#>  3     0 ""            (0008,0018) SOPInstanceUID       UI    2.25.237524028953…
#>  4     0 ""            (0008,0060) Modality             CS    SR                
#>  5     0 ""            (0008,103E) SeriesDescription    LO    Chest CT Report   
#>  6     0 ""            (0010,0010) PatientName          PN    ANONYMOUS         
#>  7     0 ""            (0010,0020) PatientID            LO    ANON001           
#>  8     0 ""            (0020,000D) StudyInstanceUID     UI    2.25.426680793909…
#>  9     0 ""            (0020,000E) SeriesInstanceUID    UI    2.25.888432010192…
#> 10     0 ""            (0020,0013) InstanceNumber       IS    1                 
#> 11     0 ""            (0040,A040) ValueType            CS    TEXT              
#> 12     0 ""            (0040,A160) TextValue            UT    No acute cardiopu…
#> 13     0 ""            (0040,A491) CompletionFlag       CS    COMPLETE          
#> 14     0 ""            (0040,A493) VerificationFlag     CS    UNVERIFIED        
```
