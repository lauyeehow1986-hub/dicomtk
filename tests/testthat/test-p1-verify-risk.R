test_that("dicom_deid_verify() catches planted residual leaks across 4 surfaces and passes clean studies", {
  raw_dir <- tempfile(pattern = "raw_leak_")
  clean_dir <- tempfile(pattern = "clean_deid_")
  att_file <- tempfile(pattern = "attest_", fileext = ".json")
  dir.create(raw_dir, recursive = TRUE)
  on.exit(unlink(c(raw_dir, clean_dir, att_file), recursive = TRUE), add = TRUE)

  kp <- dicom_key_provider(passphrase = "super-secret-key-for-attestation", salt = "site-sg-01")

  # Synthesize a raw study containing planted residual leaks across all 4 surfaces:
  # 1. tag_policy: PatientName = "TAN^AH^KOW", PatientID = "PAT_RAW_001", non-2.25 instance UIDs
  # 2. private_tags: (0009,1001) = "SecretPrivateVendorTag"
  # 3. free_text_pii: ImageComments containing Singapore NRIC "S8012345D" and canary "TAN^AH^KOW"
  # 4. pixel_wsi: BurnedInAnnotation = "YES"
  px <- as.numeric(matrix(seq_len(16), 4, 4))
  raw_file <- file.path(raw_dir, "raw_study.dcm")

  ok <- dicomtk:::cpp_write_dicom_multiframe(
    pixels = px,
    dims = c(4L, 4L, 1L),
    out_path = raw_file,
    meta_tags = c(
      "Modality", "SOPClassUID", "PatientName", "PatientID",
      "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID",
      "StudyDate", "BurnedInAnnotation", "ImageComments", "(0009,1001)"
    ),
    meta_values = c(
      "CT", "1.2.840.10008.5.1.4.1.1.2", "TAN^AH^KOW", "PAT_RAW_001",
      "1.3.6.1.4.1.9999.1001", "1.3.6.1.4.1.9999.1001.1", "1.3.6.1.4.1.9999.1001.1.1",
      "20240115", "YES", "Subject S8012345D clinical follow-up", "SecretPrivateVendorTag"
    )
  )
  expect_true(ok)

  # Run verifier on raw study
  v_bad <- dicom_deid_verify(
    raw_dir,
    jurisdictions = "sg_pdpa_hib",
    canaries = "TAN^AH^KOW"
  )
  expect_false(v_bad$passed)
  expect_gt(nrow(v_bad$findings), 0L)
  expect_true("tag_policy" %in% v_bad$findings$surface)
  expect_true("private_tags" %in% v_bad$findings$surface)
  expect_true("free_text_pii" %in% v_bad$findings$surface)
  expect_true("pixel_wsi" %in% v_bad$findings$surface)

  # De-identify with options c("clean_descriptors", "clean_pixel") and sg_pdpa_hib
  res <- dicom_deid(
    raw_dir,
    clean_dir,
    options = c("clean_descriptors", "clean_pixel"),
    jurisdictions = "sg_pdpa_hib",
    key = kp
  )
  expect_gt(length(res$files), 0L)

  # Run verifier on de-identified output with attestation generation
  v_ok <- dicom_deid_verify(
    clean_dir,
    options = c("clean_descriptors", "clean_pixel"),
    jurisdictions = "sg_pdpa_hib",
    canaries = "TAN^AH^KOW",
    attest_path = att_file,
    key = kp
  )
  expect_true(v_ok$passed)
  expect_equal(nrow(v_ok$findings), 0L)
  expect_true(file.exists(att_file))
})

