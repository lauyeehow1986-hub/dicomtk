# De-Identify a DICOM File, Directory, or Cohort

De-identifies single DICOM files or entire cohorts according to DICOM
PS3.15 Annex E application-level confidentiality profiles and optional
statutory jurisdiction overlays (e.g. HIPAA Safe Harbor, Singapore
PDPA/HIB, GDPR). Provides deterministic pseudonymization, longitudinal
UID and date consistency, parallel execution via `mirai`, structured
JSONL audit logging, and ChaCha20-Poly1305 encrypted crosswalk
generation.

## Usage

``` r
dicom_deid(
  path,
  out_dir = NULL,
  profile = "ps3.15",
  options = character(0),
  jurisdictions = NULL,
  key = NULL,
  layout = c("preserve", "hierarchy", "flat"),
  workers = 1L,
  audit_path = NULL,
  crosswalk_path = NULL,
  override_tags = list(),
  drop_wsi_labels = TRUE,
  pixel_method = c("none", "blackout", "inpaint"),
  pixel_boxes = NULL,
  overwrite = FALSE
)
```

## Arguments

- path:

  Character vector of one or more DICOM file paths, or a directory path.

- out_dir:

  Output directory path. If `NULL`, a temporary directory is created.

- profile:

  Character string identifying the base profile, or a compiled
  `dicom_deid_profile` object. Default is `"ps3.15"`.

- options:

  Character vector of standard PS3.15 options to enable.

- jurisdictions:

  Optional character vector of statutory jurisdiction overlays.

- key:

  Optional `dicom_key_provider` object. If `NULL`, a local key provider
  is generated.

- layout:

  Character string specifying output directory layout:

  - `"preserve"` (default): Preserves relative subdirectory structure.

  - `"hierarchy"`: Formats as
    `<pseudo_pid>/<pseudo_study>/<pseudo_sop>.dcm`.

  - `"flat"`: Places all files directly in `out_dir` as
    `<pseudo_sop>.dcm`.

- workers:

  Integer number of parallel workers. When `workers > 1L` and the
  `mirai` package is available, files are processed concurrently.

- audit_path:

  Optional file path where structured JSONL audit records will be
  written.

- crosswalk_path:

  Optional file path where the AEAD-encrypted crosswalk will be saved.

- override_tags:

  Optional named list of tag-action overrides.

- drop_wsi_labels:

  Logical. Whether whole slide microscopy (WSI) label and overview
  instances should be skipped. Default is `TRUE`.

- pixel_method:

  Character string specifying pixel de-identification method: `"none"`
  (default), `"blackout"`, or `"inpaint"`. If `options` contains
  `"clean_pixel"` and `pixel_method == "none"`, defaults to
  `"blackout"`.

- pixel_boxes:

  Optional data frame or matrix with candidate pixel bounding boxes
  `(ymin, xmin, ymax, xmax)`.

- overwrite:

  Logical. Whether existing output files should be overwritten. Default
  is `FALSE`.

## Value

An object of class `"dicom_deid_result"` containing:

- files:

  Character vector of successfully written de-identified DICOM files.

- summary:

  Tibble summarizing input/output paths, digests, pseudonyms, and action
  counts.

- actions_total:

  Named integer vector of total tag actions applied.

- skipped_wsi_labels:

  Count of skipped WSI label/overview instances.

- audit_path:

  Path to audit JSONL file if requested, or `NULL`.

- crosswalk_path:

  Path to encrypted crosswalk file if requested, or `NULL`.

- profile:

  The resolved `dicom_deid_profile` object.

- jurisdictions:

  Character vector of active jurisdictions.

- key_provider:

  The `dicom_key_provider` used.

## Examples

``` r
if (FALSE) { # \dontrun{
kp <- dicom_key_provider(passphrase = "my-secret-passphrase")
res <- dicom_deid("path/to/dicom/dir", "path/to/out/dir", key = kp)
print(res)
} # }
```
