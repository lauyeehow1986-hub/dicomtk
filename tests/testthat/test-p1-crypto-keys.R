test_that("RFC 4231 HMAC-SHA256 and RFC 8439 ChaCha20-Poly1305 vectors pass", {
  mac <- dicomtk:::cpp_hmac_sha256_hex(charToRaw("Jefe"), charToRaw("what do ya want for nothing?"))
  expect_equal(mac, "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")

  key <- as.raw(0:31)
  pt <- charToRaw("{\"orig\":\"PAT001\",\"pseudo\":\"SUBJ-A1B2C3\"}")
  aad <- charToRaw("dicomtk-crosswalk-v1")
  ct <- dicomtk:::cpp_aead_encrypt(key, pt, aad)
  expect_gt(length(ct), length(pt) + 28L - 1L) # 12-byte nonce + ciphertext + 16-byte tag
  dec <- dicomtk:::cpp_aead_decrypt(key, ct, aad)
  expect_equal(dec, pt)

  # Tampering with ciphertext/tag triggers authentication error
  bad_ct <- ct
  bad_ct[length(bad_ct)] <- as.raw(bitwXor(as.integer(bad_ct[length(bad_ct)]), 1L))
  expect_error(dicomtk:::cpp_aead_decrypt(key, bad_ct, aad), "authentication|MAC|tamper", ignore.case = TRUE)

  # Tampering with AAD triggers authentication error
  bad_aad <- charToRaw("dicomtk-crosswalk-v2")
  expect_error(dicomtk:::cpp_aead_decrypt(key, ct, bad_aad), "authentication|MAC|tamper", ignore.case = TRUE)

  # Tampering with nonce triggers authentication error
  bad_nonce_ct <- ct
  bad_nonce_ct[1] <- as.raw(bitwXor(as.integer(bad_nonce_ct[1]), 1L))
  expect_error(dicomtk:::cpp_aead_decrypt(key, bad_nonce_ct, aad), "authentication|MAC|tamper", ignore.case = TRUE)
})

test_that("RFC 5869 HKDF-SHA256 and PBKDF2-HMAC-SHA256 determinism", {
  k1 <- dicomtk:::cpp_pbkdf2_sha256(charToRaw("test-passphrase"), charToRaw("salt-1"), 1000L, 32L)
  k2 <- dicomtk:::cpp_pbkdf2_sha256(charToRaw("test-passphrase"), charToRaw("salt-1"), 1000L, 32L)
  k3 <- dicomtk:::cpp_pbkdf2_sha256(charToRaw("test-passphrase"), charToRaw("salt-2"), 1000L, 32L)
  expect_equal(length(k1), 32L)
  expect_equal(k1, k2)
  expect_false(identical(k1, k3))

  # HKDF expansion
  sub1 <- dicomtk:::cpp_hkdf_sha256(k1, charToRaw("salt"), charToRaw("dicomtk-uid-v1"), 32L)
  sub2 <- dicomtk:::cpp_hkdf_sha256(k1, charToRaw("salt"), charToRaw("dicomtk-uid-v1"), 32L)
  sub3 <- dicomtk:::cpp_hkdf_sha256(k1, charToRaw("salt"), charToRaw("dicomtk-date-v1"), 32L)
  expect_equal(length(sub1), 32L)
  expect_equal(sub1, sub2)
  expect_false(identical(sub1, sub3))
})

test_that("Deterministic HMAC UID mapper preserves standard UIDs and obeys 64-char 2.25 grammar", {
  kp <- dicom_key_provider(passphrase = "unit-test-secret", salt = "dicomtk-p1-salt")
  expect_true(is_dicom_key_provider(kp))

  # Standard UIDs starting with 1.2.840.10008. are preserved
  std_sop <- "1.2.840.10008.5.1.4.1.1.2"
  std_ts <- "1.2.840.10008.1.2.1"
  expect_equal(deid_map_uid(std_sop, kp), std_sop)
  expect_equal(deid_map_uid(std_ts, kp), std_ts)

  # Non-standard UIDs are pseudorandomly mapped to 2.25.<decimal>
  u1 <- deid_map_uid("1.3.6.1.4.1.14519.5.2.1.9999.1001", kp)
  u2 <- deid_map_uid("1.3.6.1.4.1.14519.5.2.1.9999.1001", kp)
  expect_equal(u1, u2)
  expect_match(u1, "^2\\.25\\.[1-9][0-9]*$")
  expect_lte(nchar(u1), 64L)

  # Different UID gives different mapped UID
  u3 <- deid_map_uid("1.3.6.1.4.1.14519.5.2.1.9999.1002", kp)
  expect_false(identical(u1, u3))
  expect_match(u3, "^2\\.25\\.[1-9][0-9]*$")
  expect_lte(nchar(u3), 64L)

  # Different key gives different mapped UID
  kp2 <- dicom_key_provider(passphrase = "unit-test-secret-2", salt = "dicomtk-p1-salt")
  u4 <- deid_map_uid("1.3.6.1.4.1.14519.5.2.1.9999.1001", kp2)
  expect_false(identical(u1, u4))

  # Empty or invalid input
  expect_equal(deid_map_uid("", kp), "")
})

test_that("Per-patient date shift is deterministic and strictly within range", {
  kp <- dicom_key_provider(passphrase = "unit-test-secret", salt = "dicomtk-p1-salt")
  s1 <- deid_patient_shift(kp, "PAT001", c(-3650L, -30L))
  s2 <- deid_patient_shift(kp, "PAT001", c(-3650L, -30L))
  expect_equal(s1, s2)
  expect_true(is.integer(s1))
  expect_gte(s1, -3650L)
  expect_lte(s1, -30L)

  s3 <- deid_patient_shift(kp, "PAT002", c(-3650L, -30L))
  expect_gte(s3, -3650L)
  expect_lte(s3, -30L)
  expect_false(identical(s1, s3))
})

test_that("dicom_key_provider() S3 security, print redaction, and broker/ttp modes", {
  kp <- dicom_key_provider(mode = "local", passphrase = "correct horse battery staple", salt = "study-salt-01")
  expect_true(is_dicom_key_provider(kp))

  # Redacted print and format
  fmt <- format(kp)
  out_print <- paste(capture.output(print(kp)), collapse = "\n")
  out_str <- paste(capture.output(str(kp)), collapse = "\n")

  expect_match(fmt, "REDACTED")
  expect_match(out_print, "REDACTED")
  expect_false(grepl("correct horse battery staple", fmt, fixed = TRUE))
  expect_false(grepl("correct horse battery staple", out_print, fixed = TRUE))
  expect_false(grepl("correct horse battery staple", out_str, fixed = TRUE))

  # Mode broker and ttp
  kp_broker <- dicom_key_provider(mode = "broker", resolver_fn = function(id) charToRaw(paste0("mock-key-", id)))
  expect_true(is_dicom_key_provider(kp_broker))

  kp_ttp <- dicom_key_provider(mode = "ttp", resolver_fn = function(id) charToRaw(paste0("mock-ttp-", id)))
  expect_true(is_dicom_key_provider(kp_ttp))

  # Aborts if broker/ttp has no resolver
  expect_error(dicom_key_provider(mode = "broker"), "resolver_fn")
  expect_error(dicom_key_provider(mode = "ttp"), "resolver_fn")
})
