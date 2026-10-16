# Changelog

## dicomtk 0.1.0

- Initial release of `dicomtk`, a full rebuild of the `dcmtk` R wrapper
  synchronized with **OFFIS DCMTK 3.7.1 (`PS 3.6-2026d`)**.
- Bundled the complete 5,354-tag DCMTK 3.7.1 data dictionary, all 23
  module header trees (`inst/include/dcmtk/`), and a self-contained
  C++17 / `Rcpp` engine requiring no external installation.
- Added tidyverse-compliant DICOM I/O and tag functions
  ([`read_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom.md),
  [`read_dicom_header()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_header.md),
  [`read_dicom_pixels()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_pixels.md),
  [`read_dicom_series()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_series.md),
  [`write_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_dicom.md),
  [`dicom_tags()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tags.md),
  [`dicom_tag_value()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tag_value.md),
  [`dicom_modify()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_modify.md),
  [`dicom_tag_lookup()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tag_lookup.md)).
- Added HIPAA Safe Harbor and DICOM PS3.15 de-identification
  ([`dicom_anonymize()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_anonymize.md))
  with date shifting, private tag removal, and UID regeneration.
- Added `ggplot2` visualization
  ([`plot_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/plot_dicom.md),
  [`ggdicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/ggdicom.md),
  [`dicom_window()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_window.md)
  with clinical CT presets), interactive `Shiny` viewer
  ([`dicom_viewer()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_viewer.md)),
  and 3D volume rendering
  ([`render_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/render_volume.md)
  with MPR, MIP, and `rgl`).
- Added PACS networking
  ([`dicom_connect()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_connect.md),
  [`dicom_echo()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_echo.md),
  [`dicom_find()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_find.md),
  [`dicom_get()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_get.md),
  [`dicom_send()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_send.md),
  [`dicom_receive()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_receive.md),
  [`dicom_qrdb_index()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_qrdb_index.md),
  [`dicom_worklist()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_worklist.md),
  [`dicom_tls_config()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tls_config.md)).
- Added Structured Reporting and specialized IOD interfaces
  ([`read_dicom_sr()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_sr.md),
  [`create_dicom_sr()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/create_dicom_sr.md),
  [`read_dicom_rt()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_rt.md),
  [`read_dicom_seg()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_seg.md),
  [`read_dicom_pmap()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_pmap.md),
  [`read_dicom_tract()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_tract.md),
  [`read_dicom_pstate()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_pstate.md),
  [`read_dicom_ect()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_ect.md),
  [`dicom_verify_signature()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_verify_signature.md)).
- Added unified LLM integration
  ([`dicom_llm()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_llm.md),
  [`dicom_summarize()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_summarize.md),
  [`dicom_describe_image()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_describe_image.md),
  [`dicom_report()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_report.md),
  [`dicom_ask()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_ask.md))
  supporting local **Ollama** and **OpenAI-compatible** APIs (OpenAI,
  Anthropic Claude, Azure, vLLM, LM Studio).
- Maintained full backward compatibility with legacy `dcmtk` functions
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
