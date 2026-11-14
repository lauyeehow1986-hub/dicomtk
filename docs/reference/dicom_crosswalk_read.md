# Read and Decrypt a DICOM De-Identification Crosswalk

Reads and decrypts a ChaCha20-Poly1305 encrypted crosswalk file produced
by
[`dicom_deid`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid.md).

## Usage

``` r
dicom_crosswalk_read(path, key)
```

## Arguments

- path:

  File path to the encrypted crosswalk file.

- key:

  A `dicom_key_provider` object or 32-byte raw vector.

## Value

A tibble with columns:

- orig_patient_id:

  Original PatientID.

- pseudo_patient_id:

  Pseudonymous PatientID.

- orig_study_uid:

  Original StudyInstanceUID.

- pseudo_study_uid:

  Pseudonymous StudyInstanceUID.

- shift_days:

  Integer number of days shifted for dates.

## Examples

``` r
if (FALSE) { # \dontrun{
kp <- dicom_key_provider(passphrase = "my-secret-passphrase")
cw <- dicom_crosswalk_read("path/to/crosswalk.enc", kp)
print(cw)
} # }
```
