# Phase 2 Implementation Plan: Segmentation, RTSTRUCT/RTDOSE, Quantitative SR & DL Prep (`v0.4.0`)

- **Worktree:** `C:/Users/lauye/.gemini/antigravity/scratch/dicomtk/.worktrees/p2-seg-rt` (`feature/p2-seg-rt`)
- **Design:** `dev/plans/2026-11-11-p2-seg-rt-design.md`
- **Baseline Verification:** `0 FAIL | 0 WARN | 3 SKIP | 1,768 PASS`

---

### Task 1: C++17 Polygon Rasterizer & 2D Contour Tracer
- **Files:** `src/rcpp_rasterize.cpp`, `src/rcpp_rasterize.h`, `R/rasterize.R`, `tests/testthat/test-p2-rasterize.R`
- **Description:** Implement pure C++17 scanline winding-number polygon rasterization to fill interior 2D grid pixels from polygonal vertices, and marching squares / boundary traversal to convert 2D binary masks back into closed planar polygon coordinates.
- **Verification:** Unit tests verifying convex polygons, concave polygons, holes/donuts, and self-intersections against synthetic geometry.

---

### Task 2: Unified `dicom_seg` S3 Class & DICOM-SEG IOD Reader/Writer
- **Files:** `R/seg.R`, `R/dicom-volume.R`, `src/rcpp_seg.cpp`, `tests/testthat/test-p2-seg.R`
- **Description:** Implement `dicom_seg` as an S3 subclass of `dicom_volume`. Support 1-bit packed binary frames, 8-bit fractional probability maps, and Sup 243 multi-class label-maps with full `SegmentSequence` metadata and 4x4 spatial affine alignment.
- **Verification:** Unit tests reading and writing synthetic DICOM-SEG objects, round-tripping masks, and asserting spatial coordinates against the parent `dicom_volume`.

---

### Task 3: `RTSTRUCT` $\leftrightarrow$ `dicom_seg` Bi-Directional Conversion
- **Files:** `R/rt-struct.R`, `R/rt_seg.R`, `tests/testthat/test-p2-rtstruct.R`
- **Description:** Implement `rtstruct_to_seg(rt, ref_volume)` to rasterize clinical contours into 3D volume masks aligned with the CT/MR slice coordinates. Implement `seg_to_rtstruct(seg, ref_volume, roi_names)` to extract planar contours and construct valid `RTSTRUCT` DICOM objects with `ROIContourSequence` and `StructureSetROISequence`.
- **Verification:** Unit tests verifying contour-to-mask and mask-to-contour round-trip spatial volume accuracy.

---

### Task 4: `RTDOSE` Spatial Integration & Dose-Volume Histogram (`dicom_dvh()`)
- **Files:** `R/rt-dose.R`, `tests/testthat/test-p2-rtdose.R`
- **Description:** Spatial alignment of `RTDOSE` grids with reference volumes and `dicom_seg` structures. Compute cumulative and differential Dose-Volume Histograms ($D_{95}$, $D_{50}$, $V_{20}$, min/max/mean dose) and DVH summary tables.
- **Verification:** Mathematical verification of DVH curves against analytical geometric phantoms (e.g. uniform dose sphere).

---

### Task 5: Quantitative Imaging SR TID 1500 (Measurement Report) & GSPS Reader/Writer
- **Files:** `R/sr-tid1500.R`, `R/gsps.R`, `tests/testthat/test-p2-sr.R`
- **Description:** Implement native parsing and building of DICOM Structured Reporting **TID 1500** for quantitative volumetric and morphologic measurements (volume in $\text{mm}^3$, RECIST longest diameter, mean/std HU/SUV within segments). Implement Grayscale Softcopy Presentation State (GSPS) parser.
- **Verification:** Unit tests creating and verifying TID 1500 trees, validating coded concept sequences (SNOMED, UCUM units).

---

### Task 6: Safe Derived Burned-Annotation Exporter
- **Files:** `R/export-burned.R`, `tests/testthat/test-p2-burned-export.R`
- **Description:** Implement `dicom_burn_annotations(volume, annotations, out_dir)` to generate derived Secondary Capture (`ImageType = DERIVED\SECONDARY`) with burned arrows, calipers, and labels for conference and teaching files while strictly prohibiting mutation of original pixel data.
- **Verification:** Unit tests verifying that source files remain unchanged, `ImageType` contains `DERIVED`, and new SOP Instance UIDs are minted.

---

### Task 7: Deep Learning Preprocessing (Resampling, Windowing & Patient Splits)
- **Files:** `src/rcpp_resample.cpp`, `R/dl-prep.R`, `tests/testthat/test-p2-dl-prep.R`
- **Description:** C++17 3D volume resampling with trilinear interpolation for continuous voxel intensities and nearest-neighbor for segmentation labels. Add window-level HU clipping, z-score normalization, and leakage-free patient-level split generator (`train`, `val`, `test`).
- **Verification:** Resampling precision tests verifying isotropic voxel dimensions and zero patient leakage across folds.

---

### Task 8: Dataset Exporters (nnU-Net v2, MONAI, RO-Crate & Croissant Metadata)
- **Files:** `R/export-dataset.R`, `tests/testthat/test-p2-exporters.R`
- **Description:** Standardized export pipelines for **nnU-Net v2** (`dataset.json`, `imagesTr`, `labelsTr`) and **MONAI** dictionary formats. Generate dataset provenance schemas using **RO-Crate** and **MLCommons Croissant** JSON-LD.
- **Verification:** Validation of exported JSON metadata against official nnU-Net v2 and Croissant schema specifications.

---

### Task 9: Automated Image QC, Release Prep (`v0.4.0`), Vignette & Six-Sigma CRAN Check
- **Files:** `R/qc.R`, `DESCRIPTION`, `NEWS.md`, `MEMORY.md`, `vignettes/segmentation_and_rt.Rmd`, `_pkgdown.yml`, `tests/testthat/test-p2-qc.R`
- **Description:** Automated detection of acquisition artifacts, FOV truncation, and motion artifacts with SNR/CNR metrics. Bump version to `0.4.0`. Add comprehensive vignette and pkgdown reference. Execute full Six-Sigma CRAN gating on **Gemini 4 Argon (High)**.
- **Verification:** `0 ERRORs | 0 WARNINGs` on `R CMD check --as-cran`, pure ASCII, 0 temp detritus.
