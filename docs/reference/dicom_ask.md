# Ask a Natural-Language Question About a DICOM File

Answers arbitrary questions about a DICOM file's metadata or image
content using the configured LLM (or local metadata inspection).

## Usage

``` r
dicom_ask(path, question, llm = dicom_llm("ollama"), include_image = FALSE)
```

## Arguments

- path:

  Path to a DICOM file.

- question:

  Character string question (e.g.,
  `"What is the pixel spacing and modality?"`).

- llm:

  A `"dicom_llm"` object created by
  [`dicom_llm()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_llm.md).

- include_image:

  Logical. Attach the rendered DICOM image for multimodal vision models.
  Default is `FALSE`.

## Value

Character string answer.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
dicom_ask(dcm_file, "What is the modality and image dimensions?", llm = dicom_llm("offline"))
#> [1] "Image Type ((0008,0008)): ORIGINAL\\PRIMARY\\AXIAL; Modality ((0008,0060)): CT; Image Position (Patient) ((0020,0032)): -72.199997\\-143.000000\\-101.237503; Image Orientation (Patient) ((0020,0037)): 1.000000\\0.000000\\0.000000\\0.000000\\1.000000\\0.000000"
```
