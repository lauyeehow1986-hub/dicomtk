# Automated Image Quality Control for DICOM Volumes

Evaluates signal-to-noise ratio (SNR), contrast-to-noise ratio (CNR),
field-of-view (FOV) border truncation, slice spacing regularity, gantry
tilt, and high-frequency striping/ringing artifacts on a
[`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md).

## Usage

``` r
dicom_image_qc(
  vol,
  snr_warn = 5,
  border_threshold_frac = 0.05,
  artifact_warn = 0.35,
  artifact_fail = 0.65,
  tilt_warn_deg = 1
)
```

## Arguments

- vol:

  A
  [`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  object.

- snr_warn:

  Minimum acceptable SNR before raising a warning (default `5.0`).

- border_threshold_frac:

  Maximum fraction of FOV perimeter voxels allowed above the foreground
  threshold before flagging border truncation (default `0.05`).

- artifact_warn:

  High-frequency artifact score threshold for `"WARN"` (default `0.35`).

- artifact_fail:

  High-frequency artifact score threshold for `"FAIL"` (default `0.65`).

- tilt_warn_deg:

  Maximum slice-normal tilt angle in degrees before flagging
  `tilt_anomaly` (default `1.0`).

## Value

A list with components `snr`, `cnr`, `border_truncation`,
`spacing_anomaly`, `tilt_anomaly`, `artifact_score`, `qc_status`
(`"PASS"`, `"WARN"`, or `"FAIL"`), and `issues` (character vector).
