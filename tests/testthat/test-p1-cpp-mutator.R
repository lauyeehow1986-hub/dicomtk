test_that("Deep recursive SQ de-identification mutates nested UIDs and dates while preserving geometry", {
  in_dcm <- tempfile(pattern = "mutator_in_", fileext = ".dcm")
  out_dcm <- tempfile(pattern = "mutator_out_", fileext = ".dcm")
  on.exit(unlink(c(in_dcm, out_dcm)), add = TRUE)

  px <- array(seq_len(4 * 4 * 2), dim = c(4L, 4L, 2L))

  # 3-level nested sequence:
  # PerFrameFunctionalGroupsSequence (5200,9230)
  #   -> DerivationImageSequence (0008,9124)
  #     -> SourceImageSequence (0008,2112)
  #       -> ReferencedSOPInstanceUID (0008,1155) = "1.3.6.1.4.1.14519.5.2.1.9999.5555"
  #   -> PlanePositionSequence (0020,9113)
  #       -> ImagePositionPatient (0020,0032) = "10.0\20.0\30.0"
  per_frame <- list(
    list(
      DerivationImageSequence = list(
        list(
          SourceImageSequence = list(
            list(
              ReferencedSOPInstanceUID = "1.3.6.1.4.1.14519.5.2.1.9999.5555"
            )
          )
        )
      ),
      PlanePositionSequence = list(
        list(
          ImagePositionPatient = "10.0\\20.0\\30.0"
        )
      )
    ),
    list(
      DerivationImageSequence = list(
        list(
          SourceImageSequence = list(
            list(
              ReferencedSOPInstanceUID = "1.3.6.1.4.1.14519.5.2.1.9999.5556"
            )
          )
        )
      ),
      PlanePositionSequence = list(
        list(
          ImagePositionPatient = "10.0\\20.0\\35.0"
        )
      )
    )
  )

  shared <- list(
    list(
      PixelMeasuresSequence = list(
        list(
          PixelSpacing = "0.75\\0.75",
          SliceThickness = "5.0"
        )
      )
    )
  )

  ok <- dicomtk:::cpp_write_dicom_multiframe(
    pixels = as.numeric(px),
    dims = c(4L, 4L, 2L),
    out_path = in_dcm,
    meta_tags = c(
      "Modality", "SOPClassUID", "PatientName", "PatientID",
      "ReferringPhysicianName", "AcquisitionDateTime", "StudyInstanceUID", "SeriesInstanceUID"
    ),
    meta_values = c(
      "CT", "1.2.840.10008.5.1.4.1.1.2.1", "Doe^Jane", "PAT9999",
      "Dr^Bob^Smith", "20240510143000.000000",
      "1.3.6.1.4.1.14519.5.2.1.1111", "1.3.6.1.4.1.14519.5.2.1.2222"
    ),
    shared_fg = shared,
    per_frame_fg = per_frame
  )
  expect_true(ok)

  kp <- dicom_key_provider(passphrase = "test-secret-phase1", salt = "dicomtk-p1-salt")
  uid_key <- dicomtk:::deid_get_subkey(kp, "uid")
  pid_key <- dicomtk:::deid_get_subkey(kp, "pid")
  date_key <- dicomtk:::deid_get_subkey(kp, "date")

  prof <- dicom_deid_profile(options = "retain_longitudinal_modified_dates")

  res <- dicomtk:::cpp_deid_file(
    in_path = in_dcm,
    out_path = out_dcm,
    profile_spec = prof,
    uid_key = uid_key,
    pid_key = pid_key,
    date_key = date_key,
    drop_wsi_labels = TRUE
  )

  expect_equal(res$status, "ok")
  expect_false(res$skipped_wsi_label)
  expect_true(file.exists(out_dcm))
  expect_true(nzchar(res$in_sha256))
  expect_true(nzchar(res$out_sha256))
  expect_false(identical(res$in_sha256, res$out_sha256))

  # Read modified DICOM and inspect elements
  hdr <- read_dicom(out_dcm, include_sequences = TRUE)

  # PHI stripped / mutated
  pn_row <- hdr[hdr$keyword == "PatientName", , drop = FALSE]
  expect_true(nrow(pn_row) == 0L || pn_row$value %in% c("", "ANONYMOUS"))

  rpn_row <- hdr[hdr$keyword == "ReferringPhysicianName", , drop = FALSE]
  expect_true(nrow(rpn_row) == 0L || rpn_row$value == "")

  # Pseudonymous PatientID generated
  pid_row <- hdr[hdr$keyword == "PatientID", , drop = FALSE]
  expect_equal(nrow(pid_row), 1L)
  expect_match(pid_row$value, "^SUBJ-[0-9A-F]{12}$")
  expect_equal(pid_row$value, res$pseudo_patient_id)

  # Nested ReferencedSOPInstanceUID mapped to 2.25 UIDs
  ref_uid_rows <- hdr[hdr$keyword == "ReferencedSOPInstanceUID", , drop = FALSE]
  expect_equal(nrow(ref_uid_rows), 2L)
  for (u in ref_uid_rows$value) {
    expect_match(u, "^2\\.25\\.[1-9][0-9]*$")
    expect_false(grepl("9999", u))
  }

  # Slice geometry preserved exactly
  ipp_rows <- hdr[hdr$keyword == "ImagePositionPatient", , drop = FALSE]
  expect_equal(nrow(ipp_rows), 2L)
  expect_equal(ipp_rows$value, c("10.0\\20.0\\30.0", "10.0\\20.0\\35.0"))

  ps_rows <- hdr[hdr$keyword == "PixelSpacing", , drop = FALSE]
  expect_equal(nrow(ps_rows), 1L)
  expect_equal(ps_rows$value, "0.75\\0.75")

  # Date shifted
  acq_dt_row <- hdr[hdr$keyword == "AcquisitionDateTime", , drop = FALSE]
  if (nrow(acq_dt_row) > 0L) {
    expect_false(startsWith(acq_dt_row$value, "20240510"))
    expect_true(res$shift_days != 0L)
  }
})

