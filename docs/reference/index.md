# Package index

## Core DICOM I/O

Read and write DICOM headers, pixel matrices, and 3D multi-slice series.

- [`read_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom.md)
  : Read DICOM Metadata into a Tidy Tibble
- [`read_dicom_header()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_header.md)
  : Read DICOM Header Metadata
- [`read_dicom_pixels()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_pixels.md)
  : Extract Pixel Data from a DICOM File
- [`read_dicom_series()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_series.md)
  : Read a Multi-Slice DICOM Series into a 3D Volume
- [`write_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_dicom.md)
  : Write a Matrix, Array, or DICOM Series to a DICOM File
- [`is_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/is_dicom.md)
  : Check Whether File(s) Are Valid DICOM Files
- [`have_dcmtk()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/have_dcmtk.md)
  : Check DCMTK Backend Availability and Version
- [`dicom_info()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_info.md)
  : Inspect Bundled DCMTK Configuration and Version Info

## DICOM Tags & Dictionary

Inspect, modify, and query the 5,354-tag DCMTK 3.7.1 data dictionary.

- [`dicom_tags`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tags.md)
  [`dicom_tags()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tags.md)
  : Standard DICOM Data Dictionary (DCMTK 3.7.1 / PS 3.6-2026d)
- [`dicom_tag_value()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tag_value.md)
  : Quickly Extract Specific Tag Values from a DICOM File
- [`dicom_modify()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_modify.md)
  : Modify, Insert, or Delete DICOM Header Tags
- [`dicom_tag_lookup()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tag_lookup.md)
  : Search or Query the DICOM Data Dictionary
