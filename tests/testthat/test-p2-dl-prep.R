test_that("volume_resample performs C++17 3D trilinear and nearest-neighbor resampling with exact affine updates", {
  # Synthesize 32x32x8 CT volume with spacing (1.0, 1.0, 2.5) mm
  synth <- dicom_synthesize(modality = "CT", dims = c(32L, 32L, 8L))
  vol <- read_dicom_volume(synth[["out_dir"]])

  # Resample to isotropic 1x1x1 mm -> z slices should expand from 8 to ~19-20
  vol_iso <- volume_resample(vol, target_spacing = c(1.0, 1.0, 1.0), method = "trilinear")
  expect_s3_class(vol_iso, "dicom_volume")
  expect_equal(vol_iso$spacing, c(1.0, 1.0, 1.0), tolerance = 1e-5)
  expect_equal(dim(vol_iso)[1:2], c(32L, 32L))
  expect_gte(dim(vol_iso)[3L], 18L)
  expect_lte(dim(vol_iso)[3L], 21L)

  # World coordinate of voxel (1,1,1) should match original origin
  expect_equal(
    voxel_to_world(vol_iso, c(1, 1, 1)),
    voxel_to_world(vol, c(1, 1, 1)),
    tolerance = 1e-5
  )

  # Nearest-neighbor resampling on a multi-label dicom_seg must preserve exact integer labels
  mask_arr <- array(0L, dim = c(32L, 32L, 8L))
  mask_arr[8:16, 8:16, 2:4] <- 1L
  mask_arr[18:24, 18:24, 5:7] <- 2L
  seg <- dicom_seg(
    mask_arr,
    vol,
    tibble::tibble(segment_id = c(1L, 2L), label = c("Organ_1", "Lesion_2"))
  )

  seg_iso <- volume_resample(seg, target_spacing = c(2.0, 2.0, 2.5), method = "nearest")
  expect_s3_class(seg_iso, "dicom_seg")
  expect_s3_class(seg_iso, "dicom_volume")
  expect_equal(dim(seg_iso)[1:2], c(16L, 16L))
  expect_equal(seg_iso$spacing, c(2.0, 2.0, 2.5), tolerance = 1e-5)
  # Only integer labels 0, 1, 2 allowed (no interpolated 0.5 or 1.5)
  u_vals <- sort(unique(as.vector(seg_iso$voxels)))
  expect_true(all(u_vals %in% c(0, 1, 2)))
  expect_equal(seg_iso$segments$label, c("Organ_1", "Lesion_2"))
})

test_that("volume_window clips HU intensities and applies minmax/zscore normalization", {
  vox <- array(c(-1000, -500, 0, 40, 200, 1000, 2000, 3000), dim = c(2L, 2L, 2L))
  vol <- new_dicom_volume(vox, modality = "CT", units = "HU")

  # Soft-tissue window: center = 40, width = 400 -> [-160, 240]
  w_clip <- volume_window(vol, center = 40, width = 400, normalize = "none")
  expect_equal(min(w_clip$voxels), -160)
  expect_equal(max(w_clip$voxels), 240)

  # Minmax normalization -> [0, 1]
  w_mm <- volume_window(vol, center = 40, width = 400, normalize = "minmax")
  expect_equal(min(w_mm$voxels), 0.0, tolerance = 1e-6)
  expect_equal(max(w_mm$voxels), 1.0, tolerance = 1e-6)

  # Z-score normalization -> mean 0, sd 1
  w_z <- volume_window(vol, center = 40, width = 400, normalize = "zscore")
  expect_equal(mean(w_z$voxels), 0.0, tolerance = 1e-6)
  expect_equal(stats::sd(w_z$voxels), 1.0, tolerance = 1e-6)
})

test_that("dicom_patient_splits enforces zero patient leakage across train/val/test folds", {
  # 20 patients with multiple series/studies each
  df <- tibble::tibble(
    patient_id = rep(paste0("PAT_", sprintf("%02d", 1:20)), each = 3L),
    series_uid = paste0("UID_", seq_len(60L))
  )

  splits <- dicom_patient_splits(
    df,
    patient_col = "patient_id",
    val_frac = 0.2,
    test_frac = 0.2,
    seed = 123L
  )

  expect_true("split" %in% names(splits))
  expect_equal(nrow(splits), 60L)
  expect_setequal(unique(splits$split), c("train", "val", "test"))

  # Each patient must belong to exactly ONE split
  pats_per_split <- tapply(splits$split, splits$patient_id, function(x) length(unique(x)))
  expect_true(all(pats_per_split == 1L))

  train_pats <- unique(splits$patient_id[splits$split == "train"])
  val_pats <- unique(splits$patient_id[splits$split == "val"])
  test_pats <- unique(splits$patient_id[splits$split == "test"])

  expect_length(intersect(train_pats, val_pats), 0L)
  expect_length(intersect(train_pats, test_pats), 0L)
  expect_length(intersect(val_pats, test_pats), 0L)
})
