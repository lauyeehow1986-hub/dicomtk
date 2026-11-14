# Phase 7 (`dicomtk 0.6.0` & `dicomtk.ai 0.2.0`) Design: DICOM WSI Pyramids, IBSI Radiomics + ComBat & MONAI MAISI Synthetic Data

## 1. `dicomtk 0.6.0` — DICOM Whole Slide Imaging (WSI) Pyramids & Sup 222 Annotations (`R/wsi.R`)

1. **Multi-Resolution WSI Pyramid Reader (`read_dicom_wsi_pyramid()`)**:
   - Inspects VL Whole Slide Microscopy Image (`1.2.840.10008.5.1.4.1.1.77.1.6`) series or single multi-frame files.
   - Extracts `TotalPixelMatrixColumns` `(0048,0006)`, `TotalPixelMatrixRows` `(0048,0007)`, `Columns`, `Rows`, `DimensionOrganizationType` (`TILED_FULL` or `TILED_SPARSE`), `NumberOfFrames`, and physical millimeter pixel spacing (`ImagedVolumeWidth` / `ImagedVolumeHeight`).
   - Computes exact tile grid coordinates `(tile_row, tile_col, x_offset, y_offset)` for every frame under both `TILED_FULL` (implicit raster scan order) and `TILED_SPARSE` (explicit per-frame `ColumnPositionInTotalImagePixelMatrix` / `RowPositionInTotalImagePixelMatrix`), and sorts pyramid levels from Level 0 (base highest resolution) to Level $L-1$ (overview thumbnail).
2. **Out-of-Core Tile Extraction & Region Stitching (`wsi_extract_tile()`, `wsi_stitch_region()`)**:
   - `wsi_extract_tile(pyramid, level = 1L, tile_row = 1L, tile_col = 1L)`: Reads only the requested tile frame without loading the full gigapixel slide.
   - `wsi_stitch_region(pyramid, level = 1L, x = 1L, y = 1L, width = 128L, height = 128L)`: Identifies intersecting tiles at `level`, reads and stitches them into a contiguous `height x width` array, and crops to the exact bounding box.
3. **Supplement 222 Microscopy Bulk Simple Annotations (`dicom_wsi_annotations()`)**:
   - Creates, reads, and converts slide-coordinate (`2D` `STAGE` / `SLIDE` or `IMAGE` total-pixel-matrix coordinates) polygon/polyline/point ROI groups for digital pathology nuclei/tissue annotations, with round-trip JSON/tibble export and raster mask conversion (`wsi_annotations_to_mask()`).

---

## 2. `dicomtk.ai 0.2.0` — IBSI-Compliant Radiomics, ComBat Harmonisation & MONAI MAISI (`R/radiomics-ibsi.R`, `R/combat.R`, `R/maisi-synthetic.R`)

1. **IBSI Phase-1 Digital Phantom & Standardized 3D Radiomics (`R/radiomics-ibsi.R`)**:
   - `ibsi_digital_phantom()`: Returns the canonical IBSI Phase-1 $5 \times 4 \times 4$ (74-voxel ROI inside a $5 \times 4 \times 4$ grid with intensities $\{1, 3, 4, 6, 7, 8, 9\}$ and `NA`/outside-ROI voxels) digital phantom volume and binary mask.
   - `ai_extract_radiomics(volume, mask, discretization = c("none", "fbn", "fbw"), n_bins = 16L, bin_width = 25, backend = c("native", "pyradiomics"))`:
     - Computes IBSI-standardized features across 5 families:
       1. **Morphology**: `morph_voxel_volume`, `morph_surface_area`, `morph_sphericity`, `morph_compactness_1`.
       2. **First-Order Intensity / Histogram**: `stat_mean`, `stat_var`, `stat_skewness`, `stat_kurtosis`, `stat_median`, `stat_iqr`, `stat_energy`, `stat_entropy`, `stat_uniformity`.
       3. **3D GLCM (Gray-Level Co-occurrence Matrix, 26-connected merged/averaged)**: `glcm_joint_max`, `glcm_joint_average`, `glcm_contrast`, `glcm_dissimilarity`, `glcm_inverse_difference` (homogeneity), `glcm_angular_second_moment` (energy), `glcm_joint_entropy`, `glcm_correlation`.
       4. **3D GLRLM (Gray-Level Run-Length Matrix)**: `glrlm_short_runs_emphasis`, `glrlm_long_runs_emphasis`, `glrlm_gray_level_non_uniformity`, `glrlm_run_length_non_uniformity`, `glrlm_run_percentage`.
       5. **3D GLSZM (Gray-Level Size-Zone Matrix, 26-connected)**: `glszm_small_zone_emphasis`, `glszm_large_zone_emphasis`, `glszm_gray_level_non_uniformity`, `glszm_zone_size_non_uniformity`, `glszm_zone_percentage`.
     - Verified against published IBSI Phase-1 Digital Phantom reference values within IBSI tolerance.

2. **Train/Test-Safe Empirical Bayes ComBat Harmonisation (`R/combat.R`)**:
   - `combat_fit(features, batch, mod = NULL, eb = TRUE, ref_batch = NULL)`: Fits location ($\hat{\gamma}_{ig}^*$) and scale ($\hat{\delta}_{ig}^{2*}$) Empirical Bayes batch parameters on training data while preserving biological covariates `mod` (`matrix` or `model.matrix`).
   - `combat_apply(fit, features, batch, mod = NULL)`: Applies the fitted harmonisation parameters to training or held-out test cohorts without refitting on test data (preventing data leakage).
   - `ai_combat_harmonize(features, batch, mod = NULL, eb = TRUE, ref_batch = NULL)`: Convenience wrapper returning both `harmonized` features and `fit` object.

3. **MONAI MAISI 3D Synthetic CT + Organ Mask Generator (`R/maisi-synthetic.R`)**:
   - Registers `"maisi"` in the `dicomtk.ai` backend registry.
   - `ai_generate_maisi(out_dir = tempfile("maisi_"), anatomy_list = c("liver", "spleen", "left_kidney", "right_kidney"), dims = c(32L, 32L, 16L), spacing = c(1.5, 1.5, 2.0), mode = c("phantom", "http"), endpoint = NULL)`:
     - Generates paired 3D synthetic CT (`dicom_volume` + DICOM slices with `ImageType = "DERIVED\\SECONDARY\\SYNTHETIC"`) and multi-organ `dicom_seg` masks, plus a provenance manifest preventing synthetic data from being mistaken for real patient scans.
