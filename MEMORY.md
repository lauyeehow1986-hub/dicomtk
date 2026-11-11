# MEMORY.md — `dicomtk` Project Memory & State

## Project Identity & Decisions
- **Package Name**: `dicomtk` (replaces legacy `dcmtk` R wrapper from `lauyeehow1986-hub/dcmtk_r` / `muschellij2/dcmtk`).
- **Workspace Path**: `C:\Users\lauye\.gemini\antigravity\scratch\dicomtk`
- **Reference Clones**:
  - Legacy R wrapper: `C:\Users\lauye\.gemini\antigravity\scratch\dcmtk_r_ref` (v0.8.0)
  - Upstream DCMTK C++ repo: `C:\Users\lauye\.gemini\antigravity\scratch\dcmtk_upstream` (v3.7.1)
- **User Requirements**:
  1. Full sync with official DCMTK functionalities across all modules (`dcmdata`, `dcmimgle`, `dcmimage`, `dcmjpeg`, `dcmjpls`, `dcmnet`, `dcmsr`, `dcmiod`, `dcmfg`, `dcmrt`, `dcmseg`, `dcmpmap`, `dcmtract`, `dcmect`, `dcmpstat`, `dcmqrdb`, `dcmwlm`, `dcmsign`, `dcmtls`).
  2. Bundle DCMTK C++ headers (`inst/include/dcmtk/`), 5,354-entry 2026d data dictionary (`src/dcmtk_dict_builtin.h` + `data/dicom_tags.rda` + `inst/extdata/dicom.dic`), and native C++17 / Rcpp engine in the R package so users do not need external DCMTK installation.
  3. Direct Rcpp C++ API bindings (replacing fragile CLI `system()` + stdout regex parsing), while retaining backward-compatible wrappers for existing `dcmtk` R functions.
  4. Tidyverse-compliant API (`tibble` outputs, `snake_case`, pipe-friendly `|>`).
  5. Complete DICOM visualization suite: `ggplot2` (`plot_dicom()`, `ggdicom()`), interactive `Shiny` viewer (`dicom_viewer()`), and 3D volume rendering via MPR/MIP/`rgl` (`render_volume()`).
  6. LLM integration: Local LLMs via **Ollama** and cloud/subscription **OpenAI-compatible APIs** (OpenAI, Anthropic Claude, custom endpoints) for metadata summarization, vision-based image description, structured radiology report generation, and natural-language DICOM tag lookup/querying.
  7. Target all 3 CRAN platforms (Windows, macOS, Linux) and design for CRAN compliance.

---

## Implementation Progress Log

### Completed (All Phases 1–6)
- [x] Cloned `lauyeehow1986-hub/dcmtk_r` (`dcmtk_r_ref`) and `DCMTK/dcmtk` (`dcmtk_upstream`).
- [x] Audited all 21 R files in `dcmtk_r_ref` and mapped DCMTK 3.7.1 C++ headers.
- [x] Created `dicomtk` directory structure (`R/`, `src/`, `inst/`, `tests/`, `vignettes/`, `tools/`, `.github/workflows/`).
- [x] Created `DESCRIPTION`, `NAMESPACE`, `.Rbuildignore`, `NEWS.md`, `_pkgdown.yml`, `CLAUDE.md`, and `MEMORY.md`.
- [x] Synchronized all 5,354 DICOM tags from DCMTK 3.7.1 (`PS 3.6-2026d`) via `tools/bundle_dcmtk.R` into `data/dicom_tags.rda`, `inst/extdata/dicom.dic`, and `src/dcmtk_dict_builtin.h`.
- [x] Bundled all 23 DCMTK 3.7.1 module C++ header trees into `inst/include/dcmtk/`.
- [x] Implemented `configure`, `configure.win`, `cleanup`, `src/Makevars.in`, and `src/Makevars.win`.
- [x] Implemented C++17 / Rcpp bindings (`src/rcpp_dcmtk.h`, `src/rcpp_init.cpp`, `src/rcpp_read.cpp`, `src/rcpp_write.cpp`, `src/rcpp_image.cpp`, `src/rcpp_convert.cpp`, `src/rcpp_network.cpp`, `src/rcpp_sr_rt.cpp`) with zero compiler warnings.
- [x] Implemented all R modules covering every DCMTK subsystem (`read.R`, `write.R`, `tags.R`, `anonymize.R`, `convert.R`, `compress.R`, `plot.R`, `viewer.R`, `volume.R`, `network.R`, `sr.R`, `rt_seg.R`, `llm-providers.R`, `llm-prompts.R`, `llm.R`, `legacy.R`, `utils.R`, `zzz.R`).
- [x] Created interactive 4-tab Shiny DICOM & AI Radiology workstation (`inst/shiny/viewer/app.R`).
- [x] Created all 5 vignettes (`getting-started.Rmd`, `image-visualization.Rmd`, `pacs-networking.Rmd`, `llm-integration.Rmd`, `anonymization.Rmd`) and package hex logo (`man/figures/logo.png`).
- [x] 95 unit tests (`testthat`), including a live DIMSE C-ECHO SCP/SCU TCP loopback test (runs only when `NOT_CRAN=true`).
  - Note: commit `75e2749` (the version submitted to CRAN) failed on `macos-latest` with `ignoring SIGPIPE signal` in `cpp_dicom_echo_loopback_test()` because the client closed the socket before draining `C-ECHO-RSP`/`A-RELEASE-RP`. Fixed in `94df4b2` (drain PDUs + `SO_NOSIGPIPE`/`MSG_NOSIGNAL`) and the test is now skipped on CRAN.
