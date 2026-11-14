# `dicomtk` Phase 4 (`v0.5.0` Interoperability, DuckDB Index & OMOP MI-CDM) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Build Phase 4 (`dicomtk 0.5.0`) adding PS3.18 DICOMweb (`QIDO-RS`, `WADO-RS`, `STOW-RS` + OAuth2), HL7 FHIR R4/R5 imaging resources (`ImagingStudy`, `ImagingSelection`, `DiagnosticReport`, `Provenance`) + Synthea patient linkage, a normalized DuckDB/Parquet archive index with AST-guardrailed NL-to-SQL cohort building, and OHDSI OMOP Medical Imaging CDM (`MI-CDM` `image_occurrence` & `image_feature`) export.

**Architecture:** Extends core `dicomtk` (`0.5.0`) with pure-R interoperability modules (`R/dicomweb.R`, `R/fhir.R`, `R/fhir-link.R`, `R/archive-index.R`, `R/cohort-nl.R`, `R/omop-micdm.R`) and a bundled `omop_imaging_concepts` dataset. `DBI` and `duckdb` live in `Suggests` with an automatic pure-R tibble fallback so `dicomtk` passes `R CMD check --as-cran` even under `_R_CHECK_DEPENDS_ONLY_=true`.

**Tech Stack:** R (>= 4.1.0), `httr2`, `jsonlite`, `tibble`, `dplyr`, `DBI` (Suggests), `duckdb` (Suggests), `testthat` (>= 3.0.0).

**Effort Routing (`/effort-harness-router`):**
- **Hydrogen (`Medium`)**: Tasks 1–8 (implementation, unit tests, property tests, vignette & docs).
- **Argon (`High`)**: Task 9 (final SQL-injection / OAuth2 security review, Six-Sigma `R CMD check --as-cran`, merge to `main`, and push).

---

### Task 1: Package Metadata (`v0.5.0`) & `omop_imaging_concepts` Dataset
**Files:**
- Modify: `DESCRIPTION`
- Create: `data-raw/build_omop_imaging_concepts.R`, `data/omop_imaging_concepts.rda`, `R/data-omop.R`
- Test: `tests/testthat/test-omop-concepts.R`

**Steps:**
1. Write failing test `tests/testthat/test-omop-concepts.R` checking `omop_imaging_concepts` has `>= 45` rows and columns `concept_id`, `concept_name`, `domain_id`, `vocabulary_id`, `concept_class_id`, `concept_code`, `dicom_code`, `category`.
2. Run RED test -> expect `FAIL`.
3. Update `DESCRIPTION` (`Version: 0.5.0`, add `DBI (>= 1.2.0)` and `duckdb (>= 1.0.0)` to `Suggests`), create `data-raw/build_omop_imaging_concepts.R`, generate `data/omop_imaging_concepts.rda`, and document in `R/data-omop.R`.
4. Run GREEN test -> expect `PASS`, `roxygenise()`, commit.

---

### Task 2: DICOMweb (`QIDO-RS`, `WADO-RS`, `STOW-RS`), OAuth2 & Binary `multipart/related` Codec
**Files:**
- Modify: `R/network.R`
- Create: `R/dicomweb.R`
- Test: `tests/testthat/test-dicomweb.R`

**Steps:**
1. Write failing tests in `tests/testthat/test-dicomweb.R`:
   - `as_dicom_json()` and `from_dicom_json()` round-trip DICOM headers (`(0010,0010)`, `(0020,000D)`, `(0008,0060)`, etc.) losslessly.
   - `pack_multipart_dicom()` and `unpack_multipart_dicom()` pack multiple `.dcm` files into an RFC 2387 `multipart/related; type="application/dicom"` payload and unpack them with bit-identical MD5/size.
   - `dicom_connect()` accepts `auth = list(type = "bearer", token = "...")` and `oauth2_client_credentials`.
   - `dicomweb_qido()`, `dicomweb_wado()`, `dicomweb_stow()`, and `dicomweb_metadata()` work end-to-end against a loopback/local connection and return standard tibbles / STOW response summaries.
