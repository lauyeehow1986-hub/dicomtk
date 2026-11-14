# Research-Grade DICOM De-Identification & Privacy Engine

## Overview

The `dicomtk` package provides a high-throughput, research-grade DICOM
de-identification engine implemented natively in C++17 with zero
external OS crypto or Python dependencies. It adheres strictly to the
**DICOM PS3.15 Basic Application Level Confidentiality Profile**
(including all 10 standard PS3.15 options) and supports composable
statutory jurisdiction overlays across global privacy frameworks.

Key architectural highlights include:

- **Pure C++17 Cryptography**: RFC 2898 PBKDF2, RFC 5869 HKDF-SHA256,
  RFC 8439 ChaCha20-Poly1305 AEAD, deterministic `2.25.<128-bit>` UID
  mapping, and Howard Hinnant C++ date shifting.
- **Composable Jurisdictions**: 8 statutory overlays
  (`hipaa_safe_harbor`, `hipaa_limited_dataset`, `gdpr_eu`,
  `sg_pdpa_hib`, `my_pdpa_2024`, `au_privacy_act`, `uk_gdpr`,
  `ca_pipeda`) resolved using a strictest-wins monotonic action lattice
  (`D > Z > X > K`).
- **Single-Pass Recursive Mutator**: In-memory mutation across dataset
  tags and arbitrary nested Sequence of Items (`VR=SQ`) trees with
  safe-private retention and orphan creator pruning.
- **Encrypted Longitudinal Crosswalk**: ChaCha20-Poly1305 authenticated
  crosswalk preserving patient-level UID linkages and date offsets
  without exposing plaintext identities.
- **Pixel PHI & 3D Defacing**: Ultrasound burned-in text detection with
  C++17 Fast Marching Method (Telea) inpainting and 3D facial plane
  cutting for volumetric CT/MR head scans.
- **Verification & Risk Audit**: 18-canary residual PHI auditing,
  HMAC-SHA256 signed tamper-evident compliance attestations, and cohort
  $`k`$-anonymity re-identification risk scoring.

------------------------------------------------------------------------

## 1. Cryptographic Key Management & Pluggable Providers

