# dicomtk 0.1.0

* Initial release of `dicomtk`, a full rebuild of the `dcmtk` R wrapper synchronized with **OFFIS DCMTK 3.7.1 (`PS 3.6-2026d`)**.
* Bundled the complete 5,354-tag DCMTK 3.7.1 data dictionary, all 23 module header trees (`inst/include/dcmtk/`), and a self-contained C++17 / `Rcpp` engine requiring no external installation.
* Added tidyverse-compliant DICOM I/O and tag functions (`read_dicom()`, `read_dicom_header()`, `read_dicom_pixels()`, `read_dicom_series()`, `write_dicom()`, `dicom_tags()`, `dicom_tag_value()`, `dicom_modify()`, `dicom_tag_lookup()`).
* Added HIPAA Safe Harbor and DICOM PS3.15 de-identification (`dicom_anonymize()`) with date shifting, private tag removal, and UID regeneration.
* Added `ggplot2` visualization (`plot_dicom()`, `ggdicom()`, `dicom_window()` with clinical CT presets), interactive `Shiny` viewer (`dicom_viewer()`), and 3D volume rendering (`render_volume()` with MPR, MIP, and `rgl`).
* Added PACS networking (`dicom_connect()`, `dicom_echo()`, `dicom_find()`, `dicom_get()`, `dicom_send()`, `dicom_receive()`, `dicom_qrdb_index()`, `dicom_worklist()`, `dicom_tls_config()`).
* Added Structured Reporting and specialized IOD interfaces (`read_dicom_sr()`, `create_dicom_sr()`, `read_dicom_rt()`, `read_dicom_seg()`, `read_dicom_pmap()`, `read_dicom_tract()`, `read_dicom_pstate()`, `read_dicom_ect()`, `dicom_verify_signature()`).
* Added unified LLM integration (`dicom_llm()`, `dicom_summarize()`, `dicom_describe_image()`, `dicom_report()`, `dicom_ask()`) supporting local **Ollama** and **OpenAI-compatible** APIs (OpenAI, Anthropic Claude, Azure, vLLM, LM Studio).
* Maintained full backward compatibility with legacy `dcmtk` functions (`dcmdump()`, `dcmhd()`, `wide_hdr()`, `burned_annot()`, `dcmodify()`, `dcm_anon()`, `dcm_subtract_date()`, `dcmj2pnm()`, `dcmdjpeg()`, `dcmdrle()`, `dcmcrle()`).
