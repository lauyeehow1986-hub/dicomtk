# Verify Cryptographic Attestation Manifest

Verifies the integrity and authenticity of a signed JSON attestation
manifest against a directory or cohort of de-identified DICOM files.

## Usage

``` r
dicom_verify_attestation(
  path,
  attest_path,
  key = NULL,
  cert = NULL,
  rsa_pubkey = cert
)
```

## Arguments

- path:

  Directory path containing the de-identified DICOM files.

- attest_path:

  File path to the JSON attestation manifest.

- key:

  Optional `dicom_key_provider` or raw key used to verify HMAC-SHA256
  signatures.

- cert:

  Optional public certificate, RSA/ECDSA public key, or raw cert for PKI
  verification.

- rsa_pubkey:

  Optional alias for `cert`.

## Value

Logical scalar. `TRUE` if all file hashes and the cryptographic
signature match; `FALSE` otherwise.

## Examples

``` r
if (FALSE) { # \dontrun{
kp <- dicom_key_provider(passphrase = "my-secret")
ok <- dicom_verify_attestation("path/to/clean", "attest.json", key = kp)
print(ok)
} # }
```