test_that("Dynamic private creator block allowlist scopes retention and purges unknown blocks", {
  in_dcm <- tempfile(pattern = "priv_in_", fileext = ".dcm")
  out_safe_dcm <- tempfile(pattern = "priv_safe_out_", fileext = ".dcm")
  out_purge_dcm <- tempfile(pattern = "priv_purge_out_", fileext = ".dcm")
  on.exit(unlink(c(in_dcm, out_safe_dcm, out_purge_dcm)), add = TRUE)

  px <- matrix(seq_len(16), 4, 4)
  ok <- dicomtk:::cpp_write_dicom_matrix(
    pixels = px,
    out_path = in_dcm,
    meta_tags = c(
      "Modality", "SOPClassUID",
      "(2005,0010)", "(2005,100D)", "(2005,100E)",
      "(2005,0011)", "(2005,1101)"
    ),
    meta_values = c(
      "MR", "1.2.840.10008.5.1.4.1.1.4",
      "Philips Imaging DD 001", "0.0", "2.5",
      "VENDOR SECRET NOTES", "John Doe NRIC S1234567D"
    )
  )
  expect_true(ok)

  kp <- dicom_key_provider(passphrase = "test-secret-phase1", salt = "dicomtk-p1-salt")
  uid_key <- dicomtk:::deid_get_subkey(kp, "uid")
  pid_key <- dicomtk:::deid_get_subkey(kp, "pid")
  date_key <- dicomtk:::deid_get_subkey(kp, "date")

  # 1. Profile with retain_safe_private = FALSE
  prof_no_priv <- dicom_deid_profile()
  res_purge <- dicomtk:::cpp_deid_file(
    in_path = in_dcm,
    out_path = out_purge_dcm,
    profile_spec = prof_no_priv,
    uid_key = uid_key,
    pid_key = pid_key,
    date_key = date_key
  )
  expect_equal(res_purge$status, "ok")

  hdr_purged <- read_dicom(out_purge_dcm)
  priv_purged <- hdr_purged[grepl("^\\(2005,", hdr_purged$tag), , drop = FALSE]
  expect_equal(nrow(priv_purged), 0L)

  # 2. Profile with retain_safe_private = TRUE
  prof_safe_priv <- dicom_deid_profile(options = "retain_safe_private")
  res_safe <- dicomtk:::cpp_deid_file(
    in_path = in_dcm,
    out_path = out_safe_dcm,
    profile_spec = prof_safe_priv,
    uid_key = uid_key,
    pid_key = pid_key,
    date_key = date_key
  )
  expect_equal(res_safe$status, "ok")

  hdr_safe <- read_dicom(out_safe_dcm)
  priv_safe <- hdr_safe[grepl("^\\(2005,", hdr_safe$tag), , drop = FALSE]

  # Safe tags survive: (2005,0010), (2005,100D), (2005,100E)
  expect_true("(2005,0010)" %in% priv_safe$tag)
  expect_true("(2005,100D)" %in% priv_safe$tag)
  expect_true("(2005,100E)" %in% priv_safe$tag)
  expect_equal(priv_safe[priv_safe$tag == "(2005,0010)", ]$value, "Philips Imaging DD 001")
  expect_equal(priv_safe[priv_safe$tag == "(2005,100D)", ]$value, "0.0")
  expect_equal(priv_safe[priv_safe$tag == "(2005,100E)", ]$value, "2.5")

  # Unknown block (2005,0011) and (2005,1101) are completely purged
  expect_false("(2005,0011)" %in% priv_safe$tag)
  expect_false("(2005,1101)" %in% priv_safe$tag)
  expect_false(any(grepl("John Doe", priv_safe$value, ignore.case = TRUE)))
  expect_false(any(grepl("S1234567D", priv_safe$value)))
})

