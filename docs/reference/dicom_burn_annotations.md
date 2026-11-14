# Export Derived Burned-In Annotation Secondary Capture DICOMs

Renders graphic annotations (polylines, circles, points, or GSPS
objects) directly into a **new derived Secondary Capture series**
(`SOPClassUID = 1.2.840.10008.5.1.4.1.1.7`,
`ImageType = "DERIVED\\SECONDARY"`, `BurnedInAnnotation = "YES"`) for
teaching files and presentations. Source DICOM files are never modified,
and writing into the source directory is strictly prohibited.

## Usage

``` r
dicom_burn_annotations(
  volume,
  annotations,
  out_dir,
  slices = NULL,
  burn_value = NULL
)
```

## Arguments

- volume:

  A
  [dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  object.

- annotations:

  A `data.frame` /
  [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
  (same schema as
  [`write_dicom_gsps()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_dicom_gsps.md))
  with columns `slice`, `graphic_type`, `coords`, and optional `text`,
  or a `dicom_gsps` object.

- out_dir:

  Output directory path where derived `.dcm` files will be written. Must
  not match any directory containing source files of `volume`.

- slices:

  Optional integer vector of 1-based slice indices to export. Defaults
  to all slices referenced in `annotations` (or all slices if none).

- burn_value:

  Optional numeric intensity for burned-in overlays. Defaults to the
  slice maximum plus a bright margin (clamped to unsigned 16-bit range).

## Value

An S3 object of class `"dicom_burned_export"` containing `files`,
`out_dir`, `series_uid`, `slices`, and `n_annotations`.

## Examples

``` r
synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 3L))
vol <- read_dicom_volume(synth[["out_dir"]])
ann <- tibble::tibble(
  slice = 2L,
  graphic_type = "POLYLINE",
  coords = list(c(8, 8, 22, 8, 22, 22, 8, 22, 8, 8)),
  text = "Lesion"
)
out_dir <- file.path(tempdir(), "burned_ex")
res <- dicom_burn_annotations(vol, ann, out_dir)
unlink(out_dir, recursive = TRUE)
```
