# CLAUDE.md — dicomtk Development Guide

## Project Overview

`dicomtk` is a comprehensive, CRAN-ready R package wrapping the **OFFIS
DICOM Toolkit (DCMTK 3.7.1)** via native **Rcpp** bindings, designed
with: 1. **Self-contained C++ bundling**: Bundles trimmed DCMTK source
inside `src/dcmtk/` compiled during `R CMD INSTALL` (with
fallback/hybrid support for system DCMTK or CMake builds) and built-in
DICOM dictionary (`DCM_DICT_DEFAULT_USE_BUILTIN`). 2. **Tidyverse
compliance**: Returns `tibble` objects (`tbl_df`), uses `snake_case`
function names, supports pipe-friendly (`|>`) workflows, and integrates
with `dplyr`/`tidyr`. 3. **Comprehensive DCMTK coverage**: - **Core
(`dcmdata`)**: Header parsing
([`read_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom.md),
[`read_dicom_header()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_header.md),
[`dicom_tags()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tags.md)),
tag modification
([`dicom_modify()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_modify.md)),
de-identification/anonymization
([`dicom_anonymize()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_anonymize.md)),
XML/JSON/PDF conversion
([`dcm2xml()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dcm2xml.md),
[`dcm2json()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dcm2json.md),
[`dcm2pdf()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dcm2pdf.md)). -
**Image Processing & Codecs (`dcmimgle`, `dcmimage`, `dcmjpeg`,
`dcmjpls`)**: Pixel extraction
([`read_dicom_pixels()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_pixels.md),
[`read_dicom_series()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_series.md)),
VOI LUT & window/level presets
([`dicom_window()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_window.md)),
RLE/JPEG/JPEG-LS compression and decompression
([`dicom_compress()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_compress.md),
[`dicom_decompress()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_decompress.md)),
PNG/NIfTI export
([`dicom_to_png()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_to_png.md),
[`dicom_to_nifti()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_to_nifti.md)). -
**Visualization**: Static `ggplot2` plotting
([`plot_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/plot_dicom.md),
[`ggdicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/ggdicom.md)),
interactive `Shiny` multi-slice viewer
([`dicom_viewer()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_viewer.md)),
and 3D volume rendering via `rgl`
([`render_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/render_volume.md)). -
**Networking (`dcmnet`, `dcmqrdb`, `dcmwlm`)**: PACS connectivity
([`dicom_connect()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_connect.md),
[`dicom_echo()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_echo.md),
[`dicom_find()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_find.md),
[`dicom_get()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_get.md),
[`dicom_send()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_send.md),
[`dicom_receive()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_receive.md)). -
**Structured Reporting & Advanced IODs (`dcmsr`, `dcmrt`, `dcmseg`,
`dcmpmap`, `dcmtract`, `dcmect`, `dcmpstat`, `dcmsign`, `dcmtls`)**:
Reading and creating DICOM SR, RT Structure Sets/Dose/Plan,
Segmentations, Parametric Maps, and Tractography. 4. **LLM
Integration**: Unified AI assistant interface
([`dicom_llm()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_llm.md),
[`dicom_summarize()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_summarize.md),
[`dicom_describe_image()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_describe_image.md),
[`dicom_report()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_report.md),
[`dicom_ask()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_ask.md),
[`dicom_tag_lookup()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tag_lookup.md))
supporting local **Ollama** models and **OpenAI-compatible APIs**
(OpenAI, Anthropic Claude, Azure, local vLLM/LM Studio) with HIPAA-aware
automatic de-identification before cloud transmission.

------------------------------------------------------------------------

## Repository Structure

    dicomtk/
    ├── CLAUDE.md                 # AI assistant & developer guide (this file)
    ├── MEMORY.md                 # Persistent project memory, architectural state & progress log
    ├── DESCRIPTION               # Package metadata & dependencies
    ├── NAMESPACE                 # Exported functions & imports
    ├── LICENSE                   # License terms
    ├── configure / configure.win # Build configuration scripts for DCMTK + Rcpp
    ├── R/
    │   ├── dicomtk-package.R     # Package-level docs & roxygen imports
    │   ├── zzz.R                 # .onLoad / .onAttach codec registration & dict init
    │   ├── utils.R               # Internal assertions, path helpers, S3 constructors
    │   ├── read.R                # read_dicom(), read_dicom_header(), read_dicom_pixels(), read_dicom_series()
    │   ├── write.R               # write_dicom()
    │   ├── tags.R                # dicom_tags(), dicom_modify(), dicom_tag_value(), dicom_tag_lookup()
    │   ├── anonymize.R           # dicom_anonymize(), HIPAA/PS3.15 de-identification profiles, date shifting
    │   ├── convert.R             # dicom_to_png(), dicom_to_nifti(), dcm2xml(), dcm2json(), dcm2pdf()
    │   ├── compress.R            # dicom_compress(), dicom_decompress(), legacy aliases (dcmdjpeg, dcmdrle, dcmcrle)
    │   ├── plot.R                # plot_dicom(), ggdicom(), dicom_window(), CT window presets
    │   ├── viewer.R              # dicom_viewer() Shiny application launcher
    │   ├── volume.R              # render_volume() 3D rgl volume/isosurface rendering
    │   ├── network.R             # dicom_connect(), dicom_echo(), dicom_find(), dicom_get(), dicom_send(), dicom_receive()
    │   ├── sr.R                  # read_dicom_sr(), create_dicom_sr()
    │   ├── rt_seg.R              # read_dicom_rt(), read_dicom_seg(), read_dicom_pmap(), read_dicom_tract()
    │   ├── llm.R                 # dicom_llm(), dicom_summarize(), dicom_describe_image(), dicom_report(), dicom_ask()
    │   ├── llm-providers.R       # Ollama, OpenAI, and Anthropic API request/response handlers via httr2
    │   ├── llm-prompts.R         # System prompts & structured output schemas for radiology AI tasks
    │   └── legacy.R              # Backward-compatible wrappers for muschellij2/dcmtk functions
    ├── src/
    │   ├── Makevars.in           # Unix Makevars template
    │   ├── Makevars.win          # Windows Makevars
    │   ├── rcpp_dcmtk.h          # Shared C++ declarations & DCMTK header includes
    │   ├── rcpp_init.cpp         # Codec registration (JPEG, JPEG-LS, RLE) & dictionary status
    │   ├── rcpp_read.cpp         # DcmFileFormat / DcmDataset / DcmElement reader & tag parser
    │   ├── rcpp_write.cpp        # Tag modification, UID generation, anonymization, file saving
    │   ├── rcpp_image.cpp        # DicomImage pixel extraction, VOI LUT windowing, RGB/monochrome arrays
    │   ├── rcpp_convert.cpp      # XML, JSON, PDF extraction, transfer syntax transcoding
    │   ├── rcpp_network.cpp      # C-ECHO, C-FIND, C-STORE, C-GET/C-MOVE SCU bindings
    │   ├── rcpp_sr_rt.cpp        # Structured Reporting (DSRDocument) & RT/SEG helpers
    │   └── dcmtk/                # Bundled trimmed DCMTK 3.7.1 source & CMake build glue
    ├── inst/
    │   ├── extdata/              # Sample DICOM files for tests and examples
    │   └── shiny/viewer/         # Interactive Shiny DICOM viewer app
    ├── tests/
    │   ├── testthat.R
    │   └── testthat/             # Unit tests covering I/O, tags, visualization, anonymization, LLM mocks
    ├── vignettes/                # Package vignettes
    └── tools/
        └── bundle_dcmtk.R        # Script to sync & trim upstream DCMTK source for CRAN size limits

------------------------------------------------------------------------

## Coding Standards & Conventions

1.  **Tidyverse Style**:
    - All exported functions use `snake_case`.
    - Tabular return values must be
      [`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html).
    - Functions operating on DICOM objects or file paths should take the
      primary data/path as the first argument so they compose naturally
      with `|>`.
    - Use
      [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html),
      [`cli::cli_warn()`](https://cli.r-lib.org/reference/cli_abort.html),
      and
      [`cli::cli_inform()`](https://cli.r-lib.org/reference/cli_abort.html)
      (or
      [`rlang::abort()`](https://rlang.r-lib.org/reference/abort.html))
      for informative error messages.
2.  **C++ / Rcpp Guidelines**:
    - Never call `std::exit()`, `abort()`, or write directly to
      `std::cout`/`std::cerr` in C++ code (CRAN policy). Route all
      errors through `Rcpp::stop()` and warnings through
      `Rcpp::warning()`.
    - Always check `OFCondition::bad()` after DCMTK calls and report
      `cond.text()`.
    - Wrap heap-allocated DCMTK objects (`DicomImage`, `DcmFileFormat`,
      etc.) in `std::unique_ptr` so `Rcpp::checkUserInterrupt()` or
      exceptions never leak memory.
    - Always register codecs (`DJDecoderRegistration`,
      `DJEncoderRegistration`, `DJLSDecoderRegistration`,
      `DJLSEncoderRegistration`, `DcmRLEDecoderRegistration`,
      `DcmRLEEncoderRegistration`) at package load time and clean them
      up on unload.
3.  **LLM Privacy & Safety**:
    - When sending DICOM metadata or images to non-local LLM providers
      (`provider != "ollama"` and non-localhost URLs), automatically
      strip PHI/HIPAA tags by default (`anonymize = TRUE`) and warn the
      user if `anonymize = FALSE`.
4.  **Backward Compatibility**:
    - Preserve legacy functions from `muschellij2/dcmtk`
      ([`dcmdump()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
      [`dcmhd()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
      [`wide_hdr()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
      [`burned_annot()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
      [`dcm_anon()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
      [`dcm_subtract_date()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
      [`dcmj2pnm()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
      [`dcmdjpeg()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
      [`dcmdrle()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
      [`dcmcrle()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
      [`dcmodify()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md))
      in `R/legacy.R`, implemented on top of the fast native Rcpp
      engine.

------------------------------------------------------------------------

## Common Commands

``` bash
# Generate RcppExports and roxygen documentation
Rscript -e "Rcpp::compileAttributes(); roxygen2::roxygenise()"

# Bundle/sync trimmed DCMTK sources from upstream clone
Rscript tools/bundle_dcmtk.R

# Build and install package locally
R CMD build .
R CMD INSTALL dicomtk_0.1.0.tar.gz

# Run test suite
Rscript -e "testthat::test_local()"

# Run CRAN check
R CMD check dicomtk_0.1.0.tar.gz --as-cran
```
