# Configure a Local DICOM Storage Receiver Directory (C-STORE SCP)

Sets up and returns a local directory-backed `"dicom_connection"` ready
to receive, index, and query DICOM files.

## Usage

``` r
dicom_receive(
  output_dir = tempfile("dicom_scp_"),
  port = 11112L,
  aetitle = "DICOMTK-SCP"
)
```

## Arguments

- output_dir:

  Directory to store received DICOM files.

- port:

  Port number for metadata registration. Default is `11112L`.

- aetitle:

  Application Entity Title for the receiver. Default is `"DICOMTK-SCP"`.

## Value

A `"dicom_connection"` object configured with `local_dir = output_dir`.

## Examples

``` r
scp <- dicom_receive(tempfile("scp_"))
scp
#> ℹ DICOM Connection: DICOMTK-SCP -> DICOMTK-SCP@127.0.0.1:11112
#> ℹ Local PACS directory: C:\Users\lauye\AppData\Local\Temp\RtmpoN3Ypn\scp_58dc64141b2f
```
