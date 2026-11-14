# Verify De-Identification Residual PHI and Generate Cryptographic Attestation

Scans DICOM files across four forensic surfaces (tag policy violations,
unallowlisted private tags, free-text/structured report PII
regexes/canaries, and pixel/WSI artifacts) to verify complete residual
PHI elimination. Optionally emits and signs a canonical JSON
cryptographic attestation with HMAC-SHA256 or X.509 PKI signatures.

## Usage

``` r
dicom_deid_verify(
  path,
  profile = "ps3.15",
  options = character(0),
  jurisdictions = NULL,
  canaries = character(0),
  attest_path = NULL,
  key = NULL,
  cert = NULL,
  private_key = NULL,
  allowed_private_tags = NULL
)
```

## Arguments

- path:

  Character vector of one or more DICOM file paths, or a directory path.

- profile:

  Character string identifying the base profile, or a compiled
  `dicom_deid_profile` object. Default is `"ps3.15"`.

- options:

  Character vector of standard PS3.15 options enabled during
  de-identification.

- jurisdictions:

  Optional character vector of statutory jurisdiction overlays.

- canaries:

  Character vector of user-supplied canary strings or identifiers to
  detect.

- attest_path:

  Optional file path where the signed JSON attestation will be saved.

- key:

  Optional `dicom_key_provider` or 32-byte raw key used for HMAC-SHA256
  attestation signing.

- cert:

  Optional public certificate or public key object for PKI verification.

- private_key:

  Optional private key object (e.g. from
  [`openssl::rsa_keygen`](https://jeroen.r-universe.dev/openssl/reference/keygen.html))
  for PKI signing.

- allowed_private_tags:

  Optional list or character vector of allowlisted private tags or
  creators.

## Value

An S3 object of class `"dicom_deid_report"` containing:

- passed:

  Logical scalar. `TRUE` if zero findings were detected, `FALSE`
  otherwise.

- findings:

  A tibble of detected residual PHI violations with columns `file`,
  `surface`, `tag`, `keyword`, `value`, and `rule`.

- files_scanned:

  Integer count of scanned files.

- profile:

  Profile identifier.

- options:

  Active confidentiality options.

- jurisdictions:

  Active jurisdictions.

- attest_path:

  Path to generated attestation file, or `NULL`.

## Examples

``` r
if (FALSE) { # \dontrun{
v <- dicom_deid_verify("path/to/clean_dir", canaries = "TAN^AH^KOW")
if (!v$passed) print(v$findings)
} # }
```
