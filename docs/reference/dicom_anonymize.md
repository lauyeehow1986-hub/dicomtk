# De-identify / Anonymize a DICOM File (HIPAA & DICOM PS3.15 Profile)

Removes or replaces Protected Health Information (PHI) tags according to
HIPAA Safe Harbor and the DICOM PS3.15 Basic Application Level
Confidentiality Profile. Supports date shifting, private tag removal,
UID regeneration, and custom tag overrides.

## Usage

``` r
dicom_anonymize(
  path,
  out_path = NULL,
  patient_name = "ANONYMOUS",
  patient_id = "ANON001",
  shift_days = NULL,
  erase_private = TRUE,
  regenerate_uids = TRUE,
  extra_remove_tags = character(),
  replace_tags = list()
)
```

## Arguments

- path:

  Path to input DICOM file.

- out_path:

  Output path for anonymized DICOM file. If `NULL` (default), writes to
  a temporary `.dcm` file.

- patient_name:

  Replacement string for `PatientName (0010,0010)`. Default is
  `"ANONYMOUS"`.

- patient_id:

  Replacement string for `PatientID (0010,0020)`. Default is
  `"ANON001"`.

- shift_days:

  Optional integer number of days to shift all date (`DA`) tags (e.g.,
  `-365` shifts dates back by 1 year). If `NULL` (default), date tags
  are replaced with `"19000101"`.

- erase_private:

  Logical. Remove all odd-group private tags. Default is `TRUE`.

- regenerate_uids:

  Logical. Regenerate `SOPInstanceUID`, `StudyInstanceUID`, and
  `SeriesInstanceUID`. Default is `TRUE`.

- extra_remove_tags:

  Optional character vector of additional tags or keywords to remove.

- replace_tags:

  Named list of additional tag/value replacements.

## Value

Invisibly returns the path to the anonymized DICOM file.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
anon_file <- dicom_anonymize(dcm_file, patient_name = "STUDY^SUBJECT01")
dicom_tag_value(anon_file, c("PatientName", "PatientIdentityRemoved"))
#>            PatientName PatientIdentityRemoved 
#>      "STUDY^SUBJECT01"                  "YES" 
```