test_that("Signed Cryptographic Attestation Verification detects tampering", {
  in_dir <- tempfile(pattern = "att_test_in_")
  clean_dir <- tempfile(pattern = "att_test_out_")
  att_file <- tempfile(pattern = "attest_crypto_", fileext = ".json")
  dir.create(in_dir, recursive = TRUE)
  on.exit(unlink(c(in_dir, clean_dir, att_file), recursive = TRUE), add = TRUE)

  kp <- dicom_key_provider(passphrase = "tamper-proof-attestation-passphrase", salt = "salt-test-01")

  px <- as.numeric(matrix(1:16, 4, 4))
  f1 <- file.path(in_dir, "slice_01.dcm")
  f2 <- file.path(in_dir, "slice_02.dcm")

  dicomtk:::cpp_write_dicom_multiframe(
    pixels = px, dims = c(4L, 4L, 1L), out_path = f1,
    meta_tags = c("Modality", "SOPClassUID", "PatientName", "PatientID", "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID", "StudyDate"),
    meta_values = c("MR", "1.2.840.10008.5.1.4.1.1.4", "DOE^JOHN", "P01", "1.3.6.1.4.1.9999.1", "1.3.6.1.4.1.9999.1.1", "1.3.6.1.4.1.9999.1.1.1", "20240201")
  )
  dicomtk:::cpp_write_dicom_multiframe(
    pixels = px, dims = c(4L, 4L, 1L), out_path = f2,
    meta_tags = c("Modality", "SOPClassUID", "PatientName", "PatientID", "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID", "StudyDate"),
    meta_values = c("MR", "1.2.840.10008.5.1.4.1.1.4", "DOE^JOHN", "P01", "1.3.6.1.4.1.9999.1", "1.3.6.1.4.1.9999.1.1", "1.3.6.1.4.1.9999.1.1.2", "20240201")
  )

  res <- dicom_deid(in_dir, clean_dir, key = kp)
  expect_equal(length(res$files), 2L)

  v_res <- dicom_deid_verify(clean_dir, attest_path = att_file, key = kp)
  expect_true(v_res$passed)

  # Verification with correct key succeeds
  expect_true(dicom_verify_attestation(clean_dir, att_file, key = kp))

  # Verification with wrong key fails
  wrong_kp <- dicom_key_provider(passphrase = "completely-wrong-passphrase", salt = "salt-test-01")
  expect_false(dicom_verify_attestation(clean_dir, att_file, key = wrong_kp))

  # Tamper with 1 byte of one clean DICOM file
  target_file <- res$files[1L]
  bytes <- readBin(target_file, what = "raw", n = file.info(target_file)$size)
  bytes[length(bytes)] <- as.raw(as.integer(bytes[length(bytes)]) + 1L)
  writeBin(bytes, target_file)

  # Verification now fails due to digest mismatch
  expect_false(dicom_verify_attestation(clean_dir, att_file, key = kp))

  # Test optional openssl PKI signature if openssl is available
  if (requireNamespace("openssl", quietly = TRUE)) {
    att_pki <- tempfile(pattern = "attest_pki_", fileext = ".json")
    rsa_key <- openssl::rsa_keygen(bits = 2048L)
    pub_key <- as.list(rsa_key)$pubkey

    v_pki <- dicom_deid_verify(
      clean_dir,
      attest_path = att_pki,
      private_key = rsa_key
    )
    # Target file is tampered, but we restore it first
    orig_res <- dicom_deid(in_dir, clean_dir, key = kp, overwrite = TRUE)
    v_pki <- dicom_deid_verify(
      clean_dir,
      attest_path = att_pki,
      private_key = rsa_key
    )
    expect_true(v_pki$passed)
    expect_true(dicom_verify_attestation(clean_dir, att_pki, cert = pub_key))

    # Wrong public key fails
    wrong_rsa <- openssl::rsa_keygen(bits = 2048L)
    wrong_pub <- as.list(wrong_rsa)$pubkey
    expect_false(dicom_verify_attestation(clean_dir, att_pki, cert = wrong_pub))
    unlink(att_pki)
  }
})

