test_that("Cohort dicom_deid() preserves longitudinal relationships, UIDs, and crosswalk", {
  in_dir <- tempfile(pattern = "cohort_in_")
  out_dir <- tempfile(pattern = "cohort_out_")
  aud_file <- tempfile(pattern = "audit_", fileext = ".jsonl")
  cw_file <- tempfile(pattern = "crosswalk_", fileext = ".enc")
  dir.create(in_dir, recursive = TRUE)
  on.exit(unlink(c(in_dir, out_dir, aud_file, cw_file), recursive = TRUE), add = TRUE)

  # Synthesize longitudinal multi-modality cohort
  px <- as.numeric(matrix(seq_len(16), 4, 4))

  # Patient A Visit 1 CT
  ct1_file <- file.path(in_dir, "patA_v1_ct.dcm")
  ok1 <- dicomtk:::cpp_write_dicom_multiframe(
    pixels = px,
    dims = c(4L, 4L, 1L),
    out_path = ct1_file,
    meta_tags = c("Modality", "SOPClassUID", "PatientName", "PatientID", "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID", "StudyDate"),
    meta_values = c("CT", "1.2.840.10008.5.1.4.1.1.2", "John^Doe", "PAT_A", "1.3.6.1.4.1.9999.1001", "1.3.6.1.4.1.9999.1001.1", "1.3.6.1.4.1.9999.1001.1.1", "20240115")
  )
  expect_true(ok1)

  # Patient A Visit 1 RTSTRUCT referencing CT SOPInstanceUID
  rt1_file <- file.path(in_dir, "patA_v1_rt.dcm")
  ok2 <- dicomtk:::cpp_write_dicom_multiframe(
    pixels = px,
    dims = c(4L, 4L, 1L),
    out_path = rt1_file,
    meta_tags = c("Modality", "SOPClassUID", "PatientName", "PatientID", "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID", "StudyDate"),
    meta_values = c("RTSTRUCT", "1.2.840.10008.5.1.4.1.1.481.3", "John^Doe", "PAT_A", "1.3.6.1.4.1.9999.1001", "1.3.6.1.4.1.9999.1001.2", "1.3.6.1.4.1.9999.1001.2.1", "20240115"),
    extra_sequences = list(
      ROIContourSequence = list(
        list(
          ContourSequence = list(
            list(
              ContourImageSequence = list(
                list(ReferencedSOPInstanceUID = "1.3.6.1.4.1.9999.1001.1.1")
              )
            )
          )
        )
      )
    )
  )
  expect_true(ok2)

  # Patient A Visit 2 CT (exactly +180 days later in leap year 2024)
  ct2_file <- file.path(in_dir, "patA_v2_ct.dcm")
  ok3 <- dicomtk:::cpp_write_dicom_multiframe(
    pixels = px,
    dims = c(4L, 4L, 1L),
    out_path = ct2_file,
    meta_tags = c("Modality", "SOPClassUID", "PatientName", "PatientID", "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID", "StudyDate"),
    meta_values = c("CT", "1.2.840.10008.5.1.4.1.1.2", "John^Doe", "PAT_A", "1.3.6.1.4.1.9999.1002", "1.3.6.1.4.1.9999.1002.1", "1.3.6.1.4.1.9999.1002.1.1", "20240713")
  )
  expect_true(ok3)

  # Patient B Visit 1 MR
  mr1_file <- file.path(in_dir, "patB_v1_mr.dcm")
  ok4 <- dicomtk:::cpp_write_dicom_multiframe(
    pixels = px,
    dims = c(4L, 4L, 1L),
    out_path = mr1_file,
    meta_tags = c("Modality", "SOPClassUID", "PatientName", "PatientID", "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID", "StudyDate"),
    meta_values = c("MR", "1.2.840.10008.5.1.4.1.1.4", "Smith^Bob", "PAT_B", "1.3.6.1.4.1.9999.2001", "1.3.6.1.4.1.9999.2001.1", "1.3.6.1.4.1.9999.2001.1.1", "20240301")
  )
  expect_true(ok4)

  kp <- dicom_key_provider(passphrase = "longitudinal-cohort-secret", salt = "site-singapore-01")

  # Run de-identification with longitudinal dates, dual jurisdictions, audit JSONL, and encrypted crosswalk
  res <- dicom_deid(
    path = in_dir,
    out_dir = out_dir,
    options = "retain_longitudinal_modified_dates",
    jurisdictions = c("hipaa_safe_harbor", "sg_pdpa_hib"),
    key = kp,
    audit_path = aud_file,
    crosswalk_path = cw_file
  )

  expect_s3_class(res, "dicom_deid_result")
  expect_equal(length(res$files), 4L)
  expect_true(file.exists(aud_file))
  expect_true(file.exists(cw_file))

  # Read de-identified files
  deid_ct1 <- read_dicom(file.path(out_dir, "patA_v1_ct.dcm"), include_sequences = TRUE)
  deid_rt1 <- read_dicom(file.path(out_dir, "patA_v1_rt.dcm"), include_sequences = TRUE)
  deid_ct2 <- read_dicom(file.path(out_dir, "patA_v2_ct.dcm"), include_sequences = TRUE)
  deid_mr1 <- read_dicom(file.path(out_dir, "patB_v1_mr.dcm"), include_sequences = TRUE)

  # Check PatientID consistency
  pid_ct1 <- deid_ct1$value[deid_ct1$keyword == "PatientID"]
  pid_rt1 <- deid_rt1$value[deid_rt1$keyword == "PatientID"]
  pid_ct2 <- deid_ct2$value[deid_ct2$keyword == "PatientID"]
  pid_mr1 <- deid_mr1$value[deid_mr1$keyword == "PatientID"]

  expect_equal(pid_ct1, pid_rt1)
  expect_equal(pid_ct1, pid_ct2)
  expect_match(pid_ct1, "^SUBJ-[0-9A-F]{12}$")
  expect_match(pid_mr1, "^SUBJ-[0-9A-F]{12}$")
  expect_false(identical(pid_ct1, pid_mr1))

  # Check UID mapping: RTSTRUCT ReferencedSOPInstanceUID matches de-identified CT1 SOPInstanceUID
  sop_ct1 <- deid_ct1$value[deid_ct1$keyword == "SOPInstanceUID"]
  ref_rt1 <- deid_rt1$value[deid_rt1$keyword == "ReferencedSOPInstanceUID"]
  expect_equal(length(sop_ct1), 1L)
  expect_equal(length(ref_rt1), 1L)
  expect_equal(ref_rt1, sop_ct1)
  expect_match(sop_ct1, "^2\\.25\\.[1-9][0-9]*$")

  # Check longitudinal study dates: exactly 180 days difference preserved
  d_ct1 <- deid_ct1$value[deid_ct1$keyword == "StudyDate"]
  d_ct2 <- deid_ct2$value[deid_ct2$keyword == "StudyDate"]
  expect_false(identical(d_ct1, "20240115"))
  expect_false(identical(d_ct2, "20240713"))
  date_diff <- as.numeric(as.Date(d_ct2, "%Y%m%d") - as.Date(d_ct1, "%Y%m%d"))
  expect_equal(date_diff, 180)

  # Audit log verification: valid JSONL, 4 records, ZERO original PHI
  audit_lines <- readLines(aud_file)
  expect_equal(length(audit_lines), 4L)
  for (line in audit_lines) {
    record <- jsonlite::fromJSON(line)
    expect_true(all(c("in_sha256", "out_sha256", "profile", "actions") %in% names(record)))
    # Original PHI strings must NEVER appear in audit log
    expect_false(grepl("John^Doe", line, fixed = TRUE))
    expect_false(grepl("Smith^Bob", line, fixed = TRUE))
    expect_false(grepl("PAT_A", line, fixed = TRUE))
    expect_false(grepl("PAT_B", line, fixed = TRUE))
    expect_false(grepl("1.3.6.1.4.1.9999", line, fixed = TRUE))
  }

  # Encrypted crosswalk verification
  cw <- dicom_crosswalk_read(cw_file, kp)
  expect_s3_class(cw, "tbl_df")
  expect_true(all(c("orig_patient_id", "pseudo_patient_id", "orig_study_uid", "pseudo_study_uid", "shift_days") %in% names(cw)))
  expect_true("PAT_A" %in% cw$orig_patient_id)
  expect_true("PAT_B" %in% cw$orig_patient_id)

  row_a <- cw[cw$orig_patient_id == "PAT_A", , drop = FALSE]
  expect_equal(row_a$pseudo_patient_id[1L], pid_ct1)
  expect_true(all(row_a$shift_days == row_a$shift_days[1L]))

  # Decrypting with wrong key errors cleanly
  wrong_kp <- dicom_key_provider(passphrase = "wrong-passphrase-attempt", salt = "site-singapore-01")
  expect_error(dicom_crosswalk_read(cw_file, wrong_kp))
})

