# Detect Burned-In Annotation / Pixel PHI Regions

Scans DICOM metadata, Ultrasound region sequences (0018,6011), cine
multi-frame static temporal overlays, and border text strokes to detect
candidate burned-in protected health information (PHI) bounding boxes.

## Usage

``` r
dicom_detect_burned_phi(x, ocr = FALSE, detector_fn = NULL)
```

## Arguments

- x:

  Character path to a DICOM file, or a parsed DICOM dataset / pixel
  matrix.

- ocr:

  Logical. Whether to run optical character recognition (OCR) via the
  optional `tesseract` package if installed. Default is `FALSE`.

- detector_fn:

  Optional user callback function taking `(path, pixels, header)` and
  returning a data frame of bounding boxes.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
containing candidate bounding boxes with columns:

- `ymin`: Integer 1-based top row.

- `xmin`: Integer 1-based left column.

- `ymax`: Integer 1-based bottom row.

- `xmax`: Integer 1-based right column.

- `region_type`: Character description of the detection mechanism.

- `score`: Numeric confidence score between 0 and 1.

## Examples

``` r
if (FALSE) { # \dontrun{
boxes <- dicom_detect_burned_phi("ultrasound.dcm")
print(boxes)
} # }
```