test_that("HIPAA Age Cap caps age > 89 to 090Y and preserves younger ages", {
  in_dcm <- tempfile(pattern = "age_in_", fileext = ".dcm")
  out_old_dcm <- tempfile(pattern = "age_old_out_", fileext = ".dcm")
  out_young_dcm <- tempfile(pattern = "age_young_out_", fileext = ".dcm")
  on.exit(unlink(c(in_dcm, out_old_dcm, out_young_dcm)), add = TRUE)

  px <- matrix(seq_len(16), 4, 4)
  dicomtk:::cpp_write_dicom_matrix(
    pixels = px,
    out_path = in_dcm,
    meta_tags = c("Modality", "SOPClassUID", "PatientAge"),
    meta_values = c("CT", "1.2.840.10008.5.1.4.1.1.2", "094Y")
  )

  kp <- dicom_key_provider(passphrase = "test-secret-phase1", salt = "dicomtk-p1-salt")
  uid_key <- dicomtk:::deid_get_subkey(kp, "uid")
  pid_key <- dicomtk:::deid_get_subkey(kp, "pid")
  date_key <- dicomtk:::deid_get_subkey(kp, "date")

  prof_hipaa <- dicom_deid_profile(jurisdictions = "hipaa_safe_harbor")

  # 94Y should be capped to 090Y
  dicomtk:::cpp_deid_file(
    in_path = in_dcm,
    out_path = out_old_dcm,
    profile_spec = prof_hipaa,
    uid_key = uid_key,
    pid_key = pid_key,
    date_key = date_key
  )
  hdr_old <- read_dicom(out_old_dcm)
  age_old <- hdr_old[hdr_old$keyword == "PatientAge", , drop = FALSE]
  expect_equal(age_old$value, "090Y")

  # 45Y should remain 045Y
  in_young_dcm <- tempfile(pattern = "age_y_in_", fileext = ".dcm")
  on.exit(unlink(in_young_dcm), add = TRUE)
  dicomtk:::cpp_write_dicom_matrix(
    pixels = px,
    out_path = in_young_dcm,
    meta_tags = c("Modality", "SOPClassUID", "PatientAge"),
    meta_values = c("CT", "1.2.840.10008.5.1.4.1.1.2", "045Y")
  )
  dicomtk:::cpp_deid_file(
    in_path = in_young_dcm,
    out_path = out_young_dcm,
    profile_spec = prof_hipaa,
    uid_key = uid_key,
    pid_key = pid_key,
    date_key = date_key
  )
  hdr_young <- read_dicom(out_young_dcm)
  age_young <- hdr_young[hdr_young$keyword == "PatientAge", , drop = FALSE]
  expect_equal(age_young$value, "045Y")
})

