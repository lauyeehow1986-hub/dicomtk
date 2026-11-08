test_that("Default dicom_deid_profile() loads PS3.15 basic and resolves compound action codes to atomic actions", {
  p0 <- dicom_deid_profile()
  expect_s3_class(p0, "dicom_deid_profile")
  expect_equal(p0$profile, "ps3.15")

  # CID 7050 code 113100 Basic Application Confidentiality Profile
  expect_true("113100" %in% names(p0$cid7050_codes) || "113100" %in% p0$cid7050_codes)

  # Check tags structure and atomic actions
  expect_s3_class(p0$tags, "tbl_df")
  expect_s3_class(p0$tags, "data.frame")
  expect_gt(nrow(p0$tags), 200L)
  expect_true(all(p0$tags$action %in% c("X", "Z", "D", "U", "C", "K")))
  expect_false(any(grepl("/", p0$tags$action)))
  expect_false(any(grepl("\\*", p0$tags$action)))

  # Core UIDs are mapped with atomic action U
  tag_map <- setNames(p0$tags$action, toupper(p0$tags$tag))
  expect_equal(tag_map[["(0020,000D)"]], "U") # StudyInstanceUID
  expect_equal(tag_map[["(0020,000E)"]], "U") # SeriesInstanceUID
  expect_equal(tag_map[["(0008,0018)"]], "U") # SOPInstanceUID

  # Format and print methods
  out <- capture.output(print(p0))
  expect_true(any(grepl("PS3.15|Confidentiality Profile|dicom_deid_profile", out, ignore.case = TRUE)))
})

test_that("Enabling options updates CID 7050 codes, date policy, and safe private dictionary", {
  p_opts <- dicom_deid_profile(options = c("retain_longitudinal_modified_dates", "retain_safe_private"))

  # CID 7050 codes 113107 and 113111
  codes <- if (is.null(names(p_opts$cid7050_codes))) p_opts$cid7050_codes else names(p_opts$cid7050_codes)
  expect_true("113100" %in% codes)
  expect_true("113107" %in% codes)
  expect_true("113111" %in% codes)

  # Date policy switches to shift_per_patient
  expect_equal(p_opts$date_policy, "shift_per_patient")

  # Safe private dictionary contains expected creators
  expect_true(length(p_opts$safe_private) > 0L)
  creators <- toupper(names(p_opts$safe_private))

  expect_true(any(grepl("PHILIPS MR IMAGING DD 005|PHILIPS IMAGING DD 001", creators)))
  expect_true(any(grepl("PHILIPS PET PRIVATE GROUP", creators)))
  expect_true(any(grepl("GEMS_ACQU_01", creators)))
  expect_true(any(grepl("SIEMENS MR HEADER", creators)))

  # Offsets 0x0D / 0x0E for Philips MR scale factors
  philips_mr <- p_opts$safe_private[[grep("PHILIPS MR IMAGING DD 005|PHILIPS IMAGING DD 001", names(p_opts$safe_private), value = TRUE)[1]]]
  expect_true(any(c(0x0D, 13L, "0x0D", "0D") %in% philips_mr$offsets | c(0x0D, 13L) %in% philips_mr))
  expect_true(any(c(0x0E, 14L, "0x0E", "0E") %in% philips_mr$offsets | c(0x0E, 14L) %in% philips_mr))
})

test_that("dicom_list_jurisdictions() lists all 8 built-in jurisdictions", {
  jurs <- dicom_list_jurisdictions()
  expected_8 <- c(
    "au_privacy_nhmrc",
    "gdpr",
    "hipaa_expert_determination",
    "hipaa_safe_harbor",
    "my_pdpa_2024",
    "sg_pdpa_hib",
    "tcia_ctp",
    "uk_gdpr"
  )
  expect_equal(sort(jurs), sort(expected_8))
})