- [x] Verified live local Ollama integration (`http://localhost:11434`) with `llama3.2:3b`, `llava:7b`, and `amsaravi/medgemma-4b-it:q8`.
- [x] Initialized Git repository on `main` and pushed to `origin` (`https://github.com/lauyeehow1986-hub/dicomtk.git`).
- [x] Built and deployed `pkgdown` documentation site to GitHub Pages (`https://lauyeehow1986-hub.github.io/dicomtk/`).
- [x] Published GitHub Release `v0.1.0` (`https://github.com/lauyeehow1986-hub/dicomtk/releases/tag/v0.1.0`) with source (`dicomtk_0.1.0.tar.gz`) and Windows binary (`dicomtk_0.1.0.zip`) assets.
- [x] Configured automated weekly & on-demand upstream DCMTK synchronization (`.github/workflows/sync-upstream-dcmtk.yaml` + `dicom_sync_upstream()`).
- [x] Published R-Universe package registry (`https://github.com/lauyeehow1986-hub/lauyeehow1986-hub.r-universe.dev`) for `install.packages("dicomtk", repos = "https://lauyeehow1986-hub.r-universe.dev")`.



### Phase 0 (`v0.2.0` Foundations) — Completed
- [x] **Task 1: C++ Hierarchical Sequences & Nested `SQ` Writer**:
  - Implemented recursive sequence indexing and explicit-length nested `SQ` serialization via `cpp_write_dicom_multiframe()`, `cpp_modify_dicom()`, and `cpp_dcm_transcode_rle()` in `src/rcpp_read.cpp`, `src/rcpp_write.cpp`, and `src/rcpp_convert.cpp`.
- [x] **Task 2: Synthetic Phantom Generator (`dicom_synthesize()`)**:
  - Parametric synthesis of CT, MR, and PET series in `R/synthesize.R` with known analytical ground-truth LPS/RAS affines, voxel arrays, non-orthogonal gantry tilt, and PHI injection/scrubbing.
- [x] **Task 3: `dicom_volume` S3 Class & Spatial Transforms**:
  - Implemented `new_dicom_volume()`, `print.dicom_volume()`, `dim.dicom_volume()`, `[.dicom_volume()` (with affine translation/rescaling), `as.array.dicom_volume()`, `dicom_orientation()`, `dicom_to_lps()`, and `dicom_to_ras()` in `R/dicom-volume.R`.
- [x] **Task 4: Geometry-Aware `read_dicom_volume()`**:
  - Implemented `read_dicom_volume()` in `R/volume-read.R` with enhanced multi-frame support (`SharedFunctionalGroupsSequence` / `PerFrameFunctionalGroupsSequence`), series splitting, and transparent delegation for `read_dicom_series()`.
- [x] **Task 5: Modality Quantitative Transforms**:
  - Implemented `dicom_pet_suv()` (bw, lbm James/Janmahasatian, bsa with decay correction), `dicom_apply_voi_lut()` (linear and sigmoid windowing), and `dicom_mr_rescale()` (Philips private attributes 2005,100D/100E) in `R/modality-transforms.R`.
- [x] **Task 6: `write_nifti()` with `dcm2niix` Parity**:
  - Implemented `write_nifti()` in `R/nifti.R` with exact RAS `sform`, polar SVD `qform` decomposition, BIDS JSON sidecar, zero-dependency pure R binary writer, `RNifti` backend fallback, gantry-tilt notification, and `dicom_to_nifti()` delegation.
- [x] **Task 7: CI Fixture Downloader & Parity Validation**:
  - Implemented `tools/download_fixtures.R` syncing 11 scanner fixtures, `tests/testthat/helper-fixtures.R` Chris Rorden oracle, and `tests/testthat/test-p0-dcm2niix-parity.R`.
- [x] **Task 8: `dicomtk-lab` Container Testbed**:
  - Standalone multi-profile Docker Compose environment at `C:/Users/lauye/.gemini/antigravity/scratch/dicomtk-lab` with `core`, `enterprise`, `ehr`, `ohdsi`, `ttp`, and `fl` profiles, and `tests/testthat/test-p0-lab-core.R` smoke test.
- [x] **Task 9: `v0.2.0` Release Documentation & Vignettes**:
  - Updated `DESCRIPTION` (0.2.0), `NEWS.md`, `_pkgdown.yml`, `vignettes/volume-geometry.Rmd`, and verified full test suite.

