# Verify DICOM PACS Connectivity (C-ECHO SCU)

Performs a DICOM Upper Layer `A-ASSOCIATE-RQ` handshake followed by a
Verification SOP Class (`1.2.840.10008.1.1`) `C-ECHO-RQ` over TCP, or
verifies a local directory-backed PACS connection.

## Usage

``` r
dicom_echo(
  x,
  port = 104L,
  called_ae = "ANY-SCP",
  calling_ae = "DICOMTK",
  timeout_ms = 5000L
)
```

## Arguments

- x:

  A `"dicom_connection"` object from
  [`dicom_connect()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_connect.md)
  or a hostname string.

- port:

  Integer port (used if `x` is a hostname string). Default is `104L`.

- called_ae:

  Called AE Title. Default is `"ANY-SCP"`.

- calling_ae:

  Calling AE Title. Default is `"DICOMTK"`.

- timeout_ms:

  Timeout in milliseconds. Default is `5000L`.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `host`, `port`, `called_ae`, `success`, `status`,
`message`, and `elapsed_ms`.

## Examples

``` r
conn <- dicom_connect(local_dir = system.file("extdata", package = "dicomtk"))
dicom_echo(conn)
#> # A tibble: 1 × 7
#>   host       port called_ae success status        message             elapsed_ms
#>   <chr>     <int> <chr>     <lgl>   <chr>         <chr>                    <dbl>
#> 1 127.0.0.1   104 ANY-SCP   TRUE    SUCCESS_LOCAL Local DICOM reposi…        0.1
```