test_that("Single jurisdiction sg_pdpa_hib configures NRIC scrubbing and MOH HIB flags", {
  p_sg <- dicom_deid_profile(jurisdictions = "sg_pdpa_hib")

  # Regex scrubber includes NRIC/FIN pattern
  expect_true(any(grepl("\\[STFGM\\]\\[0-9\\]\\{7\\}\\[A-Z\\]", p_sg$regex_scrubbers)))

  # MOH HIB flag
  expect_true(isTRUE(p_sg$flags$hib_enclave) || isTRUE(p_sg$flags$shi_enclave))

  # Disclaimer is present
  expect_true(any(grepl("not legal advice", p_sg$disclaimers, ignore.case = TRUE)))
})

test_that("Multiple jurisdictions merge monotonically under K < C < U < D < Z < X lattice", {
  base_p <- dicom_deid_profile()
  multi_p <- dicom_deid_profile(jurisdictions = c("sg_pdpa_hib", "my_pdpa_2024", "hipaa_safe_harbor", "gdpr"))

  # Age cap resolves to 89Y under HIPAA Safe Harbor
  expect_equal(as.integer(multi_p$age_cap_years), 89L)

  # Regex scrubbers union cleanly
  expect_true(any(grepl("\\[STFGM\\]\\[0-9\\]\\{7\\}\\[A-Z\\]", multi_p$regex_scrubbers)))
  expect_true(any(grepl("[0-9]{6}", multi_p$regex_scrubbers, fixed = TRUE)))

  # Monotonicity invariant: rank(action_with_jurisdictions) >= rank(action_base)
  # Lattice order: K (1) < C (2) < U (3) < D (4) < Z (5) < X (6)
  ranks <- c(K = 1L, C = 2L, U = 3L, D = 4L, Z = 5L, X = 6L)

  base_tags <- setNames(base_p$tags$action, toupper(base_p$tags$tag))
  multi_tags <- setNames(multi_p$tags$action, toupper(multi_p$tags$tag))

  common_tags <- intersect(names(base_tags), names(multi_tags))
  expect_gt(length(common_tags), 100L)

  diff_violations <- character(0)
  for (tg in common_tags) {
    r_base <- ranks[base_tags[[tg]]]
    r_multi <- ranks[multi_tags[[tg]]]
    if (r_multi < r_base) {
      diff_violations <- c(diff_violations, sprintf("%s: base=%s (%d), multi=%s (%d)",
                                                    tg, base_tags[[tg]], r_base,
                                                    multi_tags[[tg]], r_multi))
    }
  }
  expect_equal(diff_violations, character(0))
})

test_that("Custom user YAML profile loading works", {
  tmp_yaml <- tempfile(fileext = ".yml")
  on.exit(unlink(tmp_yaml), add = TRUE)

  yaml_content <- paste(
    "name: custom_trial_profile",
    "description: Custom trial deid profile",
    "cid7050_codes:",
    "  113100: Basic Application Confidentiality Profile",
    "date_policy: shift_per_patient",
    "age_cap_years: 85",
    "tags:",
    "  '(0010,0010)': Z",
    "  '(0010,0020)': Z",
    "  '(0020,000D)': U",
    "  '(0008,1030)': C",
    "  '(0008,0080)': X",
    "regex_scrubbers:",
    "  - 'TRIAL-[0-9]{4}'",
    sep = "\n"
  )
  writeLines(yaml_content, tmp_yaml)

  p_custom <- dicom_deid_profile(file = tmp_yaml)
  expect_s3_class(p_custom, "dicom_deid_profile")
  expect_equal(p_custom$date_policy, "shift_per_patient")
  expect_equal(as.integer(p_custom$age_cap_years), 85L)
  expect_true(any(grepl("TRIAL", p_custom$regex_scrubbers)))

  tag_map <- setNames(p_custom$tags$action, toupper(p_custom$tags$tag))
  expect_equal(tag_map[["(0010,0010)"]], "Z")
  expect_equal(tag_map[["(0008,1030)"]], "C")
  expect_equal(tag_map[["(0008,0080)"]], "X")
})

