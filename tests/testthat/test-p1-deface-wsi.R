test_that("3D coordinate-aware head CT/MR defacing masks facial features while preserving brain", {
  dims <- c(32L, 32L, 32L)
  origin <- c(-93.0, -125.0, -60.0)
  spc <- c(6.0, 6.0, 4.0)

  aff <- diag(c(spc, 1.0))
  aff[1:3, 4] <- origin

  # Initialize CT array with air (-1000 HU)
  arr <- array(-1000.0, dim = dims)

  grid_i <- rep(seq_len(dims[1]) - 1, times = dims[2] * dims[3])
  grid_j <- rep(rep(seq_len(dims[2]) - 1, each = dims[1]), times = dims[3])
  grid_k <- rep(seq_len(dims[3]) - 1, each = dims[1] * dims[2])

  x_lps <- origin[1] + grid_i * spc[1]
  y_lps <- origin[2] + grid_j * spc[2]
  z_lps <- origin[3] + grid_k * spc[3]

  # Brain sphere centered at (0, 0, +15) mm (40 HU)
  d_brain <- sqrt(x_lps^2 + y_lps^2 + (z_lps - 15.0)^2)
  brain_idx <- which(d_brain <= 22.0)
  arr[brain_idx] <- 40.0

  # Nose/jaw feature centered at (0, -95, -45) mm (200 HU)
  d_nose <- sqrt(x_lps^2 + (y_lps - (-95.0))^2 + (z_lps - (-45.0))^2)
  nose_idx <- which(d_nose <= 15.0)
  arr[nose_idx] <- 200.0

  expect_gt(length(brain_idx), 0L)
  expect_gt(length(nose_idx), 0L)
  expect_equal(length(intersect(brain_idx, nose_idx)), 0L)

  head_vol <- new_dicom_volume(
    voxels = arr,
    affine = aff,
    coord_system = "LPS",
    modality = "CT",
    units = "HU"
  )

  # Run defacing on LPS volume
  defaced <- dicom_deface(head_vol)
  expect_s3_class(defaced, "dicom_volume")

  # Nose/jaw voxels replaced with air (-1000 HU)
  expect_true(all(defaced$voxels[nose_idx] == -1000.0))

  # 100% of intracranial brain sphere voxels remain untouched (40 HU)
  expect_true(all(defaced$voxels[brain_idx] == 40.0))

  # Provenance logs "dicom_deface"
  has_deface_prov <- any(vapply(defaced$provenance, function(p) {
    identical(p$action, "dicom_deface")
  }, logical(1L)))
  expect_true(has_deface_prov)

  # Orientation invariance: defacing to_ras(head_vol) yields identical result
  head_ras <- to_ras(head_vol)
  defaced_ras <- dicom_deface(head_ras)
  expect_true(all(defaced_ras$voxels[nose_idx] == -1000.0))
  expect_true(all(defaced_ras$voxels[brain_idx] == 40.0))

  # Orientation invariance: coronal-reoriented acquisition
  aff_cor <- matrix(0.0, 4, 4)
  aff_cor[1, 1] <- 6.0   # row = X
  aff_cor[3, 2] <- 4.0   # col = Z
  aff_cor[2, 3] <- 6.0   # slice = Y
  aff_cor[4, 4] <- 1.0
  aff_cor[1:3, 4] <- c(-93.0, -125.0, -60.0)

  pos_cor <- aff_cor %*% rbind(grid_i, grid_j, grid_k, 1.0)
  d_brain_cor <- sqrt(pos_cor[1, ]^2 + pos_cor[2, ]^2 + (pos_cor[3, ] - 15.0)^2)
  brain_cor_idx <- which(d_brain_cor <= 22.0)
  d_nose_cor <- sqrt(pos_cor[1, ]^2 + (pos_cor[2, ] - (-95.0))^2 + (pos_cor[3, ] - (-45.0))^2)
  nose_cor_idx <- which(d_nose_cor <= 15.0)

  arr_cor <- array(-1000.0, dim = dims)
  arr_cor[brain_cor_idx] <- 40.0
  arr_cor[nose_cor_idx] <- 200.0

  vol_cor <- new_dicom_volume(
    voxels = arr_cor,
    affine = aff_cor,
    coord_system = "LPS",
    modality = "CT",
    units = "HU"
  )
  def_cor <- dicom_deface(vol_cor)
  expect_true(all(def_cor$voxels[nose_cor_idx] == -1000.0))
  expect_true(all(def_cor$voxels[brain_cor_idx] == 40.0))

  # Test MR modality fill with 0 instead of -1000
  mr_arr <- arr
  mr_arr[mr_arr == -1000.0] <- 0.0
  mr_vol <- new_dicom_volume(
    voxels = mr_arr,
    affine = aff,
    coord_system = "LPS",
    modality = "MR",
    units = "counts"
  )
  defaced_mr <- dicom_deface(mr_vol, fill = "auto")
  expect_true(all(defaced_mr$voxels[nose_idx] == 0.0))
  expect_true(all(defaced_mr$voxels[brain_idx] == 40.0))

  # Test writing out_dir
  out_dir <- tempfile("test_deface_out_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  written_vol <- dicom_deface(head_vol, out_dir = out_dir)
  expect_true(dir.exists(out_dir))
  out_files <- list.files(out_dir, pattern = "\\.dcm$", full.names = TRUE)
  expect_gt(length(out_files), 0L)

  # Check metadata stamped in written slices
  hdr <- read_dicom(out_files[[1L]], include_sequences = TRUE)
  rvf <- subset(hdr, tag == "(0028,0302)")$value
  expect_equal(rvf, "NO")

  img_type <- subset(hdr, tag == "(0008,0008)")$value
  expect_true(grepl("DERIVED\\\\SECONDARY", img_type))

  # Check CID 7050 code 113102 in DeidentificationMethodCodeSequence (0012,0064)
  code_val <- subset(hdr, tag == "(0008,0100)")$value
  expect_true("113102" %in% code_val)
})

test_that("dicom_deid drops WSI label and macro images while stripping group 2200 tags", {
  kp <- dicom_key_provider(passphrase = "test-wsi-key", salt = "test-salt")
  wsi_dir <- tempfile("test_wsi_in_")
  out_dir <- tempfile("test_wsi_out_")
  dir.create(wsi_dir, recursive = TRUE)
  on.exit({
    unlink(wsi_dir, recursive = TRUE)
    unlink(out_dir, recursive = TRUE)
  }, add = TRUE)

  # 1. Synthesize pyramid_0.dcm (VOLUME image with BarcodeValue and LabelText)
  px1 <- matrix(seq(1, 16), nrow = 4, ncol = 4)
  cpp_write_dicom_matrix(
    pixels = px1,
    out_path = file.path(wsi_dir, "pyramid_0.dcm"),
    meta_tags = c("(0008,0016)", "(0008,0008)", "(2200,0005)", "(2200,0002)", "PatientName", "PatientID"),
    meta_values = c(
      "1.2.840.10008.5.1.4.1.1.77.1.6",
      "ORIGINAL\\PRIMARY\\VOLUME\\NONE",
      "BARCODE-9999",
      "SLIDE-LABEL-SECRET",
      "SPECIMEN^ANONYMOUS",
      "WSI-001"
    )
  )

  # 2. Synthesize slide_label.dcm (LABEL image)
  cpp_write_dicom_matrix(
    pixels = px1,
    out_path = file.path(wsi_dir, "slide_label.dcm"),
    meta_tags = c("(0008,0016)", "(0008,0008)", "PatientName", "PatientID"),
    meta_values = c(
      "1.2.840.10008.5.1.4.1.1.77.1.6",
      "ORIGINAL\\PRIMARY\\LABEL\\NONE",
      "SPECIMEN^ANONYMOUS",
      "WSI-001"
    )
  )

  # 3. Synthesize macro.dcm (OVERVIEW image)
  cpp_write_dicom_matrix(
    pixels = px1,
    out_path = file.path(wsi_dir, "macro.dcm"),
    meta_tags = c("(0008,0016)", "(0008,0008)", "PatientName", "PatientID"),
    meta_values = c(
      "1.2.840.10008.5.1.4.1.1.77.1.6",
      "ORIGINAL\\PRIMARY\\OVERVIEW\\NONE",
      "SPECIMEN^ANONYMOUS",
      "WSI-001"
    )
  )

  # Run dicom_deid on the WSI directory
  res <- dicom_deid(wsi_dir, out_dir, key = kp)

  # Check that 2 WSI label/macro instances were dropped
  expect_equal(res$skipped_wsi_labels, 2L)

  # Check that only pyramid_0.dcm was written to out_dir
  out_files <- list.files(out_dir, pattern = "\\.dcm$", full.names = FALSE)
  expect_equal(length(out_files), 1L)
  expect_equal(out_files[[1L]], "pyramid_0.dcm")

  # Read de-identified pyramid_0.dcm and verify group 2200 tags are removed/zeroed
  d_out <- read_dicom(file.path(out_dir, "pyramid_0.dcm"))
  tag_2200_0005 <- subset(d_out, tag == "(2200,0005)")
  tag_2200_0002 <- subset(d_out, tag == "(2200,0002)")

  # BarcodeValue and LabelText must either be absent or empty/zeroed
  if (nrow(tag_2200_0005) > 0L) {
    expect_true(is.na(tag_2200_0005$value) || tag_2200_0005$value == "")
  }
  if (nrow(tag_2200_0002) > 0L) {
    expect_true(is.na(tag_2200_0002$value) || tag_2200_0002$value == "")
  }
})
