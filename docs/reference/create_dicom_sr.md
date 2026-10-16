# Create a DICOM Basic Text Structured Report (SR)

Writes a valid DICOM Basic Text SR Storage
(`1.2.840.10008.5.1.4.1.1.88.11`) Part 10 file containing a structured
report title, text content, and patient /study identifiers.

## Usage

``` r
create_dicom_sr(
  out_path,
  title = "Radiology Structured Report",
  text,
  patient_name = "ANONYMOUS",
  patient_id = "ANON001",
  study_uid = ""
)
```

## Arguments

- out_path:

  Output `.dcm` file path.

- title:

  Document / Series title (`SeriesDescription (0008,103E)`).

- text:

  Report body text (`TextValue (0040,A160)`).

- patient_name:

  Patient name (`(0010,0010)`). Default is `"ANONYMOUS"`.

- patient_id:

  Patient ID (`(0010,0020)`). Default is `"ANON001"`.

- study_uid:

  Optional `StudyInstanceUID` to link the report to an existing study.
  If `""`, generates a new UID.

## Value

Invisibly returns `out_path`.

## Examples

``` r
sr_file <- tempfile(fileext = ".dcm")
create_dicom_sr(
  sr_file,
  title = "AI Radiology Summary",
  text = "FINDINGS: Unremarkable brain parenchyma. IMPRESSION: Normal head CT."
)
read_dicom_sr(sr_file)
#> # A tibble: 14 × 6
#>    depth sequence_path tag         keyword              vr    value             
#>    <int> <chr>         <chr>       <chr>                <chr> <chr>             
#>  1     0 ""            (0008,0005) SpecificCharacterSet CS    ISO_IR 192        
#>  2     0 ""            (0008,0016) SOPClassUID          UI    1.2.840.10008.5.1…
#>  3     0 ""            (0008,0018) SOPInstanceUID       UI    2.25.264755622839…
#>  4     0 ""            (0008,0060) Modality             CS    SR                
#>  5     0 ""            (0008,103E) SeriesDescription    LO    AI Radiology Summ…
#>  6     0 ""            (0010,0010) PatientName          PN    ANONYMOUS         
#>  7     0 ""            (0010,0020) PatientID            LO    ANON001           
#>  8     0 ""            (0020,000D) StudyInstanceUID     UI    2.25.582353801954…
#>  9     0 ""            (0020,000E) SeriesInstanceUID    UI    2.25.514926707017…
#> 10     0 ""            (0020,0013) InstanceNumber       IS    1                 
#> 11     0 ""            (0040,A040) ValueType            CS    TEXT              
#> 12     0 ""            (0040,A160) TextValue            UT    FINDINGS: Unremar…
#> 13     0 ""            (0040,A491) CompletionFlag       CS    COMPLETE          
#> 14     0 ""            (0040,A493) VerificationFlag     CS    UNVERIFIED        
```