test_that("Unknown options or jurisdictions abort with clear cli::cli_abort", {
  expect_error(
    dicom_deid_profile(options = "non_existent_option_xyz"),
    class = "rlang_error"
  )
  expect_error(
    dicom_deid_profile(jurisdictions = "mars_privacy_law_2099"),
    class = "rlang_error"
  )
})

test_that("Jurisdiction date_policy merges along strictest lattice when no explicit date option is passed", {
  p_hipaa <- dicom_deid_profile(jurisdictions = "hipaa_safe_harbor")
  expect_equal(p_hipaa$date_policy, "year_only")

  p_sg <- dicom_deid_profile(jurisdictions = "sg_pdpa_hib")
  expect_equal(p_sg$date_policy, "shift_per_patient")

  # Strictest wins: shift_per_patient (2) < year_only (3)
  p_multi <- dicom_deid_profile(jurisdictions = c("sg_pdpa_hib", "hipaa_safe_harbor"))
  expect_equal(p_multi$date_policy, "year_only")

  # Explicit PS3.15 date option retains user intent over jurisdiction policy
  p_override <- dicom_deid_profile(
    options = "retain_longitudinal_full_dates",
    jurisdictions = "hipaa_safe_harbor"
  )
  expect_equal(p_override$date_policy, "keep")
})

test_that("override_tags normalizes whitespace in tag keys", {
  p_norm <- dicom_deid_profile(override_tags = list("(0010, 0010)" = "X", " (0008, 1030) " = "Z"))
  tag_map <- setNames(p_norm$tags$action, p_norm$tags$tag)
  expect_equal(tag_map[["(0010,0010)"]], "X")
  expect_equal(tag_map[["(0008,1030)"]], "Z")
})

test_that("options and jurisdictions are cleanly deduplicated", {
  p_dup <- dicom_deid_profile(
    options = c("clean_pixel_data", "clean_pixel_data", "clean_graphics"),
    jurisdictions = c("gdpr", "gdpr", "sg_pdpa_hib")
  )
  expect_equal(p_dup$options, c("clean_pixel_data", "clean_graphics"))
  expect_equal(p_dup$jurisdictions, c("gdpr", "sg_pdpa_hib"))
})

test_that("sg_pdpa_hib keeps month and year for date of birth but not day (dob_policy year_month)", {
  p_sg <- dicom_deid_profile(jurisdictions = "sg_pdpa_hib")
  expect_equal(p_sg$dob_policy, "year_month")
})

test_that("date_shift can be explicitly turned on or off", {
  # Explicitly turned off even with sg_pdpa_hib
  p_off <- dicom_deid_profile(jurisdictions = "sg_pdpa_hib", date_shift = FALSE)
  expect_identical(p_off$date_shift, FALSE)
  expect_false(p_off$date_policy == "shift_per_patient")

  # Explicitly turned on
  p_on <- dicom_deid_profile(date_shift = TRUE)
  expect_identical(p_on$date_shift, TRUE)
  expect_equal(p_on$date_policy, "shift_per_patient")
})

test_that("patient deidentification can be turned off for operational use", {
  # Patient identity preserved for operational use
  p_ops <- dicom_deid_profile(patient_deid = FALSE)
  expect_false(p_ops$patient_deid)
  tag_map <- setNames(p_ops$tags$action, p_ops$tags$tag)
  expect_equal(tag_map[["(0010,0010)"]], "K") # PatientName
  expect_equal(tag_map[["(0010,0020)"]], "K") # PatientID
  expect_equal(tag_map[["(0010,0030)"]], "K") # PatientBirthDate
  expect_equal(tag_map[["(0010,0040)"]], "K") # PatientSex

  # Entire de-identification bypassed for operational passthrough
  p_pass <- dicom_deid_profile(deidentify = FALSE)
  expect_false(p_pass$deidentify)
  expect_true(all(p_pass$tags$action == "K"))
  expect_equal(p_pass$date_policy, "keep")
})
