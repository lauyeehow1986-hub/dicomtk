# Generate a Structured Radiology Report from a DICOM File

Combines DICOM technical metadata and vision analysis to produce a
structured radiology report (`EXAMINATION`, `TECHNIQUE`, `FINDINGS`,
`IMPRESSION`), and optionally saves it as a DICOM Structured Report
(`.dcm`) via
[`create_dicom_sr()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/create_dicom_sr.md).

## Usage

``` r
dicom_report(
  path,
  llm = dicom_llm("ollama"),
  frame = 1L,
  window = "auto",
  save_sr_path = NULL
)
```

## Arguments

- path:

  Path to a DICOM file.

- llm:

  A `"dicom_llm"` object created by
  [`dicom_llm()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_llm.md).

- frame:

  Integer frame/slice index (1-based). Default is `1L`.

- window:

  Window preset. Default is `"auto"`.

- save_sr_path:

  Optional output `.dcm` path to save the generated report as a formal
  DICOM Structured Report (`Basic Text SR`).

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `section` and `content`, and the full formatted report text
in attribute `"report_text"`.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
rpt <- dicom_report(dcm_file, llm = dicom_llm("offline"))
rpt
#> # A tibble: 4 × 2
#>   section     content                                                           
#>   <chr>       <chr>                                                             
#> 1 EXAMINATION CT -  - SmartScore - Gated 0.5 sec                                
#> 2 TECHNIQUE   DICOM Study Summary: CT imaging study (General Study) acquired on…
#> 3 FINDINGS    DICOM Image Analysis (CT, 512x512, Photometric: MONOCHROME2): Res…
#> 4 IMPRESSION  Automated quantitative and metadata review completed. Correlate c…
```
