# Pack DICOM Files Into an RFC 2387 `multipart/related` Binary Payload

Pack DICOM Files Into an RFC 2387 `multipart/related` Binary Payload

## Usage

``` r
pack_multipart_dicom(
  files,
  boundary = paste0("dicomtk_", as.integer(Sys.time()))
)
```

## Arguments

- files:

  Character vector of `.dcm` file paths.

- boundary:

  Multipart boundary string.

## Value

A list with `body` (raw vector), `content_type`, and `boundary`.

## Examples

``` r
dcm <- system.file("extdata", "example.dcm", package = "dicomtk")
if (nzchar(dcm)) {
  mp <- pack_multipart_dicom(dcm)
  length(mp$body)
}
#> [1] 527801
```