test_that("Parallel execution (workers = 2L) matches sequential execution (workers = 1L)", {
  skip_if_not(requireNamespace("mirai", quietly = TRUE), "mirai package required for parallel test")

  in_dir <- tempfile(pattern = "cohort_par_in_")
  out_seq <- tempfile(pattern = "cohort_seq_out_")
  out_par <- tempfile(pattern = "cohort_par_out_")
  cw_seq <- tempfile(pattern = "cw_seq_", fileext = ".enc")
  cw_par <- tempfile(pattern = "cw_par_", fileext = ".enc")
  dir.create(in_dir, recursive = TRUE)
  on.exit(unlink(c(in_dir, out_seq, out_par, cw_seq, cw_par), recursive = TRUE), add = TRUE)

  px <- as.numeric(matrix(1:9, 3, 3))
  for (i in 1:4) {
    f <- file.path(in_dir, sprintf("slice_%02d.dcm", i))
    dicomtk:::cpp_write_dicom_multiframe(
      pixels = px,
      dims = c(3L, 3L, 1L),
      out_path = f,
      meta_tags = c("Modality", "PatientName", "PatientID", "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID", "StudyDate"),
      meta_values = c("CT", paste0("SUBJ^", i), paste0("PAT", i), paste0("1.3.6.1.4.1.9999.100", i), paste0("1.3.6.1.4.1.9999.100", i, ".1"), paste0("1.3.6.1.4.1.9999.100", i, ".1.1"), "20240101")
    )
  }

  kp <- dicom_key_provider(passphrase = "parallel-reproducibility-key", salt = "salt-par")

  # Sequential
  res_seq <- dicom_deid(
    path = in_dir,
    out_dir = out_seq,
    key = kp,
    workers = 1L,
    crosswalk_path = cw_seq
  )

  # Parallel with 2 workers
  res_par <- dicom_deid(
    path = in_dir,
    out_dir = out_par,
    key = kp,
    workers = 2L,
    crosswalk_path = cw_par
  )

  expect_equal(length(res_seq$files), length(res_par$files))

  # Compare crosswalks
  cw_s <- dicom_crosswalk_read(cw_seq, kp)
  cw_p <- dicom_crosswalk_read(cw_par, kp)
  cw_s <- cw_s[order(cw_s$orig_patient_id), ]
  cw_p <- cw_p[order(cw_p$orig_patient_id), ]
  expect_equal(cw_s$pseudo_patient_id, cw_p$pseudo_patient_id)
  expect_equal(cw_s$pseudo_study_uid, cw_p$pseudo_study_uid)
  expect_equal(cw_s$shift_days, cw_p$shift_days)

  # Compare header tags byte for byte across output files
  for (fn in basename(res_seq$files)) {
    h_s <- read_dicom(file.path(out_seq, fn))
    h_p <- read_dicom(file.path(out_par, fn))
    expect_equal(h_s$value, h_p$value)
  }
})

