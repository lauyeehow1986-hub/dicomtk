# PACS Networking & DICOM Query/Retrieve

## Overview

`dicomtk` provides a tidyverse-friendly interface to DICOM networking
(`dcmnet`, `dcmqrdb`, `dcmwlm`, `dcmtls`): -
[`dicom_connect()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_connect.md):
Configure a remote DIMSE PACS peer, DICOMweb REST endpoint, or local
PACS storage directory. -
[`dicom_tls_config()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_tls_config.md):
Configure BCP 195 TLS transport security (`dcmtls`). -
[`dicom_echo()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_echo.md):
Verify connectivity via DICOM Upper Layer `A-ASSOCIATE-RQ` +
`C-ECHO-RQ`. -
[`dicom_find()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_find.md):
Query studies, series, or instances as a tidy `tibble`. -
[`dicom_get()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_get.md):
Retrieve matched DICOM files into a local directory. -
[`dicom_send()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_send.md)
/
[`dicom_receive()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_receive.md):
Store and receive DICOM objects (`C-STORE`). -
[`dicom_qrdb_index()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_qrdb_index.md)
&
[`dicom_worklist()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_worklist.md):
Local index database (`dcmqrdb`) and Modality Worklist (`dcmwlm`).

[`library`](https://rdrr.io/r/base/library.html)`(`[`dicomtk`](https://github.com/lauyeehow1986-hub/dicomtk)`)`` `[`library`](https://rdrr.io/r/base/library.html)`(`[`dplyr`](https://dplyr.tidyverse.org)`)`` ``#> `` ``#> Attaching package: 'dplyr'`` ``#> The following objects are masked from 'package:stats':`` ``#> `` ``#> filter, lag`` ``#> The following objects are masked from 'package:base':`` ``#> `` ``#> intersect, setdiff, setequal, union`` `` ``dcm_file`` ``<-`` `[`system.file`](https://rdrr.io/r/base/system.file.html)`(``"extdata"``, ``"example.dcm"``, package ``=`` ``"dicomtk"``)`` `` ``# 1. Start a local PACS storage receiver (SCP directory)`` ``pacs_dir`` ``<-`` `[`tempfile`](https://rdrr.io/r/base/tempfile.html)`(``"local_pacs_"``)`` ``conn`` ``<-`` `[`dicom_receive`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_receive.md)`(``pacs_dir``, port ``=`` ``11112``, aetitle ``=`` ``"DICOMTK-SCP"``)`` ``conn`` ``#> ``ℹ`` DICOM Connection: DICOMTK-SCP -> DICOMTK-SCP@127.0.0.1:11112`` ``#> ``ℹ`` Local PACS directory: C:\Users\lauye\AppData\Local\Temp\RtmpOw6Eyu\local_pacs_56b44b6c70b`` `` ``# 2. Verify PACS connectivity`` `[`dicom_echo`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_echo.md)`(``conn``)`` ``#> ``# A tibble: 1 × 7`` ``#> host port called_ae success status message elapsed_ms`` ``#> ``<chr>`` ``<int>`` ``<chr>`` ``<lgl>`` ``<chr>`` ``<chr>`` ``<dbl>`` ``#> ``1`` 127.0.0.1 ``11``112 DICOMTK-SCP TRUE SUCCESS_LOCAL ``"``Local DICOM rep… 0.1`` `` ``# 3. Send DICOM file(s) to the PACS peer (C-STORE)`` `[`dicom_send`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_send.md)`(``dcm_file``, ``conn``)`` ``#> ``# A tibble: 1 × 4`` ``#> file destination success status`` ``#> ``<chr>`` ``<chr>`` ``<lgl>`` ``<chr>`` `` ``#> ``1`` ``"``C:\\Users\\lauye\\AppData\\Local\\Temp\\RtmpeuFNW… ``"``C:\\Users… TRUE STORE…`` `` ``# 4. Query PACS studies with tidyverse piping and retrieve matching files`` ``retrieved_files`` ``<-`` ``conn`` ``|>`` `` `[`dicom_find`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_find.md)`(``level ``=`` ``"STUDY"``)`` ``|>`` `` `[`dicom_get`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_get.md)`(``)`` `` ``retrieved_files`` ``#> [1] "C:\\Users\\lauye\\AppData\\Local\\Temp\\RtmpOw6Eyu\\dicom_get_56b4100c635a\\example.dcm"`` `` ``# 5. Build a local dcmqrdb index table`` `[`dicom_qrdb_index`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_qrdb_index.md)`(``pacs_dir``)`` ``|>`` `` `[`select`](https://dplyr.tidyverse.org/reference/select.html)`(``PatientID``, ``Modality``, ``Rows``, ``Columns``)`` ``#> ``# A tibble: 1 × 4`` ``#> PatientID Modality Rows Columns`` ``#> ``<chr>`` ``<chr>`` ``<chr>`` ``<chr>`` `` ``#> ``1`` 98890234 CT 512 512`
