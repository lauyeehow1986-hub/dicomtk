# Create a Quantitative Imaging DICOM SR TID 1500 Measurement Report

Computes volumetric and morphologic quantitative imaging biomarkers
(volume in cubic millimeters and cubic centimeters, RECIST longest
in-plane diameter in millimeters, and mean, standard deviation, minimum,
and maximum voxel intensity) for each segment in a
[dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
object against a reference
[dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md),
and optionally writes a DICOM Structured Report following **TID 1500
(Measurement Report)**.

## Usage

``` r
dicom_sr_tid1500(
  vol,
  seg,
  out_path = NULL,
  patient_name = "ANONYMOUS",
  patient_id = "ANON001",
  study_uid = NULL,
  title = "Imaging Measurement Report"
)
```

## Arguments

- vol:

  Reference
  [dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  object containing image intensities.

- seg:

  A
  [dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
  segmentation object aligned with `vol`.

- out_path:

  Optional output `.dcm` file path. If provided, writes a DICOM
  Comprehensive 3D SR (`1.2.840.10008.5.1.4.1.1.88.34`) Part 10 file.

- patient_name:

  Optional `PatientName (0010,0010)`. Defaults to `"ANONYMOUS"`.

- patient_id:

  Optional `PatientID (0010,0020)`. Defaults to `"ANON001"`.

- study_uid:

  Optional `StudyInstanceUID (0020,000D)`. Defaults to
  `vol$uids$study_instance_uid` or a newly generated UID.

- title:

  Report title (`SeriesDescription`). Default is
  `"Imaging Measurement Report"`.

## Value

An S3 object of class `"dicom_sr_tid1500"` containing:

- summary:

  A tibble with one row per ROI (`segment_id`, `label`, `volume_mm3`,
  `volume_cm3`, `recist_diameter_mm`, `mean_intensity`, `sd_intensity`,
  `min_intensity`, `max_intensity`, `units`).

- measurements:

  A tidy long-format tibble of all TID 1500 `NUM` measurement items.

- content_tree:

  Nested list representation of the DICOM `ContentSequence (0040,A730)`
  tree.

- file:

  Normalized path to `out_path` if written, otherwise `NULL`.

## Examples

``` r
synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 4L))
vol <- read_dicom_volume(synth[["out_dir"]])
m <- array(0L, dim = c(32L, 32L, 4L))
m[10:19, 10:19, 2:3] <- 1L
seg <- dicom_seg(m, vol, tibble::tibble(segment_id = 1L, label = "Lesion_1"))
sr <- dicom_sr_tid1500(vol, seg)
sr$summary
#> # A tibble: 1 × 10
#>   segment_id label    volume_mm3 volume_cm3 recist_diameter_mm mean_intensity
#>        <int> <chr>         <dbl>      <dbl>              <dbl>          <dbl>
#> 1          1 Lesion_1        500        0.5               13.7           61.9
#> # ℹ 4 more variables: sd_intensity <dbl>, min_intensity <dbl>,
#> #   max_intensity <dbl>, units <chr>
```
