test_that("Nested DICOM sequences round-trip with 0-based item indices in sequence_path", {
  out_dcm <- tempfile(fileext = ".dcm")
  on.exit(unlink(out_dcm), add = TRUE)

  px <- array(seq_len(4 * 4 * 3), dim = c(4L, 4L, 3L))
  per_frame <- list(
    list(
      PlanePositionSequence = list(list(ImagePositionPatient = "0\\0\\0")),
      PixelValueTransformationSequence = list(list(RescaleIntercept = "-1024", RescaleSlope = "1"))
    ),
    list(
      PlanePositionSequence = list(list(ImagePositionPatient = "0\\0\\2.5")),
      PixelValueTransformationSequence = list(list(RescaleIntercept = "-1024", RescaleSlope = "1"))
    ),
    list(
      PlanePositionSequence = list(list(ImagePositionPatient = "0\\0\\5.0")),
      PixelValueTransformationSequence = list(list(RescaleIntercept = "-1024", RescaleSlope = "2"))
    )
  )
  shared <- list(
    list(
      PlaneOrientationSequence = list(list(ImageOrientationPatient = "1\\0\\0\\0\\1\\0")),
      PixelMeasuresSequence = list(list(PixelSpacing = "0.5\\0.5", SliceThickness = "2.5"))
    )
  )

  ok <- dicomtk:::cpp_write_dicom_multiframe(
    pixels = as.numeric(px),
    dims = c(4L, 4L, 3L),
    out_path = out_dcm,
    meta_tags = c("Modality", "SOPClassUID", "PatientName"),
    meta_values = c("CT", "1.2.840.10008.5.1.4.1.1.2.1", "SEQ^PHANTOM"),
    shared_fg = shared,
    per_frame_fg = per_frame
  )
  expect_true(ok)
  expect_true(is_dicom(out_dcm))

  hdr <- read_dicom(out_dcm, include_sequences = TRUE)

  # PerFrameFunctionalGroupsSequence (5200,9230) item indexing
  ipp_rows <- hdr[hdr$keyword == "ImagePositionPatient", , drop = FALSE]
  expect_equal(nrow(ipp_rows), 3L)
  expect_equal(ipp_rows$value, c("0\\0\\0", "0\\0\\2.5", "0\\0\\5.0"))
  expect_equal(
    ipp_rows$sequence_path,
    c(
      "(5200,9230)[0]/(0020,9113)[0]",
      "(5200,9230)[1]/(0020,9113)[0]",
      "(5200,9230)[2]/(0020,9113)[0]"
    )
  )
  expect_true(all(grepl("5200,9230", ipp_rows$sequence_path, fixed = TRUE)))

  slope_rows <- hdr[hdr$keyword == "RescaleSlope", , drop = FALSE]
  expect_equal(nrow(slope_rows), 3L)
  expect_equal(slope_rows$value, c("1", "1", "2"))
  expect_equal(
    slope_rows$sequence_path,
    c(
      "(5200,9230)[0]/(0028,9145)[0]",
      "(5200,9230)[1]/(0028,9145)[0]",
      "(5200,9230)[2]/(0028,9145)[0]"
    )
  )

  # SharedFunctionalGroupsSequence (5200,9229) nested sequence paths
  iop_rows <- hdr[hdr$keyword == "ImageOrientationPatient", , drop = FALSE]
  expect_equal(nrow(iop_rows), 1L)
  expect_equal(iop_rows$value, "1\\0\\0\\0\\1\\0")
  expect_equal(iop_rows$sequence_path, "(5200,9229)[0]/(0020,9116)[0]")

  ps_rows <- hdr[hdr$keyword == "PixelSpacing", , drop = FALSE]
  expect_equal(nrow(ps_rows), 1L)
  expect_equal(ps_rows$value, "0.5\\0.5")
  expect_equal(ps_rows$sequence_path, "(5200,9229)[0]/(0028,9110)[0]")

  st_rows <- hdr[hdr$keyword == "SliceThickness", , drop = FALSE]
  expect_equal(nrow(st_rows), 1L)
  expect_equal(st_rows$value, "2.5")
  expect_equal(st_rows$sequence_path, "(5200,9229)[0]/(0028,9110)[0]")

  # Multi-frame pixel data round-trip
  px_read <- read_dicom_pixels(out_dcm, frame = 0L, rescale = FALSE)
  expect_equal(dim(px_read), c(4L, 4L, 3L))
  expect_equal(as.numeric(px_read), as.numeric(px))

  # Modifying top-level tag preserves nested sequences and pixel data
  mod_dcm <- tempfile(fileext = ".dcm")
  on.exit(unlink(mod_dcm), add = TRUE)
  dicom_modify(out_dcm, tags = list(PatientName = "MODIFIED^PATIENT"), out_path = mod_dcm)

  hdr_mod <- read_dicom(mod_dcm, include_sequences = TRUE)
  expect_equal(unname(dicom_tag_value(mod_dcm, "PatientName")), "MODIFIED^PATIENT")

  ipp_mod <- hdr_mod[hdr_mod$keyword == "ImagePositionPatient", , drop = FALSE]
  expect_equal(ipp_mod$value, c("0\\0\\0", "0\\0\\2.5", "0\\0\\5.0"))
  expect_equal(
    ipp_mod$sequence_path,
    c(
      "(5200,9230)[0]/(0020,9113)[0]",
      "(5200,9230)[1]/(0020,9113)[0]",
      "(5200,9230)[2]/(0020,9113)[0]"
    )
  )

  iop_mod <- hdr_mod[hdr_mod$keyword == "ImageOrientationPatient", , drop = FALSE]
  expect_equal(iop_mod$value, "1\\0\\0\\0\\1\\0")
  expect_equal(iop_mod$sequence_path, "(5200,9229)[0]/(0020,9116)[0]")

  px_mod <- read_dicom_pixels(mod_dcm, frame = 0L, rescale = FALSE)
  expect_equal(dim(px_mod), c(4L, 4L, 3L))
  expect_equal(as.numeric(px_mod), as.numeric(px))
})

