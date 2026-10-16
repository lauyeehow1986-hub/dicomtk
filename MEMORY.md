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
- [x] Created interactive Shiny DICOM viewer (`inst/shiny/viewer/app.R`).
- [x] Created all 5 vignettes (`getting-started.Rmd`, `image-visualization.Rmd`, `pacs-networking.Rmd`, `llm-integration.Rmd`, `anonymization.Rmd`).
- [x] Passed all unit tests (`testthat`) and built/installed `dicomtk_0.1.0.tar.gz` cleanly.