test_that("Free-text descriptions scrub matching regex patterns with [REDACTED]", {
  in_dcm <- tempfile(pattern = "desc_in_", fileext = ".dcm")
  out_dcm <- tempfile(pattern = "desc_out_", fileext = ".dcm")
  on.exit(unlink(c(in_dcm, out_dcm)), add = TRUE)

  px <- matrix(seq_len(16), 4, 4)
  dicomtk:::cpp_write_dicom_matrix(
    pixels = px,
    out_path = in_dcm,
    meta_tags = c("Modality", "SOPClassUID", "StudyDescription"),
    meta_values = c("CT", "1.2.840.10008.5.1.4.1.1.2", "CT Thorax Pt S8812345Z Dr Tan")
  )

  kp <- dicom_key_provider(passphrase = "test-secret-phase1", salt = "dicomtk-p1-salt")
  uid_key <- dicomtk:::deid_get_subkey(kp, "uid")
  pid_key <- dicomtk:::deid_get_subkey(kp, "pid")
  date_key <- dicomtk:::deid_get_subkey(kp, "date")

  prof_sg <- dicom_deid_profile(jurisdictions = "sg_pdpa_hib", options = "clean_descriptors")

  dicomtk:::cpp_deid_file(
    in_path = in_dcm,
    out_path = out_dcm,
    profile_spec = prof_sg,
    uid_key = uid_key,
    pid_key = pid_key,
    date_key = date_key
  )

  hdr <- read_dicom(out_dcm)
  desc_row <- hdr[hdr$keyword == "StudyDescription", , drop = FALSE]
  expect_equal(nrow(desc_row), 1L)
  expect_equal(desc_row$value, "CT Thorax Pt [REDACTED] Dr Tan")
})

test_that("CID 7050 metadata is stamped into output DICOM", {
  in_dcm <- tempfile(pattern = "stamp_in_", fileext = ".dcm")
  out_dcm <- tempfile(pattern = "stamp_out_", fileext = ".dcm")
  on.exit(unlink(c(in_dcm, out_dcm)), add = TRUE)

  px <- matrix(seq_len(16), 4, 4)
  dicomtk:::cpp_write_dicom_matrix(
    pixels = px,
    out_path = in_dcm,
    meta_tags = c("Modality", "SOPClassUID"),
    meta_values = c("CT", "1.2.840.10008.5.1.4.1.1.2")
  )

  kp <- dicom_key_provider(passphrase = "test-secret-phase1", salt = "dicomtk-p1-salt")
  uid_key <- dicomtk:::deid_get_subkey(kp, "uid")
  pid_key <- dicomtk:::deid_get_subkey(kp, "pid")
  date_key <- dicomtk:::deid_get_subkey(kp, "date")

  prof <- dicom_deid_profile(options = c("retain_longitudinal_modified_dates", "retain_safe_private"))

  dicomtk:::cpp_deid_file(
    in_path = in_dcm,
    out_path = out_dcm,
    profile_spec = prof,
    uid_key = uid_key,
    pid_key = pid_key,
    date_key = date_key
  )

  hdr <- read_dicom(out_dcm, include_sequences = TRUE)

  # (0012,0062) PatientIdentityRemoved == "YES"
  rem_row <- hdr[hdr$tag == "(0012,0062)", , drop = FALSE]
  expect_equal(nrow(rem_row), 1L)
  expect_equal(rem_row$value, "YES")

  # (0012,0063) DeidentificationMethod is present
  meth_row <- hdr[hdr$tag == "(0012,0063)", , drop = FALSE]
  expect_equal(nrow(meth_row), 1L)
  expect_true(nzchar(meth_row$value))

  # (0012,0064) DeidentificationMethodCodeSequence items
  # Must contain CodeValue, CodingSchemeDesignator ("DCM"), CodeMeaning
  code_val_rows <- hdr[hdr$keyword == "CodeValue" & grepl("0012,0064", hdr$sequence_path), , drop = FALSE]
  expect_gt(nrow(code_val_rows), 0L)
  expect_true("113100" %in% code_val_rows$value)
  expect_true("113107" %in% code_val_rows$value)
  expect_true("113111" %in% code_val_rows$value)

  scheme_rows <- hdr[hdr$keyword == "CodingSchemeDesignator" & grepl("0012,0064", hdr$sequence_path), , drop = FALSE]
  expect_true(all(scheme_rows$value == "DCM"))
})

