# Apply Philips MR Quantitative Floating-Point or Console Display Scaling

Rescales MR pixel intensities following Chenevert et al. (2014) and the
Philips DICOM Conformance Statement using public
`RescaleIntercept (0028,1052)` (`RI`) / `RescaleSlope (0028,1053)`
(`RS`) and proprietary Philips private tags `(2005,100D)`
(`ScaleIntercept`, `SI`) and `(2005,100E)` (`ScaleSlope`, `SS`).

## Usage

``` r
dicom_mr_rescale(x, philips_float = TRUE)
```

## Arguments

- x:

  A
  [`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  or path to DICOM files.

- philips_float:

  Logical. When `TRUE` (default) and Philips `ScaleSlope` `(2005,100E)`
  is present, returns quantitative floating-point values \\P = D / (RS
  \times SS)\\; when `FALSE`, returns console display values `D`.

## Value

A
[`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
with rescaled voxel values and appended provenance.

## Details

For stored integer pixel values `R`, console display values are \\D = R
\times RS + RI\\ and quantitative floating-point values are \\P = D /
(RS \times SS)\\. Automatically accounts for whether `x` was already
`RS`/`RI`-rescaled by
[`read_dicom_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md),
preventing double-rescaling.

## Examples

``` r
out_dir <- tempfile("mr_demo_")
dicom_synthesize(
  out_dir = out_dir,
  modality = "MR",
  dims = c(16L, 16L, 2L),
  extra_tags = list("(2005,100D)" = "5.0", "(2005,100E)" = "2.0")
)
vol <- read_dicom_volume(out_dir)
rescaled <- dicom_mr_rescale(vol, philips_float = TRUE)
rescaled
#> <dicom_volume [MR] 16x16x2 | coord=LPS>
#>   spacing: (1, 1, 2.5) mm | origin: (-16, -16, 0) mm
#>   frame_meta: 2 row(s) | provenance: 2 step(s)
unlink(out_dir, recursive = TRUE)
```
