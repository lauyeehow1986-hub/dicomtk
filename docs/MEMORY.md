# MEMORY.md — dicomtk Project Memory & State

## Project Identity & Decisions

- **Package Name**: `dicomtk` (replaces legacy `dcmtk` R wrapper from
  `lauyeehow1986-hub/dcmtk_r` / `muschellij2/dcmtk`).
- **Workspace Path**:
  `C:\Users\lauye\.gemini\antigravity\scratch\dicomtk`
- **Reference Clones**:
  - Legacy R wrapper:
    `C:\Users\lauye\.gemini\antigravity\scratch\dcmtk_r_ref` (v0.8.0)
  - Upstream DCMTK C++ repo:
    `C:\Users\lauye\.gemini\antigravity\scratch\dcmtk_upstream` (v3.7.1)
- **User Requirements**:
  1.  Full sync with official DCMTK functionalities across all modules
      (`dcmdata`, `dcmimgle`, `dcmimage`, `dcmjpeg`, `dcmjpls`,
      `dcmnet`, `dcmsr`, `dcmiod`, `dcmfg`, `dcmrt`, `dcmseg`,
      `dcmpmap`, `dcmtract`, `dcmect`, `dcmpstat`, `dcmqrdb`, `dcmwlm`,
      `dcmsign`, `dcmtls`).
  2.  Bundle DCMTK C++ headers (`inst/include/dcmtk/`), 5,354-entry
      2026d data dictionary (`src/dcmtk_dict_builtin.h` +
      `data/dicom_tags.rda` + `inst/extdata/dicom.dic`), and native
      C++17 / Rcpp engine in the R package so users do not need external
      DCMTK installation.
  3.  Direct Rcpp C++ API bindings (replacing fragile CLI
      [`system()`](https://rdrr.io/r/base/system.html) + stdout regex
      parsing), while retaining backward-compatible wrappers for
      existing `dcmtk` R functions.
  4.  Tidyverse-compliant API (`tibble` outputs, `snake_case`,
      pipe-friendly `|>`).
  5.  Complete DICOM visualization suite: `ggplot2`
      ([`plot_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/plot_dicom.md),
      [`ggdicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/ggdicom.md)),
      interactive `Shiny` viewer
      ([`dicom_viewer()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_viewer.md)),
      and 3D volume rendering via MPR/MIP/`rgl`
      ([`render_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/render_volume.md)).
  6.  LLM integration: Local LLMs via **Ollama** and cloud/subscription
      **OpenAI-compatible APIs** (OpenAI, Anthropic Claude, custom
      endpoints) for metadata summarization, vision-based image
      description, structured radiology report generation, and
      natural-language DICOM tag lookup/querying.
  7.  Target all 3 CRAN platforms (Windows, macOS, Linux) and design for
      CRAN compliance.

------------------------------------------------------------------------

## Implementation Progress Log

### Completed (All Phases 1–6)

Cloned `lauyeehow1986-hub/dcmtk_r` (`dcmtk_r_ref`) and `DCMTK/dcmtk`
(`dcmtk_upstream`).

Audited all 21 R files in `dcmtk_r_ref` and mapped DCMTK 3.7.1 C++
headers.

Created `dicomtk` directory structure (`R/`, `src/`, `inst/`, `tests/`,
`vignettes/`, `tools/`, `.github/workflows/`).

Created `DESCRIPTION`, `NAMESPACE`, `.Rbuildignore`, `NEWS.md`,
`_pkgdown.yml`, `CLAUDE.md`, and `MEMORY.md`.

Synchronized all 5,354 DICOM tags from DCMTK 3.7.1 (`PS 3.6-2026d`) via
`tools/bundle_dcmtk.R` into `data/dicom_tags.rda`,
`inst/extdata/dicom.dic`, and `src/dcmtk_dict_builtin.h`.

Bundled all 23 DCMTK 3.7.1 module C++ header trees into
`inst/include/dcmtk/`.

Implemented `configure`, `configure.win`, `cleanup`, `src/Makevars.in`,
and `src/Makevars.win`.

Implemented C++17 / Rcpp bindings (`src/rcpp_dcmtk.h`,
`src/rcpp_init.cpp`, `src/rcpp_read.cpp`, `src/rcpp_write.cpp`,
`src/rcpp_image.cpp`, `src/rcpp_convert.cpp`, `src/rcpp_network.cpp`,
`src/rcpp_sr_rt.cpp`) with zero compiler warnings.

Implemented all R modules covering every DCMTK subsystem (`read.R`,
`write.R`, `tags.R`, `anonymize.R`, `convert.R`, `compress.R`, `plot.R`,
`viewer.R`, `volume.R`, `network.R`, `sr.R`, `rt_seg.R`,
`llm-providers.R`, `llm-prompts.R`, `llm.R`, `legacy.R`, `utils.R`,
`zzz.R`).

Created interactive 4-tab Shiny DICOM & AI Radiology workstation
(`inst/shiny/viewer/app.R`).

Created all 5 vignettes (`getting-started.Rmd`,
`image-visualization.Rmd`, `pacs-networking.Rmd`, `llm-integration.Rmd`,
`anonymization.Rmd`) and package hex logo (`man/figures/logo.png`).

95 unit tests (`testthat`), including a live DIMSE C-ECHO SCP/SCU TCP
loopback test (runs only when `NOT_CRAN=true`).

- Note: commit `75e2749` (the version submitted to CRAN) failed on
  `macos-latest` with `ignoring SIGPIPE signal` in
  `cpp_dicom_echo_loopback_test()` because the client closed the socket
  before draining `C-ECHO-RSP`/`A-RELEASE-RP`. Fixed in `94df4b2` (drain
  PDUs + `SO_NOSIGPIPE`/`MSG_NOSIGNAL`) and the test is now skipped on
  CRAN.

Verified live local Ollama integration (`http://localhost:11434`) with
`llama3.2:3b`, `llava:7b`, and `amsaravi/medgemma-4b-it:q8`.

Initialized Git repository on `main` and pushed to `origin`
(`https://github.com/lauyeehow1986-hub/dicomtk.git`).

Built and deployed `pkgdown` documentation site to GitHub Pages
(`https://lauyeehow1986-hub.github.io/dicomtk/`).

Published GitHub Release `v0.1.0`
(`https://github.com/lauyeehow1986-hub/dicomtk/releases/tag/v0.1.0`)
with source (`dicomtk_0.1.0.tar.gz`) and Windows binary
(`dicomtk_0.1.0.zip`) assets.

Configured automated weekly & on-demand upstream DCMTK synchronization
(`.github/workflows/sync-upstream-dcmtk.yaml` +
[`dicom_sync_upstream()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_sync_upstream.md)).

Published R-Universe package registry
(`https://github.com/lauyeehow1986-hub/lauyeehow1986-hub.r-universe.dev`)
for
`install.packages("dicomtk", repos = "https://lauyeehow1986-hub.r-universe.dev")`.

### Phase 0 (`v0.2.0` Foundations) — Completed

**Task 1: C++ Hierarchical Sequences & Nested `SQ` Writer**:

- Implemented recursive sequence indexing and explicit-length nested
  `SQ` serialization via `cpp_write_dicom_multiframe()`,
  `cpp_modify_dicom()`, and `cpp_dcm_transcode_rle()` in
  `src/rcpp_read.cpp`, `src/rcpp_write.cpp`, and `src/rcpp_convert.cpp`.

**Task 2: Synthetic Phantom Generator
([`dicom_synthesize()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md))**:

- Parametric synthesis of CT, MR, and PET series in `R/synthesize.R`
  with known analytical ground-truth LPS/RAS affines, voxel arrays,
  non-orthogonal gantry tilt, and PHI injection/scrubbing.

**Task 3: `dicom_volume` S3 Class & Spatial Transforms**:

- Implemented
  [`new_dicom_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md),
  [`print.dicom_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md),
  [`dim.dicom_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md),
  `[.dicom_volume()` (with affine translation/rescaling),
  [`as.array.dicom_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md),
  [`dicom_orientation()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_orientation.md),
  [`dicom_to_lps()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_ras.md),
  and
  [`dicom_to_ras()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_ras.md)
  in `R/dicom-volume.R`.

**Task 4: Geometry-Aware
[`read_dicom_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md)**:

- Implemented
  [`read_dicom_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md)
  in `R/volume-read.R` with enhanced multi-frame support
  (`SharedFunctionalGroupsSequence` /
  `PerFrameFunctionalGroupsSequence`), series splitting, and transparent
  delegation for
  [`read_dicom_series()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_series.md).

**Task 5: Modality Quantitative Transforms**:

- Implemented
  [`dicom_pet_suv()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_pet_suv.md)
  (bw, lbm James/Janmahasatian, bsa with decay correction),
  [`dicom_apply_voi_lut()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_apply_voi_lut.md)
  (linear and sigmoid windowing), and
  [`dicom_mr_rescale()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_mr_rescale.md)
  (Philips private attributes 2005,100D/100E) in
  `R/modality-transforms.R`.

**Task 6:
[`write_nifti()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_nifti.md)
with `dcm2niix` Parity**:

- Implemented
  [`write_nifti()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_nifti.md)
  in `R/nifti.R` with exact RAS `sform`, polar SVD `qform`
  decomposition, BIDS JSON sidecar, zero-dependency pure R binary
  writer, `RNifti` backend fallback, gantry-tilt notification, and
  [`dicom_to_nifti()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_to_nifti.md)
  delegation.

**Task 7: CI Fixture Downloader & Parity Validation**:

- Implemented `tools/download_fixtures.R` syncing 11 scanner fixtures,
  `tests/testthat/helper-fixtures.R` Chris Rorden oracle, and
  `tests/testthat/test-p0-dcm2niix-parity.R`.

**Task 8: `dicomtk-lab` Container Testbed**:

- Standalone multi-profile Docker Compose environment at
  `C:/Users/lauye/.gemini/antigravity/scratch/dicomtk-lab` with `core`,
  `enterprise`, `ehr`, `ohdsi`, `ttp`, and `fl` profiles, and
  `tests/testthat/test-p0-lab-core.R` smoke test.

**Task 9: `v0.2.0` Release Documentation & Vignettes**:

- Updated `DESCRIPTION` (0.2.0), `NEWS.md`, `_pkgdown.yml`,
  `vignettes/volume-geometry.Rmd`, and verified full test suite.

### Phase 1 (`v0.3.0` Research-Grade De-Identification Engine) — Completed

**Task 1: C++17 RFC Cryptography & Pluggable Key Provider**:

- Implemented standalone C++17 implementations of RFC 6234 SHA-256, RFC
  4231 HMAC-SHA256, RFC 2898 PBKDF2-HMAC-SHA256, RFC 5869 HKDF-SHA256,
  and RFC 8439 ChaCha20-Poly1305 AEAD (`src/rcpp_crypto.h`,
  `src/rcpp_crypto.cpp`).
- Added
  [`dicom_key_provider()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_key_provider.md)
  S3 class supporting `local`, `broker`, and `ttp` modes, credential
  redaction, deterministic `2.25.<128-bit>` UID pseudonymization
  ([`deid_map_uid()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/deid_map_uid.md)),
  and per-patient pseudo-random date shifting
  ([`derive_patient_shift_days()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/derive_patient_shift_days.md),
  [`deid_patient_shift()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/deid_patient_shift.md)).

**Task 2: PS3.15 Profile Compiler & Composable Jurisdictions**:

- Added
  [`dicom_deid_profile()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid_profile.md)
  and
  [`dicom_list_jurisdictions()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_list_jurisdictions.md)
  compiling declarative YAML profiles (`ps3.15-basic.yml` + 10 PS3.15
  options) with 8 composable statutory jurisdiction overlays
  (`hipaa_safe_harbor`, `hipaa_limited_dataset`, `gdpr_eu`,
  `sg_pdpa_hib`, `my_pdpa_2024`, `au_privacy_act`, `uk_gdpr`,
  `ca_pipeda`) and strictest-wins monotonic action lattice
  (`D > Z > X > K`).

**Task 3: Single-Pass Recursive C++17 Mutator**:

- Implemented `cpp_deid_file()` in `src/rcpp_deid.cpp` executing
  in-memory DICOM mutation across dataset tags and arbitrary nested
  Sequence of Items (`VR=SQ`) trees with Howard Hinnant date shifting,
  safe-private retention, orphan creator pruning, and W3C PROV audit
  logging.

**Task 4: Cohort
[`dicom_deid()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid.md)
& Encrypted Crosswalk**:

- Added
  [`dicom_deid()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid.md)
  supporting file, directory, and vector inputs with progress reporting
  and optional `mirai` parallelism.
- Implemented ChaCha20-Poly1305 AEAD-encrypted crosswalk files
  (`dicomtk_crosswalk.enc`) decryptable via
  [`dicom_crosswalk_read()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_crosswalk_read.md)
  using the original key provider.

**Task 5: Burned-In Pixel PHI & C++17 Telea Inpainting**:

- Added
  [`dicom_detect_burned_phi()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_detect_burned_phi.md)
  and
  [`dicom_clean_pixels()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_clean_pixels.md)
  for identifying and blacking out burned-in text in secondary captures
  and ultrasound overlays.
- Implemented C++17 Fast Marching Method Telea inpainting
  (`cpp_telea_inpaint()`) with aspect-ratio bounding-box guardrails and
  optional OCR verification (`tesseract`).

**Task 6: 3D Head CT/MR Defacing & WSI Safeguards**:

- Added
  [`dicom_deface()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deface.md)
  performing analytical cutting-plane facial stripping on 3D volumetric
  CT and MR series in LPS/RAS space.

### Phase 2 (`v0.4.0` Segmentation, RTSTRUCT/RTDOSE, Quantitative SR & Deep Learning Prep) — Completed

**Task 1: C++17 Scanline Rasterizer & Contour Tracer**:
[`rasterize_polygon_2d()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/rasterize_polygon_2d.md),
[`rasterize_polygons_2d()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/rasterize_polygons_2d.md),
[`trace_contours_2d()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/trace_contours_2d.md)
(`src/rcpp_rasterize.cpp`, `R/rasterize.R`).

**Task 2: `dicom_seg` S3 Class & DICOM SEG Writer**:
[`dicom_seg()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md),
[`write_dicom_seg()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_dicom_seg.md),
[`as_labelmap()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_labelmap.md)
(`src/rcpp_seg.cpp`, `R/seg.R`).

**Task 3: RTSTRUCT \<-\> `dicom_seg` Conversion**:
[`rtstruct_to_seg()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/rtstruct_to_seg.md),
[`seg_to_rtstruct()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/seg_to_rtstruct.md)
(`R/rt-struct.R`).

**Task 4: RTDOSE & DVH Engine**:
[`dicom_dvh()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_dvh.md)
(`R/rt-dose.R`).

**Task 5: Quantitative SR (TID 1500) & GSPS**:
[`dicom_sr_tid1500()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_sr_tid1500.md),
[`read_sr_tid1500()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_sr_tid1500.md),
[`write_dicom_gsps()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_dicom_gsps.md),
[`read_dicom_gsps()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_gsps.md)
(`src/rcpp_sr_rt.cpp`, `R/sr-tid1500.R`, `R/gsps.R`).

**Task 6: Burned-In Visual Annotations**:
[`dicom_burn_annotations()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_burn_annotations.md),
[`burned_annot()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)
(`R/export-burned.R`).

**Task 7: Deep Learning Prep**:
[`volume_resample()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/volume_resample.md),
[`volume_window()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/volume_window.md),
[`dicom_patient_splits()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_patient_splits.md)
(`src/rcpp_resample.cpp`, `R/dl-prep.R`).

**Task 8: ML & FAIR Dataset Exporters**:
[`export_nnunet()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/export_nnunet.md),
[`export_monai()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/export_monai.md),
[`export_rocrate()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/export_rocrate.md),
[`export_croissant()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/export_croissant.md)
(`R/export-dataset.R`).

**Task 9a: Automated Image QC & Release Prep**:
[`dicom_image_qc()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_image_qc.md)
(`R/qc.R`), `vignettes/segmentation_and_rt.Rmd`, `DESCRIPTION`
(`0.4.0`), `NEWS.md`, `_pkgdown.yml`.

- Added Whole Slide Imaging (WSI) label/macro frame stripping to prevent
  specimen identifier leakage.

**Task 7: Residual-PHI Verifier & Risk Scorer**:

- Added
  [`dicom_deid_verify()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid_verify.md)
  scanning processed datasets for 18 statutory PHI canary categories.
- Added HMAC-SHA256 signed compliance certificates
  ([`dicom_verify_attestation()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_verify_attestation.md)).
- Added
  [`dicom_deid_risk()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid_risk.md)
  computing cohort re-identification risk metrics including equivalence
  class distribution, $`k`$-anonymity, $`l`$-diversity, and prosecutor
  risk.

**Task 8: MIDI-B Synthetic Benchmark & Published Scorecard**:

- Extended
  [`dicom_synthesize()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md)
  with `phi_profile = c("basic", "midi_b")` planting 18 HIPAA, PS3.15,
  and international canaries across structured tags, nested sequences,
  and free text.
- Added `tools/run_midib_benchmark.R` producing validated audit
  scorecard (`inst/extdata/midib_scorecard.json`) demonstrating 100.0%
  sensitivity, 100.0% specificity, zero residual PHI leaks, and exact
  longitudinal UID isomorphism.

**Task 9: `v0.3.0` Release Documentation, Vignette & Six-Sigma Check**:

- Updated `DESCRIPTION` (0.3.0), `NEWS.md`, `_pkgdown.yml`,
  `vignettes/anonymization.Rmd`, and verified full test suite and CRAN
  checks.

### Next Phase Roadmap (validated 2026-10-24)

- Design: `dev/plans/2026-10-24-roadmap-v0.2-v1.0-design.md` (plans live
  in `dev/` because `docs/` is pkgdown output).
- Packages: `dicomtk` (CRAN core) + `dicomtk.ai` + `dicomtk.server` +
  `dicomtk.fl`; test lab in separate repo `dicomtk-lab` (docker-compose
  profiles: core, ai, ehr, ohdsi, ttp, fl).
- Phases: P0 geometry/`dicom_volume` -\> P1 de-id engine -\> P2
  SEG/RT/data prep -\> P3 AI -\> P4 interop -\> P5 server -\> P6
  SMART/EHR -\> P7 WSI/radiomics -\> P8 federated.
- Key custody: local \| broker (server default) \| ttp.
  [`read_dicom_series()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_series.md)
  kept as soft-deprecated wrapper over
  [`read_dicom_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md).
