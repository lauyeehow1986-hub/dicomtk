# Describe a DICOM Image Using a Vision-Capable LLM

Renders the DICOM slice with clinical windowing to a PNG, encodes it as
base64, and sends it along with anonymized technical metadata and pixel
intensity statistics to a vision-capable LLM (e.g., Ollama `llava`,
OpenAI `gpt-4o`, or Anthropic `claude-sonnet-4-20250514`).

## Usage

``` r
dicom_describe_image(
  path,
  llm = dicom_llm("ollama"),
  frame = 1L,
  window = "auto",
  prompt =
    "Describe the anatomical structures, image quality, windowing, and any notable visual patterns in this medical image for research/educational review."
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

  Window preset (`"auto"`, `"brain"`, `"lung"`, `"bone"`, etc.). Default
  is `"auto"`.

- prompt:

  Custom instruction prompt for the vision model.

## Value

A character string with the image description and quantitative stats.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
llm <- dicom_llm("offline")
dicom_describe_image(dcm_file, llm = llm)
#> [1] "DICOM Image Analysis (CT, 512x512, Photometric: MONOCHROME2): Rescaled pixel intensities range from -3024 to 1483 (mean: -704.75, SD: 1230.16, median: -78; 5th-95th percentile: [-3024, 102]). Window Center: 40, Window Width: 400."
```