test_that("Re-Identification Risk Scoring (dicom_deid_risk()) computes k-anonymity, l-diversity, and risks", {
  cohort_dir <- tempfile(pattern = "cohort_risk_")
  cohort_gen_dir <- tempfile(pattern = "cohort_gen_")
  dir.create(cohort_dir, recursive = TRUE)
  dir.create(cohort_gen_dir, recursive = TRUE)
  on.exit(unlink(c(cohort_dir, cohort_gen_dir), recursive = TRUE), add = TRUE)

  px <- as.numeric(matrix(1:16, 4, 4))

  # Synthesize 12 patients:
  # - Cell 1: 5 patients Male, 40Y, CT, StudyDate 20240101
  # - Cell 2: 5 patients Female, 50Y, MR, StudyDate 20240201
  # - Rare: 2 patients forming singletons (k=1 each):
  #   - Patient 11: Female, 90Y, PET, StudyDate 20240301 (StudyDescription = "Brain PET Scan")
  #   - Patient 12: Male, 95Y, PET, StudyDate 20240401 (StudyDescription = "Cardiac PET Scan")
  synthesize_risk_patient <- function(dir, pid, sex, age, mod, date, body_part, study_desc) {
    f <- file.path(dir, paste0(pid, ".dcm"))
    dicomtk:::cpp_write_dicom_multiframe(
      pixels = px,
      dims = c(4L, 4L, 1L),
      out_path = f,
      meta_tags = c(
        "Modality", "SOPClassUID", "PatientName", "PatientID",
        "PatientSex", "PatientAge", "StudyDate", "BodyPartExamined", "StudyDescription",
        "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID"
      ),
      meta_values = c(
        mod, "1.2.840.10008.5.1.4.1.1.2", paste0("SUBJECT^", pid), pid,
        sex, age, date, body_part, study_desc,
        paste0("1.3.6.1.4.1.9999.", pid), paste0("1.3.6.1.4.1.9999.", pid, ".1"), paste0("1.3.6.1.4.1.9999.", pid, ".1.1")
      )
    )
  }

  for (i in 1:5) {
    pid <- sprintf("PAT_M40_%02d", i)
    synthesize_risk_patient(cohort_dir, pid, "M", "040Y", "CT", "20240101", "CHEST", paste0("Routine Chest CT ", i))
    synthesize_risk_patient(cohort_gen_dir, pid, "M", "040Y", "CT", "20240101", "CHEST", paste0("Routine Chest CT ", i))
  }
  for (i in 1:5) {
    pid <- sprintf("PAT_F50_%02d", i)
    synthesize_risk_patient(cohort_dir, pid, "F", "050Y", "MR", "20240201", "BRAIN", paste0("Brain MRI Protocol ", i))
    synthesize_risk_patient(cohort_gen_dir, pid, "F", "050Y", "MR", "20240201", "BRAIN", paste0("Brain MRI Protocol ", i))
  }
  # Singletons in cohort_dir
  synthesize_risk_patient(cohort_dir, "PAT_RARE_01", "F", "090Y", "PET", "20240301", "BRAIN", "Brain PET Scan")
  synthesize_risk_patient(cohort_dir, "PAT_RARE_02", "M", "095Y", "PET", "20240401", "HEART", "Cardiac PET Scan")

  # Generalized version in cohort_gen_dir: age generalized to "089Y+" or grouped with other PET cases
  # Here we add 4 more Female 90Y PET and 4 more Male 95Y PET so both cells have k >= 5
  for (i in 1:5) {
    pid <- sprintf("PAT_F90_%02d", i)
    synthesize_risk_patient(cohort_gen_dir, pid, "F", "090Y", "PET", "20240301", "BRAIN", paste0("Brain PET ", i))
  }
  for (i in 1:5) {
    pid <- sprintf("PAT_M95_%02d", i)
    synthesize_risk_patient(cohort_gen_dir, pid, "M", "095Y", "PET", "20240401", "HEART", paste0("Cardiac PET ", i))
  }

  # Risk analysis on ungeneralized cohort
  rk <- dicom_deid_risk(cohort_dir, k_threshold = 5L)
  expect_s3_class(rk, "dicom_deid_risk")
  expect_equal(rk$k_min, 1L)
  expect_equal(rk$max_prosecutor_risk, 1.0)
  expect_true(any(c("PAT_RARE_01", "PAT_RARE_02") %in% rk$flagged_subjects))
  expect_gt(nrow(rk$equivalence_classes), 0L)

  # Risk analysis on generalized cohort
  rk2 <- dicom_deid_risk(cohort_gen_dir, k_threshold = 5L)
  expect_gte(rk2$k_min, 5L)
  expect_lte(rk2$max_prosecutor_risk, 0.20)
  expect_equal(length(rk2$flagged_subjects), 0L)
})
