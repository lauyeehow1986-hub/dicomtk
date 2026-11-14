test_that("as_dicom_json and from_dicom_json round-trip DICOM headers losslessly", {
  synth <- dicom_synthesize(modality = "CT", dims = c(8L, 8L, 2L), phi_profile = "basic")
  on.exit(unlink(synth[["out_dir"]], recursive = TRUE), add = TRUE)

  hdr <- read_dicom_header(synth[["files"]][1L])
  dj <- as_dicom_json(hdr)
  expect_type(dj, "list")
  expect_true("0020000D" %in% names(dj))
  expect_equal(dj[["00080060"]][["vr"]], "CS")
  expect_equal(dj[["00080060"]][["Value"]][[1L]], "CT")

  # PN VR uses Alphabetic object per PS3.18
  expect_true("00100010" %in% names(dj))
  expect_true(is.list(dj[["00100010"]][["Value"]][[1L]]))

  rt <- from_dicom_json(dj)
  expect_s3_class(rt, "tbl_df")
  expect_true(all(c("tag", "vr", "value") %in% names(rt)))
  expect_equal(rt$value[rt$tag == "(0008,0060)"][1L], "CT")
  expect_equal(
    rt$value[rt$tag == "(0020,000D)"][1L],
    hdr$value[hdr$tag == "(0020,000D)"][1L]
  )
})

test_that("pack_multipart_dicom and unpack_multipart_dicom preserve exact binary bytes", {
  synth <- dicom_synthesize(modality = "CT", dims = c(8L, 8L, 2L))
  out_unpack <- tempfile("dw_unpack_")
  on.exit(unlink(c(synth[["out_dir"]], out_unpack), recursive = TRUE), add = TRUE)

  packed <- pack_multipart_dicom(synth[["files"]], boundary = "DICOMTK_BOUNDARY_01")
  expect_type(packed, "list")
  expect_true(is.raw(packed$body))
  expect_match(packed$content_type, "multipart/related")
  expect_match(packed$content_type, "DICOMTK_BOUNDARY_01")

  files_back <- unpack_multipart_dicom(
    raw_bytes = packed$body,
    boundary = "DICOMTK_BOUNDARY_01",
    out_dir = out_unpack
  )
  expect_equal(length(files_back), length(synth[["files"]]))
  expect_true(all(file.exists(files_back)))
  expect_equal(
    unname(file.info(files_back)$size),
    unname(file.info(synth[["files"]])$size)
  )
  expect_equal(
    unname(tools::md5sum(files_back)),
    unname(tools::md5sum(synth[["files"]]))
  )
})

test_that("dicom_connect auth and local dicomweb_qido/wado/stow/metadata work end-to-end", {
  synth <- dicom_synthesize(modality = "MR", dims = c(8L, 8L, 2L))
  pacs_dir <- tempfile("dw_local_pacs_")
  wado_out <- tempfile("dw_wado_out_")
  dir.create(pacs_dir, recursive = TRUE)
  on.exit(unlink(c(synth[["out_dir"]], pacs_dir, wado_out), recursive = TRUE), add = TRUE)

  conn <- dicom_connect(
    host = "127.0.0.1",
    port = 8042L,
    dicomweb_url = "https://pacs.example.org/dicom-web",
    local_dir = pacs_dir,
    auth = list(type = "bearer", token = "secret-test-token"),
    headers = c("X-Study-Site" = "SG-01")
  )
  expect_s3_class(conn, "dicom_connection")
  expect_equal(conn$auth$type, "bearer")
  expect_equal(conn$headers[["X-Study-Site"]], "SG-01")

  # STOW-RS into local mock PACS
  stow_res <- dicomweb_stow(conn, files = synth[["files"]])
  expect_s3_class(stow_res, "tbl_df")
  expect_equal(nrow(stow_res), length(synth[["files"]]))
  expect_true(all(stow_res$success))

  # QIDO-RS study and series queries
  studies <- dicomweb_qido(conn, level = "studies", Modality = "MR")
  expect_s3_class(studies, "tbl_df")
  expect_gte(nrow(studies), 1L)
  expect_true("StudyInstanceUID" %in% names(studies))

  study_uid <- studies$StudyInstanceUID[1L]
  meta <- dicomweb_metadata(conn, study_uid = study_uid)
  expect_type(meta, "list")
  expect_gte(length(meta), 1L)

  # WADO-RS retrieval
  retrieved <- dicomweb_wado(conn, study_uid = study_uid, out_dir = wado_out)
  expect_equal(length(retrieved), length(synth[["files"]]))
  expect_true(all(file.exists(retrieved)))
})
