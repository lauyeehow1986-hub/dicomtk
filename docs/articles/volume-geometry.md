# 3D/4D Volume Geometry, Spatial Transforms, and NIfTI Export

## Overview

Medical cross-sectional imaging (CT, MR, PET, SPECT) inherently captures
3D volumes across space and time. However, different software ecosystems
adopt contrasting spatial coordinate systems:

1.  **DICOM Patient Coordinate System (LPS)**:
    - $`+X`$: towards the patient’s Left
    - $`+Y`$: towards the patient’s Posterior
    - $`+Z`$: towards the patient’s Superior (head)
    - Defined by `ImageOrientationPatient` ($`F_{col}`$, $`F_{row}`$
      direction cosines) and `ImagePositionPatient` ($`S_0`$).
2.  **Neuroimaging / NIfTI Coordinate System (RAS)**:
    - $`+X`$: towards the patient’s Right (inverted from LPS)
    - $`+Y`$: towards the patient’s Anterior (inverted from LPS)
    - $`+Z`$: towards the patient’s Superior
    - Represented by a $`4 \times 4`$ homogeneous affine transformation
      matrix (`sform`) and quaternion rotation (`qform`).

`dicomtk` v0.2.0 introduces end-to-end, standards-compliant 3D/4D volume
processing: - `dicom_volume`: An S3 class binding numerical voxel arrays
with analytical affine matrices and slice metadata. -
[`read_dicom_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md):
Geometry-aware reader for multi-slice directories and enhanced
multi-frame DICOM IODs. -
[`dicom_orientation()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_orientation.md),
[`dicom_to_lps()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_ras.md),
[`dicom_to_ras()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_ras.md):
Lossless spatial transformations. -
[`dicom_pet_suv()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_pet_suv.md),
[`dicom_apply_voi_lut()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_apply_voi_lut.md),
[`dicom_mr_rescale()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_mr_rescale.md):
Modality-specific quantitative physics calibrations. -
[`write_nifti()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_nifti.md):
`dcm2niix`-compatible NIfTI-1 export with BIDS JSON sidecars.

