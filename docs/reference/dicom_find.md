# Query DICOM Studies, Series, or Instances (C-FIND / QIDO-RS / Local PACS)

Queries a DICOM connection or local PACS directory for matching studies,
series, or instances, returning a tidy
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
that can be piped into
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html)
and
[`dicom_get()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_get.md).

## Usage

``` r
dicom_find(conn, level = c("STUDY", "SERIES", "IMAGE"), ...)
```

## Arguments

- conn:

  A `"dicom_connection"` object from
  [`dicom_connect()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_connect.md),
  or a local directory path.

- level:

  Query level: `"STUDY"`, `"SERIES"`, or `"IMAGE"`. Default is
  `"STUDY"`.

- ...:

  Optional tag filters as named arguments (e.g., `Modality = "CT"`,
  `PatientName = "DOE*"`).

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
of matching DICOM records.

## Examples

``` r
ext_dir <- system.file("extdata", package = "dicomtk")
conn <- dicom_connect(local_dir = ext_dir)
dicom_find(conn)
#> # A tibble: 2 × 88
#>   file      FileMetaInformationG…¹ FileMetaInformationV…² MediaStorageSOPClass…³
#>   <chr>     <chr>                  <chr>                  <chr>                 
#> 1 C:/Users… 192                    "00\\01"               1.2.840.10008.5.1.4.1…
#> 2 C:/Users… 192                    "00\\01"               1.2.840.10008.5.1.4.1…
#> # ℹ abbreviated names: ¹​FileMetaInformationGroupLength,
#> #   ²​FileMetaInformationVersion, ³​MediaStorageSOPClassUID
#> # ℹ 84 more variables: MediaStorageSOPInstanceUID <chr>,
#> #   TransferSyntaxUID <chr>, ImplementationClassUID <chr>,
#> #   ImplementationVersionName <chr>, SourceApplicationEntityTitle <chr>,
#> #   SpecificCharacterSet <chr>, ImageType <chr>, InstanceCreationDate <chr>,
#> #   InstanceCreationTime <chr>, InstanceCreatorUID <chr>, SOPClassUID <chr>, …
```