2. Run RED -> implement `R/dicomweb.R` and update `R/network.R` -> run GREEN -> `roxygenise()`, commit.

---

### Task 3: HL7 FHIR R4/R5 Imaging Resources (`ImagingStudy`, `ImagingSelection`, `DiagnosticReport`, `Provenance`)
**Files:**
- Create: `R/fhir.R`
- Test: `tests/testthat/test-fhir.R`

**Steps:**
1. Write failing tests in `tests/testthat/test-fhir.R`:
   - `as_fhir_imaging_study()` and `from_fhir_imaging_study()` round-trip `StudyInstanceUID` (`urn:dicom:uid:...`), `SeriesInstanceUID`, `Modality`, `numberOfSeries`, and `numberOfInstances`.
   - `as_fhir_imaging_selection()` converts a `dicom_seg` mask and a `dicom_gsps` object into valid FHIR `ImagingSelection` resources.
   - `as_fhir_diagnostic_report()` converts a `read_sr_tid1500()` quantitative report into a FHIR `DiagnosticReport` with linked `Observation` entries.
   - `as_fhir_provenance()` and `as_w3c_prov()` convert `dicom_deid()` audit logs / `dicom_volume` provenance into valid FHIR `Provenance` and W3C PROV-JSON structures.
2. Run RED -> implement `R/fhir.R` -> run GREEN -> `roxygenise()`, commit.

---

### Task 4: FHIR REST Client & Synthea Coherent Data Set Linkage
**Files:**
- Create: `R/fhir-link.R`
- Test: `tests/testthat/test-fhir-link.R`

**Steps:**
1. Write failing tests in `tests/testthat/test-fhir-link.R`:
   - Generate synthetic Synthea FHIR bundle JSON files (`Patient`, `Encounter`, `Condition`, `ImagingStudy`) matching synthesized DICOM studies (`StudyInstanceUID` and `PatientID`).
   - `link_synthea_cohort(dicom_dir, fhir_dir)` joins the FHIR resources with the DICOM series into a unified tibble with `patient_id`, `birth_date`, `gender`, `condition_code`, `condition_display`, `study_uid`, `series_uid`, `modality`, and `n_instances`.
   - `fhir_post()` and `fhir_get()` support local mock directory or live FHIR REST servers.
2. Run RED -> implement `R/fhir-link.R` -> run GREEN -> `roxygenise()`, commit.

---

### Task 5: Normalized DuckDB / Parquet Archive Index (`dicom_index_build()`)
**Files:**
- Create: `R/archive-index.R`
- Test: `tests/testthat/test-archive-index.R`

**Steps:**
1. Write failing tests in `tests/testthat/test-archive-index.R`:
   - `dicom_index_build(path, db_path = ..., parquet_dir = ...)` indexes multiple multi-modality synthetic studies into `studies`, `series`, and `instances` tables and writes `studies.parquet`, `series.parquet`, and `instances.parquet`.
   - `dicom_index_query(idx, "SELECT Modality, COUNT(*) AS n FROM series GROUP BY Modality")` returns expected counts.
   - Pure-R tibble fallback works cleanly when `engine = "tibble"`.
   - `dicom_index_close(idx)` releases all DuckDB file locks and `.wal` files cleanly.
2. Run RED -> implement `R/archive-index.R` -> run GREEN -> `roxygenise()`, commit.

---

### Task 6: Guardrailed NL-to-SQL Cohort Builder & Portable Cohort Specs
**Files:**
- Create: `R/cohort-nl.R`
- Test: `tests/testthat/test-cohort-nl.R`