### Phase 1 (`v0.3.0` Research-Grade De-Identification Engine) — Completed
- [x] **Task 1: C++17 RFC Cryptography & Pluggable Key Provider**:
  - Implemented standalone C++17 implementations of RFC 6234 SHA-256, RFC 4231 HMAC-SHA256, RFC 2898 PBKDF2-HMAC-SHA256, RFC 5869 HKDF-SHA256, and RFC 8439 ChaCha20-Poly1305 AEAD (`src/rcpp_crypto.h`, `src/rcpp_crypto.cpp`).
  - Added `dicom_key_provider()` S3 class supporting `local`, `broker`, and `ttp` modes, credential redaction, deterministic `2.25.<128-bit>` UID pseudonymization (`deid_map_uid()`), and per-patient pseudo-random date shifting (`derive_patient_shift_days()`, `deid_patient_shift()`).
- [x] **Task 2: PS3.15 Profile Compiler & Composable Jurisdictions**:
  - Added `dicom_deid_profile()` and `dicom_list_jurisdictions()` compiling declarative YAML profiles (`ps3.15-basic.yml` + 10 PS3.15 options) with 8 composable statutory jurisdiction overlays (`hipaa_safe_harbor`, `hipaa_limited_dataset`, `gdpr_eu`, `sg_pdpa_hib`, `my_pdpa_2024`, `au_privacy_act`, `uk_gdpr`, `ca_pipeda`) and strictest-wins monotonic action lattice (`D > Z > X > K`).
- [x] **Task 3: Single-Pass Recursive C++17 Mutator**:
  - Implemented `cpp_deid_file()` in `src/rcpp_deid.cpp` executing in-memory DICOM mutation across dataset tags and arbitrary nested Sequence of Items (`VR=SQ`) trees with Howard Hinnant date shifting, safe-private retention, orphan creator pruning, and W3C PROV audit logging.
- [x] **Task 4: Cohort `dicom_deid()` & Encrypted Crosswalk**:
  - Added `dicom_deid()` supporting file, directory, and vector inputs with progress reporting and optional `mirai` parallelism.
  - Implemented ChaCha20-Poly1305 AEAD-encrypted crosswalk files (`dicomtk_crosswalk.enc`) decryptable via `dicom_crosswalk_read()` using the original key provider.
- [x] **Task 5: Burned-In Pixel PHI & C++17 Telea Inpainting**:
  - Added `dicom_detect_burned_phi()` and `dicom_clean_pixels()` for identifying and blacking out burned-in text in secondary captures and ultrasound overlays.
  - Implemented C++17 Fast Marching Method Telea inpainting (`cpp_telea_inpaint()`) with aspect-ratio bounding-box guardrails and optional OCR verification (`tesseract`).
- [x] **Task 6: 3D Head CT/MR Defacing & WSI Safeguards**:
  - Added `dicom_deface()` performing analytical cutting-plane facial stripping on 3D volumetric CT and MR series in LPS/RAS space.
  - Added Whole Slide Imaging (WSI) label/macro frame stripping to prevent specimen identifier leakage.
- [x] **Task 7: Residual-PHI Verifier & Risk Scorer**:
  - Added `dicom_deid_verify()` scanning processed datasets for 18 statutory PHI canary categories.
  - Added HMAC-SHA256 signed compliance certificates (`dicom_verify_attestation()`).
  - Added `dicom_deid_risk()` computing cohort re-identification risk metrics including equivalence class distribution, $k$-anonymity, $l$-diversity, and prosecutor risk.
- [x] **Task 8: MIDI-B Synthetic Benchmark & Published Scorecard**:
  - Extended `dicom_synthesize()` with `phi_profile = c("basic", "midi_b")` planting 18 HIPAA, PS3.15, and international canaries across structured tags, nested sequences, and free text.
  - Added `tools/run_midib_benchmark.R` producing validated audit scorecard (`inst/extdata/midib_scorecard.json`) demonstrating 100.0% sensitivity, 100.0% specificity, zero residual PHI leaks, and exact longitudinal UID isomorphism.
- [x] **Task 9: `v0.3.0` Release Documentation, Vignette & Six-Sigma Check**:
  - Updated `DESCRIPTION` (0.3.0), `NEWS.md`, `_pkgdown.yml`, `vignettes/anonymization.Rmd`, and verified full test suite and CRAN checks.

### Next Phase Roadmap (validated 2026-10-24)
- Design: `dev/plans/2026-10-24-roadmap-v0.2-v1.0-design.md` (plans live in `dev/` because `docs/` is pkgdown output).
- Packages: `dicomtk` (CRAN core) + `dicomtk.ai` + `dicomtk.server` + `dicomtk.fl`; test lab in separate repo `dicomtk-lab` (docker-compose profiles: core, ai, ehr, ohdsi, ttp, fl).
- Phases: P0 geometry/`dicom_volume` -> P1 de-id engine -> P2 SEG/RT/data prep -> P3 AI -> P4 interop -> P5 server -> P6 SMART/EHR -> P7 WSI/radiomics -> P8 federated.
- Key custody: local | broker (server default) | ttp. `read_dicom_series()` kept as soft-deprecated wrapper over `read_dicom_volume()`.