test_that("WSI Label/Overview Detection skips label images without writing output", {
  wsi_label_dcm <- tempfile(pattern = "wsi_label_", fileext = ".dcm")
  wsi_vol_dcm <- tempfile(pattern = "wsi_vol_", fileext = ".dcm")
  out_label_dcm <- tempfile(pattern = "wsi_out_label_", fileext = ".dcm")
  out_vol_dcm <- tempfile(pattern = "wsi_out_vol_", fileext = ".dcm")
  on.exit(unlink(c(wsi_label_dcm, wsi_vol_dcm, out_label_dcm, out_vol_dcm)), add = TRUE)

  px <- matrix(seq_len(16), 4, 4)
  wsi_sop_class <- "1.2.840.10008.5.1.4.1.1.77.1.6"

  # 1. Label image
  dicomtk:::cpp_write_dicom_matrix(
    pixels = px,
    out_path = wsi_label_dcm,
    meta_tags = c("Modality", "SOPClassUID", "ImageType"),
    meta_values = c("SM", wsi_sop_class, "ORIGINAL\\PRIMARY\\LABEL")
  )

  # 2. Volume image (non-label)
  dicomtk:::cpp_write_dicom_matrix(
    pixels = px,
    out_path = wsi_vol_dcm,
    meta_tags = c("Modality", "SOPClassUID", "ImageType"),
    meta_values = c("SM", wsi_sop_class, "ORIGINAL\\PRIMARY\\VOLUME")
  )

  kp <- dicom_key_provider(passphrase = "test-secret-phase1", salt = "dicomtk-p1-salt")
  uid_key <- dicomtk:::deid_get_subkey(kp, "uid")
  pid_key <- dicomtk:::deid_get_subkey(kp, "pid")
  date_key <- dicomtk:::deid_get_subkey(kp, "date")
  prof <- dicom_deid_profile()

  # Label image with drop_wsi_labels = TRUE -> skipped
  res_label <- dicomtk:::cpp_deid_file(
    in_path = wsi_label_dcm,
    out_path = out_label_dcm,
    profile_spec = prof,
    uid_key = uid_key,
    pid_key = pid_key,
    date_key = date_key,
    drop_wsi_labels = TRUE
  )
  expect_equal(res_label$status, "skipped_wsi_label")
  expect_true(res_label$skipped_wsi_label)
  expect_false(file.exists(out_label_dcm))

  # Volume image with drop_wsi_labels = TRUE -> processed normally
  res_vol <- dicomtk:::cpp_deid_file(
    in_path = wsi_vol_dcm,
    out_path = out_vol_dcm,
    profile_spec = prof,
    uid_key = uid_key,
    pid_key = pid_key,
    date_key = date_key,
    drop_wsi_labels = TRUE
  )
  expect_equal(res_vol$status, "ok")
  expect_false(res_vol$skipped_wsi_label)
  expect_true(file.exists(out_vol_dcm))
})

