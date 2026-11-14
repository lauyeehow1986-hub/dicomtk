# Unpack an RFC 2387 `multipart/related` DICOM Payload to Disk

Unpack an RFC 2387 `multipart/related` DICOM Payload to Disk

## Usage

``` r
unpack_multipart_dicom(raw_bytes, boundary, out_dir = tempfile("dw_wado_"))
```

## Arguments

- raw_bytes:

  Raw vector containing a `multipart/related` HTTP body.

- boundary:

  Multipart boundary string (without leading `--`).

- out_dir:

  Output directory for extracted `.dcm` files.

## Value

Character vector of extracted file paths.

## Examples

``` r
dcm <- system.file("extdata", "example.dcm", package = "dicomtk")
if (nzchar(dcm)) {
  mp <- pack_multipart_dicom(dcm, boundary = "B1")
  out <- tempfile("unpack_")
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  unpack_multipart_dicom(mp$body, boundary = "B1", out_dir = out)
}
#> [1] "C:\\Users\\lauye\\AppData\\Local\\Temp\\RtmpeMd5Zu\\unpack_586c1b3a14/instance_0001.dcm"
```