test_that("Layout options: hierarchy, flat, and preserve organize output files correctly", {
  in_dir <- tempfile(pattern = "layout_in_")
  out_hier <- tempfile(pattern = "layout_hier_")
  out_flat <- tempfile(pattern = "layout_flat_")
  dir.create(in_dir, recursive = TRUE)
  on.exit(unlink(c(in_dir, out_hier, out_flat), recursive = TRUE), add = TRUE)

  px <- as.numeric(matrix(1:4, 2, 2))
  f1 <- file.path(in_dir, "test_slice.dcm")
  dicomtk:::cpp_write_dicom_multiframe(
    pixels = px,
    dims = c(2L, 2L, 1L),
    out_path = f1,
    meta_tags = c("Modality", "PatientName", "PatientID", "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID"),
    meta_values = c("CT", "Test^Patient", "PID42", "1.3.6.1.4.1.9999.42", "1.3.6.1.4.1.9999.42.1", "1.3.6.1.4.1.9999.42.1.1")
  )

  kp <- dicom_key_provider(passphrase = "layout-test-key", salt = "layout-salt")

  # Hierarchy layout: <pseudo_pid>/<pseudo_study>/<pseudo_sop>.dcm
  res_h <- dicom_deid(path = in_dir, out_dir = out_hier, layout = "hierarchy", key = kp)
  expect_equal(length(res_h$files), 1L)
  rel_h <- sub(paste0("^", normalizePath(out_hier, winslash = "/"), "/?"), "", normalizePath(res_h$files[1L], winslash = "/"))
  parts <- strsplit(rel_h, "/", fixed = TRUE)[[1L]]
  expect_equal(length(parts), 3L)
  expect_match(parts[1L], "^SUBJ-[0-9A-F]{12}$")
  expect_match(parts[2L], "^2\\.25\\.[1-9][0-9]*$")
  expect_match(parts[3L], "^2\\.25\\.[1-9][0-9]*\\.dcm$")

  # Flat layout: <pseudo_sop>.dcm directly in out_dir
  res_f <- dicom_deid(path = in_dir, out_dir = out_flat, layout = "flat", key = kp)
  expect_equal(length(res_f$files), 1L)
  rel_f <- sub(paste0("^", normalizePath(out_flat, winslash = "/"), "/?"), "", normalizePath(res_f$files[1L], winslash = "/"))
  expect_match(rel_f, "^2\\.25\\.[1-9][0-9]*\\.dcm$")
})

test_that("dicom_anonymize() emits lifecycle soft-deprecation warning and maintains backward compatibility", {
  dcm <- tempfile(fileext = ".dcm")
  on.exit(unlink(dcm), add = TRUE)
  dicomtk:::cpp_write_dicom_matrix(
    matrix(1:4, 2, 2),
    out_path = dcm,
    meta_tags = c("PatientName", "PatientID", "Modality"),
    meta_values = c("ANON^TEST", "ID001", "CT")
  )

  withr::with_options(
    list(lifecycle_verbosity = "warning"),
    expect_warning(
      dicom_anonymize(dcm),
      class = "lifecycle_warning_deprecated"
    )
  )
})
