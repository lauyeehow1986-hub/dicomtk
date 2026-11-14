# DICOM De-Identification Profiles and Composable Jurisdictions

Compiles declarative DICOM PS3.15 Annex E Table E.1-1 confidentiality
profiles, standard confidentiality options, safe-private creator
allowlists, and composable statutory jurisdiction overlays into a
concrete, deterministic tag mutator table.

## Usage

``` r
dicom_deid_profile(
  profile = "ps3.15",
  options = character(0),
  jurisdictions = NULL,
  file = NULL,
  override_tags = list(),
  date_shift = NULL,
  dob_policy = NULL,
  patient_deid = TRUE,
  deidentify = TRUE
)
```

## Arguments

- profile:

  Character string identifying the base profile. Default is `"ps3.15"`
  (DICOM PS3.15 Annex E Basic Application Level Confidentiality
  Profile).

- options:

  Character vector of standard PS3.15 options to enable. Valid options
  include:

  - `"clean_pixel_data"` (CID 7050 113101)

  - `"clean_recognizable_visual_features"` (CID 7050 113102)

  - `"clean_graphics"` (CID 7050 113103)

  - `"clean_structured_content"` (CID 7050 113104)

  - `"clean_descriptors"` (CID 7050 113105)

  - `"retain_longitudinal_full_dates"` (CID 7050 113106)

  - `"retain_longitudinal_modified_dates"` (CID 7050 113107)

  - `"retain_patient_characteristics"` (CID 7050 113108)

  - `"retain_device_identity"` (CID 7050 113109)

  - `"retain_institution_identity"` (CID 7050 113110)

  - `"retain_safe_private"` (CID 7050 113111)

  - `"retain_uids"` (CID 7050 113112)

- jurisdictions:

  Optional character vector of statutory jurisdiction overlays to
  compose onto the profile. See
  [`dicom_list_jurisdictions`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_list_jurisdictions.md)
  for available presets. Default is `NULL` (pure PS3.15 standard rules).

- file:

  Optional file path to a custom YAML profile definition. If provided,
  overrides `profile`.

- override_tags:

  Optional named list of tag-action overrides (e.g.,
  `list("(0010,0010)" = "X", "(0008,1030)" = "C")`) applied after all
  base rules, options, and jurisdictions have been resolved.

- date_shift:

  Optional logical. Whether date shifting is explicitly enabled (`TRUE`)
  or disabled (`FALSE`). If `NULL` (default), date shifting is
  determined by active options (e.g.
  `"retain_longitudinal_modified_dates"`) and jurisdictions.

- dob_policy:

  Optional character string specifying policy for date of birth
  (`"year_month"`, `"year_only"`, `"shift_per_patient"`, `"dummy"`, or
  `"keep"`). Default is `NULL` (resolved from base profile and active
  jurisdictions, e.g. `"year_month"` for Singapore PDPA/HIB).

- patient_deid:

  Logical. Whether patient-level de-identification is enabled. Default
  is `TRUE`. If `FALSE`, all patient identification tags (Group
  `(0010,xxxx)` such as `PatientName`, `PatientID`, `PatientBirthDate`,
  `PatientSex`) are retained intact (`"K"`) for operational or clinical
  routing use.

- deidentify:

  Logical. Whether general de-identification is enabled. Default is
  `TRUE`. If `FALSE`, de-identification is entirely bypassed and all
  tags are retained (`"K"`) for operational use.

## Value

An object of class `"dicom_deid_profile"` containing:

- profile:

  Profile name or file identifier.

- description:

  Human-readable profile description.

- cid7050_codes:

  Named character vector of CID 7050 codes and meanings.

- date_policy:

  Resolved date policy (`"dummy"`, `"shift_per_patient"`, `"year_only"`,
  or `"keep"`).

- date_shift:

  Explicit date shift setting (`TRUE`, `FALSE`, or `NULL`).

- dob_policy:

  Resolved date of birth policy (e.g. `"year_month"`, `"year_only"`, or
  `NULL`).

- patient_deid:

  Logical indicating whether patient-level de-identification is active.

- deidentify:

  Logical indicating whether general de-identification is active.

- age_cap_years:

  Integer age cap (e.g. 89L) or NULL.

- zip_prefix_digits:

  Integer retained zip prefix digits (e.g. 3L) or NULL.

- regex_scrubbers:

  Character vector of regular expression patterns for text scrubbing.

- disclaimers:

  Character vector of legal disclaimers associated with active
  jurisdictions.

- flags:

  Named list of arbitrary jurisdictional or workflow flags.

- safe_private:

  Named list of allowlisted private creators and offset numbers.

- tags:

  Tibble of compiled tags with columns `tag`, `action`, `name`,
  `keyword`, and `vr`.

## Details

Conflicting tag rules across composed options and jurisdictions merge
monotonically along the strictest-wins join-semilattice:

      K (keep) < C (clean) < U (UID) < D (dummy) < Z (zero) < X (remove)

Adding any statutory jurisdiction overlay (e.g., `"hipaa_safe_harbor"`,
`"sg_pdpa_hib"`, `"gdpr"`) cannot weaken base protection.

## Examples

``` r
# Basic PS3.15 Profile
prof <- dicom_deid_profile()
print(prof)
#> === dicom_deid_profile: ps3.15 ===
#> Description: DICOM PS3.15 Annex E Table E.1-1 Basic Application Level Confidentiality Profile
#> 
#> CID 7050 Codes:
#>   * [113100] Basic Application Confidentiality Profile
#> 
#> Configuration & Policies:
#>   * Date Policy: dummy
#>   * Age Cap: None
#>   * Zip Prefix: None
#>   * Options (0): none
#>   * Jurisdictions (0): none
#>   * Safe Private Creators: 0 allowlisted
#>   * Regex Text Scrubbers: 0 active
#> 
#> Tag Action Breakdown (273 tags):
#>   U: 19 | X: 234 | Z: 20

# Longitudinal research with safe private tags and Singapore HIB + HIPAA
prof_multi <- dicom_deid_profile(
  options = c("retain_longitudinal_modified_dates", "retain_safe_private"),
  jurisdictions = c("sg_pdpa_hib", "hipaa_safe_harbor")
)

# Operational mode (patient identity retained intact)
prof_ops <- dicom_deid_profile(patient_deid = FALSE)
```
