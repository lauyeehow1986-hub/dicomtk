# Write a Matrix, Array, or DICOM Series to a DICOM File

Creates a standard DICOM Part 10 Explicit VR Little Endian file from an
R 2D matrix or 3D array of pixel values and an optional named list or
character vector of DICOM metadata tags.

## Usage

``` r
write_dicom(x, path, metadata = list())
```

## Arguments

- x:

  A numeric 2D matrix `[rows, cols]`, 3D array `[rows, cols, frames]`,
  or `"dicom_pixels"` object.

- path:

  Output file path for the written `.dcm` file.

- metadata:

  Named list or named character vector of DICOM tags/keywords and values
  (e.g., `list(PatientName = "DOE^JOHN", Modality = "CT")`).

## Value

Invisibly returns the normalized output `path`.

## Examples

``` r
mat <- matrix(seq(0, 255), nrow = 16, ncol = 16)
out <- tempfile(fileext = ".dcm")
write_dicom(mat, out, metadata = list(PatientName = "TEST^PATIENT", Modality = "CT"))
read_dicom(out, wide = TRUE)
#> # A tibble: 1 × 21
#>   file      FileMetaInformationG…¹ MediaStorageSOPClass…² MediaStorageSOPInsta…³
#>   <chr>     <chr>                  <chr>                  <chr>                 
#> 1 "C:\\Use… 162                    1.2.840.10008.5.1.4.1… 2.25.1106846380142337…
#> # ℹ abbreviated names: ¹​FileMetaInformationGroupLength,
#> #   ²​MediaStorageSOPClassUID, ³​MediaStorageSOPInstanceUID
#> # ℹ 17 more variables: TransferSyntaxUID <chr>, ImplementationClassUID <chr>,
#> #   ImplementationVersionName <chr>, SOPClassUID <chr>, SOPInstanceUID <chr>,
#> #   Modality <chr>, PatientName <chr>, StudyInstanceUID <chr>,
#> #   SeriesInstanceUID <chr>, SamplesPerPixel <chr>,
#> #   PhotometricInterpretation <chr>, Rows <chr>, Columns <chr>, …
```
