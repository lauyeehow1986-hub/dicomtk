# Task 8: dicomtk-lab Core PACS (Orthanc, dcm4chee, Keycloak) Integration Smoke Test

test_that("dicomtk-lab Orthanc core container connects, echoes, round-trips series, and preserves exact affine", {
  skip_if_not(
    identical(tolower(Sys.getenv("DICOMTK_TEST_LAB")), "true"),
    "dicomtk-lab container smoke tests skipped. Set DICOMTK_TEST_LAB=true to run."
  )

  orthanc_host <- Sys.getenv("DICOMTK_LAB_ORTHANC_HOST", "127.0.0.1")
  dimse_port   <- as.integer(Sys.getenv("DICOMTK_LAB_ORTHANC_PORT", "4242"))
  http_port    <- as.integer(Sys.getenv("DICOMTK_LAB_ORTHANC_HTTP", "8042"))
  called_ae    <- Sys.getenv("DICOMTK_LAB_ORTHANC_AET", "ORTHANC")

  # 1. Verify HTTP REST API health
  rest_url <- sprintf("http://%s:%d/system", orthanc_host, http_port)
  sys_info <- tryCatch({
    req <- httr2::request(rest_url) |>
      httr2::req_timeout(5)
    resp <- httr2::req_perform(req)
    httr2::resp_body_json(resp)
  }, error = function(e) {
    skip(sprintf("Orthanc HTTP endpoint not responding at %s: %s", rest_url, conditionMessage(e)))
  })

  expect_type(sys_info, "list")
  expect_true(!is.null(sys_info$Version))
  expect_equal(sys_info$DicomAet, called_ae)

  # 2. Verify DIMSE C-ECHO SCU -> SCP
  conn <- dicom_connect(
    host = orthanc_host,
    port = dimse_port,
    called_ae = called_ae,
    calling_ae = "DICOMTK",
    timeout_ms = 5000L
  )
  echo_res <- dicom_echo(conn)
  expect_s3_class(echo_res, "tbl_df")
  expect_true(isTRUE(echo_res$success[1L]))
  expect_equal(echo_res$status[1L], "SUCCESS")

  # 3. Synthesize a 4-slice oblique CT phantom with exact ground truth geometry
  synth_dir <- tempfile("lab_synth_")
  dl_dir    <- tempfile("lab_dl_")
  on.exit(unlink(c(synth_dir, dl_dir), recursive = TRUE), add = TRUE)

  ph <- dicom_synthesize(
    out_dir = synth_dir,
    modality = "CT",
    dims = c(16L, 16L, 4L),
    spacing = c(0.8, 0.9, 2.5),
    origin = c(-15.0, -12.0, 5.0),
    orientation = "oblique",
    oblique_angles_deg = c(12, -8, 4),
    phi = FALSE
  )
  expect_equal(length(ph$files), 4L)

  # 4. Upload synthesized instances to Orthanc via HTTP REST
  instance_ids <- character(0)
  for (f in ph$files) {
    up_req <- httr2::request(sprintf("http://%s:%d/instances", orthanc_host, http_port)) |>
      httr2::req_method("POST") |>
      httr2::req_body_file(f, type = "application/dicom")
    up_resp <- httr2::req_perform(up_req)
    expect_equal(httr2::resp_status(up_resp), 200L)
    res_json <- httr2::resp_body_json(up_resp)
    instance_ids <- c(instance_ids, res_json$ID)
  }
  expect_equal(length(instance_ids), 4L)

  # Clean up uploaded instances from Orthanc on test exit
  on.exit({
    for (id in instance_ids) {
      tryCatch({
        del_req <- httr2::request(sprintf("http://%s:%d/instances/%s", orthanc_host, http_port, id)) |>
          httr2::req_method("DELETE")
        httr2::req_perform(del_req)
      }, error = function(e) NULL)
    }
  }, add = TRUE)

  # 5. Download instances back from Orthanc into dl_dir
  dir.create(dl_dir, recursive = TRUE, showWarnings = FALSE)
  for (i in seq_along(instance_ids)) {
    inst_id <- instance_ids[i]
    get_req <- httr2::request(sprintf("http://%s:%d/instances/%s/file", orthanc_host, http_port, inst_id))
    dest_file <- file.path(dl_dir, sprintf("downloaded_%02d.dcm", i))
    httr2::req_perform(get_req, path = dest_file)
    expect_true(file.exists(dest_file))
  }

  # 6. Read downloaded DICOM volume and assert analytical LPS affine recovery
  vol_dl <- read_dicom_volume(dl_dir, warn = FALSE)
  expect_s3_class(vol_dl, "dicom_volume")
  expect_equal(dim(vol_dl), ph$dims)
  expect_lt(max(abs(vol_dl$affine - ph$truth_affine_lps)), 1e-4)
  expect_lt(max(abs(vol_dl$voxels - ph$truth_voxels)), 1e-4)
})
