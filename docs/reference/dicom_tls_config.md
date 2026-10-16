# Configure DICOM TLS Transport Security Parameters (`dcmtls`)

Attaches TLS certificate, private key, and CA bundle paths to a
`"dicom_connection"` object for secure DICOM-over-TLS communication (RFC
3240 / DICOM PS3.15).

## Usage

``` r
dicom_tls_config(
  conn,
  cert_file = NULL,
  key_file = NULL,
  ca_file = NULL,
  profile = c("BCP195", "BCP195-ND", "AES")
)
```

## Arguments

- conn:

  A `"dicom_connection"` object created by
  [`dicom_connect()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_connect.md).

- cert_file:

  Optional path to client X.509 PEM certificate.

- key_file:

  Optional path to client private key.

- ca_file:

  Optional path to trusted CA certificate bundle.

- profile:

  DICOM TLS security profile (`"BCP195"`, `"BCP195-ND"`, or `"AES"`).
  Default is `"BCP195"`.

## Value

Updated `"dicom_connection"` object with TLS settings enabled.

## Examples

``` r
conn <- dicom_connect("pacs.hospital.org", port = 2762) |>
  dicom_tls_config(profile = "BCP195")
conn
#> ℹ DICOM Connection: DICOMTK -> ANY-SCP@pacs.hospital.org:2762
```
