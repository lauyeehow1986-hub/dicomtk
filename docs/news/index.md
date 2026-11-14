# Changelog

## dicomtk 0.6.0

#### Whole Slide Imaging (WSI) Pyramids & Sup 222 Annotations (Phase 7)

- **WSI Pyramid Reader & Tile Stitcher (`R/wsi.R`)**:
  - Added
    [`dicom_synthesize_wsi()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize_wsi.md),
    [`read_dicom_wsi_pyramid()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_wsi_pyramid.md),
    [`wsi_extract_tile()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/wsi_extract_tile.md),
    and
    [`wsi_stitch_region()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/wsi_stitch_region.md)
    supporting `TILED_FULL` and `TILED_SPARSE` multi-resolution WSI
    pyramids with out-of-core tile extraction and cross-tile region
    stitching.
  - Added
    [`dicom_wsi_annotations()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_wsi_annotations.md)
    and
    [`wsi_annotations_to_mask()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/wsi_annotations_to_mask.md)
    for Supplement 222 Microscopy Bulk Simple Annotations.

## dicomtk 0.5.0

#### Interoperability, DuckDB/Parquet Index & OHDSI OMOP MI-CDM (Phase 4)

- **DICOMweb (PS3.18) & OAuth2 (`R/dicomweb.R`, `R/network.R`)**:
  - Extended
    [`dicom_connect()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_connect.md)
    with Bearer, Basic, and OAuth2 client-credentials authentication
    (`auth` and custom `headers`) and wired
    [`dicom_find()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_find.md)
    /
    [`dicom_send()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_send.md)
    to delegate to DICOMweb when `dicomweb_url` is set.
  - Added
    [`as_dicom_json()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_dicom_json.md),
    [`from_dicom_json()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/from_dicom_json.md),
    [`pack_multipart_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/pack_multipart_dicom.md),
    [`unpack_multipart_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/unpack_multipart_dicom.md),
    [`dicomweb_qido()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicomweb_qido.md),
    [`dicomweb_wado()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicomweb_wado.md),
    [`dicomweb_stow()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicomweb_stow.md),
    and
    [`dicomweb_metadata()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicomweb_metadata.md).
- **HL7 FHIR R4/R5 Imaging & Synthea Linkage (`R/fhir.R`,
  `R/fhir-link.R`)**:
  - Added
    [`as_fhir_imaging_study()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_fhir_imaging_study.md),
    [`from_fhir_imaging_study()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/from_fhir_imaging_study.md),
    [`as_fhir_imaging_selection()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_fhir_imaging_selection.md),
    [`as_fhir_diagnostic_report()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_fhir_diagnostic_report.md),
    [`as_fhir_provenance()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_fhir_provenance.md),
    and
    [`as_w3c_prov()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_w3c_prov.md).
  - Added
    [`fhir_post()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/fhir_post.md),
    [`fhir_get()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/fhir_get.md),
    and
    [`link_synthea_cohort()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/link_synthea_cohort.md)
    for HAPI FHIR / Epic sandboxes and Synthea Coherent Data Set
    patient-imaging linkage.
- **DuckDB/Parquet Archive Index & Guardrailed NL-to-SQL
  (`R/archive-index.R`, `R/cohort-nl.R`)**:
  - Added
    [`dicom_index_build()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_index_build.md),
    [`dicom_index_query()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_index_query.md),
    and
    [`dicom_index_close()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_index_close.md)
    building normalized `studies`, `series`, and `instances` tables with
    Parquet export and pure-R tibble fallback.
  - Added
    [`validate_readonly_sql()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/validate_readonly_sql.md),
    [`dicom_cohort_nl()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_cohort_nl.md),
    [`export_cohort_spec()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/export_cohort_spec.md),
    and
    [`run_cohort_spec()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/run_cohort_spec.md)
    with strict read-only SQL enforcement blocking DDL/DML,
    multi-statements, comments, and host-file reader functions.
- **OHDSI OMOP Medical Imaging CDM (`R/omop-micdm.R`,
  `omop_imaging_concepts`)**:
  - Added `omop_imaging_concepts` dataset,
    [`to_omop_image_occurrence()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_omop_image_occurrence.md),
    [`to_omop_image_feature()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_omop_image_feature.md),
    and
    [`write_omop_micdm()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_omop_micdm.md).

------------------------------------------------------------------------

## dicomtk 0.4.0

#### Segmentation, Radiotherapy, Quantitative SR & Deep Learning Prep (Phase 2)

