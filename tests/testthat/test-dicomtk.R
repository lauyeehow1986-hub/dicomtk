test_that("Bundled DCMTK engine and 3.7.1 dictionary initialize properly", {
  expect_true(have_dcmtk())
  info <- dicom_info()
  expect_s3_class(info, "tbl_df")
  expect_equal(info$dcmtk_version, "3.7.1")
  expect_gt(info$dictionary_entries, 5000)

  dict <- dicom_tags()
  expect_s3_class(dict, "tbl_df")
  expect_gt(nrow(dict), 5000)

  wc <- dicom_tag_lookup("WindowCenter")
  expect_true("(0028,1050)" %in% wc$tag)
})

test_that("Reading DICOM headers, pixels, and series works in tidyverse format", {
  dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
  expect_true(file.exists(dcm_file))
  expect_true(is_dicom(dcm_file))

  hdr_long <- read_dicom(dcm_file)
  expect_s3_class(hdr_long, "tbl_df")
  expect_true(all(c("file", "tag", "vr", "keyword", "name", "value") %in% names(hdr_long)))
  expect_gt(nrow(hdr_long), 20)

  hdr_wide <- read_dicom(dcm_file, wide = TRUE)
  expect_s3_class(hdr_wide, "tbl_df")
  expect_equal(nrow(hdr_wide), 1L)
  expect_true("Rows" %in% names(hdr_wide))

  vals <- dicom_tag_value(dcm_file, c("Rows", "Columns", "(0028,0010)"))
  expect_equal(length(vals), 3L)
  expect_false(is.na(vals[["Rows"]]))

  px <- read_dicom_pixels(dcm_file)
  expect_s3_class(px, "dicom_pixels")
  expect_equal(length(dim(px)), 2L)
  expect_gt(nrow(px), 0L)
  expect_gt(ncol(px), 0L)

  series <- read_dicom_series(c(dcm_file, dcm_file))
  expect_s3_class(series, "dicom_series")
  expect_equal(dim(series$volume)[3L], 2L)
})

test_that("Writing, modifying, anonymizing, and RLE compressing/decompressing DICOM work", {
  mat <- matrix(seq(0, 255), nrow = 16, ncol = 16)
  tmp_dcm <- tempfile(fileext = ".dcm")
  on.exit(unlink(tmp_dcm), add = TRUE)

  write_dicom(
    mat,
    tmp_dcm,
    metadata = list(
      PatientName = "DOE^JANE",
      PatientID = "PID12345",
      Modality = "CT",
      StudyDate = "20250615"
    )
  )
  expect_true(is_dicom(tmp_dcm))
  expect_equal(unname(dicom_tag_value(tmp_dcm, "PatientName")), "DOE^JANE")
  expect_equal(unname(dicom_tag_value(tmp_dcm, "Modality")), "CT")

  px_read <- read_dicom_pixels(tmp_dcm, rescale = FALSE)
  expect_equal(dim(px_read), c(16L, 16L))
  expect_equal(as.numeric(px_read), as.numeric(mat))

  # Modify tag
  mod_dcm <- tempfile(fileext = ".dcm")
  on.exit(unlink(mod_dcm), add = TRUE)
  dicom_modify(tmp_dcm, tags = list(PatientName = "SMITH^JOHN"), out_path = mod_dcm)
  expect_equal(unname(dicom_tag_value(mod_dcm, "PatientName")), "SMITH^JOHN")

  # Anonymize with date shifting
  anon_dcm <- dicom_anonymize(
    tmp_dcm,
    patient_name = "ANON^SUBJ",
    patient_id = "ANON99",
    shift_days = -10L
  )
  on.exit(unlink(anon_dcm), add = TRUE)
  expect_equal(unname(dicom_tag_value(anon_dcm, "PatientName")), "ANON^SUBJ")
  expect_equal(unname(dicom_tag_value(anon_dcm, "PatientIdentityRemoved")), "YES")
  expect_equal(unname(dicom_tag_value(anon_dcm, "StudyDate")), "20250605")

  # RLE compression and decompression round-trip
  rle_dcm <- dicom_compress(tmp_dcm, method = "rle")
  on.exit(unlink(rle_dcm), add = TRUE)
  expect_true(is_dicom(rle_dcm))
  expect_equal(unname(dicom_tag_value(rle_dcm, "TransferSyntaxUID")), "1.2.840.10008.1.2.5")

  px_rle <- read_dicom_pixels(rle_dcm, rescale = FALSE)
  expect_equal(as.numeric(px_rle), as.numeric(mat))

  dec_dcm <- dicom_decompress(rle_dcm)
  on.exit(unlink(dec_dcm), add = TRUE)
  expect_equal(unname(dicom_tag_value(dec_dcm, "TransferSyntaxUID")), "1.2.840.10008.1.2.1")
  px_dec <- read_dicom_pixels(dec_dcm, rescale = FALSE)
  expect_equal(as.numeric(px_dec), as.numeric(mat))
})

