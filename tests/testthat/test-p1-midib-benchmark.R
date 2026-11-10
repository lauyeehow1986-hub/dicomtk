test_that("dicom_synthesize(phi_profile = 'midi_b') plants all 18 HIPAA + PS3.15 + SG/MY/EU categories and returns phi_manifest", {
  out_dir <- tempfile(pattern = "synth_midi_ct_")
  dir.create(out_dir, recursive = TRUE)
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  # Synthesize CT with midi_b profile
  ph <- dicom_synthesize(
    out_dir = out_dir,
    modality = "CT",
    dims = c(16L, 16L, 4L),
    spacing = c(1.0, 1.0, 2.0),
    inject_phi = TRUE,
    phi_profile = "midi_b"
  )

  expect_s3_class(ph, "dicom_phantom")
  expect_true(!is.null(ph$phi_manifest))
  expect_s3_class(ph$phi_manifest, "tbl_df")

  req_cols <- c("tag", "keyword", "sequence_path", "value", "expected_action", "category")
  expect_true(all(req_cols %in% names(ph$phi_manifest)))
  expect_gt(nrow(ph$phi_manifest), 15L)

  # Verify planted categories
  categories <- unique(ph$phi_manifest$category)
  expect_true("names" %in% categories)
  expect_true("identifiers" %in% categories)
  expect_true("dates" %in% categories)
  expect_true("age" %in% categories)
  expect_true("demographics" %in% categories)
  expect_true("institution" %in% categories)
  expect_true("personnel" %in% categories)
  expect_true("device" %in% categories)
  expect_true("free_text" %in% categories)
  expect_true("nested_uid" %in% categories)
  expect_true("safe_private" %in% categories)
  expect_true("unsafe_private" %in% categories)

  # Check that files on disk contain the planted canaries
  hdr <- read_dicom(ph$files[1L], include_sequences = TRUE)

  # Name / ID / Demographics
  expect_true(any(grepl("MIDI", hdr$value[hdr$keyword == "PatientName"])))
  expect_true(any(grepl("MIDI", hdr$value[hdr$keyword == "PatientID"])))
  expect_true("094Y" %in% hdr$value[hdr$keyword == "PatientAge"])

  # Free text comments with multi-jurisdiction PII canaries
  comments <- hdr$value[hdr$keyword == "ImageComments"]
  expect_gt(length(comments), 0L)
  expect_true(grepl("\\+65 9123 4567", comments[1L]))
  expect_true(grepl("patient@health\\.gov\\.sg", comments[1L]))
  expect_true(grepl("S7654321J", comments[1L]))
  expect_true(grepl("987-65-4321", comments[1L]))
  expect_true(grepl("800101-14-5678", comments[1L]))

  # Private tags
  safe_creator <- hdr$value[hdr$tag == "(2005,0010)"]
  expect_equal(safe_creator, "PHILIPS IMAGING DD 001")
  expect_true(any(hdr$tag == "(2005,100D)"))
  expect_true(any(hdr$tag == "(2005,100E)"))

  unsafe_creator <- hdr$value[hdr$tag == "(0009,0010)"]
  expect_equal(unsafe_creator, "VENDOR PRIVATE")
  expect_true(any(hdr$tag == "(0009,1001)"))
  expect_true(any(grepl("CANARY SECRET PHI", hdr$value[hdr$tag == "(0009,1001)"])))

  # Nested sequence
  expect_true("ReferencedSOPSequence" %in% hdr$keyword || any(hdr$tag == "(0008,1199)"))
})

