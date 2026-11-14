# Compute Dose-Volume Histogram (DVH) and Clinical Radiation Metrics

Evaluates cumulative and differential Dose-Volume Histograms (DVHs) and
extracts key radiation oncology clinical metrics (`D95`, `D90`, `D50`,
`V20`, min, max, and mean dose) across ROIs from an `RTDOSE` volume and
a
[dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
mask.

## Usage

``` r
dicom_dvh(dose, seg, n_bins = 100L)
```

## Arguments

- dose:

  An `RTDOSE`
  [dicom_volume](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  or path to a DICOM `RTDOSE` file.

- seg:

  A
  [dicom_seg](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)
  segmentation object containing one or more ROIs.

- n_bins:

  Number of dose bins for the histogram curves. Default is `100L`.

## Value

An object of class `"dicom_dvh"` containing:

- metrics:

  A tibble with clinical metrics per ROI (`roi_number`, `roi_label`,
  `volume_cc`, `min_dose`, `max_dose`, `mean_dose`, `D95`, `D90`, `D50`,
  `V20`).

- curves:

  A tibble of dose evaluation points with cumulative
  (`vol_pct_cumulative`) and differential (`vol_pct_differential`)
  volumes.

## Examples

``` r
synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 5L))
vol <- read_dicom_volume(synth[["out_dir"]])
unlink(synth[["out_dir"]], recursive = TRUE)
```
