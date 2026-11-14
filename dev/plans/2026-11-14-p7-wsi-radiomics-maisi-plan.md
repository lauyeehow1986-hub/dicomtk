# Phase 7 (`dicomtk 0.6.0` & `dicomtk.ai 0.2.0`) Implementation Plan

## Task 1: DICOM WSI Multi-Resolution Pyramid Reader & Out-of-Core Tile Stitcher (`dicomtk/R/wsi.R`)
- **Files**: `C:/Users/lauye/.gemini/antigravity/scratch/dicomtk/R/wsi.R`, `tests/testthat/test-wsi.R`
- **Functions**:
  - `dicom_synthesize_wsi(out_dir = tempfile("wsi_"), base_dims = c(64L, 64L), tile_dims = c(16L, 16L), levels = 2L, organization = c("TILED_FULL", "TILED_SPARSE"))`
  - `read_dicom_wsi_pyramid(path)`
  - `wsi_extract_tile(pyramid, level = 1L, tile_row = 1L, tile_col = 1L)`
  - `wsi_stitch_region(pyramid, level = 1L, x = 1L, y = 1L, width = 32L, height = 32L)`
  - `dicom_wsi_annotations(rois, coordinate_type = c("2D", "3D"), pixel_matrix_dims = c(64L, 64L))`
  - `wsi_annotations_to_mask(annotations, level_dims = NULL)`
- **Verification**: RED -> GREEN `testthat::test_local(filter = "wsi")` verifying `TILED_FULL` and `TILED_SPARSE` pyramid indexing, exact region stitching across tile boundaries, and Supplement 222 polygon ROI rasterization.

## Task 2: `dicomtk 0.6.0` Version Bump, `NEWS.md`, `_pkgdown.yml` & `R CMD check --as-cran`
- **Files**: `C:/Users/lauye/.gemini/antigravity/scratch/dicomtk/DESCRIPTION`, `NEWS.md`, `_pkgdown.yml`
- **Verification**: Run `roxygen2::roxygenise()`, `pkgdown::check_pkgdown()`, `devtools::check(..., args = c("--no-manual", "--as-cran"))` -> `0 errors | 0 warnings`, and install `dicomtk 0.6.0` into the local R library.

## Task 3: IBSI Phase-1 Digital Phantom & Standardized 3D Radiomics Engine (`dicomtk.ai/R/radiomics-ibsi.R`)
- **Files**: `C:/Users/lauye/.gemini/antigravity/scratch/dicomtk.ai/R/radiomics-ibsi.R`, `tests/testthat/test-radiomics-ibsi.R`
- **Functions**:
  - `ibsi_digital_phantom()`
  - `ai_extract_radiomics(volume, mask = NULL, discretization = c("none", "fbn", "fbw"), n_bins = 16L, bin_width = 25, backend = c("native", "pyradiomics"))`
- **Verification**: RED -> GREEN `testthat::test_local(filter = "radiomics-ibsi")` comparing computed first-order (`stat_mean = 2.15`, `stat_median = 1`, `stat_var`, `stat_skewness`, `stat_kurtosis`), morphological (`morph_voxel_volume = 592` for $2\times2\times2\text{ mm}$ spacing), 3D GLCM, 3D GLRLM, and 3D GLSZM features against IBSI Phase-1 reference benchmarks.

## Task 4: Train/Test-Safe Empirical Bayes ComBat Harmonisation (`dicomtk.ai/R/combat.R`)
- **Files**: `C:/Users/lauye/.gemini/antigravity/scratch/dicomtk.ai/R/combat.R`, `tests/testthat/test-combat.R`
- **Functions**:
  - `combat_fit(features, batch, mod = NULL, eb = TRUE, ref_batch = NULL)`
  - `combat_apply(fit, features, batch, mod = NULL)`
  - `ai_combat_harmonize(features, batch, mod = NULL, eb = TRUE, ref_batch = NULL)`
- **Verification**: RED -> GREEN `testthat::test_local(filter = "combat")` verifying removal of synthetic scanner location/scale shifts while preserving biological covariate effect (`mod`) and zero leakage between `combat_fit(train)` and `combat_apply(fit, test)`.

## Task 5: MONAI MAISI 3D Synthetic CT + Organ Mask Generator (`dicomtk.ai/R/maisi-synthetic.R`)
- **Files**: `C:/Users/lauye/.gemini/antigravity/scratch/dicomtk.ai/R/maisi-synthetic.R`, `R/zzz.R`, `tests/testthat/test-maisi-synthetic.R`
- **Functions**:
  - `ai_generate_maisi(out_dir = tempfile("maisi_"), anatomy_list = c("liver", "spleen", "left_kidney", "right_kidney"), dims = c(32L, 32L, 16L), spacing = c(1.5, 1.5, 2.0), mode = c("phantom", "http"), endpoint = NULL)`
- **Verification**: RED -> GREEN `testthat::test_local(filter = "maisi-synthetic")` verifying multi-organ HU synthesis, paired `dicom_seg` mask alignment, and `DERIVED\SECONDARY\SYNTHETIC` header tagging.

## Task 6: `dicomtk.ai 0.2.0` Version Bump, `NEWS.md`, `_pkgdown.yml` & `R CMD check --as-cran`
- **Files**: `C:/Users/lauye/.gemini/antigravity/scratch/dicomtk.ai/DESCRIPTION`, `NEWS.md`, `_pkgdown.yml`
- **Verification**: Run `roxygen2::roxygenise()`, `pkgdown::check_pkgdown()`, `devtools::check(..., args = c("--no-manual", "--as-cran"))` -> `0 errors | 0 warnings`.

## Task 7: Final Argon (High) IBSI Mathematical & ComBat Leakage Audit + Release Push (`dicomtk 0.6.0` & `dicomtk.ai 0.2.0`)
- **Verification**: Switch to **Gemini 4 Argon (High)** for mathematical verification of IBSI Phase-1 equations and Empirical Bayes prior convergence, install both packages locally, and push `dicomtk 0.6.0` and `dicomtk.ai 0.2.0` to `origin/main`.