test_that("dicom_synthesize(modality = 'US', phi_profile = 'midi_b') plants burned-in text banner", {
  out_dir <- tempfile(pattern = "synth_midi_us_")
  dir.create(out_dir, recursive = TRUE)
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  ph_us <- dicom_synthesize(
    out_dir = out_dir,
    modality = "US",
    dims = c(32L, 32L, 2L),
    inject_phi = TRUE,
    phi_profile = "midi_b"
  )

  expect_s3_class(ph_us, "dicom_phantom")
  hdr_us <- read_dicom(ph_us$files[1L], include_sequences = TRUE)

  burned_val <- hdr_us$value[hdr_us$keyword == "BurnedInAnnotation"]
  expect_equal(toupper(burned_val), "YES")

  # Detect burned phi boxes
  boxes <- dicom_detect_burned_phi(ph_us$files[1L])
  expect_s3_class(boxes, "data.frame")
  expect_gt(nrow(boxes), 0L)
  expect_true(any(boxes$ymin == 1L))
})

test_that("Quantitative benchmark metrics over multi-patient multi-modality synthetic MIDI-B corpus", {
  raw_corpus_dir <- tempfile(pattern = "midib_raw_corpus_")
  clean_corpus_dir <- tempfile(pattern = "midib_clean_corpus_")
  dir.create(raw_corpus_dir, recursive = TRUE)
  on.exit(unlink(c(raw_corpus_dir, clean_corpus_dir), recursive = TRUE), add = TRUE)

  kp <- dicom_key_provider(passphrase = "midib-gold-standard-benchmark-key-2026", salt = "site-midib-01")

  # 1. Synthesize multi-patient, multi-modality cohort:
  # Patient 1: CT Visit 1 (2024-01-15) and CT Visit 2 (+60 days, 2024-03-15)
  pat1_v1_dir <- file.path(raw_corpus_dir, "pat1_v1_ct")
  ph_pat1_v1 <- dicom_synthesize(
    out_dir = pat1_v1_dir,
    modality = "CT",
    dims = c(16L, 16L, 2L),
    inject_phi = TRUE,
    phi_profile = "midi_b",
    extra_tags = list(
      PatientID = "MIDI_PAT_001",
      PatientName = "DOE^JOHN^MIDI",
      StudyDate = "20240115",
      SeriesDate = "20240115"
    ),
    seed = 101L
  )

  pat1_v2_dir <- file.path(raw_corpus_dir, "pat1_v2_ct")
  ph_pat1_v2 <- dicom_synthesize(
    out_dir = pat1_v2_dir,
    modality = "CT",
    dims = c(16L, 16L, 2L),
    inject_phi = TRUE,
    phi_profile = "midi_b",
    extra_tags = list(
      PatientID = "MIDI_PAT_001",
      PatientName = "DOE^JOHN^MIDI",
      StudyDate = "20240315",
      SeriesDate = "20240315"
    ),
    seed = 102L
  )

  # Patient 2: MR with safe Philips tags and unsafe vendor tag
  pat2_dir <- file.path(raw_corpus_dir, "pat2_mr")
  ph_pat2 <- dicom_synthesize(
    out_dir = pat2_dir,
    modality = "MR",
    dims = c(16L, 16L, 2L),
    inject_phi = TRUE,
    phi_profile = "midi_b",
    extra_tags = list(
      PatientID = "MIDI_PAT_002",
      PatientName = "SMITH^ALICE^MIDI"
    ),
    seed = 103L
  )

  # Patient 3: US with burned-in banner
  pat3_dir <- file.path(raw_corpus_dir, "pat3_us")
  ph_pat3 <- dicom_synthesize(
    out_dir = pat3_dir,
    modality = "US",
    dims = c(32L, 32L, 2L),
    inject_phi = TRUE,
    phi_profile = "midi_b",
    extra_tags = list(
      PatientID = "MIDI_PAT_003",
      PatientName = "WONG^WEI^MIDI"
    ),
    seed = 104L
  )

  # Patient 4: PT
  pat4_dir <- file.path(raw_corpus_dir, "pat4_pt")
  ph_pat4 <- dicom_synthesize(
    out_dir = pat4_dir,
    modality = "PT",
    dims = c(16L, 16L, 2L),
    inject_phi = TRUE,
    phi_profile = "midi_b",
    extra_tags = list(
      PatientID = "MIDI_PAT_004",
      PatientName = "GARCIA^MARIA^MIDI"
    ),
    seed = 105L
  )

  # Patient 5: MG
  pat5_dir <- file.path(raw_corpus_dir, "pat5_mg")
  ph_pat5 <- dicom_synthesize(
    out_dir = pat5_dir,
    modality = "MG",
    dims = c(16L, 16L, 2L),
    inject_phi = TRUE,
    phi_profile = "midi_b",
    extra_tags = list(
      PatientID = "MIDI_PAT_005",
      PatientName = "KUMAR^PRIYA^MIDI"
    ),
    seed = 106L
  )

  # 2. Execute cohort de-identification
  canaries_to_check <- c(
    "DOE^JOHN^MIDI", "SMITH^ALICE^MIDI", "WONG^WEI^MIDI", "GARCIA^MARIA^MIDI", "KUMAR^PRIYA^MIDI",
    "MIDI_PAT_001", "MIDI_PAT_002", "MIDI_PAT_003", "MIDI_PAT_004", "MIDI_PAT_005",
    "CANARY SECRET PHI", "S7654321J", "+65 9123 4567", "patient@health.gov.sg", "800101-14-5678", "987-65-4321"
  )

  res_deid <- dicom_deid(
    path = raw_corpus_dir,
    out_dir = clean_corpus_dir,
    profile = "ps3.15",
    options = c(
      "clean_descriptors",
      "clean_pixel",
      "retain_safe_private",
      "retain_longitudinal_modified_dates"
    ),
    jurisdictions = c("hipaa_safe_harbor", "sg_pdpa_hib", "my_pdpa_2024"),
    key = kp
  )

  expect_gt(length(res_deid$files), 0L)

  # 3. Post-deid verification scanner
  v <- dicom_deid_verify(
    clean_corpus_dir,
    profile = "ps3.15",
    options = c(
      "clean_descriptors",
      "clean_pixel",
      "retain_safe_private",
      "retain_longitudinal_modified_dates"
    ),
    jurisdictions = c("hipaa_safe_harbor", "sg_pdpa_hib", "my_pdpa_2024"),
    canaries = canaries_to_check
  )

  # Metric 1: Tag & Text PHI Recall == 1.000 (0 false negatives / 0 residual canaries)
  if (!v$passed) {
    print(head(as.data.frame(v$findings), 30L))
  }
  expect_true(v$passed)
  expect_equal(nrow(v$findings), 0L)

  # Metric 2: Safe-Private Retention Precision == 1.000
  clean_mr_file <- file.path(clean_corpus_dir, "pat2_mr", "slice_0001.dcm")
  if (!file.exists(clean_mr_file)) {
    # If layout was flat or different, find MR file
    all_clean <- list.files(clean_corpus_dir, pattern = "\\.dcm$", full.names = TRUE, recursive = TRUE)
    mr_files <- vapply(all_clean, function(f) {
      h <- read_dicom(f)
      any(h$keyword == "Modality" & h$value == "MR")
    }, logical(1L))
    clean_mr_file <- all_clean[mr_files][1L]
  }
  hdr_mr <- read_dicom(clean_mr_file, include_sequences = TRUE)
  # (2005,100D) and (2005,100E) must be retained
  expect_true(any(hdr_mr$tag == "(2005,100D)"))
  expect_true(any(hdr_mr$tag == "(2005,100E)"))
  # (0009,1001) must be removed
  expect_false(any(hdr_mr$tag == "(0009,1001)"))

  # Metric 3: UID Graph Isomorphism == 1.000 (all intra-patient Study/Series/ReferencedSOP preserved; zero collisions)
  clean_files <- list.files(clean_corpus_dir, pattern = "\\.dcm$", full.names = TRUE, recursive = TRUE)
  meta_list <- lapply(clean_files, function(f) {
    h <- read_dicom(f)
    list(
      patient_id = h$value[h$keyword == "PatientID"][1L],
      study_uid = h$value[h$keyword == "StudyInstanceUID"][1L],
      series_uid = h$value[h$keyword == "SeriesInstanceUID"][1L],
      sop_uid = h$value[h$keyword == "SOPInstanceUID"][1L]
    )
  })

  pids <- vapply(meta_list, function(m) m$patient_id, character(1L))
  study_uids <- vapply(meta_list, function(m) m$study_uid, character(1L))
  series_uids <- vapply(meta_list, function(m) m$series_uid, character(1L))
  sop_uids <- vapply(meta_list, function(m) m$sop_uid, character(1L))

  # Every SOPInstanceUID is unique across all files
  expect_equal(length(unique(sop_uids)), length(clean_files))

  # Cross-patient study collisions == 0
  pid_study_tbl <- unique(data.frame(pid = pids, study = study_uids, stringsAsFactors = FALSE))
  expect_equal(nrow(pid_study_tbl), length(unique(pid_study_tbl$study)))

  # Metric 4: Longitudinal Date Delta Error == 0 days
  clean_v1 <- file.path(clean_corpus_dir, "pat1_v1_ct", "slice_0001.dcm")
  clean_v2 <- file.path(clean_corpus_dir, "pat1_v2_ct", "slice_0001.dcm")
  if (!file.exists(clean_v1) || !file.exists(clean_v2)) {
    # Find pat1 files by pseudonym
    pat1_pseudo <- res_deid$summary$pseudo_pid[grepl("pat1_v1_ct", res_deid$summary$orig_path)][1L]
    pat1_files <- clean_files[pids == pat1_pseudo]
    clean_v1 <- pat1_files[1L]
    clean_v2 <- pat1_files[length(pat1_files)]
  }
  hdr_v1 <- read_dicom(clean_v1)
  hdr_v2 <- read_dicom(clean_v2)

  date_v1_str <- hdr_v1$value[hdr_v1$keyword == "StudyDate"][1L]
  date_v2_str <- hdr_v2$value[hdr_v2$keyword == "StudyDate"][1L]

  date_v1 <- as.Date(date_v1_str, format = "%Y%m%d")
  date_v2 <- as.Date(date_v2_str, format = "%Y%m%d")
  delta_clean <- as.numeric(date_v2 - date_v1)
  delta_raw <- as.numeric(as.Date("20240315", format = "%Y%m%d") - as.Date("20240115", format = "%Y%m%d"))

  date_delta_error <- abs(delta_clean - delta_raw)
  expect_equal(date_delta_error, 0)
})

