test_that("as_fhir_imaging_study and from_fhir_imaging_study round-trip Study/Series metadata", {
  synth <- dicom_synthesize(modality = "CT", dims = c(16L, 16L, 3L))
  on.exit(unlink(synth[["out_dir"]], recursive = TRUE), add = TRUE)

  vol <- read_dicom_volume(synth[["out_dir"]])
  study <- as_fhir_imaging_study(vol, patient_ref = "Patient/p-001")
  expect_type(study, "list")
  expect_equal(study$resourceType, "ImagingStudy")
  expect_equal(study$status, "available")
  expect_equal(study$subject$reference, "Patient/p-001")
  expect_gte(study$numberOfSeries, 1L)
  expect_gte(study$numberOfInstances, 3L)
  expect_true(grepl("^urn:dicom:uid:", study$identifier[[1L]]$value))

  rt <- from_fhir_imaging_study(study)
  expect_s3_class(rt, "tbl_df")
  expect_true(all(c("study_uid", "series_uid", "modality", "number_of_instances", "patient_ref") %in% names(rt)))
  expect_equal(rt$modality[1L], "CT")
  expect_equal(rt$patient_ref[1L], "Patient/p-001")
})

test_that("as_fhir_imaging_selection builds valid ImagingSelection from dicom_seg and dicom_gsps", {
  synth <- dicom_synthesize(modality = "CT", dims = c(16L, 16L, 3L))
  on.exit(unlink(synth[["out_dir"]], recursive = TRUE), add = TRUE)

  vol <- read_dicom_volume(synth[["out_dir"]])
  mask <- array(0L, dim = dim(vol))
  mask[5:10, 5:10, 2] <- 1L
  seg <- dicom_seg(mask, vol, tibble::tibble(segment_id = 1L, label = "Lesion"))

  sel_seg <- as_fhir_imaging_selection(seg, study_ref = "ImagingStudy/s-001")
  expect_equal(sel_seg$resourceType, "ImagingSelection")
  expect_equal(sel_seg$status, "available")
  expect_equal(sel_seg$derivedFrom[[1L]]$reference, "ImagingStudy/s-001")
  expect_true(!is.null(sel_seg$imageRegion3D))

  ann <- tibble::tibble(
    slice = 2L,
    layer = "ROI_LAYER",
    graphic_type = "POLYLINE",
    coords = list(c(4, 4, 12, 4, 12, 12, 4, 12, 4, 4)),
    text = "Target"
  )
  gsps_path <- tempfile(fileext = ".dcm")
  on.exit(unlink(gsps_path), add = TRUE)
  write_dicom_gsps(ann, out_path = gsps_path, ref_volume = vol)
  gsps <- read_dicom_gsps(gsps_path)
  sel_gsps <- as_fhir_imaging_selection(gsps, study_ref = "ImagingStudy/s-001")
  expect_equal(sel_gsps$resourceType, "ImagingSelection")
  expect_true(!is.null(sel_gsps$imageRegion2D))
})

test_that("as_fhir_diagnostic_report and as_fhir_provenance convert TID 1500 SR and de-id provenance", {
  synth <- dicom_synthesize(modality = "CT", dims = c(16L, 16L, 3L), phi_profile = "basic")
  sr_path <- tempfile(fileext = ".dcm")
  deid_dir <- tempfile("fhir_deid_")
  on.exit(unlink(c(synth[["out_dir"]], sr_path, deid_dir), recursive = TRUE), add = TRUE)

  vol <- read_dicom_volume(synth[["out_dir"]])
  mask <- array(0L, dim = dim(vol))
  mask[4:10, 4:10, 1:2] <- 1L
  seg <- dicom_seg(mask, vol, tibble::tibble(segment_id = 1L, label = "Nodule"))
  dicom_sr_tid1500(vol = vol, seg = seg, out_path = sr_path, title = "Lung Nodule Report")
  sr <- read_sr_tid1500(sr_path)

  dr <- as_fhir_diagnostic_report(sr, patient_ref = "Patient/p-001", imaging_study_ref = "ImagingStudy/s-001")
  expect_equal(dr$resourceType, "DiagnosticReport")
  expect_equal(dr$status, "final")
  expect_true(length(dr$contained) >= 1L)
  expect_equal(dr$contained[[1L]]$resourceType, "Observation")

  deid_res <- dicom_deid(synth[["out_dir"]], out_dir = deid_dir, profile = dicom_deid_profile("ps3.15"))
  prov <- as_fhir_provenance(deid_res, target_ref = "ImagingStudy/s-001", agent_name = "dicomtk-deid")
  expect_equal(prov$resourceType, "Provenance")
  expect_equal(prov$target[[1L]]$reference, "ImagingStudy/s-001")

  w3c <- as_w3c_prov(deid_res, agent_name = "dicomtk-deid")
  expect_true(all(c("entity", "activity", "agent") %in% names(w3c)))
})
