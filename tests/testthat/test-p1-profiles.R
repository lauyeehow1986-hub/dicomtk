test_that("Default dicom_deid_profile() loads PS3.15 basic and resolves compound action codes to atomic actions", {
  p0 <- dicom_deid_profile()
  expect_s3_class(p0, "dicom_deid_profile")
  expect_equal(p0$profile, "ps3.15")

  # CID 7050 code 113100 Basic Application Confidentiality Profile
  expect_true("113100" %in% names(p0$cid7050_codes) || "113100" %in% p0$cid7050_codes)

  # Check tags structure and atomic actions
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