- [`date_tags`](https://lauyeehow1986-hub.github.io/dicomtk/reference/date_tags.md)
  : DICOM Date Tags
- [`datetime_tags`](https://lauyeehow1986-hub.github.io/dicomtk/reference/datetime_tags.md)
  : DICOM DateTime Tags
- [`removal_tags`](https://lauyeehow1986-hub.github.io/dicomtk/reference/removal_tags.md)
  : HIPAA / DICOM De-identification Removal Tags

## De-identification & Anonymization

HIPAA Safe Harbor and DICOM PS3.15 confidentiality profile
anonymization.

- [`dicom_anonymize()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_anonymize.md)
  : De-identify / Anonymize a DICOM File (HIPAA & DICOM PS3.15 Profile)

## Visualization (ggplot2, Shiny, and 3D Volume)

Clinical windowing, ggplot2 rendering, interactive Shiny viewer, and 3D
MPR/MIP/rgl.

- [`dicom_window()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_window.md)
  : Apply VOI LUT Window/Level Transformation to DICOM Pixels
- [`plot_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/plot_dicom.md)
  : Plot a DICOM Image Using ggplot2
- [`ggdicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/ggdicom.md)
  : Create a ggplot2 DICOM Image Object
- [`dicom_viewer()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_viewer.md)
  : Launch Interactive Shiny DICOM Viewer
- [`render_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/render_volume.md)
  : Render a 3D DICOM Volume (Orthogonal MPR, MIP, or Interactive rgl
  3D)

## Conversion & Compression

Convert between DICOM, PNG, NIfTI, XML, JSON, PDF, and RLE compression.

- [`dicom_to_png()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_to_png.md)
  : Export a DICOM Image Slice to PNG
- [`dicom_to_nifti()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_to_nifti.md)
  : Convert DICOM File(s) or Series to NIfTI-1 Format
- [`dcm2xml()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dcm2xml.md)
  : Convert a DICOM File to XML (Native DICOM Model PS3.19)
- [`dcm2json()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dcm2json.md)
  : Convert a DICOM File to JSON (DICOM JSON Model PS3.18)
- [`dcm2pdf()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dcm2pdf.md)
  : Extract Encapsulated PDF from a DICOM File
- [`dicom_compress()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_compress.md)
  : Compress a DICOM File (Lossless RLE)
- [`dicom_decompress()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_decompress.md)
  : Decompress an Encapsulated DICOM File

## PACS Networking & Worklists

DIMSE C-ECHO, C-FIND, C-GET, C-STORE, local index DB, worklists, and
TLS.

- [`dicom_connect()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_connect.md)
  : Create a DICOM PACS Network Connection Specification

- [`dicom_echo()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_echo.md)
  : Verify DICOM PACS Connectivity (C-ECHO SCU)

- [`dicom_find()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_find.md)
  : Query DICOM Studies, Series, or Instances (C-FIND / QIDO-RS / Local
  PACS)

- [`dicom_get()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_get.md)
  : Retrieve DICOM Files from PACS Connection (C-GET / C-MOVE / Local
  PACS)

- [`dicom_send()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_send.md)
  : Send DICOM Files to a PACS Peer (C-STORE SCU)

- [`dicom_receive()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_receive.md)
  : Configure a Local DICOM Storage Receiver Directory (C-STORE SCP)

- [`dicom_qrdb_index()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_qrdb_index.md)
  :

  Build or Query a Local DICOM Query/Retrieve Index Database (`dcmqrdb`)

- [`dicom_worklist()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_worklist.md)
  :

  Query or Create Modality Worklist Entries (`dcmwlm`)

- [`dicom_tls_config()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tls_config.md)
  :

  Configure DICOM TLS Transport Security Parameters (`dcmtls`)

## Structured Reports & Specialized IODs (RT, SEG, PMAP, Tractography)

Interfaces for dcmsr, dcmrt, dcmseg, dcmpmap, dcmtract, dcmect,
dcmpstat, and dcmsign.

- [`read_dicom_sr()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_sr.md)
  : Read a DICOM Structured Report (SR) or Advanced IOD

- [`create_dicom_sr()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/create_dicom_sr.md)
  : Create a DICOM Basic Text Structured Report (SR)

- [`read_dicom_rt()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_rt.md)
  :

  Read Radiation Therapy (RT) DICOM Objects (`dcmrt`)

- [`read_dicom_seg()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_seg.md)
  :

  Read DICOM Segmentation Objects (`dcmseg`)

- [`read_dicom_pmap()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_pmap.md)
  :

  Read DICOM Parametric Map Objects (`dcmpmap`)

- [`read_dicom_tract()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_tract.md)
  :

  Read DICOM Tractography Results (`dcmtract`)

- [`read_dicom_pstate()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_pstate.md)
  :

  Read DICOM Grayscale Softcopy Presentation State (`dcmpstat`)

- [`read_dicom_ect()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_ect.md)
  :

  Read DICOM Tractography Results (`dcmtract`) and Enhanced Multi-Frame
  IODs (`dcmect` / `dcmfg`)

- [`dicom_verify_signature()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_verify_signature.md)
  :

  Inspect Digital Signatures in a DICOM File (`dcmsign`)

## AI & LLM Integration (Ollama, OpenAI, Claude)

Connect DICOM studies and images to local Ollama and cloud
OpenAI/Anthropic models.

- [`dicom_llm()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_llm.md)
  : Configure an LLM Provider for DICOM Analysis
- [`ollama_list_models()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/ollama_list_models.md)
  : List Available Local Ollama Models
- [`dicom_summarize()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_summarize.md)
  : Summarize a DICOM Study Using an LLM
- [`dicom_describe_image()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_describe_image.md)
  : Describe a DICOM Image Using a Vision-Capable LLM
- [`dicom_report()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_report.md)
  : Generate a Structured Radiology Report from a DICOM File
- [`dicom_ask()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_ask.md)
  : Ask a Natural-Language Question About a DICOM File

## Legacy Compatibility

Backward-compatible wrappers for original dcmtk R package functions.

- [`dcmdump()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)
  [`dcmdump_full()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)
  [`dcmhd()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)
  [`wide_hdr()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)
  [`burned_annot()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)
  [`dcmodify()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)
  [`dcm_anon()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)
  [`dcm_subtract_date()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)
  [`dcmj2pnm()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)
  [`dcmdjpeg()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)
  [`dcmdrle()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)
  [`dcmcrle()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)
  [`check_dcmtk_cmd()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)
  :

  Legacy Compatibility Functions from `dcmtk`
