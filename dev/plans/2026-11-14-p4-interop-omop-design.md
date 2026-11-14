# `dicomtk` Phase 4 (`v0.5.0` Interoperability, DuckDB Index & OMOP MI-CDM) Design Specification

**Date:** 2026-11-14  
**Package:** `dicomtk` (`0.5.0`)  
**Branch:** `feat/p4-interop-omop`

---

## 1. Architectural Decisions
1. **Lean CRAN Footprint (`DESCRIPTION`)**:
   - Bump `Version: 0.5.0`.
   - Place `DBI (>= 1.2.0)` and `duckdb (>= 1.0.0)` in `Suggests` alongside existing `Imports` (`httr2`, `jsonlite`, `tibble`, `dplyr`, `cli`, `rlang`).
   - All archive indexing and OMOP MI-CDM features use `duckdb` when installed and fall back seamlessly to an in-memory tibble engine when running under `_R_CHECK_DEPENDS_ONLY_=true`.
   - Bundle `omop_imaging_concepts` (`data/omop_imaging_concepts.rda`) containing ~50 curated OHDSI OMOP / SNOMED / LOINC / RadLex concepts for imaging modalities, anatomic sites, and quantitative features.

2. **DICOMweb (`QIDO-RS`, `WADO-RS`, `STOW-RS`) & OAuth2 (`R/dicomweb.R`, `R/network.R`)**:
   - Extend `dicom_connect()` with `auth = list(type = "none" | "bearer" | "basic" | "oauth2_client_credentials", ...)` and `headers`.
   - Provide lossless PS3.18 DICOM JSON Model converters (`as_dicom_json()`, `from_dicom_json()`) and RFC 2387 `multipart/related; type="application/dicom"` binary framing (`pack_multipart_dicom()`, `unpack_multipart_dicom()`).
   - Provide `dicomweb_qido()`, `dicomweb_wado()`, `dicomweb_stow()`, and `dicomweb_metadata()` supporting both live REST servers (`httr2`) and local directory loopback (`conn$local_dir`), and wire `dicom_find()`, `dicom_get()`, and `dicom_send()` to delegate when `dicomweb_url` is set.

3. **HL7 FHIR R4/R5 Imaging Resources & Synthea Linkage (`R/fhir.R`, `R/fhir-link.R`)**:
   - Bi-directional resource builders/parsers: `as_fhir_imaging_study()`, `from_fhir_imaging_study()`, `as_fhir_imaging_selection()`, `as_fhir_diagnostic_report()`, `as_fhir_provenance()`, and `as_w3c_prov()`.
   - REST helpers `fhir_post()` and `fhir_get()` for HAPI FHIR / Epic sandboxes.
   - `link_synthea_cohort()` joins Synthea FHIR `Patient` / `Encounter` / `ImagingStudy` / `Condition` JSON bundles with DICOM studies (`StudyInstanceUID`, `AccessionNumber`, `PatientID`).

4. **DuckDB/Parquet Archive Index & Guardrailed NL-to-SQL (`R/archive-index.R`, `R/cohort-nl.R`)**:
   - `dicom_index_build(path, db_path = ":memory:", parquet_dir = NULL)` builds normalized `studies`, `series`, and `instances` tables with optional Parquet export (`studies.parquet`, `series.parquet`, `instances.parquet`).
   - `validate_readonly_sql(sql)` enforces an unbypassable read-only `SELECT` policy, blocking multi-statement `;`, DDL/DML (`DROP`, `DELETE`, `INSERT`, `UPDATE`, `ALTER`, `CREATE`, `ATTACH`, `COPY`, `PRAGMA`, `INSTALL`, `LOAD`), and DuckDB host-file functions (`read_csv`, `read_parquet`, `read_json`, `glob`).
   - `dicom_cohort_nl()`, `export_cohort_spec()`, and `run_cohort_spec()` translate natural-language criteria into validated read-only SQL and portable JSON cohort specs for Phase 8 (`dicomtk.fl`).

5. **OHDSI OMOP Medical Imaging CDM (`MI-CDM`) (`R/omop-micdm.R`)**:
   - `to_omop_image_occurrence()` and `to_omop_image_feature()` map DICOM studies, `dicom_seg` masks, and TID 1500 SR measurements onto standard OHDSI MI-CDM tables using `omop_imaging_concepts`.
   - `write_omop_micdm()` writes and validates `image_occurrence` and `image_feature` tables in a DBI/DuckDB connection.
