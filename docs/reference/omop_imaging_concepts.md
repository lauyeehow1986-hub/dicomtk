# OHDSI OMOP Medical Imaging CDM Concept Crosswalk

Curated reference crosswalk mapping DICOM modalities, anatomic sites,
quantitative TID 1500 / segmentation features, UCUM units, and
provenance type codes onto standard OHDSI OMOP, SNOMED CT, LOINC, and
RadLex concepts.

## Usage

``` r
data(omop_imaging_concepts)
```

## Format

A tibble with 52 rows and 8 variables:

- concept_id:

  Integer OMOP standard concept identifier.

- concept_name:

  Human-readable concept name.

- domain_id:

  OMOP domain (`"Procedure"`, `"Spec Anatomic Site"`, `"Measurement"`,
  `"Unit"`, `"Type Concept"`).

- vocabulary_id:

  Source vocabulary (`"SNOMED"`, `"LOINC"`, `"RadLex"`, `"UCUM"`,
  `"OMOP"`, `"Type Concept"`).

- concept_class_id:

  OMOP concept class.

- concept_code:

  Vocabulary-specific concept code.

- dicom_code:

  Normalized DICOM / `dicomtk` lookup key.

- category:

  Crosswalk category (`"modality"`, `"anatomic_site"`, `"feature"`,
  `"unit"`, `"feature_type"`).

## Source

OHDSI Medical Imaging Working Group (`MI-CDM`) & DICOM PS3.16.
