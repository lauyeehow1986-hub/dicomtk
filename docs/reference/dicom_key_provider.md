# Pluggable Cryptographic Key Provider for DICOM De-Identification

Manages cryptographic master keys, password-based key derivation
(PBKDF2), domain-separated subkey expansion (HKDF-SHA256), and pluggable
enterprise key broker/trusted-third-party (TTP) resolution.

## Usage

``` r
dicom_key_provider(
  mode = c("local", "broker", "ttp"),
  key = NULL,
  passphrase = NULL,
  salt = NULL,
  keyfile = NULL,
  resolver_fn = NULL
)
```

## Arguments

- mode:

  Character string specifying key management mode: `"local"` for local
  key derivation via PBKDF2/HKDF, `"broker"` for an enterprise
  cryptographic key broker callback, `"ttp"` for a trusted third party
  pseudonym resolution service.

- key:

  Optional 32-byte raw vector containing a pre-shared master key.

- passphrase:

  Optional character string or raw vector containing a passphrase used
  to derive the master key via PBKDF2-HMAC-SHA256.

- salt:

  Optional character string or raw vector containing salt for PBKDF2.
  Defaults to an internal versioned salt if omitted.

- keyfile:

  Optional file path pointing to a binary file containing the 32-byte
  key.

- resolver_fn:

  Optional function callback used when `mode` is `"broker"` or `"ttp"`.
  Must accept a domain name string and return raw key bytes.

## Value

An S3 object of class `dicom_key_provider`.

## Details

Subkeys are stored in a private environment closure to ensure that
secret key bytes and passphrases are never leaked through
[`print()`](https://rdrr.io/r/base/print.html),
[`format()`](https://rdrr.io/r/base/format.html), or
[`str()`](https://rdrr.io/r/utils/str.html).

## Examples

``` r
kp <- dicom_key_provider(passphrase = "clinical-trial-secret", salt = "site-001")
is_dicom_key_provider(kp)
#> [1] TRUE
print(kp)
#> <dicom_key_provider: local [REDACTED]> 
#>   Status: active
#>   Keys:   <REDACTED>
```