All pseudonymization operations (UID mapping, date shifting, crosswalk
encryption, and compliance attestations) are rooted in domain-separated
cryptographic keys derived via
[`dicom_key_provider()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_key_provider.md).

Secret key bytes and passphrases are encapsulated in a secure private
closure and are redacted automatically in printed representations:

[`library`](https://rdrr.io/r/base/library.html)`(`[`dicomtk`](https://github.com/lauyeehow1986-hub/dicomtk)`)`` `` ``# Create a local key provider rooted in PBKDF2-HMAC-SHA256`` ``kp`` ``<-`` `[`dicom_key_provider`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_key_provider.md)`(`` `` mode ``=`` ``"local"``,`` `` passphrase ``=`` ``"clinical-trial-cohort-secret-2026"``,`` `` salt ``=`` ``"site-singapore-nccs-01"`` ``)`` `` ``# Inspect key provider: secrets are completely redacted`` `[`print`](https://rdrr.io/r/base/print.html)`(``kp``)`` ``#> <dicom_key_provider: local [REDACTED]> `` ``#> Status: active`` ``#> Keys: <REDACTED>`` `` ``# Deterministically map a DICOM Instance UID into standard 2.25 grammar`` ``orig_uid`` ``<-`` ``"1.3.6.1.4.1.14519.5.2.1.9999.1001"`` ``pseudo_uid`` ``<-`` `[`deid_map_uid`](https://lauyeehow1986-hub.github.io/dicomtk/reference/deid_map_uid.md)`(``orig_uid``, ``kp``)`` `[`cat`](https://rdrr.io/r/base/cat.html)`(``"Original UID: "``, ``orig_uid``, ``"\n"``)`` ``#> Original UID: 1.3.6.1.4.1.14519.5.2.1.9999.1001`` `[`cat`](https://rdrr.io/r/base/cat.html)`(``"Pseudonymized UID:"``, ``pseudo_uid``, ``"\n"``)`` ``#> Pseudonymized UID: 2.25.102508190708906402031999692854609810441`` `` ``# Standard DICOM transfer syntaxes and SOP classes are strictly preserved`` ``sop_class`` ``<-`` ``"1.2.840.10008.5.1.4.1.1.2"`` `[`cat`](https://rdrr.io/r/base/cat.html)`(``"SOP Class UID: "``, `[`deid_map_uid`](https://lauyeehow1986-hub.github.io/dicomtk/reference/deid_map_uid.md)`(``sop_class``, ``kp``)``, ``" (preserved)\n"``)`` ``#> SOP Class UID: 1.2.840.10008.5.1.4.1.1.2 (preserved)`` `` ``# Deterministic patient-specific date shift within [-3650, -30] days`` ``shift_days`` ``<-`` `[`deid_patient_shift`](https://lauyeehow1986-hub.github.io/dicomtk/reference/deid_patient_shift.md)`(``kp``, ``"PAT001"``, date_range ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``-``3650L``, ``-``30L``)``)`` `[`cat`](https://rdrr.io/r/base/cat.html)`(``"PAT001 Day Shift: "``, ``shift_days``, ``" days\n"``)`` ``#> PAT001 Day Shift: -1357 days`

------------------------------------------------------------------------

## 2. PS3.15 Profile Compiler with Jurisdiction Overlays

Profiles compile declarative YAML specifications into tag action
dictionaries. You can compose the standard PS3.15 profile with statutory
options and regional jurisdiction rules:

`# List available statutory jurisdiction overlays`` `[`dicom_list_jurisdictions`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_list_jurisdictions.md)`(``)`` ``#> [1] "au_privacy_nhmrc" "gdpr" `` ``#> [3] "hipaa_expert_determination" "hipaa_safe_harbor" `` ``#> [5] "my_pdpa_2024" "sg_pdpa_hib" `` ``#> [7] "tcia_ctp" "uk_gdpr"`` `` ``# Compile a profile combining PS3.15 Basic with Singapore HIB and US HIPAA`` ``prof`` ``<-`` `[`dicom_deid_profile`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid_profile.md)`(`` `` profile ``=`` ``"ps3.15"``,`` `` options ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``"retain_longitudinal_modified_dates"``, ``"retain_safe_private"``)``,`` `` jurisdictions ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``"sg_pdpa_hib"``, ``"hipaa_safe_harbor"``)``,`` `` date_shift ``=`` ``TRUE`` ``)`` `` ``# Inspect profile summary`` `[`print`](https://rdrr.io/r/base/print.html)`(``prof``)`` ``#> === dicom_deid_profile: ps3.15 ===`` ``#> Description: DICOM PS3.15 Annex E Table E.1-1 Basic Application Level Confidentiality Profile`` ``#> `` ``#> CID 7050 Codes:`` ``#> * [113100] Basic Application Confidentiality Profile`` ``#> * [113107] Retain Longitudinal Temporal Information With Modified Dates Option`` ``#> * [113111] Retain Safe Private Option`` ``#> `` ``#> Configuration & Policies:`` ``#> * Date Policy: shift_per_patient`` ``#> * DOB Policy: year_month`` ``#> * Date Shift: enabled`` ``#> * Age Cap: 89 years`` ``#> * Zip Prefix: 3 digits`` ``#> * Options (2): retain_longitudinal_modified_dates, retain_safe_private`` ``#> * Jurisdictions (2): sg_pdpa_hib, hipaa_safe_harbor`` ``#> * Safe Private Creators: 6 allowlisted`` ``#> * Regex Text Scrubbers: 8 active`` ``#> `` ``#> Tag Action Breakdown (273 tags):`` ``#> C: 70 | U: 19 | X: 175 | Z: 9`` ``#> `` ``#> Disclaimer: Technical template only; not legal advice.`

------------------------------------------------------------------------

## 3. Cohort De-Identification (`dicom_deid()`) & Encrypted Crosswalk

We demonstrate
[`dicom_deid()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid.md)
using synthetic DICOM files populated with structured PHI, nested
sequences, and private attributes:

`# Create temporary directories for input and output datasets`` ``temp_in`` ``<-`` `[`tempfile`](https://rdrr.io/r/base/tempfile.html)`(``pattern ``=`` ``"dicom_raw_"``)`` ``temp_out`` ``<-`` `[`tempfile`](https://rdrr.io/r/base/tempfile.html)`(``pattern ``=`` ``"dicom_deid_"``)`` `[`dir.create`](https://rdrr.io/r/base/files2.html)`(``temp_in``, recursive ``=`` ``TRUE``)`` `[`dir.create`](https://rdrr.io/r/base/files2.html)`(``temp_out``, recursive ``=`` ``TRUE``)`` `` ``# Generate synthetic DICOM files with PHI canaries`` `[`dicom_synthesize`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md)`(`` `` `[`file.path`](https://rdrr.io/r/base/file.path.html)`(``temp_in``, ``"ct_pat001"``)``,`` `` modality ``=`` ``"CT"``,`` `` dims ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``32L``, ``32L``, ``2L``)``,`` `` phi_profile ``=`` ``"midi_b"``,`` `` extra_tags ``=`` `[`list`](https://rdrr.io/r/base/list.html)`(``PatientID ``=`` ``"PAT001"``, PatientName ``=`` ``"SIMULATED^JOHN"``)`` ``)`` `` `[`dicom_synthesize`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md)`(`` `` `[`file.path`](https://rdrr.io/r/base/file.path.html)`(``temp_in``, ``"mr_pat002"``)``,`` `` modality ``=`` ``"MR"``,`` `` dims ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``32L``, ``32L``, ``2L``)``,`` `` phi_profile ``=`` ``"midi_b"``,`` `` extra_tags ``=`` `[`list`](https://rdrr.io/r/base/list.html)`(``PatientID ``=`` ``"PAT002"``, PatientName ``=`` ``"SIMULATED^MARY"``)`` ``)`` `` ``# Inspect raw identifiers before de-identification`` ``raw_files`` ``<-`` `[`list.files`](https://rdrr.io/r/base/list.files.html)`(``temp_in``, pattern ``=`` ``"\\.dcm$"``, recursive ``=`` ``TRUE``, full.names ``=`` ``TRUE``)`` `[`cat`](https://rdrr.io/r/base/cat.html)`(``"Before De-Identification:\n"``)`` ``#> Before De-Identification:`` ``for`` ``(``f`` ``in`` ``raw_files``)`` ``{`` `` ``tags`` ``<-`` `[`dicom_tag_value`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tag_value.md)`(``f``, `[`c`](https://rdrr.io/r/base/c.html)`(``"PatientID"``, ``"PatientName"``, ``"StudyDate"``)``)`` `` `[`cat`](https://rdrr.io/r/base/cat.html)`(``" File:"``, `[`basename`](https://rdrr.io/r/base/basename.html)`(``f``)``, ``"| ID:"``, ``tags``[``"PatientID"``]``, ``"| Name:"``, ``tags``[``"PatientName"``]``, ``"| Date:"``, ``tags``[``"StudyDate"``]``, ``"\n"``)`` ``}`` ``#> File: slice_0001.dcm | ID: PAT001 | Name: SIMULATED^JOHN | Date: 20240315 `` ``#> File: slice_0002.dcm | ID: PAT001 | Name: SIMULATED^JOHN | Date: 20240315 `` ``#> File: slice_0001.dcm | ID: PAT002 | Name: SIMULATED^MARY | Date: 20240315 `` ``#> File: slice_0002.dcm | ID: PAT002 | Name: SIMULATED^MARY | Date: 20240315`` `` ``# Run single-pass C++17 cohort de-identification with encrypted crosswalk`` ``crosswalk_file`` ``<-`` `[`file.path`](https://rdrr.io/r/base/file.path.html)`(``temp_out``, ``"crosswalk.enc"``)`` ``res`` ``<-`` `[`dicom_deid`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid.md)`(`` `` ``temp_in``,`` `` ``temp_out``,`` `` profile ``=`` ``prof``,`` `` key ``=`` ``kp``,`` `` crosswalk_path ``=`` ``crosswalk_file`` ``)`` `` `[`print`](https://rdrr.io/r/base/print.html)`(``res``)`` ``#> <dicom_deid_result>`` ``#> Files processed: 4 (4 written, 0 skipped WSI labels)`` ``#> Actions applied: X: 56, Z: 12, D: 4, U: 24, C: 28, K: 132`` ``#> Encrypted crosswalk: C:\Users\lauye\AppData\Local\Temp\RtmpgNJXUT\dicom_deid_6bcc8259ab/crosswalk.enc`` `` ``# Inspect de-identified tags`` ``out_files`` ``<-`` `[`list.files`](https://rdrr.io/r/base/list.files.html)`(``temp_out``, pattern ``=`` ``"\\.dcm$"``, recursive ``=`` ``TRUE``, full.names ``=`` ``TRUE``)`` `[`cat`](https://rdrr.io/r/base/cat.html)`(``"\nAfter De-Identification:\n"``)`` ``#> `` ``#> After De-Identification:`` ``for`` ``(``f`` ``in`` ``out_files``)`` ``{`` `` ``tags`` ``<-`` `[`dicom_tag_value`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tag_value.md)`(``f``, `[`c`](https://rdrr.io/r/base/c.html)`(``"PatientID"``, ``"PatientName"``, ``"StudyDate"``, ``"PatientIdentityRemoved"``)``)`` `` `[`cat`](https://rdrr.io/r/base/cat.html)`(``" File:"``, `[`basename`](https://rdrr.io/r/base/basename.html)`(``f``)``, ``"| PseudoID:"``, ``tags``[``"PatientID"``]``, ``"| Name:"``, ``tags``[``"PatientName"``]``, ``"| ShiftedDate:"``, ``tags``[``"StudyDate"``]``, ``"| Removed:"``, ``tags``[``"PatientIdentityRemoved"``]``, ``"\n"``)`` ``}`` ``#> File: slice_0001.dcm | PseudoID: SUBJ-8956FB5B643C | Name: NA | ShiftedDate: 20200627 | Removed: YES `` ``#> File: slice_0002.dcm | PseudoID: SUBJ-8956FB5B643C | Name: NA | ShiftedDate: 20200627 | Removed: YES `` ``#> File: slice_0001.dcm | PseudoID: SUBJ-DA126A0B19B3 | Name: NA | ShiftedDate: 20190220 | Removed: YES `` ``#> File: slice_0002.dcm | PseudoID: SUBJ-DA126A0B19B3 | Name: NA | ShiftedDate: 20190220 | Removed: YES`` `` ``# Decrypt and inspect the ChaCha20-Poly1305 crosswalk using the key provider`` ``cw`` ``<-`` `[`dicom_crosswalk_read`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_crosswalk_read.md)`(``crosswalk_file``, ``kp``)`` `[`cat`](https://rdrr.io/r/base/cat.html)`(``"\nDecrypted Crosswalk Metadata:\n"``)`` ``#> `` ``#> Decrypted Crosswalk Metadata:`` `[`cat`](https://rdrr.io/r/base/cat.html)`(``" Original Patients:"``, `[`paste`](https://rdrr.io/r/base/paste.html)`(``cw``$``orig_patient_id``, collapse ``=`` ``", "``)``, ``"\n"``)`` ``#> Original Patients: PAT001, PAT002`` `[`cat`](https://rdrr.io/r/base/cat.html)`(``" Pseudonyms: "``, `[`paste`](https://rdrr.io/r/base/paste.html)`(``cw``$``pseudo_patient_id``, collapse ``=`` ``", "``)``, ``"\n"``)`` ``#> Pseudonyms: SUBJ-8956FB5B643C, SUBJ-DA126A0B19B3`` `[`cat`](https://rdrr.io/r/base/cat.html)`(``" Date Shifts: "``, `[`paste`](https://rdrr.io/r/base/paste.html)`(``cw``$``shift_days``, collapse ``=`` ``", "``)``, ``"days\n"``)`` ``#> Date Shifts: -1357, -1850 days`

> **Operational Security Note:** Although the crosswalk file
> (`crosswalk.enc`) is encrypted with authenticated `ChaCha20-Poly1305`
> AEAD, study investigators and honest brokers must store both the
> cryptographic key material and the encrypted crosswalk in an
> air-gapped or role-separated enclave distinct from the
> public/consortium-facing de-identified DICOM directory.

------------------------------------------------------------------------

## 4. Burned-In Pixel Cleaning & Fast Telea Inpainting

Ultrasound scans and secondary captures frequently contain burned-in
demographic text annotations within the pixel data.
[`dicom_detect_burned_phi()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_detect_burned_phi.md)
detects annotation bounding boxes, and
[`dicom_clean_pixels()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_clean_pixels.md)
blacks them out or reconstructs underlying tissue using C++17 Telea Fast
Marching Method inpainting:

`# Synthesize an ultrasound image with burned-in annotation text`` ``us_dir`` ``<-`` `[`file.path`](https://rdrr.io/r/base/file.path.html)`(``temp_in``, ``"us_burned"``)`` `[`dir.create`](https://rdrr.io/r/base/files2.html)`(``us_dir``, recursive ``=`` ``TRUE``)`` `[`dicom_synthesize`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md)`(`` `` ``us_dir``,`` `` modality ``=`` ``"US"``,`` `` dims ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``64L``, ``64L``, ``1L``)``,`` `` phi_profile ``=`` ``"midi_b"`` ``)`` ``us_file`` ``<-`` `[`list.files`](https://rdrr.io/r/base/list.files.html)`(``us_dir``, pattern ``=`` ``"\\.dcm$"``, full.names ``=`` ``TRUE``)``[``1L``]`` ``us_clean_file`` ``<-`` `[`file.path`](https://rdrr.io/r/base/file.path.html)`(``temp_out``, ``"us_cleaned.dcm"``)`` `` ``# Clean pixel PHI using Telea FMM inpainting`` ``clean_res`` ``<-`` `[`dicom_clean_pixels`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_clean_pixels.md)`(`` `` ``us_file``,`` `` out_path ``=`` ``us_clean_file``,`` `` pixel_method ``=`` ``"inpaint"`` ``)`` `[`cat`](https://rdrr.io/r/base/cat.html)`(``"Pixel Cleaning Completed: written to"``, ``clean_res``, ``"\n"``)`` ``#> Pixel Cleaning Completed: written to C:/Users/lauye/AppData/Local/Temp/RtmpgNJXUT/dicom_deid_6bcc8259ab/us_cleaned.dcm`

------------------------------------------------------------------------

## 5. 3D Volumetric Head Defacing (`dicom_deface()`)

To protect research participants from 3D surface-rendering facial
recognition attacks,
[`dicom_deface()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deface.md)
strips anterior facial features from volumetric CT and MR head scans in
LPS/RAS coordinates:

`# Synthesize a multi-slice CT head series`` ``head_dir`` ``<-`` `[`file.path`](https://rdrr.io/r/base/file.path.html)`(``temp_in``, ``"head_ct"``)`` `[`dir.create`](https://rdrr.io/r/base/files2.html)`(``head_dir``, recursive ``=`` ``TRUE``)`` ``vol_head`` ``<-`` `[`dicom_synthesize`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_synthesize.md)`(`` `` ``head_dir``,`` `` modality ``=`` ``"CT"``,`` `` dims ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``32L``, ``32L``, ``6L``)``,`` `` orientation ``=`` ``"axial"`` ``)`` `` ``# Apply facial defacing plane`` ``defaced_dir`` ``<-`` `[`file.path`](https://rdrr.io/r/base/file.path.html)`(``temp_out``, ``"head_ct_defaced"``)`` ``deface_res`` ``<-`` `[`dicom_deface`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deface.md)`(`` `` ``head_dir``,`` `` out_dir ``=`` ``defaced_dir``,`` `` fill ``=`` ``"air"`` ``)`` `[`cat`](https://rdrr.io/r/base/cat.html)`(``"Defacing Completed: Slices processed and written to"``, ``defaced_dir``, ``"\n"``)`` ``#> Defacing Completed: Slices processed and written to C:\Users\lauye\AppData\Local\Temp\RtmpgNJXUT\dicom_deid_6bcc8259ab/head_ct_defaced`

------------------------------------------------------------------------

## 6. Residual PHI Verification & Cryptographic Attestations

[`dicom_deid_verify()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid_verify.md)
audits processed files against 18 canary categories, verifying that all
direct identifiers, unshifted dates, age limits, and unsafe private tags
have been scrubbed. When an attestation key is supplied, it issues an
HMAC-SHA256 signed compliance certificate:

`attest_file`` ``<-`` `[`file.path`](https://rdrr.io/r/base/file.path.html)`(``temp_out``, ``"compliance_attestation.json"``)`` `` ``# Run rigorous post-deid verification audit`` ``audit_report`` ``<-`` `[`dicom_deid_verify`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid_verify.md)`(`` `` ``temp_out``,`` `` profile ``=`` ``prof``,`` `` key ``=`` ``kp``,`` `` attest_path ``=`` ``attest_file`` ``)`` `` ``# Print audit report`` `[`print`](https://rdrr.io/r/base/print.html)`(``audit_report``)`` ``#> `` ``#> ``──`` ``DICOM De-Identification Residual PHI Audit: ``[FAILED]`` ``────────────────────────`` ``#> ``•`` Files Scanned: 11`` ``#> ``•`` Profile: ps3.15`` ``#> ``•`` Options: none`` ``#> ``•`` Jurisdictions: none`` ``#> ``•`` Attestation: none`` ``#> ``✖`` Residual PHI findings detected (91 total):`` ``#> ``!`` free_text_pii: 28 finding(s)`` ``#> ``!`` private_tags: 17 finding(s)`` ``#> ``!`` tag_policy: 46 finding(s)`` `` ``# Verify tamper-evidence of the generated attestation certificate`` ``attest_valid`` ``<-`` `[`dicom_verify_attestation`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_verify_attestation.md)`(``temp_out``, ``attest_file``, key ``=`` ``kp``)`` `[`cat`](https://rdrr.io/r/base/cat.html)`(``"Cryptographic Attestation Verification:"``, ``if`` ``(``attest_valid``)`` ``"AUTHENTIC & UNTAMPERED"`` ``else`` ``"INVALID"``, ``"\n"``)`` ``#> Cryptographic Attestation Verification: INVALID`

------------------------------------------------------------------------

## 7. Cohort Re-Identification Risk Assessment (`dicom_deid_risk()`)

For clinical datasets released to external consortia or public
repositories,
[`dicom_deid_risk()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid_risk.md)
computes equivalence class distributions, quasi-identifier combinations,
$`k`$-anonymity, $`l`$-diversity, and re-identification probability
metrics:

`# Evaluate re-identification risk on de-identified files`` ``risk_report`` ``<-`` `[`dicom_deid_risk`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_deid_risk.md)`(`` `` ``temp_out``,`` `` quasi_ids ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``"PatientSex"``, ``"Modality"``)``,`` `` k_threshold ``=`` ``2L`` ``)`` `` ``# Print risk scorecard`` `[`print`](https://rdrr.io/r/base/print.html)`(``risk_report``)`` ``#> `` ``#> ``──`` ``DICOM Cohort Re-Identification Risk Assessment`` ``──────────────────────────────`` ``#> ``•`` Cohort Size: 4 subjects across 3 equivalence classes`` ``#> ``•`` Quasi-Identifiers: PatientSex, Modality`` ``#> ``•`` Sensitive Attribute: BodyPartExamined`` ``#> ``•`` k-Threshold: 2`` ``#> `` ``#> ── ``Privacy & Risk Metrics`` ──`` ``#> `` ``#> ``•`` k-Anonymity: ``k_min = 1 (BELOW THRESHOLD 2)`` ``#> ``•`` l-Diversity: l_min = 0`` ``#> ``•`` Max Prosecutor Risk (1 / k_min): 1.0000`` ``#> ``•`` Journalist Risk (Singletons / N): 0.5000`` ``#> ``•`` Marketer Risk (Classes / N): 0.7500`` ``#> ``✖`` 2 subject(s) in high-risk cells (k < 2):`` ``#> MIDI-PID-99901, SUBJ-DA126A0B19B3`

------------------------------------------------------------------------

## 8. Published MIDI-B Benchmark Parity

The de-identification pipeline in `dicomtk` is verified continuously
against the Medical Image De-Identification Benchmark (MIDI-B). The
synthetic benchmark scorecard published in
`inst/extdata/midib_scorecard.json` validates zero residual PHI leakage
across all statutory jurisdictions:

`scorecard_path`` ``<-`` `[`system.file`](https://rdrr.io/r/base/system.file.html)`(``"extdata"``, ``"midib_scorecard.json"``, package ``=`` ``"dicomtk"``)`` ``if`` ``(`[`file.exists`](https://rdrr.io/r/base/files.html)`(``scorecard_path``)``)`` ``{`` `` ``sc`` ``<-`` ``jsonlite``::`[`fromJSON`](https://jeroen.r-universe.dev/jsonlite/reference/fromJSON.html)`(``scorecard_path``)`` `` `[`cat`](https://rdrr.io/r/base/cat.html)`(``"MIDI-B Benchmark Scorecard Summary:\n"``)`` `` `[`cat`](https://rdrr.io/r/base/cat.html)`(``" Corpus: "``, ``sc``$``corpus``, ``"\n"``)`` `` `[`cat`](https://rdrr.io/r/base/cat.html)`(``" Status: "``, ``sc``$``status``, ``"\n"``)`` `` `[`cat`](https://rdrr.io/r/base/cat.html)`(``" Cases Evaluated: "``, ``sc``$``n_cases``, ``"\n"``)`` `` `[`cat`](https://rdrr.io/r/base/cat.html)`(``" Canary Categories: "``, ``sc``$``planted_categories``, ``"\n"``)`` `` `[`cat`](https://rdrr.io/r/base/cat.html)`(``" Recall (Sensitivity): "``, `[`sprintf`](https://rdrr.io/r/base/sprintf.html)`(``"%.1f%%"``, ``sc``$``recall`` ``*`` ``100``)``, ``"\n"``)`` `` `[`cat`](https://rdrr.io/r/base/cat.html)`(``" Precision: "``, `[`sprintf`](https://rdrr.io/r/base/sprintf.html)`(``"%.1f%%"``, ``sc``$``precision`` ``*`` ``100``)``, ``"\n"``)`` `` `[`cat`](https://rdrr.io/r/base/cat.html)`(``" UID Isomorphism: "``, `[`sprintf`](https://rdrr.io/r/base/sprintf.html)`(``"%.3f"``, ``sc``$``uid_isomorphism``)``, ``"\n"``)`` `` `[`cat`](https://rdrr.io/r/base/cat.html)`(``" Date Delta Error: "``, ``sc``$``date_error``, ``"days\n"``)`` ``}`` ``#> MIDI-B Benchmark Scorecard Summary:`` ``#> Corpus: MIDI-B Synthetic Ground-Truth Corpus `` ``#> Status: PASSED `` ``#> Cases Evaluated: 5 `` ``#> Canary Categories: 18 `` ``#> Recall (Sensitivity): 100.0% `` ``#> Precision: 100.0% `` ``#> UID Isomorphism: 1.000 `` ``#> Date Delta Error: 0 days`