**Steps:**
1. Write failing tests in `tests/testthat/test-cohort-nl.R`:
   - Property test with 100+ adversarial SQL injection & DuckDB file-access payloads (`; DROP TABLE studies`, `UNION SELECT * FROM read_csv('/etc/passwd')`, `COPY studies TO ...`, `ATTACH ...`, `PRAGMA ...`, `INSTALL ...`, `DELETE FROM ...`, SQL comments `--` / `/* */`) verifying 100% rejection by `validate_readonly_sql()`.
   - `dicom_cohort_nl(idx, "CT chest series with at least 2 instances")` generates valid `SELECT` SQL and returns matching series rows.
   - `export_cohort_spec()` and `run_cohort_spec()` round-trip a portable JSON cohort definition and execute it against `idx`.
2. Run RED -> implement `R/cohort-nl.R` -> run GREEN -> `roxygenise()`, commit.

---

### Task 7: OHDSI OMOP Medical Imaging CDM (`MI-CDM`) Exporter
**Files:**
- Create: `R/omop-micdm.R`
- Test: `tests/testthat/test-omop-micdm.R`

**Steps:**
1. Write failing tests in `tests/testthat/test-omop-micdm.R`:
   - `to_omop_image_occurrence()` maps a `dicom_index` or DICOM directory into standard OHDSI `image_occurrence` columns (`image_occurrence_id`, `person_id`, `image_occurrence_date`, `image_study_uid`, `image_series_uid`, `modality_concept_id`, `anatomic_site_concept_id`, `local_path`, `wadors_uri`) with valid SNOMED/OMOP concept IDs (`CT` -> `4300757`, etc.).
   - `to_omop_image_feature()` maps a `dicom_seg` mask and a `read_sr_tid1500()` report into standard OHDSI `image_feature` rows (`image_feature_id`, `image_occurrence_id`, `person_id`, `image_feature_concept_id`, `image_feature_type_concept_id`, `image_finding_concept_id`, `alg_system`, `value_as_number`, `unit_concept_id`).
   - `write_omop_micdm()` writes both tables into a DuckDB database and validates foreign-key integrity (`image_feature$image_occurrence_id %in% image_occurrence$image_occurrence_id`).
2. Run RED -> implement `R/omop-micdm.R` -> run GREEN -> `roxygenise()`, commit.

---

### Task 8: `dicomtk-lab` (`ehr` & `ohdsi` Profiles), Vignette & `R CMD check` Prep
**Files:**
- Modify: `C:/Users/lauye/.gemini/antigravity/scratch/dicomtk-lab/docker-compose.yml`
- Create: `vignettes/interop_fhir_and_omop.Rmd`, `tests/testthat/test-interop-lab.R`
- Modify: `_pkgdown.yml`, `NEWS.md`

**Steps:**
1. Verify/update `dicomtk-lab/docker-compose.yml` for `ehr` and `ohdsi` profiles and add env-gated `tests/testthat/test-interop-lab.R` (`DICOMTK_TEST_EHR` / `DICOMTK_TEST_OHDSI`).
2. Create `vignettes/interop_fhir_and_omop.Rmd` demonstrating DICOMweb JSON/multipart framing, FHIR `ImagingStudy`/`DiagnosticReport`/`Provenance`, Synthea linkage, DuckDB cohort indexing, NL-to-SQL, and OMOP MI-CDM export.
3. Update `_pkgdown.yml` and `NEWS.md` for `dicomtk 0.5.0`, run `roxygenise()`, `checkRd()`, `check_pkgdown()`, `test_local()`, and `R CMD check --as-cran --no-manual`.

---

### Task 9: Final Argon (High) Security & Six-Sigma Review, Merge & Push (`v0.5.0`)
**Steps:**
1. Switch to **Gemini 4 Argon (High)** to audit `validate_readonly_sql()`, OAuth2 token handling, and `multipart/related` binary parsing.
2. Verify `0 ERRORs | 0 WARNINGs` on `R CMD check --as-cran --no-manual`, merge `feat/p4-interop-omop` into `main`, push to `origin/main`, and install `dicomtk 0.5.0`.
