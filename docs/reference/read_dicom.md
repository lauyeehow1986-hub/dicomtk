# Read DICOM Metadata into a Tidy Tibble

Reads one or more DICOM files (or directories of DICOM files) using the
native C++17 / DCMTK parser and returns a tidy
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html).

## Usage

``` r
read_dicom(path, wide = FALSE, include_sequences = FALSE, recursive = TRUE)
```

## Arguments

- path:

  Character vector of DICOM file paths or directory paths.

- wide:

  Logical. If `FALSE` (default), returns long format with one row per
  DICOM attribute (`file`, `tag`, `group`, `element`, `vr`, `length`,
  `vm`, `keyword`, `name`, `value`). If `TRUE`, pivots to wide format
  with one row per file and one column per DICOM `keyword`.

- include_sequences:

  Logical. If `TRUE`, recursively extracts nested sequence (`SQ`) items.
  Default is `FALSE`.

- recursive:

  Logical. When `path` contains directories, search subdirectories
  recursively. Default is `TRUE`.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
of class `c("dicom_tbl", "tbl_df", "tbl", "data.frame")`.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
hdr <- read_dicom(dcm_file)
hdr
#> # A tibble: 190 × 12
#>    file         tag   group element vr    length vm    keyword name  value depth
#>    <chr>        <chr> <chr> <chr>   <chr>  <int> <chr> <chr>   <chr> <chr> <int>
#>  1 "C:\\Users\… (000… 0002  0000    UL         4 1     FileMe… File… "192"     0
#>  2 "C:\\Users\… (000… 0002  0001    OB         2 1     FileMe… File… "00\…     0
#>  3 "C:\\Users\… (000… 0002  0002    UI        26 1     MediaS… Medi… "1.2…     0
#>  4 "C:\\Users\… (000… 0002  0003    UI        48 1     MediaS… Medi… "1.3…     0
#>  5 "C:\\Users\… (000… 0002  0010    UI        20 1     Transf… Tran… "1.2…     0
#>  6 "C:\\Users\… (000… 0002  0012    UI        18 1     Implem… Impl… "1.3…     0
#>  7 "C:\\Users\… (000… 0002  0013    SH        10 1     Implem… Impl… "DCT…     0
#>  8 "C:\\Users\… (000… 0002  0016    AE         8 1     Source… Sour… "CLU…     0
#>  9 "C:\\Users\… (000… 0008  0005    CS        10 1-n   Specif… Spec… "ISO…     0
#> 10 "C:\\Users\… (000… 0008  0008    CS        22 2-n   ImageT… Imag… "ORI…     0
#> # ℹ 180 more rows
#> # ℹ 1 more variable: sequence_path <chr>

# Wide format (1 row per file)
read_dicom(dcm_file, wide = TRUE)
#> # A tibble: 1 × 88
#>   file      FileMetaInformationG…¹ FileMetaInformationV…² MediaStorageSOPClass…³
#>   <chr>     <chr>                  <chr>                  <chr>                 
#> 1 "C:\\Use… 192                    "00\\01"               1.2.840.10008.5.1.4.1…
#> # ℹ abbreviated names: ¹​FileMetaInformationGroupLength,
#> #   ²​FileMetaInformationVersion, ³​MediaStorageSOPClassUID
#> # ℹ 84 more variables: MediaStorageSOPInstanceUID <chr>,
#> #   TransferSyntaxUID <chr>, ImplementationClassUID <chr>,
#> #   ImplementationVersionName <chr>, SourceApplicationEntityTitle <chr>,
#> #   SpecificCharacterSet <chr>, ImageType <chr>, InstanceCreationDate <chr>,
#> #   InstanceCreationTime <chr>, InstanceCreatorUID <chr>, SOPClassUID <chr>, …
```
