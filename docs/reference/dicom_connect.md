# Create a DICOM PACS Network Connection Specification

Creates a `"dicom_connection"` object holding PACS / DICOM node
connection parameters for use with
[`dicom_echo()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_echo.md),
[`dicom_find()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_find.md),
[`dicom_get()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_get.md),
and
[`dicom_send()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_send.md).
Supports both DIMSE TCP connections and DICOMweb (QIDO-RS / WADO-RS /
STOW-RS) HTTP endpoints.

## Usage

``` r
dicom_connect(
  host = "127.0.0.1",
  port = 104L,
  called_ae = "ANY-SCP",
  calling_ae = "DICOMTK",
  timeout_ms = 5000L,
  dicomweb_url = NULL,
  local_dir = NULL
)
```

## Arguments

- host:

  Hostname or IP address of the remote DICOM peer (e.g., `"127.0.0.1"`
  or `"https://pacs.example.org/dicom-web"`).

- port:

  Integer TCP port for DIMSE communication. Default is `104L` (or
  `4242L` for Orthanc).

- called_ae:

  Remote Application Entity Title (Called AET). Default is `"ANY-SCP"`.

- calling_ae:

  Local Application Entity Title (Calling AET). Default is `"DICOMTK"`.

- timeout_ms:

  Socket timeout in milliseconds. Default is `5000L`.

- dicomweb_url:

  Optional base URL for DICOMweb (QIDO-RS / WADO-RS / STOW-RS) REST
  APIs.

- local_dir:

  Optional local directory path to act as a local file-backed PACS
  repository for testing queries and retrievals offline.

## Value

An S3 object of class `"dicom_connection"`.

## Examples

``` r
conn <- dicom_connect("127.0.0.1", port = 4242, called_ae = "ORTHANC")
conn
#> ℹ DICOM Connection: DICOMTK -> ORTHANC@127.0.0.1:4242
```