[`library`](https://rdrr.io/r/base/library.html)`(`[`dicomtk`](https://github.com/lauyeehow1986-hub/dicomtk)`)`

------------------------------------------------------------------------

## 1. Synthesizing Ground-Truth Medical Phantoms

For testing and reproducible research,
[`dicom_synthesize()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md)
generates standards-compliant DICOM series for CT, MR, and PET
modalities with known ground truth geometry, orientations (axial,
coronal, sagittal, or oblique), and optional gantry tilt.

`synth_dir`` ``<-`` `[`tempfile`](https://rdrr.io/r/base/tempfile.html)`(``"phantom_ct_"``)`` `[`dir.create`](https://rdrr.io/r/base/files2.html)`(``synth_dir``, recursive ``=`` ``TRUE``)`` `` ``# Generate a 4-slice oblique CT phantom`` ``phantom`` ``<-`` `[`dicom_synthesize`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md)`(`` `` out_dir ``=`` ``synth_dir``,`` `` modality ``=`` ``"CT"``,`` `` dims ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``32L``, ``32L``, ``4L``)``,`` `` spacing ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``0.8``, ``0.8``, ``2.5``)``,`` `` origin ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``-``20.0``, ``-``15.0``, ``10.0``)``,`` `` orientation ``=`` ``"oblique"``,`` `` oblique_angles_deg ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``15``, ``-``10``, ``5``)``,`` `` phi ``=`` ``FALSE`` ``)`` `` ``# Inspect synthesized files`` `[`length`](https://rdrr.io/r/base/length.html)`(``phantom``$``files``)`` ``#> [1] 4`

The returned generator object contains exact analytical ground-truth
values for `truth_affine_lps`, `truth_voxels`, `direction`, and
`spacing`.

------------------------------------------------------------------------

## 2. Reading 3D Volumes with `read_dicom_volume()`

[`read_dicom_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md)
inspects all slices in a folder, sorts them along the slice-normal
trajectory, calculates the analytical $`4 \times 4`$ voxel-to-world
affine matrix, and verifies slice continuity:

`vol`` ``<-`` `[`read_dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md)`(``synth_dir``)`` `` ``# Print summary of S3 dicom_volume object`` ``vol`` ``#> <dicom_volume [CT] 32x32x4 | coord=LPS | units=HU>`` ``#> spacing: (0.8, 0.8, 2.5) mm | origin: (-20, -15, 10) mm`` ``#> frame_meta: 4 row(s) | provenance: 1 step(s)`` `` ``# Inspect dimensions and affine matrix`` `[`dim`](https://rdrr.io/r/base/dim.html)`(``vol``)`` ``#> [1] 32 32 4`` ``vol``$``affine`` ``#> [,1] [,2] [,3] [,4]`` ``#> [1,] -0.21796232 0.7610010 -0.3613386 -20`` ``#> [2,] 0.76666649 0.2039096 -0.3223960 -15`` ``#> [3,] 0.06866532 0.1389185 2.4526507 10`` ``#> [4,] 0.00000000 0.0000000 0.0000000 1`

### Checking Orientation

[`dicom_orientation()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_orientation.md)
extracts the standard 3-letter patient anatomical direction code (e.g.,
`LPS` for axial, `LIP` for coronal, `PIR` for sagittal):

[`dicom_orientation`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_orientation.md)`(``vol``)`` ``#> [1] "LPS"`` `` ``sag_dir`` ``<-`` `[`tempfile`](https://rdrr.io/r/base/tempfile.html)`(``"phantom_sag_"``)`` `[`dicom_synthesize`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md)`(``out_dir ``=`` ``sag_dir``, modality ``=`` ``"MR"``, dims ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``16L``, ``16L``, ``4L``)``, orientation ``=`` ``"sagittal"``, phi ``=`` ``FALSE``)`` ``vol_sag`` ``<-`` `[`read_dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md)`(``sag_dir``)`` `[`dicom_orientation`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_orientation.md)`(``vol_sag``)`` ``#> [1] "PIR"`` `[`unlink`](https://rdrr.io/r/base/unlink.html)`(``sag_dir``, recursive ``=`` ``TRUE``)`

------------------------------------------------------------------------

## 3. Transforming Between LPS and RAS Coordinate Spaces

To interface cleanly between DICOM clinical viewers (LPS) and
neuroimaging packages like FSL, SPM, ANTs, or FreeSurfer (RAS), use
[`dicom_to_ras()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_ras.md)
([`to_ras()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_ras.md))
and
[`dicom_to_lps()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_ras.md)
([`to_lps()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_ras.md)):

`# Convert world coordinate frame from DICOM LPS to Neuroimaging RAS`` ``vol_ras`` ``<-`` `[`dicom_to_ras`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_ras.md)`(``vol``)`` ``vol_ras``$``coord_system`` ``#> [1] "RAS"`` `` ``# Anatomical axis directions remain invariant because voxel memory is unpermuted`` `[`dicom_orientation`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_orientation.md)`(``vol_ras``)`` ``#> [1] "LPS"`` `` ``# Inspect the negated X/Y rows of the 4x4 RAS affine`` ``vol_ras``$``affine`` ``#> [,1] [,2] [,3] [,4]`` ``#> [1,] 0.21796232 -0.7610010 0.3613386 20`` ``#> [2,] -0.76666649 -0.2039096 0.3223960 15`` ``#> [3,] 0.06866532 0.1389185 2.4526507 10`` ``#> [4,] 0.00000000 0.0000000 0.0000000 1`

[`to_ras()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_ras.md)
and
[`to_lps()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_ras.md)
premultiply `affine` and `direction` by `diag(c(-1, -1, 1, 1))` (a
180-degree rotation around the Superior $`Z`$ axis, $`\det = +1`$)
without permuting in-memory voxel arrays, preserving right-handedness
and physical world correspondence.

------------------------------------------------------------------------

## 4. Modality Quantitative Transforms

Raw stored pixel values in DICOM are typically integers requiring
physics calibrations before analysis.

### PET Standardized Uptake Value (SUV)

PET scanners record radioactivity concentrations (`BQML`).
[`dicom_pet_suv()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_pet_suv.md)
calculates SUV normalized by patient Body Weight (`bw`), Lean Body Mass
(`lbm`), or Body Surface Area (`bsa`), with radioactive half-life decay
compensation:

`pet_dir`` ``<-`` `[`tempfile`](https://rdrr.io/r/base/tempfile.html)`(``"phantom_pet_"``)`` `[`dicom_synthesize`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md)`(``out_dir ``=`` ``pet_dir``, modality ``=`` ``"PT"``, dims ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``16L``, ``16L``, ``2L``)``, phi ``=`` ``FALSE``)`` ``pet_vol`` ``<-`` `[`read_dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md)`(``pet_dir``)`` `` ``# Compute body-weight SUV (g/ml)`` ``pet_suv`` ``<-`` `[`dicom_pet_suv`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_pet_suv.md)`(``pet_vol``, method ``=`` ``"bw"``)`` ``pet_suv`` ``#> <dicom_volume [PT] 16x16x2 | coord=LPS | units=g/ml>`` ``#> spacing: (1, 1, 2.5) mm | origin: (-16, -16, 0) mm`` ``#> frame_meta: 2 row(s) | provenance: 2 step(s)`` `[`unlink`](https://rdrr.io/r/base/unlink.html)`(``pet_dir``, recursive ``=`` ``TRUE``)`

### Mammography & Radiography VOI LUT

For digital radiography (`DX`) and mammography (`MG`),
[`dicom_apply_voi_lut()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_apply_voi_lut.md)
maps stored pixel values using standard DICOM PS3.3 `LINEAR`,
`LINEAR_EXACT`, or `SIGMOID` transfer functions and automatically
inverts `MONOCHROME1` images:

`mg_dir`` ``<-`` `[`tempfile`](https://rdrr.io/r/base/tempfile.html)`(``"phantom_mg_"``)`` `[`dicom_synthesize`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md)`(``out_dir ``=`` ``mg_dir``, modality ``=`` ``"MG"``, dims ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``16L``, ``16L``, ``1L``)``, phi ``=`` ``FALSE``)`` ``mg_vol`` ``<-`` `[`read_dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md)`(``mg_dir``)`` `` ``mg_viewable`` ``<-`` `[`dicom_apply_voi_lut`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_apply_voi_lut.md)`(``mg_vol``)`` `[`range`](https://rdrr.io/r/base/range.html)`(``mg_viewable``$``voxels``)`` ``#> [1] 0.3392436 0.8779687`` `[`unlink`](https://rdrr.io/r/base/unlink.html)`(``mg_dir``, recursive ``=`` ``TRUE``)`

### Philips MR Private Scaling

Philips MR scanners store console display rescale parameters
`(0028,1052)` / `(0028,1053)` alongside private quantitative scaling
intercept `(2005,100D)` (`ScaleIntercept`) and slope `(2005,100E)`
(`ScaleSlope`).
[`dicom_mr_rescale()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_mr_rescale.md)
recovers floating-point physical values $`P = D / (RS \cdot SS)`$ per
Chenevert et al. (2014):

`mr_dir`` ``<-`` `[`tempfile`](https://rdrr.io/r/base/tempfile.html)`(``"phantom_mr_"``)`` `[`dicom_synthesize`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md)`(`` `` out_dir ``=`` ``mr_dir``,`` `` modality ``=`` ``"MR"``,`` `` dims ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``16L``, ``16L``, ``2L``)``,`` `` extra_tags ``=`` `[`list`](https://rdrr.io/r/base/list.html)`(`` `` RescaleIntercept ``=`` ``"0"``,`` `` RescaleSlope ``=`` ``"2.0"``,`` `` ``"(2005,100D)"`` ``=`` ``"0"``,`` `` ``"(2005,100E)"`` ``=`` ``"4.0"`` `` ``)``,`` `` phi ``=`` ``FALSE`` ``)`` ``mr_vol`` ``<-`` `[`read_dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md)`(``mr_dir``)`` ``mr_phys`` ``<-`` `[`dicom_mr_rescale`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_mr_rescale.md)`(``mr_vol``, philips_float ``=`` ``TRUE``)`` ``mr_phys`` ``#> <dicom_volume [MR] 16x16x2 | coord=LPS>`` ``#> spacing: (1, 1, 2.5) mm | origin: (-16, -16, 0) mm`` ``#> frame_meta: 2 row(s) | provenance: 2 step(s)`` `[`unlink`](https://rdrr.io/r/base/unlink.html)`(``mr_dir``, recursive ``=`` ``TRUE``)`

------------------------------------------------------------------------

## 5. Exporting to NIfTI-1 with BIDS Sidecar (`write_nifti()`)

[`write_nifti()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_nifti.md)
writes standards-compliant NIfTI-1 (`.nii`) files matching Chris
Rorden’s `dcm2niix` specification:

- Exact `sform` affine matrix in RAS coordinate space.
- Exact `qform` quaternion rotation derived via polar SVD decomposition.
- Companion BIDS JSON sidecar (`<filename>.json`) capturing scanner
  parameters (`RepetitionTime`, `EchoTime`, `SliceThickness`,
  `SpacingBetweenSlices`).

`out_nii`` ``<-`` `[`tempfile`](https://rdrr.io/r/base/tempfile.html)`(``fileext ``=`` ``".nii"``)`` ``bids_json`` ``<-`` `[`sub`](https://rdrr.io/r/base/grep.html)`(``"\\.nii$"``, ``".json"``, ``out_nii``)`` `[`write_nifti`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_nifti.md)`(``vol``, ``out_nii``, json_sidecar ``=`` ``TRUE``)`` `` `[`file.exists`](https://rdrr.io/r/base/files.html)`(``out_nii``)`` ``#> [1] TRUE`` `[`file.exists`](https://rdrr.io/r/base/files.html)`(``bids_json``)`` ``#> [1] TRUE`` `` ``# Clean up`` `[`unlink`](https://rdrr.io/r/base/unlink.html)`(`[`c`](https://rdrr.io/r/base/c.html)`(``synth_dir``, ``out_nii``, ``bids_json``)``, recursive ``=`` ``TRUE``)`

------------------------------------------------------------------------

## 6. Full Backward Compatibility

All existing functions from `dicomtk` v0.1.0 remain fully functional: -
[`read_dicom_series()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_series.md)
delegates directly to
[`read_dicom_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md). -
[`dicom_to_nifti()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_to_nifti.md)
delegates directly to
[`write_nifti()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_nifti.md).