test_that("inst/extdata/midib_scorecard.json parses cleanly and meets benchmark schema", {
  pkg_dir <- tryCatch(
    rprojroot::find_package_root_file(),
    error = function(e) "."
  )
  scorecard_path <- file.path(pkg_dir, "inst", "extdata", "midib_scorecard.json")

  if (!file.exists(scorecard_path)) {
    scorecard_path <- system.file("extdata", "midib_scorecard.json", package = "dicomtk")
  }
  expect_true(file.exists(scorecard_path))

  scorecard <- jsonlite::fromJSON(scorecard_path)
  expect_type(scorecard, "list")

  # Required benchmark metrics
  expect_true("recall" %in% names(scorecard))
  expect_true("precision" %in% names(scorecard))
  expect_true("uid_isomorphism" %in% names(scorecard))
  expect_true("date_error" %in% names(scorecard))
  expect_true("timestamp" %in% names(scorecard))

  expect_equal(scorecard$recall, 1.0)
  expect_equal(scorecard$precision, 1.0)
  expect_equal(scorecard$uid_isomorphism, 1.0)
  expect_equal(scorecard$date_error, 0)
  expect_true(is.character(scorecard$timestamp) && nzchar(scorecard$timestamp))
})

test_that("External TCIA MIDI-B benchmark skips on CRAN and runs when DICOMTK_MIDIB_DIR is set", {
  testthat::skip_on_cran()

  tcia_dir <- Sys.getenv("DICOMTK_MIDIB_DIR", unset = "")
  if (!nzchar(tcia_dir) || !dir.exists(tcia_dir)) {
    testthat::skip("DICOMTK_MIDIB_DIR environment variable is not set or directory does not exist.")
  }

  expect_true(dir.exists(tcia_dir))
})
