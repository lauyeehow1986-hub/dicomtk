# Quickly Extract Specific Tag Values from a DICOM File

Retrieves one or more tag values by tag code (e.g., `"(0010,0010)"`) or
standard keyword (e.g., `"PatientName"`, `"Modality"`, `"Rows"`).

## Usage

``` r
dicom_tag_value(path, tags)
```

## Arguments

- path:

  Path to a single DICOM file.

- tags:

  Character vector of tag IDs (`"(GGGG,EEEE)"`) or DICOM keywords.

## Value

A named character vector of tag values (`NA_character_` if absent).

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
dicom_tag_value(dcm_file, c("Modality", "Rows", "Columns", "(0008,0070)"))
#>             Modality                 Rows              Columns 
#>                 "CT"                "512"                "512" 
#>          (0008,0070) 
#> "GE MEDICAL SYSTEMS" 
```