test_that("Repeating group wildcards (50XX,XXXX) and (60XX,XXXX) purge (5000,0010) and (6000,3000)", {
  in_dcm <- tempfile(pattern = "wildcard_in_", fileext = ".dcm")
  out_dcm <- tempfile(pattern = "wildcard_out_", fileext = ".dcm")
  on.exit(unlink(c(in_dcm, out_dcm)), add = TRUE)

  px <- matrix(seq_len(16), 4, 4)
  ok <- dicomtk:::cpp_write_dicom_matrix(
    pixels = px,
    out_path = in_dcm,
    meta_tags = c(
      "Modality", "SOPClassUID",
      "(5000,0010)", "(6000,3000)"
    ),
    meta_values = c(
      "OT", "1.2.840.10008.5.1.4.1.1.7",
      "128", "0"
    )
  )
  expect_true(ok)

  kp <- dicom_key_provider(passphrase = "test-secret-phase1", salt = "dicomtk-p1-salt")
  uid_key <- dicomtk:::deid_get_subkey(kp, "uid")
  pid_key <- dicomtk:::deid_get_subkey(kp, "pid")
  date_key <- dicomtk:::deid_get_subkey(kp, "date")

  prof <- dicom_deid_profile()
  # ps3.15 base profile has action 'X' for (50XX,XXXX) and (60XX,XXXX)
  res <- dicomtk:::cpp_deid_file(
    in_path = in_dcm,
    out_path = out_dcm,
    profile_spec = prof,
    uid_key = uid_key,
    pid_key = pid_key,
    date_key = date_key
  )
  expect_equal(res$status, "ok")

  hdr <- read_dicom(out_dcm)
  expect_false("(5000,0010)" %in% hdr$tag)
  expect_false("(6000,3000)" %in% hdr$tag)
  expect_false(any(grepl("^\\(50[0-9A-Fa-f]{2},", hdr$tag)))
  expect_false(any(grepl("^\\(60[0-9A-Fa-f]{2},", hdr$tag)))
})

