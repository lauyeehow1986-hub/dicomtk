# DICOMweb, HL7 FHIR, DuckDB Cohort Indexing, and OMOP MI-CDM

## Overview

`dicomtk 0.5.0` introduces standards-compliant medical imaging
interoperability:

1.  **DICOMweb (PS3.18)**:
    [`as_dicom_json()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_dicom_json.md),
    [`from_dicom_json()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/from_dicom_json.md),
    [`pack_multipart_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/pack_multipart_dicom.md),
    [`unpack_multipart_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/unpack_multipart_dicom.md),
    [`dicomweb_qido()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicomweb_qido.md),
    [`dicomweb_wado()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicomweb_wado.md),
    [`dicomweb_stow()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicomweb_stow.md),
    and
    [`dicomweb_metadata()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicomweb_metadata.md)
    with OAuth2/Bearer/Basic authentication.
2.  **HL7 FHIR R4/R5**:
    [`as_fhir_imaging_study()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_fhir_imaging_study.md),
    [`from_fhir_imaging_study()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/from_fhir_imaging_study.md),
    [`as_fhir_imaging_selection()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_fhir_imaging_selection.md),
    [`as_fhir_diagnostic_report()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_fhir_diagnostic_report.md),
    [`as_fhir_provenance()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_fhir_provenance.md),
    [`as_w3c_prov()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_w3c_prov.md),
    and
    [`link_synthea_cohort()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/link_synthea_cohort.md).
3.  **DuckDB / Parquet Archive Index & Guardrailed NL-to-SQL**:
    [`dicom_index_build()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_index_build.md),
    [`dicom_index_query()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_index_query.md),
    [`validate_readonly_sql()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/validate_readonly_sql.md),
    [`dicom_cohort_nl()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_cohort_nl.md),
    [`export_cohort_spec()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/export_cohort_spec.md),
    and
    [`run_cohort_spec()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/run_cohort_spec.md).
4.  **OHDSI OMOP MI-CDM**:
    [`to_omop_image_occurrence()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_omop_image_occurrence.md),
    [`to_omop_image_feature()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_omop_image_feature.md),
    and
    [`write_omop_micdm()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/write_omop_micdm.md)
    backed by `omop_imaging_concepts`.

## 1. Archive Index & Guardrailed NL-to-SQL Cohort Builder

[`library`](https://rdrr.io/r/base/library.html)`(`[`dicomtk`](https://github.com/lauyeehow1986-hub/dicomtk)`)`` `` ``synth`` ``<-`` `[`dicom_synthesize`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md)`(``modality ``=`` ``"CT"``, dims ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``16L``, ``16L``, ``3L``)``, phi_profile ``=`` ``"basic"``)`` ``idx`` ``<-`` `[`dicom_index_build`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_index_build.md)`(``synth``[[``"out_dir"``]``]``)`` `` ``cohort`` ``<-`` `[`dicom_cohort_nl`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_cohort_nl.md)`(``idx``, ``"CT series with at least 2 instances"``)`` ``cohort``$``sql`` ``#> [1] "SELECT SeriesInstanceUID, StudyInstanceUID, Modality, SeriesDescription, BodyPartExamined, SliceThickness, n_instances FROM series WHERE Modality = 'CT' AND n_instances >= 2"`` ``cohort``$``results`` ``#> ``# A tibble: 1 × 7`` ``#> SeriesInstanceUID StudyInstanceUID Modality SeriesDescription BodyPartExamined`` ``#> ``<chr>`` ``<chr>`` ``<chr>`` ``<chr>`` ``<chr>`` `` ``#> ``1`` 2.25.17946692018… 2.25.1794669201… CT ``""`` ``""`` `` ``#> ``# ℹ 2 more variables: SliceThickness <dbl>, n_instances <int>`

## 2. HL7 FHIR `ImagingStudy` & OHDSI OMOP `MI-CDM`

`vol`` ``<-`` `[`read_dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_volume.md)`(``synth``[[``"out_dir"``]``]``)`` ``fhir_study`` ``<-`` `[`as_fhir_imaging_study`](https://lauyeehow1986-hub.github.io/dicomtk/reference/as_fhir_imaging_study.md)`(``vol``, patient_ref ``=`` ``"Patient/p-001"``)`` ``fhir_study``$``resourceType`` ``#> [1] "ImagingStudy"`` `` ``occ`` ``<-`` `[`to_omop_image_occurrence`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_omop_image_occurrence.md)`(``idx``)`` ``occ``[``, `[`c`](https://rdrr.io/r/base/c.html)`(``"image_occurrence_id"``, ``"modality_concept_id"``, ``"image_study_uid"``)``]`` ``#> ``# A tibble: 1 × 3`` ``#> image_occurrence_id modality_concept_id image_study_uid `` ``#> ``<int>`` ``<int>`` ``<chr>`` `` ``#> ``1`` 1 4``300``757 2.25.179466920183402667200000010001`` `` `[`dicom_index_close`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_index_close.md)`(``idx``)`` `[`unlink`](https://rdrr.io/r/base/unlink.html)`(``synth``[[``"out_dir"``]``]``, recursive ``=`` ``TRUE``)`
