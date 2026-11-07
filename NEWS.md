# dicomtk 0.2.0

### 3D/4D Volume Geometry & Foundations (Phase 0)

* **`dicom_volume` S3 Class & Spatial Transforms**:
  - Introduced the `dicom_volume` S3 class encapsulating 3D/4D voxel data arrays, analytical 4x4 coordinate affine matrices, and slice-level metadata.
  - Implemented S3 methods: `print()`, `dim()`, `[` (with affine translation/rescaling update and `drop = FALSE` default), and `as.array()`.
  - Added coordinate orientation helpers `dicom_orientation()`, `dicom_to_lps()`, and `dicom_to_ras()` supporting standard neurological (RAS) and radiological (LPS) conventions.

* **Geometry-Aware `read_dicom_volume()`**:
  - Added `read_dicom_volume()` supporting multi-slice series, enhanced multi-frame DICOM IODs (`SharedFunctionalGroupsSequence` and `PerFrameFunctionalGroupsSequence`), and automatic series splitting on `SeriesInstanceUID`, `FrameOfReferenceUID`, or spatial discontinuities.
  - Retained `read_dicom_series()` as a backward-compatible wrapper returning `dicom_series` / `dicom_volume`.

* **C++ Hierarchical Sequences & SQ Writer**:
  - Extended native C++17 bindings (`cpp_write_dicom_multiframe()`, `cpp_modify_dicom()`, and `cpp_dcm_transcode_rle()`) to read, prune, and write arbitrary nested Sequence of Items (`VR=SQ`) trees from R lists.
  - Added full support for multi-level nested clinical sequences (e.g. `SharedFunctionalGroupsSequence`, `PerFrameFunctionalGroupsSequence`, `RadiopharmaceuticalInformationSequence`).

* **Synthetic Modality Phantom Generator (`dicom_synthesize()`)**:
  - Implemented `dicom_synthesize()` generating standard-compliant synthetic DICOM series across CT, MR, and PET modalities.
  - Full parametric control over geometric orientation (`axial`, `coronal`, `sagittal`, `oblique`), non-orthogonal gantry tilt, slice reverse order, and PHI injection/scrubbing for offline CI testing.

* **Modality Quantitative Transforms**:
  - Added PET Standardized Uptake Value conversion (`dicom_pet_suv()`) with Body Weight (`bw`), Lean Body Mass (`lbm`, James/Janmahasatian formulations), and Body Surface Area (`bsa`) corrections with radionuclide half-life decay compensation.
  - Added Mammography/Radiography VOI LUT non-linear mapping (`dicom_apply_voi_lut()`) supporting both `LINEAR` and `SIGMOID` transfer functions.
  - Added Philips MR precise rescale slope/intercept (`dicom_mr_rescale()`) using private attributes `(2005,100D)` and `(2005,100E)`.

* **NIfTI-1 Export with `dcm2niix` Parity (`write_nifti()`)**:
  - Added `write_nifti()` producing standard NIfTI-1 files with rigorous `qform` (polar SVD decomposition) and `sform` (exact affine mapping) coordinate spaces matching Chris Rorden's `dcm2niix` specification.
  - Generates companion BIDS JSON sidecars (`SliceThickness`, `SpacingBetweenSlices`, `RepetitionTime`, `EchoTime`).
  - Implemented zero-dependency pure R binary NIfTI writer with automatic fallback to `RNifti` backend when installed.
  - Added non-orthogonal gantry tilt detection and user notification when shear is orthogonalized for quaternion storage.

* **CI Fixtures & Parity Validation**:
  - Added `tools/download_fixtures.R` syncing 11 open-license scanner fixtures from `pydicom`, `dcm_qa_ct`, and `dcm_qa_nih`.
  - Added comprehensive `test-p0-dcm2niix-parity.R` ensuring continuous orientation and voxel parity.

* **`dicomtk-lab` Multi-Container Testbed**:
  - Created standalone repository `dicomtk-lab` containing Docker Compose profiles for `core` (Orthanc PACS + Keycloak IAM), `enterprise` (dcm4chee-arc + PostgreSQL + OpenLDAP), `ehr` (HAPI FHIR R4), `ohdsi` (OMOP CDM v5.4), `ttp` (Honest Broker pseudonymization enclave), and `fl` (Federated Learning Flower/OpenFL aggregator).
  - Integrated `test-p0-lab-core.R` smoke test verifying DIMSE C-ECHO and HTTP REST series round-tripping with exact affine preservation.

---

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