test_that("Action K priority preserves StudyInstanceUID and StudyDate under dummy and shift_per_patient policies", {
  in_dcm <- tempfile(pattern = "act_k_in_", fileext = ".dcm")
  out_dummy_dcm <- tempfile(pattern = "act_k_dummy_", fileext = ".dcm")
  out_shift_dcm <- tempfile(pattern = "act_k_shift_", fileext = ".dcm")
  on.exit(unlink(c(in_dcm, out_dummy_dcm, out_shift_dcm)), add = TRUE)

  orig_study_uid <- "1.2.840.113619.2.55.3.123456789.987"
  orig_study_date <- "20230615"
  orig_patient_id <- "PATIENT_EXACT_123   "

  px <- matrix(seq_len(16), 4, 4)
  ok <- dicomtk:::cpp_write_dicom_matrix(
    pixels = px,
    out_path = in_dcm,
    meta_tags = c(
      "Modality", "SOPClassUID",
      "StudyInstanceUID", "StudyDate", "PatientID"
    ),
    meta_values = c(
      "CT", "1.2.840.10008.5.1.4.1.1.2",
      orig_study_uid, orig_study_date, orig_patient_id
    )
  )
  expect_true(ok)

  kp <- dicom_key_provider(passphrase = "test-secret-phase1", salt = "dicomtk-p1-salt")
  uid_key <- dicomtk:::deid_get_subkey(kp, "uid")
  pid_key <- dicomtk:::deid_get_subkey(kp, "pid")
  date_key <- dicomtk:::deid_get_subkey(kp, "date")

  # 1. date_policy = "dummy", but override StudyInstanceUID (0020,000D) and StudyDate (0008,0020) with "K"
  prof_dummy <- dicom_deid_profile(
    override_tags = list(
      "(0020,000D)" = "K",
      "(0008,0020)" = "K"
    )
  )
  expect_equal(prof_dummy$date_policy, "dummy")

  res_dummy <- dicomtk:::cpp_deid_file(
    in_path = in_dcm,
    out_path = out_dummy_dcm,
    profile_spec = prof_dummy,
    uid_key = uid_key,
    pid_key = pid_key,
    date_key = date_key
  )
  expect_equal(res_dummy$status, "ok")
  expect_equal(res_dummy$orig_patient_id, "PATIENT_EXACT_123")
  expect_equal(res_dummy$pseudo_study_uid, orig_study_uid)

  hdr_dummy <- read_dicom(out_dummy_dcm)
  study_uid_dummy <- hdr_dummy[hdr_dummy$keyword == "StudyInstanceUID", ]$value
  study_date_dummy <- hdr_dummy[hdr_dummy$keyword == "StudyDate", ]$value
  expect_equal(study_uid_dummy, orig_study_uid)
  expect_equal(study_date_dummy, orig_study_date)

  # 2. date_policy = "shift_per_patient", but override StudyInstanceUID and StudyDate with "K"
  prof_shift <- dicom_deid_profile(
    options = "retain_longitudinal_modified_dates",
    override_tags = list(
      "(0020,000D)" = "K",
      "(0008,0020)" = "K"
    )
  )
  expect_equal(prof_shift$date_policy, "shift_per_patient")

  res_shift <- dicomtk:::cpp_deid_file(
    in_path = in_dcm,
    out_path = out_shift_dcm,
    profile_spec = prof_shift,
    uid_key = uid_key,
    pid_key = pid_key,
    date_key = date_key
  )
  expect_equal(res_shift$status, "ok")
  expect_equal(res_shift$pseudo_study_uid, orig_study_uid)

  hdr_shift <- read_dicom(out_shift_dcm)
  study_uid_shift <- hdr_shift[hdr_shift$keyword == "StudyInstanceUID", ]$value
  study_date_shift <- hdr_shift[hdr_shift$keyword == "StudyDate", ]$value
  expect_equal(study_uid_shift, orig_study_uid)
  expect_equal(study_date_shift, orig_study_date)
})

test_that("Safe-private group scoping purges matching creator in wrong group", {
  in_dcm <- tempfile(pattern = "priv_grp_in_", fileext = ".dcm")
  out_dcm <- tempfile(pattern = "priv_grp_out_", fileext = ".dcm")
  on.exit(unlink(c(in_dcm, out_dcm)), add = TRUE)

  px <- matrix(seq_len(16), 4, 4)
  # Creator "Philips Imaging DD 001" is allowlisted for group 2005, but placed here in group 2007
  ok <- dicomtk:::cpp_write_dicom_matrix(
    pixels = px,
    out_path = in_dcm,
    meta_tags = c(
      "Modality", "SOPClassUID",
      "(2007,0010)", "(2007,100D)"
    ),
    meta_values = c(
      "MR", "1.2.840.10008.5.1.4.1.1.4",
      "Philips Imaging DD 001", "0.0"
    )
  )
  expect_true(ok)

  kp <- dicom_key_provider(passphrase = "test-secret-phase1", salt = "dicomtk-p1-salt")
  uid_key <- dicomtk:::deid_get_subkey(kp, "uid")
  pid_key <- dicomtk:::deid_get_subkey(kp, "pid")
  date_key <- dicomtk:::deid_get_subkey(kp, "date")

  prof <- dicom_deid_profile(options = "retain_safe_private")
  res <- dicomtk:::cpp_deid_file(
    in_path = in_dcm,
    out_path = out_dcm,
    profile_spec = prof,
    uid_key = uid_key,
    pid_key = pid_key,
    date_key = date_key
  )
  expect_equal(res$status, "ok")

  hdr <- read_dicom(out_dcm)
  priv_survived <- hdr[grepl("^\\(2007,", hdr$tag), , drop = FALSE]
  expect_equal(nrow(priv_survived), 0L)
})
