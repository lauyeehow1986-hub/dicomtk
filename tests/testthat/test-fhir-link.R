test_that("link_synthea_cohort joins Synthea FHIR bundles with DICOM studies", {
  synth <- dicom_synthesize(modality = "CT", dims = c(8L, 8L, 2L), phi_profile = "basic")
  fhir_dir <- tempfile("synthea_fhir_")
  dir.create(fhir_dir, recursive = TRUE)
  on.exit(unlink(c(synth[["out_dir"]], fhir_dir), recursive = TRUE), add = TRUE)

  hdr <- read_dicom(synth[["out_dir"]], wide = TRUE)
  study_uid <- hdr$StudyInstanceUID[1L]
  patient_id <- hdr$PatientID[1L]

  bundle <- list(
    resourceType = "Bundle",
    type = "collection",
    entry = list(
      list(resource = list(
        resourceType = "Patient",
        id = "pat-101",
        identifier = list(list(value = patient_id)),
        gender = "female",
        birthDate = "1975-04-12"
      )),
      list(resource = list(
        resourceType = "Condition",
        id = "cond-101",
        subject = list(reference = "Patient/pat-101"),
        code = list(coding = list(list(code = "254637007", display = "Non-small cell lung cancer")))
      )),
      list(resource = list(
        resourceType = "ImagingStudy",
        id = "img-101",
        identifier = list(list(system = "urn:dicom:uid", value = paste0("urn:dicom:uid:", study_uid))),
        subject = list(reference = "Patient/pat-101")
      ))
    )
  )
  jsonlite::write_json(bundle, file.path(fhir_dir, "patient_101.json"), auto_unbox = TRUE)

  cohort <- link_synthea_cohort(dicom_source = synth[["out_dir"]], fhir_dir = fhir_dir)
  expect_s3_class(cohort, "tbl_df")
  expect_gte(nrow(cohort), 1L)
  expect_true(all(c(
    "patient_id", "gender", "birth_date", "condition_code",
    "condition_display", "study_uid", "series_uid", "modality", "n_instances"
  ) %in% names(cohort)))
  expect_equal(cohort$study_uid[1L], study_uid)
  expect_equal(cohort$gender[1L], "female")
  expect_equal(cohort$condition_code[1L], "254637007")
})

test_that("fhir_post and fhir_get support local directory mock FHIR store", {
  mock_fhir <- tempfile("mock_fhir_srv_")
  dir.create(mock_fhir, recursive = TRUE)
  on.exit(unlink(mock_fhir, recursive = TRUE), add = TRUE)

  study <- list(
    resourceType = "ImagingStudy",
    id = "study-abc",
    status = "available",
    numberOfSeries = 1L
  )
  posted <- fhir_post(study, base_url = mock_fhir)
  expect_equal(posted$id, "study-abc")

  got <- fhir_get("ImagingStudy", id = "study-abc", base_url = mock_fhir)
  expect_equal(got$resourceType, "ImagingStudy")
  expect_equal(got$id, "study-abc")
})
