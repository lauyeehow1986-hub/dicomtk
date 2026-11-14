# dicomtk: Comprehensive 'DICOM' Toolkit for Medical Imaging in R <img src="man/figures/logo.png" align="right" height="150" alt="dicomtk hex logo" />

<!-- badges: start -->
[![R-CMD-check](https://github.com/lauyeehow1986-hub/dicomtk/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/lauyeehow1986-hub/dicomtk/actions/workflows/R-CMD-check.yaml)
[![Sync Upstream DCMTK](https://github.com/lauyeehow1986-hub/dicomtk/actions/workflows/sync-upstream-dcmtk.yaml/badge.svg)](https://github.com/lauyeehow1986-hub/dicomtk/actions/workflows/sync-upstream-dcmtk.yaml)
[![R-universe](https://lauyeehow1986-hub.r-universe.dev/badges/:name)](https://lauyeehow1986-hub.r-universe.dev)
<!-- badges: end -->

`dicomtk` (`0.6.0`) is the core R package of the four-package **dicomtk** imaging ecosystem (`dicomtk`, [`dicomtk.ai`](https://lauyeehow1986-hub.github.io/dicomtk.ai/), [`dicomtk.server`](https://lauyeehow1986-hub.github.io/dicomtk.server/), [`dicomtk.fl`](https://lauyeehow1986-hub.github.io/dicomtk.fl/)). It is synchronized with **OFFIS DCMTK 3.7.1 (PS 3.6-2026d)** and powered by a **bundled C++17 / Rcpp engine** requiring zero external installation.

---

## Installation

Install pre-compiled binaries or source directly from [R-Universe](https://lauyeehow1986-hub.r-universe.dev):

```r
install.packages(
  "dicomtk",
  repos = c(
    "https://lauyeehow1986-hub.r-universe.dev",
    "https://cloud.r-project.org"
  )
)
```

Or install from GitHub:

```r
remotes::install_github("lauyeehow1986-hub/dicomtk")
```

---

## How to Use `dicomtk`

### 1. Read Headers, 3D Volumes & Coordinate Transforms
```r
library(dicomtk)
library(dplyr)

dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")

# Read DICOM metadata as a tidy tibble
read_dicom(dcm_file) |>
  filter(group == "0028") |>
  select(tag, vr, keyword, value)

# Synthesize a 3D multi-slice phantom & reconstruct a 3D dicom_volume (LPS/RAS)
tmp_dir <- tempfile("phantom_")
dicom_synthesize("CT", slices = 16, out_dir = tmp_dir)
vol <- read_dicom_volume(tmp_dir)
ras_vol <- to_ras(vol)
voxel_to_world(vol, c(1, 1, 1))
```

### 2. Regulatory-Grade De-Identification (PS 3.15, Pixel Cleaning & Defacing)
```r
kp <- dicom_key_provider("my-consortium-hmac-key")
out_deid <- tempfile("deid_")

# Jurisdiction-aware de-identification (HIPAA, GDPR, PDPA, or custom profile)
res <- dicom_deid(
  tmp_dir,
  out_dir = out_deid,
  jurisdiction = "HIPAA",
  key = kp,
  verify = TRUE
)

# Check residual re-identification risk & verify cryptographic attestation
dicom_deid_risk(out_deid)
dicom_verify_attestation(res$attestation)
```

### 3. Segmentation (`DICOM-SEG`), Radiotherapy (`RTSTRUCT`/`RTDOSE`/`DVH`) & `TID 1500` SR
```r
# Convert 3D mask to dicom_seg and RTSTRUCT
mask <- array(0L, dim = dim(vol$voxels))
mask[20:40, 20:40, 4:12] <- 1L
seg <- as_dicom_seg(mask, reference_volume = vol, segment_label = "Lesion")
rt <- seg_to_rtstruct(seg, reference_volume = vol)

# Compute Dose-Volume Histogram (DVH) and TID 1500 Measurement Report
# dvh <- dicom_dvh(rtdose, seg)
# sr <- create_dicom_sr_tid1500(seg, reference_volume = vol)
```

### 4. Deep Learning Dataset Export (`nnU-Net`, `MONAI`, `RO-Crate`) & QC
```r
# Resample to isotropic spacing, apply clinical windowing, and check QC
iso_vol <- resample_volume(vol, target_spacing = c(1.5, 1.5, 1.5))
qc <- dicom_qc_volume(iso_vol)

# Export patient-level train/val splits for nnU-Net v2 or MONAI
# export_nnunet_v2(...) / export_monai_datalist(...)
```

### 5. Interoperability: DICOMweb, HL7 FHIR, DuckDB Index & OMOP `MI-CDM`
```r
# Build a normalized DuckDB archive index & export OMOP MI-CDM tables
idx <- dicom_index_build(out_deid)
omop <- export_omop_micdm(idx)
omop$image_occurrence
omop$image_feature
```

### 6. Whole-Slide Imaging (WSI) Pyramids & Supplement 222 Annotations
```r
# Inspect multi-resolution WSI pyramid & stitch an out-of-core tile region
# pyr <- read_wsi_pyramid("slide_level0.dcm")
# region <- wsi_stitch_region(pyr, level = 1L, x = 1L, y = 1L, width = 512L, height = 512L)
# ann <- write_wsi_annotations(points_df, out_file = "slide_ann.dcm")
```

### 7. Documentation & Vignettes
Browse the full function reference and vignettes on the [pkgdown site](https://lauyeehow1986-hub.github.io/dicomtk/).
