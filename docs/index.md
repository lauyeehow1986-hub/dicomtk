# dicomtk: Comprehensive ‘DICOM’ Toolkit for Medical Imaging in R

`dicomtk` is a complete, modern rebuild of the R `dcmtk` wrapper,
synchronized with **OFFIS DCMTK 3.7.1 (PS 3.6-2026d)** and powered by a
**bundled C++17 / Rcpp engine** requiring **zero external
installation**.

## Key Features

- **Zero External Dependencies**: Bundles the full 5,354-tag DCMTK 3.7.1
  data dictionary, headers (`inst/include/dcmtk/`), and native C++17
  DICOM engine directly inside the package.
- **Tidyverse Compliant**: All tabular functions
  ([`read_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom.md),
  [`dicom_tags()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tags.md),
  [`dicom_find()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_find.md),
  [`read_dicom_sr()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_sr.md),
  [`dicom_report()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_report.md))
  return `tibble` objects (`tbl_df`) and compose naturally with `|>` and
  `dplyr`/`tidyr`.
- **Full DCMTK Module Coverage**:
  - **Core (`dcmdata`)**:
    [`read_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom.md),
    [`read_dicom_header()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_header.md),
    [`write_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_dicom.md),
    [`dicom_tags()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tags.md),
    [`dicom_modify()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_modify.md),
    [`dicom_tag_value()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tag_value.md),
    [`dicom_tag_lookup()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tag_lookup.md),
    [`dicom_anonymize()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_anonymize.md),
    [`dcm2xml()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dcm2xml.md),
    [`dcm2json()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dcm2json.md),
    [`dcm2pdf()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dcm2pdf.md).
  - **Image Processing & Codecs (`dcmimgle`, `dcmimage`, `dcmjpeg`,
    `dcmjpls`)**:
    [`read_dicom_pixels()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_pixels.md),
    [`read_dicom_series()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_series.md),
    [`dicom_window()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_window.md),
    [`dicom_compress()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_compress.md),
    [`dicom_decompress()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_decompress.md),
    [`dicom_to_png()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_to_png.md),
    [`dicom_to_nifti()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_to_nifti.md).
  - **Visualization**:
    [`plot_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/plot_dicom.md)
    and
    [`ggdicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/ggdicom.md)
    (`ggplot2` with clinical CT/MR window presets),
    [`dicom_viewer()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_viewer.md)
    (interactive `Shiny` app), and
    [`render_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/render_volume.md)
    (3-plane MPR, MIP, and interactive `rgl` 3D rendering).
  - **PACS Networking (`dcmnet`, `dcmqrdb`, `dcmwlm`)**:
    [`dicom_connect()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_connect.md),
    [`dicom_echo()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_echo.md),
    [`dicom_find()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_find.md),
    [`dicom_get()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_get.md),
    [`dicom_send()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_send.md),
    [`dicom_receive()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_receive.md).
  - **Structured Reporting & Specialized IODs (`dcmsr`, `dcmrt`,
    `dcmseg`, `dcmpmap`, `dcmtract`, `dcmect`, `dcmsign`)**:
    [`read_dicom_sr()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_sr.md),
    [`create_dicom_sr()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/create_dicom_sr.md),
    [`read_dicom_rt()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_rt.md),
    [`read_dicom_seg()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_seg.md),
    [`read_dicom_pmap()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_pmap.md),
    [`read_dicom_ect()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_ect.md),
    [`dicom_verify_signature()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_verify_signature.md).
- **Local & Cloud LLM Integration**:
  - Native support for **local Ollama** (`http://localhost:11434`),
    **OpenAI** (`gpt-4o`, etc.), **Anthropic Claude**
    (`claude-sonnet-4-20250514`, etc.), and any **OpenAI-compatible
    endpoint** (vLLM, LM Studio, OpenRouter, Azure).
  - Automatic HIPAA Safe Harbor de-identification before sending
    metadata or images to remote APIs.
- **100% Backward Compatible**: Preserves legacy `dcmtk` functions
  ([`dcmdump()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
  [`dcmhd()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
  [`wide_hdr()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
  [`burned_annot()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
  [`dcmodify()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
  [`dcm_anon()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
  [`dcm_subtract_date()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
  [`dcmj2pnm()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
  [`dcmdjpeg()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
  [`dcmdrle()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md),
  [`dcmcrle()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)).

## Quick Start

[`library`](https://rdrr.io/r/base/library.html)`(`[`dicomtk`](https://github.com/lauyeehow1986-hub/dicomtk)`)`` `[`library`](https://rdrr.io/r/base/library.html)`(`[`dplyr`](https://dplyr.tidyverse.org)`)`` `` ``dcm_file`` ``<-`` `[`system.file`](https://rdrr.io/r/base/system.file.html)`(``"extdata"``, ``"example.dcm"``, package ``=`` ``"dicomtk"``)`` `` ``# 1. Read DICOM header as a tidy tibble`` `[`read_dicom`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom.md)`(``dcm_file``)`` ``|>`` `` `[`filter`](https://dplyr.tidyverse.org/reference/filter.html)`(``group`` ``==`` ``"0028"``)`` ``|>`` `` `[`select`](https://dplyr.tidyverse.org/reference/select.html)`(``tag``, ``vr``, ``keyword``, ``value``)`` `` ``# 2. Visualize with ggplot2 and clinical CT/MR window presets`` `[`plot_dicom`](https://lauyeehow1986-hub.github.io/dicomtk/reference/plot_dicom.md)`(``dcm_file``, window ``=`` ``"auto"``, palette ``=`` ``"gray"``)`` `` ``# 3. Launch interactive Shiny DICOM viewer`` ``if`` ``(`[`interactive`](https://rdrr.io/r/base/interactive.html)`(``)``)`` ``{`` `` `[`dicom_viewer`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_viewer.md)`(``dcm_file``)`` ``}`` `` ``# 4. Connect to Local Ollama or OpenAI / Claude for AI-Assisted Analysis`` ``llm`` ``<-`` `[`dicom_llm`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_llm.md)`(``"ollama"``, model ``=`` ``"llava:13b"``)`` `[`dicom_summarize`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_summarize.md)`(``dcm_file``, llm ``=`` ``llm``)`` `[`dicom_describe_image`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_describe_image.md)`(``dcm_file``, llm ``=`` ``llm``)`` `[`dicom_report`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_report.md)`(``dcm_file``, llm ``=`` ``llm``)`