- **C++17 Scanline Rasterizer & Contour Tracer
  (`src/rcpp_rasterize.cpp`)**:
  - Added
    [`rasterize_polygon_2d()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/rasterize_polygon_2d.md),
    [`rasterize_polygons_2d()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/rasterize_polygons_2d.md),
    and
    [`trace_contours_2d()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/trace_contours_2d.md)
    with exact even-odd fill rules, hole handling, and Moore-neighbor
    contour extraction.
- **DICOM Segmentation (`dicom_seg`)**:
  - Added
    [`dicom_seg()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_seg.md),
    [`write_dicom_seg()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_dicom_seg.md),
    and
    [`as_labelmap()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_labelmap.md)
    supporting `BINARY` and `FRACTIONAL` DICOM SEG IODs with
    `SegmentSequence`, `SharedFunctionalGroupsSequence`, and
    `PerFrameFunctionalGroupsSequence`, inheriting directly from
    `dicom_volume`.
- **RTSTRUCT & RTDOSE Radiotherapy Suite**:
  - Added
    [`rtstruct_to_seg()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/rtstruct_to_seg.md)
    and
    [`seg_to_rtstruct()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/seg_to_rtstruct.md)
    for bidirectional conversion between 3D `dicom_seg` labelmaps and
    DICOM `RTSTRUCT` `ROIContourSequence` world-space polygons.
  - Added
    [`dicom_dvh()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_dvh.md)
    computing cumulative and differential Dose-Volume Histograms (DVH)
    and clinical dosimetric metrics (`D95`, `D90`, `D50`, `V20`,
    `min_dose`, `max_dose`, `mean_dose`, `volume_cc`) from `RTDOSE` and
    `dicom_seg` masks.
- **Quantitative SR (TID 1500) & Grayscale Presentation States (GSPS)**:
  - Added
    [`dicom_sr_tid1500()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_sr_tid1500.md)
    and
    [`read_sr_tid1500()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_sr_tid1500.md)
    for DICOM TID 1500 Measurement Reports.
  - Added
    [`write_dicom_gsps()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_dicom_gsps.md)
    and
    [`read_dicom_gsps()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_gsps.md)
    for Softcopy Presentation State (`PR`) annotations.
- **Deep Learning Prep, Burned-In Annotations, QC & Dataset Exporters**:
  - Added
    [`volume_resample()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/volume_resample.md),
    [`volume_window()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/volume_window.md),
    and
    [`dicom_patient_splits()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_patient_splits.md)
    for leak-free 3D trilinear/nearest-neighbor resampling,
    HU/percentile normalization, and patient-level train/val/test
    splitting.
  - Added
    [`dicom_burn_annotations()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_burn_annotations.md)
    and
    [`burned_annot()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/legacy-dcmtk.md)
    for rendering segmentations and text overlays onto 2D PNG/DICOM
    Secondary Capture images.
  - Added
    [`dicom_image_qc()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_image_qc.md)
    for automated SNR, CNR, FOV border truncation, spacing/tilt anomaly,
    and high-frequency ringing artifact detection.
  - Added
    [`export_nnunet()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/export_nnunet.md),
    [`export_monai()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/export_monai.md),
    [`export_rocrate()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/export_rocrate.md),
    and
    [`export_croissant()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/export_croissant.md)
    for ML-ready dataset and JSON-LD metadata export.

------------------------------------------------------------------------

## dicomtk 0.3.0

#### Research-Grade De-Identification & Privacy Engine (Phase 1)

- **Pure C++17 RFC Cryptography & Pluggable Key Provider**:
  - Implemented standalone C++17 implementations of RFC 6234 SHA-256,
    RFC 4231 HMAC-SHA256, RFC 2898 PBKDF2-HMAC-SHA256, RFC 5869
    HKDF-SHA256, and RFC 8439 ChaCha20-Poly1305 AEAD
    (`src/rcpp_crypto.h`, `src/rcpp_crypto.cpp`).
  - Added
    [`dicom_key_provider()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_key_provider.md)
    S3 class supporting `local`, `broker`, and `ttp` modes with
    cryptographic subkey derivation, strict credential redaction
    ([`format()`](https://rdrr.io/r/base/format.html),
    [`print()`](https://rdrr.io/r/base/print.html),
    [`str()`](https://rdrr.io/r/utils/str.html)), deterministic
    `2.25.<128-bit>` UID pseudonymization
    ([`deid_map_uid()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/deid_map_uid.md)),
    and per-patient pseudo-random date shifting
    ([`derive_patient_shift_days()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/derive_patient_shift_days.md),
    [`deid_patient_shift()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/deid_patient_shift.md)).
    Zero external C/Python crypto runtime dependencies.
- **DICOM PS3.15 Profile Compiler & Composable Jurisdictions**:
  - Added
    [`dicom_deid_profile()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid_profile.md)
    and
    [`dicom_list_jurisdictions()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_list_jurisdictions.md)
    compiling declarative YAML profiles (`ps3.15-basic.yml` + 10 PS3.15
    options).
  - Added 8 composable statutory jurisdiction overlays
    (`hipaa_safe_harbor`, `hipaa_limited_dataset`, `gdpr_eu`,
    `sg_pdpa_hib`, `my_pdpa_2024`, `au_privacy_act`, `uk_gdpr`,
    `ca_pipeda`) with strictest-wins monotonic action lattice resolution
    (`D > Z > X > K`) and safe-private creator allowlisting.
- **Single-Pass Recursive C++17 Dataset & Sequence Mutator**:
  - Implemented `cpp_deid_file()` executing in-memory DICOM
    de-identification in a single recursive traversal across all dataset
    tags and arbitrary-depth Sequence of Items (`VR=SQ`).
  - Features Howard Hinnant C++ date shifting (`DA`, `DT`), safe-private
    block retention with orphan private creator pruning, wildcard tag
    matching (`(50xx,eeee)`, `(60xx,eeee)`), dummy string/integer
    substitution, and W3C PROV-compliant De-identification Method
    sequence logging `(0012,0062)` and `(0012,0063)`.
- **Cohort
  [`dicom_deid()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid.md)
  & Encrypted Crosswalk**:
  - Added
    [`dicom_deid()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid.md)
    supporting file, directory, and vector inputs with progress
    reporting (`cli`) and optional asynchronous multi-process
    parallelism via `mirai`.
  - Generates ChaCha20-Poly1305 AEAD-encrypted crosswalk files
    (`dicomtk_crosswalk.enc`) decryptable via
    [`dicom_crosswalk_read()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_crosswalk_read.md)
    using the original key provider.
  - Automatically records input/output checksums, timestamps, applied
    profiles, and patient mapping tables with full W3C PROV audit
    metadata.
- **Burned-In Pixel PHI Detection & C++17 Fast Telea Inpainting**:
  - Added
    [`dicom_detect_burned_phi()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_detect_burned_phi.md)
    and
    [`dicom_clean_pixels()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_clean_pixels.md)
    for identifying and blacking out burned-in text in secondary
    captures, ultrasound overlays, and scanned radiographs.
  - Implemented C++17 Fast Marching Method (FMM) Telea inpainting
    (`cpp_telea_inpaint()`) for smooth edge preservation with
    aspect-ratio bounding-box guardrails and optional OCR verification
    (`tesseract`).
- **3D Head CT/MR Defacing & WSI Whole Slide Safeguards**:
  - Added
    [`dicom_deface()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deface.md)
    performing analytical cutting-plane facial stripping on 3D
    volumetric CT and MR series in LPS/RAS coordinate space.
  - Added Whole Slide Imaging (WSI) label/macro frame stripping to
    prevent specimen identifier leakage.
- **Residual-PHI Verifier, Attestations & Re-identification Risk
  Scorer**:
  - Added
    [`dicom_deid_verify()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid_verify.md)
    scanning processed DICOM datasets for 18 statutory PHI canaries
    (MRNs, names, free-text patterns, unshifted dates, age cap
    violations \>89y, unsafe private tags, and orphan creators).
  - Added HMAC-SHA256 signed tamper-evident compliance certificates
    ([`dicom_verify_attestation()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_verify_attestation.md)).
  - Added
    [`dicom_deid_risk()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid_risk.md)
    computing cohort re-identification risk metrics including
    equivalence class distribution, $`k`$-anonymity, $`l`$-diversity,
    and prosecutor/markov re-identification probabilities.
- **Synthetic MIDI-B Ground Truth Benchmark Suite**:
  - Extended
    [`dicom_synthesize()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md)
    with `phi_profile = c("basic", "midi_b")` planting 18 HIPAA, PS3.15,
    and international PHI canary categories across structured tags,
    nested sequences, and free text.
  - Added `tools/run_midib_benchmark.R` producing validated audit
    scorecards (`inst/extdata/midib_scorecard.json`) demonstrating
    100.0% sensitivity, 100.0% specificity, zero residual PHI leaks, and
    exact longitudinal UID isomorphism.

------------------------------------------------------------------------

## dicomtk 0.2.0

#### 3D/4D Volume Geometry & Foundations (Phase 0)

- **`dicom_volume` S3 Class & Spatial Transforms**:
  - Introduced the `dicom_volume` S3 class encapsulating 3D/4D voxel
    data arrays, analytical 4x4 coordinate affine matrices, and
    slice-level metadata.
  - Implemented S3 methods:
    [`print()`](https://rdrr.io/r/base/print.html),
    [`dim()`](https://rdrr.io/r/base/dim.html), `[` (with affine
    translation/rescaling update and `drop = FALSE` default), and
    [`as.array()`](https://rdrr.io/r/base/array.html).
  - Added coordinate orientation helpers
    [`dicom_orientation()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_orientation.md),
    [`dicom_to_lps()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_ras.md),
    and
    [`dicom_to_ras()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_ras.md)
    supporting standard neurological (RAS) and radiological (LPS)
    conventions.
- **Geometry-Aware
  [`read_dicom_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md)**:
  - Added
    [`read_dicom_volume()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md)
    supporting multi-slice series, enhanced multi-frame DICOM IODs
    (`SharedFunctionalGroupsSequence` and
    `PerFrameFunctionalGroupsSequence`), and automatic series splitting
    on `SeriesInstanceUID`, `FrameOfReferenceUID`, or spatial
    discontinuities.
  - Retained
    [`read_dicom_series()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_series.md)
    as a backward-compatible wrapper returning `dicom_series` /
    `dicom_volume`.
- **C++ Hierarchical Sequences & SQ Writer**:
  - Extended native C++17 bindings (`cpp_write_dicom_multiframe()`,
    `cpp_modify_dicom()`, and `cpp_dcm_transcode_rle()`) to read, prune,
    and write arbitrary nested Sequence of Items (`VR=SQ`) trees from R
    lists.
  - Added full support for multi-level nested clinical sequences
    (e.g. `SharedFunctionalGroupsSequence`,
    `PerFrameFunctionalGroupsSequence`,
    `RadiopharmaceuticalInformationSequence`).
- **Synthetic Modality Phantom Generator
  ([`dicom_synthesize()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md))**:
  - Implemented
    [`dicom_synthesize()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md)
    generating standard-compliant synthetic DICOM series across CT, MR,
    and PET modalities.
  - Full parametric control over geometric orientation (`axial`,
    `coronal`, `sagittal`, `oblique`), non-orthogonal gantry tilt, slice
    reverse order, and PHI injection/scrubbing for offline CI testing.
- **Modality Quantitative Transforms**:
  - Added PET Standardized Uptake Value conversion
    ([`dicom_pet_suv()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_pet_suv.md))
    with Body Weight (`bw`), Lean Body Mass (`lbm`, James/Janmahasatian
    formulations), and Body Surface Area (`bsa`) corrections with
    radionuclide half-life decay compensation.
  - Added Mammography/Radiography VOI LUT non-linear mapping
    ([`dicom_apply_voi_lut()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_apply_voi_lut.md))
    supporting both `LINEAR` and `SIGMOID` transfer functions.
  - Added Philips MR precise rescale slope/intercept
    ([`dicom_mr_rescale()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_mr_rescale.md))
    using private attributes `(2005,100D)` and `(2005,100E)`.
- **NIfTI-1 Export with `dcm2niix` Parity
  ([`write_nifti()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_nifti.md))**:
  - Added
    [`write_nifti()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_nifti.md)
    producing standard NIfTI-1 files with rigorous `qform` (polar SVD
    decomposition) and `sform` (exact affine mapping) coordinate spaces
    matching Chris Rorden’s `dcm2niix` specification.
  - Generates companion BIDS JSON sidecars (`SliceThickness`,
    `SpacingBetweenSlices`, `RepetitionTime`, `EchoTime`).
  - Implemented zero-dependency pure R binary NIfTI writer with
    automatic fallback to `RNifti` backend when installed.
  - Added non-orthogonal gantry tilt detection and user notification
    when shear is orthogonalized for quaternion storage.
- **CI Fixtures & Parity Validation**:
  - Added `tools/download_fixtures.R` syncing 11 open-license scanner
    fixtures from `pydicom`, `dcm_qa_ct`, and `dcm_qa_nih`.
  - Added comprehensive `test-p0-dcm2niix-parity.R` ensuring continuous
    orientation and voxel parity.
- **`dicomtk-lab` Multi-Container Testbed**:
  - Created standalone repository `dicomtk-lab` containing Docker
    Compose profiles for `core` (Orthanc PACS + Keycloak IAM),
    `enterprise` (dcm4chee-arc + PostgreSQL + OpenLDAP), `ehr` (HAPI
    FHIR R4), `ohdsi` (OMOP CDM v5.4), `ttp` (Honest Broker
    pseudonymization enclave), and `fl` (Federated Learning
    Flower/OpenFL aggregator).
  - Integrated `test-p0-lab-core.R` smoke test verifying DIMSE C-ECHO
    and HTTP REST series round-tripping with exact affine preservation.

------------------------------------------------------------------------

## dicomtk 0.1.0

CRAN release: 2026-11-13

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
