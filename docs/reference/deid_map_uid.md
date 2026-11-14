# Deterministically Map a DICOM UID

Maps a DICOM Unique Identifier (UID) using HMAC-SHA256 and prefix 2.25.
Standard DICOM UIDs starting with `"1.2.840.10008."` are preserved.

## Usage

``` r
deid_map_uid(uid, key_provider)
```

## Arguments

- uid:

  Character vector of DICOM UIDs to map.

- key_provider:

  A `dicom_key_provider` object.

## Value

Character vector of pseudonymized UIDs obeying the 64-character limit.

## Examples

``` r
kp <- dicom_key_provider(passphrase = "secret", salt = "salt")
deid_map_uid("1.2.840.10008.5.1.4.1.1.2", kp)
#> [1] "1.2.840.10008.5.1.4.1.1.2"
deid_map_uid("1.3.6.1.4.1.14519.5.2.1.9999.1001", kp)
#> [1] "2.25.33548892277815063878744394269943615908"
```
