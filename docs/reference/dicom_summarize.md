# Summarize a DICOM Study Using an LLM

Generates a concise clinical and technical natural-language summary of a
DICOM file's header metadata (modality, anatomy, acquisition parameters,
image geometry). Automatically strips PHI tags when communicating with
non-local LLM endpoints.

## Usage

``` r
dicom_summarize(path, llm = dicom_llm("ollama"))
```

## Arguments

- path:

  Path to a DICOM file.

- llm:

  A `"dicom_llm"` object created by
  [`dicom_llm()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_llm.md).
  Defaults to `dicom_llm("ollama")`.

## Value

A character string containing the study summary.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
llm <- dicom_llm("offline")
dicom_summarize(dcm_file, llm = llm)
#> [1] "DICOM Study Summary: CT imaging study (General Study) acquired on GE MEDICAL SYSTEMS system. Series: SmartScore - Gated 0.5 sec (Body Part: Not specified). Image Matrix: 512 x 512 pixels (16-bit MONOCHROME2)."
```