test_that("extra_sequences, empty sequences, and undefined-length SQ items round-trip cleanly", {
  pet_dcm <- tempfile(fileext = ".dcm")
  on.exit(unlink(pet_dcm), add = TRUE)

  px_pet <- array(seq_len(16L), dim = c(4L, 4L, 1L))
  extra_sq <- list(
    RadiopharmaceuticalInformationSequence = list(
      list(
        RadionuclideTotalDose = "350000000",
        RadionuclideHalfLife = "6586.2",
        RadionuclideCodeSequence = list(
          list(
            CodeValue = "C-111A1",
            CodingSchemeDesignator = "SRT",
            CodeMeaning = "^18^Fluorine"
          )
        )
      )
    ),
    ContrastBolusAgentSequence = list()
  )

  ok <- dicomtk:::cpp_write_dicom_multiframe(
    pixels = as.numeric(px_pet),
    dims = c(4L, 4L, 1L),
    out_path = pet_dcm,
    meta_tags = c("Modality", "Units"),
    meta_values = c("PT", "BQML"),
    extra_sequences = extra_sq
  )
  expect_true(ok)

  hdr <- read_dicom(pet_dcm, include_sequences = TRUE)
  dose_row <- hdr[hdr$keyword == "RadionuclideTotalDose", , drop = FALSE]
  expect_equal(nrow(dose_row), 1L)
  expect_equal(dose_row$value, "350000000")
  expect_equal(dose_row$sequence_path, "(0054,0016)[0]")

  code_row <- hdr[hdr$keyword == "CodeValue", , drop = FALSE]
  expect_equal(nrow(code_row), 1L)
  expect_equal(code_row$value, "C-111A1")
  expect_equal(code_row$sequence_path, "(0054,0016)[0]/(0054,0300)[0]")

  empty_sq_row <- hdr[hdr$keyword == "ContrastBolusAgentSequence", , drop = FALSE]
  expect_equal(nrow(empty_sq_row), 1L)
  expect_equal(empty_sq_row$vr, "SQ")
  expect_equal(empty_sq_row$length, 0L)

  # Craft a valid Explicit-VR LE DICOM with undefined-length SQ (0xFFFFFFFF)
  # and two undefined-length items (FFFE,E000 + 0xFFFFFFFF ... FFFE,E00D + 0)
  undef_dcm <- tempfile(fileext = ".dcm")
  on.exit(unlink(undef_dcm), add = TRUE)

  u16 <- function(x) as.raw(c(bitwAnd(x, 0xFFL), bitwAnd(bitwShiftR(x, 8L), 0xFFL)))
  u32 <- function(x) {
    # Handle 0xFFFFFFFF (-1 in signed 32-bit)
    if (identical(x, -1L)) return(as.raw(c(0xFF, 0xFF, 0xFF, 0xFF)))
    as.raw(c(
      bitwAnd(x, 0xFFL),
      bitwAnd(bitwShiftR(x, 8L), 0xFFL),
      bitwAnd(bitwShiftR(x, 16L), 0xFFL),
      bitwAnd(bitwShiftR(x, 24L), 0xFFL)
    ))
  }
  elem_short <- function(g, e, vr, val_str) {
    b <- charToRaw(val_str)
    if (length(b) %% 2L == 1L) b <- c(b, if (vr == "UI") as.raw(0x00) else charToRaw(" "))
    c(u16(g), u16(e), charToRaw(vr), u16(length(b)), b)
  }

  ts_elem <- elem_short(0x0002L, 0x0010L, "UI", "1.2.840.10008.1.2.1")
  meta_gl <- c(u16(0x0002L), u16(0x0000L), charToRaw("UL"), u16(4L), u32(length(ts_elem)))
  mod_elem <- elem_short(0x0008L, 0x0060L, "CS", "OT")

  item0_body <- elem_short(0x0008L, 0x0100L, "SH", "CODE0")
  item1_body <- elem_short(0x0008L, 0x0100L, "SH", "CODE1")
  item_delim <- c(u16(0xFFFEL), u16(0xE00DL), u32(0L))
  seq_delim  <- c(u16(0xFFFEL), u16(0xE0DDL), u32(0L))

  # ConceptNameCodeSequence (0040,A043) with undefined length
  undef_sq <- c(
    u16(0x0040L), u16(0xA043L), charToRaw("SQ"), u16(0L), u32(-1L),
    u16(0xFFFEL), u16(0xE000L), u32(-1L), item0_body, item_delim,
    u16(0xFFFEL), u16(0xE000L), u32(-1L), item1_body, item_delim,
    seq_delim
  )
  after_sq <- elem_short(0x0040L, 0xA160L, "SH", "AFTER") # verify stream stays aligned after FFFE,E0DD

  raw_dcm <- c(rep(as.raw(0x00), 128L), charToRaw("DICM"), meta_gl, ts_elem, mod_elem, undef_sq, after_sq)
  writeBin(raw_dcm, undef_dcm)

  hdr_u <- read_dicom(undef_dcm, include_sequences = TRUE)
  cv_rows <- hdr_u[hdr_u$keyword == "CodeValue", , drop = FALSE]
  expect_equal(nrow(cv_rows), 2L)
  expect_equal(cv_rows$value, c("CODE0", "CODE1"))
  expect_equal(cv_rows$sequence_path, c("(0040,A043)[0]", "(0040,A043)[1]"))
  expect_true("AFTER" %in% hdr_u$value)

  # Modifying undefined-length SQ file re-serializes both items cleanly
  undef_mod <- tempfile(fileext = ".dcm")
  on.exit(unlink(undef_mod), add = TRUE)
  dicom_modify(undef_dcm, tags = list(PatientName = "UNDEF^MOD"), out_path = undef_mod)
  hdr_um <- read_dicom(undef_mod, include_sequences = TRUE)
  cv_um <- hdr_um[hdr_um$keyword == "CodeValue", , drop = FALSE]
  expect_equal(cv_um$value, c("CODE0", "CODE1"))
  expect_equal(cv_um$sequence_path, c("(0040,A043)[0]", "(0040,A043)[1]"))
})