test_that("Visualization (ggplot2, window presets, 3D MPR/MIP) and conversions work", {
  dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
  px <- read_dicom_pixels(dcm_file)

  for (preset in c("auto", "brain", "lung", "bone", "abdomen")) {
    w <- dicom_window(px, preset = preset)
    expect_gte(min(w), 0.0)
    expect_lte(max(w), 1.0)
  }

  p1 <- plot_dicom(dcm_file, window = "auto", palette = "gray")
  expect_s3_class(p1, "ggplot")

  p2 <- ggdicom(dcm_file, window = "brain", palette = "viridis")
  expect_s3_class(p2, "ggplot")

  series <- read_dicom_series(c(dcm_file, dcm_file, dcm_file))
  p_mpr <- render_volume(series, method = "mpr")
  expect_s3_class(p_mpr, "ggplot")
  p_mip <- render_volume(series, method = "mip")
  expect_s3_class(p_mip, "ggplot")

  png_file <- dicom_to_png(dcm_file)
  on.exit(unlink(png_file), add = TRUE)
  expect_true(file.exists(png_file))
  expect_gt(file.info(png_file)$size, 100)

  nii_file <- dicom_to_nifti(dcm_file)
  on.exit(unlink(nii_file), add = TRUE)
  expect_true(file.exists(nii_file))
  expect_gt(file.info(nii_file)$size, 352)

  xml_file <- dcm2xml(dcm_file)
  on.exit(unlink(xml_file), add = TRUE)
  expect_true(file.exists(xml_file))
  expect_true(any(grepl("NativeDicomModel", readLines(xml_file, warn = FALSE))))
})

test_that("Structured Reporting, Networking, Legacy aliases, and LLM integration work", {
  dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")

  # Structured Report round-trip
  sr_file <- tempfile(fileext = ".dcm")
  on.exit(unlink(sr_file), add = TRUE)
  create_dicom_sr(
    sr_file,
    title = "Structured Findings",
    text = "No acute abnormality identified."
  )
  sr_tbl <- read_dicom_sr(sr_file)
  expect_s3_class(sr_tbl, "tbl_df")
  expect_true(any(grepl("No acute abnormality", sr_tbl$value)))

  # Local PACS networking workflow
  scp_dir <- tempfile("pacs_")
  dir.create(scp_dir)
  on.exit(unlink(scp_dir, recursive = TRUE), add = TRUE)
  conn <- dicom_receive(scp_dir)
  echo_tbl <- dicom_echo(conn)
  expect_true(echo_tbl$success)

  send_tbl <- dicom_send(dcm_file, conn)
  expect_true(all(send_tbl$success))

  found_tbl <- dicom_find(conn)
  expect_equal(nrow(found_tbl), 1L)

  got_files <- dicom_get(found_tbl)
  expect_true(all(file.exists(got_files)))

  # LLM integration (Ollama, OpenAI, Anthropic configs + offline execution)
  llm_ollama <- dicom_llm("ollama", model = "llava:13b")
  expect_s3_class(llm_ollama, "dicom_llm")
  expect_true(llm_ollama$is_local)

  llm_openai <- dicom_llm("openai", model = "gpt-4o")
  expect_s3_class(llm_openai, "dicom_llm")
  expect_false(llm_openai$is_local)

  llm_claude <- dicom_llm("anthropic", model = "claude-sonnet-4-20250514")
  expect_s3_class(llm_claude, "dicom_llm")

  llm_off <- dicom_llm("offline")
  s_txt <- dicom_summarize(dcm_file, llm = llm_off)
  expect_type(s_txt, "character")
  expect_true(nzchar(s_txt))

  d_txt <- dicom_describe_image(dcm_file, llm = llm_off)
  expect_type(d_txt, "character")
  expect_true(grepl("Rescaled pixel intensities", d_txt))

  rpt <- dicom_report(dcm_file, llm = llm_off)
  expect_s3_class(rpt, "tbl_df")
  expect_equal(nrow(rpt), 4L)

  ans <- dicom_ask(dcm_file, "What is the modality and rows?", llm = llm_off)
  expect_type(ans, "character")
  expect_true(nzchar(ans))

  # Legacy aliases
  expect_true(check_dcmtk_cmd())
  expect_s3_class(dcmhd(dcm_file), "tbl_df")
  expect_s3_class(wide_hdr(dcmhd(dcm_file)), "tbl_df")

  # JSON export & specialized RT / SEG / PMAP / ECT / Signature modules
  js <- dcm2json(dcm_file)
  expect_type(js, "character")
  expect_true(grepl("00280010", js, fixed = TRUE))

  rt_obj <- read_dicom_rt(dcm_file)
  expect_s3_class(rt_obj, "dicom_rt")

  seg_obj <- read_dicom_seg(dcm_file)
  expect_s3_class(seg_obj, "dicom_seg")

  pmap_obj <- read_dicom_pmap(dcm_file)
  expect_s3_class(pmap_obj, "dicom_pmap")

  ect_tbl <- read_dicom_ect(dcm_file)
  expect_s3_class(ect_tbl, "tbl_df")

  sig_tbl <- dicom_verify_signature(dcm_file)
  expect_s3_class(sig_tbl, "tbl_df")

  tract_obj <- read_dicom_tract(dcm_file)
  expect_s3_class(tract_obj, "dicom_tract")

  pstate_obj <- read_dicom_pstate(dcm_file)
  expect_s3_class(pstate_obj, "dicom_pstate")

  qrdb_tbl <- dicom_qrdb_index(system.file("extdata", package = "dicomtk"))
  expect_s3_class(qrdb_tbl, "tbl_df")
  expect_gte(nrow(qrdb_tbl), 1L)

  wl_tbl <- dicom_worklist()
  expect_s3_class(wl_tbl, "tbl_df")

  tls_conn <- dicom_connect("127.0.0.1", port = 2762) |>
    dicom_tls_config(profile = "BCP195")
  expect_true(tls_conn$tls$enabled)
  expect_equal(tls_conn$tls$profile, "BCP195")
})
