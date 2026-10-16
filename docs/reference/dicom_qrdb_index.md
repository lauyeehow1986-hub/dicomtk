# Build or Query a Local DICOM Query/Retrieve Index Database (`dcmqrdb`)

Scans a directory of DICOM files and builds a tidy index table organized
by Patient, Study, Series, and Instance UIDs (`dcmqrdb` model).

## Usage

``` r
dicom_qrdb_index(directory, recursive = TRUE)
```

## Arguments

- directory:

  Path to a directory containing DICOM files.

- recursive:

  Logical. Scan subdirectories recursively. Default is `TRUE`.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `file`, `PatientID`, `PatientName`, `StudyInstanceUID`,
`StudyDate`, `Modality`, `SeriesInstanceUID`, `SOPInstanceUID`, `Rows`,
and `Columns`.

## Examples

``` r
ext_dir <- system.file("extdata", package = "dicomtk")
dicom_qrdb_index(ext_dir)
#> # A tibble: 2 × 88
#>   file                 PatientID PatientName StudyInstanceUID StudyDate Modality
#>   <chr>                <chr>     <chr>       <chr>            <chr>     <chr>   
#> 1 C:/Users/lauye/AppD… 98890234  Doe^Peter   1.3.6.1.4.1.596… 20010101  CT      
#> 2 C:/Users/lauye/AppD… 98890234  Doe^Peter   1.3.6.1.4.1.596… 20010101  CT      
#> # ℹ 82 more variables: SeriesInstanceUID <chr>, SOPInstanceUID <chr>,
#> #   Rows <chr>, Columns <chr>, FileMetaInformationGroupLength <chr>,
#> #   FileMetaInformationVersion <chr>, MediaStorageSOPClassUID <chr>,
#> #   MediaStorageSOPInstanceUID <chr>, TransferSyntaxUID <chr>,
#> #   ImplementationClassUID <chr>, ImplementationVersionName <chr>,
#> #   SourceApplicationEntityTitle <chr>, SpecificCharacterSet <chr>,
#> #   ImageType <chr>, InstanceCreationDate <chr>, InstanceCreationTime <chr>, …
```
