# Send DICOM Files to a PACS Peer (C-STORE SCU)

Transmits one or more DICOM files to a configured `"dicom_connection"`
(or local PACS repository directory).

## Usage

``` r
dicom_send(files, conn)
```

## Arguments

- files:

  Character vector of DICOM file paths to send.

- conn:

  A `"dicom_connection"` object from
  [`dicom_connect()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_connect.md).

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
summarizing the transmission status for each file.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
pacs_dir <- tempfile("pacs_store_")
dir.create(pacs_dir)
conn <- dicom_connect(local_dir = pacs_dir)
dicom_send(dcm_file, conn)
#> # A tibble: 1 × 4
#>   file                                                destination success status
#>   <chr>                                               <chr>       <lgl>   <chr> 
#> 1 "C:\\Users\\lauye\\AppData\\Local\\Temp\\RtmpeuFNW… "C:\\Users… TRUE    STORE…
```
