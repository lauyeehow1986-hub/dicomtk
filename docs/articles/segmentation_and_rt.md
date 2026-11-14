# Segmentation, Radiotherapy (RTSTRUCT/RTDOSE), and Deep Learning Prep

## Overview

`dicomtk` 0.4.0 introduces end-to-end support for **DICOM Segmentation
(`SEG`)**, **Radiotherapy (`RTSTRUCT` and `RTDOSE`)**, **Quantitative
Structured Reports (`TID 1500`)**, **Grayscale Presentation States
(`GSPS`)**, **Automated Image Quality Control**, and **ML Dataset
Exporters (`nnU-Net v2`, `MONAI`, `RO-Crate`, `Croissant`)**.

## 1. Creating and Writing a DICOM Segmentation (`dicom_seg`)

Because `dicom_seg` inherits from `dicom_volume`, it preserves full 3D
LPS/RAS spatial geometry alongside segment metadata:

[`library`](https://rdrr.io/r/base/library.html)`(`[`dicomtk`](https://github.com/lauyeehow1986-hub/dicomtk)`)`` `` ``synth`` ``<-`` `[`dicom_synthesize`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md)`(``modality ``=`` ``"CT"``, dims ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``32L``, ``32L``, ``6L``)``)`` ``vol`` ``<-`` `[`read_dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md)`(``synth``[[``"out_dir"``]``]``)`` `` ``mask`` ``<-`` `[`array`](https://rdrr.io/r/base/array.html)`(``0L``, dim ``=`` `[`dim`](https://rdrr.io/r/base/dim.html)`(``vol``)``)`` ``mask``[``10``:``22``, ``10``:``22``, ``2``:``5``]`` ``<-`` ``1L`` `` ``seg`` ``<-`` `[`dicom_seg`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md)`(`` `` mask ``=`` ``mask``,`` `` ref_volume ``=`` ``vol``,`` `` segments ``=`` ``tibble``::`[`tibble`](https://tibble.tidyverse.org/reference/tibble.html)`(``segment_id ``=`` ``1L``, label ``=`` ``"Liver"``)`` ``)`` ``seg`` ``#> ``ℹ`` DICOM Segmentation Object (Segment rows: 1, Mask dims: 32x32x6)`

## 2. Automated Image Quality Control (`dicom_image_qc`)

Before feeding volumes into a downstream pipeline or ML trainer, run
[`dicom_image_qc()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_image_qc.md)
to check SNR, CNR, FOV border truncation, slice spacing anomalies,
gantry tilt, and high-frequency ringing:

`qc`` ``<-`` `[`dicom_image_qc`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_image_qc.md)`(``vol``)`` ``qc``$``qc_status`` ``#> [1] "PASS"`

## 3. Deep Learning Preprocessing (`volume_resample`, `volume_window`)

Resample volumes to isotropic voxel spacing and apply clinical HU
windowing:

`vol_iso`` ``<-`` `[`volume_resample`](https://lauyeehow1986-hub.github.io/dicomtk/reference/volume_resample.md)`(``vol``, target_spacing ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``2``, ``2``, ``2``)``, method ``=`` ``"trilinear"``)`` ``vol_win`` ``<-`` `[`volume_window`](https://lauyeehow1986-hub.github.io/dicomtk/reference/volume_window.md)`(``vol_iso``, center ``=`` ``40``, width ``=`` ``400``, normalize ``=`` ``"minmax"``)`` `[`range`](https://rdrr.io/r/base/range.html)`(``vol_win``$``voxels``)`` ``#> [1] 0 1`

## 4. Cleanup
