#' OHDSI OMOP Medical Imaging CDM Concept Crosswalk
#'
#' Curated reference crosswalk mapping DICOM modalities, anatomic sites,
#' quantitative TID 1500 / segmentation features, UCUM units, and provenance
#' type codes onto standard OHDSI OMOP, SNOMED CT, LOINC, and RadLex concepts.
#'
#' @usage data(omop_imaging_concepts)
#' @format A tibble with 52 rows and 8 variables:
#' \describe{
#'   \item{concept_id}{Integer OMOP standard concept identifier.}
#'   \item{concept_name}{Human-readable concept name.}
#'   \item{domain_id}{OMOP domain (`"Procedure"`, `"Spec Anatomic Site"`,
#'     `"Measurement"`, `"Unit"`, `"Type Concept"`).}
#'   \item{vocabulary_id}{Source vocabulary (`"SNOMED"`, `"LOINC"`, `"RadLex"`,
#'     `"UCUM"`, `"OMOP"`, `"Type Concept"`).}
#'   \item{concept_class_id}{OMOP concept class.}
#'   \item{concept_code}{Vocabulary-specific concept code.}
#'   \item{dicom_code}{Normalized DICOM / `dicomtk` lookup key.}
#'   \item{category}{Crosswalk category (`"modality"`, `"anatomic_site"`,
#'     `"feature"`, `"unit"`, `"feature_type"`).}
#' }
#' @source OHDSI Medical Imaging Working Group (`MI-CDM`) & DICOM PS3.16.
"omop_imaging_concepts"
