test_that("Ultrasound (0018,6011) region detection and blackout cleaning", {
  tmp_dir <- tempfile(pattern = "us_pixel_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  # Synthesize a 64x64 US image with BurnedInAnnotation = "YES"
  # Bright text banner in rows 1:10 (pixel value 255)
  # Acoustic window: X0=4, Y0=12, X1=59, Y1=59 (0-based) -> acoustic region [13:60, 5:60] in 1-based R
  rows <- 64L
  cols <- 64L
  px <- matrix(0, nrow = rows, ncol = cols)

  # Fill acoustic region [13:60, 5:60] with anatomical texture (e.g. 100..150)
  set.seed(42)
  px[13:60, 5:60] <- matrix(sample(80:160, 48 * 56, replace = TRUE), nrow = 48, ncol = 56)

  # Burn in bright text banner in rows 1:10
  px[1:10, ] <- 255

  us_file <- file.path(tmp_dir, "us_annotated.dcm")
  ok <- dicomtk:::cpp_write_dicom_multiframe(
    pixels = as.numeric(px),
    dims = c(rows, cols, 1L),
    out_path = us_file,
    meta_tags = c(
      "Modality", "SOPClassUID", "PatientName", "PatientID",
      "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID",
      "BurnedInAnnotation", "ImageType", "PixelRepresentation"
    ),
    meta_values = c(
      "US", "1.2.840.10008.5.1.4.1.1.6.1", "DOE^JANE", "PAT_US_01",
      "1.3.6.1.4.1.9999.2001", "1.3.6.1.4.1.9999.2001.1", "1.3.6.1.4.1.9999.2001.1.1",
      "YES", "ORIGINAL\\PRIMARY", "0"
    ),
    extra_sequences = list(
      SequenceOfUltrasoundRegions = list(
        list(
          RegionLocationMinX0 = 4L,
          RegionLocationMinY0 = 12L,
          RegionLocationMaxX1 = 59L,
          RegionLocationMaxY1 = 59L,
          RegionSpatialFormat = 1L,
          RegionDataType = 1L
        )
      )
    )
  )
  expect_true(ok)

  # dicom_detect_burned_phi() returns bounding boxes covering the top banner (rows 1..12)
  boxes <- dicom_detect_burned_phi(us_file)
  expect_s3_class(boxes, "data.frame")
  expect_gte(nrow(boxes), 1L)

  top_banner <- boxes[boxes$ymin == 1L & boxes$ymax == 12L, ]
  expect_equal(nrow(top_banner), 1L)
  expect_equal(top_banner$ymin, 1L)
  expect_equal(top_banner$ymax, 12L)

  # dicom_clean_pixels(..., pixel_method = "blackout") zeros banner pixels
  # while leaving acoustic region [13:60, 5:60] untouched and sets BurnedInAnnotation = "NO"
  out_cleaned <- file.path(tmp_dir, "us_cleaned.dcm")
  res_clean <- dicom_clean_pixels(us_file, out_path = out_cleaned, pixel_method = "blackout")
  expect_true(file.exists(out_cleaned))

  cleaned_px <- read_dicom_pixels(out_cleaned, rescale = FALSE)
  # Rows 1:12 should be zeroed
  expect_true(all(cleaned_px[1:12, ] == 0))
  # Acoustic window [13:60, 5:60] must be 100% identical to original px
  expect_equal(cleaned_px[13:60, 5:60], px[13:60, 5:60])

  # Check BurnedInAnnotation tag is updated to "NO"
  hdr <- read_dicom(out_cleaned, wide = TRUE)
  expect_equal(hdr$BurnedInAnnotation, "NO")
})

test_that("Border stroke and cine static-overlay detector", {
  tmp_dir <- tempfile(pattern = "cine_overlay_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  # 5-frame XA/US cine loop where anatomy moves across frames
  # while a bright corner patient-ID stamp stays static in rows 1:8, cols 1:24
  rows <- 32L
  cols <- 32L
  nframes <- 5L

  px_cine <- array(0, dim = c(rows, cols, nframes))
  for (f in seq_len(nframes)) {
    for (r in seq_len(rows)) {
      for (c in seq_len(cols)) {
        # Moving anatomical feature
        px_cine[r, c, f] <- 50 + 40 * sin((r + f * 4) / 5) * cos((c - f * 3) / 5)
      }
    }
    # Static patient-ID stamp in rows 1:8, cols 1:24 across ALL frames
    px_cine[1:8, 1:24, f] <- 240
  }

  cine_file <- file.path(tmp_dir, "cine_static.dcm")
  ok <- dicomtk:::cpp_write_dicom_multiframe(
    pixels = as.numeric(px_cine),
    dims = c(rows, cols, nframes),
    out_path = cine_file,
    meta_tags = c(
      "Modality", "SOPClassUID", "PatientName", "PatientID",
      "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID",
      "NumberOfFrames", "BurnedInAnnotation"
    ),
    meta_values = c(
      "XA", "1.2.840.10008.5.1.4.1.1.12.1", "CINE^PATIENT", "PAT_CINE_01",
      "1.3.6.1.4.1.9999.3001", "1.3.6.1.4.1.9999.3001.1", "1.3.6.1.4.1.9999.3001.1.1",
      as.character(nframes), "YES"
    )
  )
  expect_true(ok)

  # dicom_detect_burned_phi() detects the static corner overlay box automatically
  detected <- dicom_detect_burned_phi(cine_file)
  expect_s3_class(detected, "data.frame")
  expect_gte(nrow(detected), 1L)

  corner_box <- detected[detected$ymin <= 2L & detected$ymax >= 7L &
                         detected$xmin <= 2L & detected$xmax >= 23L, ]
  expect_gte(nrow(corner_box), 1L)
  expect_equal(corner_box$ymin[1L], 1L)
  expect_equal(corner_box$ymax[1L], 8L)
  expect_equal(corner_box$xmin[1L], 1L)
  expect_equal(corner_box$xmax[1L], 24L)
})

test_that("Opt-in C++17 Telea inpainting and mandatory guardrails", {
  tmp_dir <- tempfile(pattern = "inpaint_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  # Create a smooth gradient image with a bright 6x16 burned-in text stroke
  rows <- 32L
  cols <- 32L
  clean_bg <- outer(seq(40, 160, length.out = rows), seq(50, 180, length.out = cols), "+") / 2

  corrupted <- clean_bg
  # Bright stroke in rows 10:15, cols 8:23 (size 6x16)
  corrupted[10:15, 8:23] <- 255

  orig_sop <- "1.3.6.1.4.1.9999.4001.1.1"
  grad_file <- file.path(tmp_dir, "gradient_stroke.dcm")
  ok <- dicomtk:::cpp_write_dicom_multiframe(
    pixels = as.numeric(corrupted),
    dims = c(rows, cols, 1L),
    out_path = grad_file,
    meta_tags = c(
      "Modality", "SOPClassUID", "PatientName", "PatientID",
      "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID",
      "ImageType", "BurnedInAnnotation"
    ),
    meta_values = c(
      "OT", "1.2.840.10008.5.1.4.1.1.7", "INPAINT^TEST", "PAT_INPAINT_01",
      "1.3.6.1.4.1.9999.4001", "1.3.6.1.4.1.9999.4001.1", orig_sop,
      "ORIGINAL\\PRIMARY", "YES"
    )
  )
  expect_true(ok)

  # Explicit box for the 6x16 stroke
  stroke_box <- matrix(c(10L, 8L, 15L, 23L), nrow = 1L)
  colnames(stroke_box) <- c("ymin", "xmin", "ymax", "xmax")

  # Run inpainting
  out_inpaint <- file.path(tmp_dir, "gradient_inpainted.dcm")
  dicom_clean_pixels(
    grad_file,
    out_path = out_inpaint,
    pixel_method = "inpaint",
    boxes = stroke_box,
    mask_sidecar = TRUE
  )
  expect_true(file.exists(out_inpaint))

  # Also run blackout for comparison
  out_blackout <- file.path(tmp_dir, "gradient_blackout.dcm")
  dicom_clean_pixels(
    grad_file,
    out_path = out_blackout,
    pixel_method = "blackout",
    boxes = stroke_box
  )

  # Check RMSE vs underlying smooth background
  inpainted_px <- read_dicom_pixels(out_inpaint, rescale = FALSE)
  blackout_px <- read_dicom_pixels(out_blackout, rescale = FALSE)

  rmse_inpaint <- sqrt(mean((inpainted_px[10:15, 8:23] - clean_bg[10:15, 8:23])^2))
  rmse_blackout <- sqrt(mean((blackout_px[10:15, 8:23] - clean_bg[10:15, 8:23])^2))

  expect_lt(rmse_inpaint, 5.0)
  expect_lt(rmse_inpaint, rmse_blackout)

  # Assert ALL 4 GUARDRAILS:
  # Guardrail 1: ImageType (0008,0008) starts with "DERIVED\\SECONDARY"
  hdr <- read_dicom(out_inpaint, wide = TRUE)
  expect_match(hdr$ImageType, "^DERIVED\\\\SECONDARY")

  # Guardrail 2: SOPInstanceUID (0008,0018) differs from input SOPInstanceUID
  expect_false(identical(hdr$SOPInstanceUID, orig_sop))
  expect_true(nzchar(hdr$SOPInstanceUID))

  # Guardrail 3: DeidentificationMethodCodeSequence (0012,0064) records "113101"
  # and "INPAINT_TELEA" description in (0012,0063)
  hdr_sq <- read_dicom(out_inpaint, include_sequences = TRUE)
  clean_code_rows <- hdr_sq[hdr_sq$keyword == "CodeValue" & hdr_sq$value == "113101", ]
  expect_gte(nrow(clean_code_rows), 1L)

  deid_method_str <- hdr$DeidentificationMethod
  expect_match(deid_method_str, "INPAINT_TELEA")

  # Guardrail 4: Sidecar mask file <out_stem>_inpaint_mask.rds exists on disk
  # with exact [rows, cols] logical mask matching modified pixels
  sidecar_file <- file.path(tmp_dir, "gradient_inpainted_inpaint_mask.rds")
  expect_true(file.exists(sidecar_file))

  mask_mat <- readRDS(sidecar_file)
  expect_true(is.matrix(mask_mat))
  expect_type(mask_mat, "logical")
  expect_equal(dim(mask_mat), c(rows, cols))
  # Exactly pixels in 10:15, 8:23 are TRUE
  expect_true(all(mask_mat[10:15, 8:23]))
  expect_false(any(mask_mat[-(10:15), ]))
  expect_false(any(mask_mat[, -(8:23)]))
})

test_that("Integration of pixel cleaning with dicom_deid()", {
  tmp_dir <- tempfile(pattern = "deid_pixel_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  rows <- 32L
  cols <- 32L
  px <- matrix(50, nrow = rows, ncol = cols)
  # Top banner
  px[1:4, ] <- 255

  dcm_in <- file.path(tmp_dir, "in.dcm")
  dicomtk:::cpp_write_dicom_multiframe(
    pixels = as.numeric(px),
    dims = c(rows, cols, 1L),
    out_path = dcm_in,
    meta_tags = c(
      "Modality", "SOPClassUID", "PatientName", "PatientID",
      "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID",
      "BurnedInAnnotation"
    ),
    meta_values = c(
      "US", "1.2.840.10008.5.1.4.1.1.6.1", "DOE^JOHN", "P123",
      "1.3.6.1.4.1.9999.5001", "1.3.6.1.4.1.9999.5001.1", "1.3.6.1.4.1.9999.5001.1.1",
      "YES"
    )
  )

  # dicom_deid(..., options = "clean_pixel", pixel_method = "blackout")
  deid_out <- file.path(tmp_dir, "deid_out")
  res <- dicom_deid(
    path = dcm_in,
    out_dir = deid_out,
    options = "clean_pixel",
    pixel_method = "blackout",
    pixel_boxes = matrix(c(1L, 1L, 4L, cols), nrow = 1L)
  )

  out_files <- res$files
  expect_equal(length(out_files), 1L)

  cleaned_px <- read_dicom_pixels(out_files[1L], rescale = FALSE)
  expect_true(all(cleaned_px[1:4, ] == 0))
  expect_true(all(cleaned_px[5:rows, ] == 50))

  hdr <- read_dicom(out_files[1L], wide = TRUE)
  expect_equal(hdr$BurnedInAnnotation, "NO")
})
