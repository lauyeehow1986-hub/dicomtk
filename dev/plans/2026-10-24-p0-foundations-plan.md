# Phase 0 (v0.2.0 Foundations — Geometry, Multi-Frame, Modality Transforms, NIfTI Parity & Test Lab) Implementation Plan

> **For Claude / Antigravity:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` to implement this plan task-by-task using strict RED-GREEN-REFACTOR TDD.

**Goal:** Build a mathematically exact 3D/4D `dicom_volume` geometry engine (classical + enhanced multi-frame + modality quantitative transforms + `dcm2niix`-compatible `qform`/`sform` NIfTI export + synthetic phantom generator + `dicomtk-lab` `core` stack) as the foundation for `dicomtk` v0.2.0.

**Architecture:** Extend `dicomtk`'s native C++17 parser/writer to index and serialize nested DICOM sequences (`SQ` items `[0]`, `[1]`, ...), enabling pure-C++ reading and synthesis of Enhanced Multi-Frame IODs (`SharedFunctionalGroupsSequence` / `PerFrameFunctionalGroupsSequence`). Introduce `dicom_volume` as the canonical S3 volume container storing `[rows, cols, slices]` (or 4D `[rows, cols, slices, frames]`) voxels alongside a 4x4 DICOM LPS affine (`[r, c, s, 1]` 0-based -> `(x_LPS, y_LPS, z_LPS, 1)` mm), per-frame metadata tibble, geometry diagnostics, and provenance records. Export NIfTI-1 files in standard RAS voxel/world alignment matching `dcm2niix` to within `1e-4` mm, while preserving `read_dicom_series()` and `dicom_to_nifti()` backward compatibility.

**Tech Stack:** R (>= 4.1), Rcpp (C++17), `tibble`, `dplyr`, `rlang`, `cli`, `lifecycle`, `jsonlite`, `RNifti` (optional Suggests, with standalone binary NIfTI-1 writer parity), `testthat` (edition 3), Docker Compose (`dicomtk-lab`).

---

## Coordinate Convention Reference (Read Before Implementing)

1. **DICOM Patient Coordinate System (LPS)**: `+x` = Left, `+y` = Posterior, `+z` = Superior (mm).
2. **`ImageOrientationPatient (0020,0037)`**: 6 direction cosines `(F11, F21, F31, F12, F22, F32)`:
   - First triplet `d_row = c(F11, F21, F31)` is the unit vector along a **row** (as column index `c` increases `0 .. cols-1`).
   - Second triplet `d_col = c(F12, F22, F32)` is the unit vector along a **column** (as row index `r` increases `0 .. rows-1`).
   - Slice normal: `n = cross(d_row, d_col)`.
3. **`PixelSpacing (0028,0030)`**: `c(dr, dc)` where `dr` = spacing between adjacent rows (along `d_col`), `dc` = spacing between adjacent columns (along `d_row`).
4. **In-memory `dicom_volume$voxels` (`[rows, cols, slices]` 1-based; `(r, c, s)` 0-based)** -> **4x4 LPS affine (`vol$affine`)**:
   - Column 1 (`r` step): `c(d_col * dr, 0)`
   - Column 2 (`c` step): `c(d_row * dc, 0)`
   - Column 3 (`s` step): `c(s_vec, 0)` where `s_vec = (IPP_last - IPP_first) / (nslices - 1)` if `nslices > 1` else `dz * n`
   - Column 4 (origin at `r=0, c=0, s=0`): `c(IPP_first, 1)`
5. **LPS <-> RAS**: `M_lps2ras = diag(c(-1, -1, 1, 1))`, so `A_ras = M_lps2ras %*% A_lps`.
6. **NIfTI / `dcm2niix` voxel layout**: NIfTI stores fastest axis `i = c` (`0..cols-1`), flipped row axis `j = rows - 1 - r` (`0..rows-1`), slice axis `k = s` (`0..slices-1`).
   - Array permutation in R: `nii_arr <- aperm(vol$voxels[rows:1, , , drop = FALSE], c(2L, 1L, 3L))` (extended to 4th dim if 4D).
   - Exact NIfTI RAS `sform` (`[i, j, k, 1]` 0-based -> `(x_RAS, y_RAS, z_RAS, 1)`):
     - Col 1 (`i` step): `d_row_ras * dc`
     - Col 2 (`j` step): `-d_col_ras * dr`
     - Col 3 (`k` step): `s_vec_ras`
     - Col 4 (origin at `i=0, j=0, k=0`, i.e. `c=0, r=rows-1, s=0`): `IPP_first_ras + (rows - 1) * d_col_ras * dr`

---

### Task 1: C++ Hierarchical Sequence Item Indexing & Nested `SQ` Writer

**Files:**
- Modify: `src/rcpp_dcmtk.h`
- Modify: `src/rcpp_read.cpp`
- Modify: `src/rcpp_write.cpp`
- Regenerate: `src/RcppExports.cpp`, `R/RcppExports.R`
- Test: `tests/testthat/test-p0-sequences.R`

**Step 1: Write the failing test**

Create `tests/testthat/test-p0-sequences.R`:

```r
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
    meta_tags = c("Modality", "SOPClassUID"),
    meta_values = c("CT", "1.2.840.10008.5.1.4.1.1.2.1"),
    shared_fg_json = jsonlite::toJSON(shared, auto_unbox = TRUE),
    per_frame_fg_json = jsonlite::toJSON(per_frame, auto_unbox = TRUE)
  )
  expect_true(ok)
  expect_true(is_dicom(out_dcm))

  hdr <- read_dicom(out_dcm, include_sequences = TRUE)
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
  # Substring compatibility for existing SEG/RT callers
  expect_true(all(grepl("5200,9230", ipp_rows$sequence_path, fixed = TRUE)))
})
```

**Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_local(filter = 'p0-sequences')"`
Expected: FAIL (`cpp_write_dicom_multiframe` not found).

**Step 3: Implement C++ sequence item indexing & `SQ` writer**

1. In `src/rcpp_dcmtk.h`, add nested `children` (`std::vector<std::vector<DcmElementRecord>> items`) to `DcmElementRecord` so a `VR == "SQ"` element can hold ordered items for serialization while `parse_dataset_range()` continues populating flat `out.elements` with indexed `seq_path`:
   - In `src/rcpp_read.cpp` (`parse_dataset_range`): maintain `int item_idx = 0;` inside sequence parsing; when `group == 0xFFFE && element == 0xE000`, pass `item_prefix = seq_prefix + "[" + std::to_string(item_idx++) + "]"` to the recursive `parse_dataset_range(...)` call.
2. In `src/rcpp_write.cpp`:
   - Add `encode_sequence_bytes(const DcmElementRecord& sq_el)` using explicit-length `FFFE,E000` items recursively, and update `write_dicom_file()` so `el.vr == "SQ"` with non-empty `el.items` is written via `write_explicit_element(buf, el.group, el.element, "SQ", encode_sequence_bytes(el))` instead of skipped.
   - Also preserve existing sequences when `cpp_modify_dicom()` reads a file by populating `sq_el.items` during `parse_dataset_range()`.
   - Add `// [[Rcpp::export]] bool cpp_write_dicom_multiframe(...)` accepting `NumericVector pixels`, `IntegerVector dims`, `std::string out_path`, `CharacterVector meta_tags`, `CharacterVector meta_values`, `std::string shared_fg_json`, `std::string per_frame_fg_json` (or R `Rcpp::List shared_fg`, `Rcpp::List per_frame_fg` directly without JSON parsing in C++ — **prefer `Rcpp::List` directly in C++** for zero parsing fragility! Update the test call to pass `shared_fg = shared, per_frame_fg = per_frame` directly!).

*(Note: Use `Rcpp::List shared_fg` and `Rcpp::List per_frame_fg` directly in `cpp_write_dicom_multiframe` and in `test-p0-sequences.R` — cleaner and faster than JSON strings.)*

3. Run `Rscript -e "Rcpp::compileAttributes()"` to update `src/RcppExports.cpp` and `R/RcppExports.R`.

**Step 4: Run tests to verify pass (including full regression suite)**

Run: `Rscript -e "testthat::test_local()"`
Expected: PASS (all existing 95 tests + new sequence tests pass, 0 warnings).

**Step 5: Commit**

```bash
git add src/rcpp_dcmtk.h src/rcpp_read.cpp src/rcpp_write.cpp src/RcppExports.cpp R/RcppExports.R tests/testthat/test-p0-sequences.R
git commit -m "feat(cpp): index sequence items in sequence_path and serialize nested SQs"
```

---

### Task 2: Synthetic Modality & PHI Phantom Generator (`dicom_synthesize()`)

**Files:**
- Create: `R/synthesize.R`
- Update: `NAMESPACE`, `man/dicom_synthesize.Rd` (via `roxygen2::roxygenise()`)
- Test: `tests/testthat/test-p0-synthesize.R`

**Step 1: Write the failing test**

Create `tests/testthat/test-p0-synthesize.R` testing:
1. Classic 3D CT axial/coronal/sagittal/oblique series generation in a temp dir with known `origin`, `spacing = c(0.8, 0.8, 2.5)`, asymmetric corner fiducial intensities (`r=1,c=1,s=1` = 1000 HU, `r=rows,c=1,s=1` = 2000 HU, `r=1,c=cols,s=nslices` = 3000 HU).
2. Enhanced multi-frame `"ENHCT"`, `"ENHMR"`, `"DBT"`, and cine `"XA_CINE"` / `"US_CINE"` single-file outputs.
3. PET (`"PT"`) phantom with `RadiopharmaceuticalInformationSequence (0054,0016)`, `PatientWeight`, `Units = "BQML"`.
4. Edge-case flags: `reverse_order = TRUE`, `irregular_z = TRUE`, `gantry_tilt_deg = 15`, `mixed_series = TRUE`, `phi = TRUE` vs `phi = FALSE`.

**Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_local(filter = 'p0-synthesize')"`
Expected: FAIL (`could not find function "dicom_synthesize"`).

**Step 3: Implement `dicom_synthesize()` in `R/synthesize.R`**

Implement exported `dicom_synthesize()`:
```r
dicom_synthesize <- function(out_dir = tempfile("dicom_synth_"),
                             modality = c("CT", "MR", "PT", "DX", "MG", "US", "XA",
                                          "ENHCT", "ENHMR", "DBT", "XA_CINE", "US_CINE"),
                             dims = c(32L, 32L, 8L),
                             spacing = c(1.0, 1.0, 2.5),
                             origin = c(-16.0, -16.0, 0.0),
                             orientation = c("axial", "coronal", "sagittal", "oblique"),
                             oblique_angles_deg = c(15, -10, 5),
                             gantry_tilt_deg = 0,
                             irregular_z = FALSE,
                             reverse_order = FALSE,
                             mixed_series = FALSE,
                             phi = TRUE,
                             seed = 42L)
```
- Computes exact orthonormal `d_row`, `d_col`, `n = cross(d_row, d_col)` (using ZYX Euler rotation for `"oblique"`).
- Applies optional gantry tilt by rotating the slice step direction around `d_row` by `gantry_tilt_deg`.
- Places a centered ellipsoid + 3 distinct fiducial voxels at `(1,1,1)`, `(rows,1,1)`, `(1,cols,slices)` so any transposition/flip is caught deterministically.
- Writes `RadiopharmaceuticalInformationSequence` for `"PT"`, VOI LUT / `PresentationIntentType` tags for `"MG"`/`"DX"`, burned-in top pixel strip + `BurnedInAnnotation = "YES"` for `"US"`, and `SharedFunctionalGroupsSequence`/`PerFrameFunctionalGroupsSequence` via `cpp_write_dicom_multiframe()` for enhanced multi-frame modalities.
- Returns invisibly a list of class `"dicom_phantom"` containing `files`, `truth_affine_lps`, `truth_voxels`, `modality`, `planted_phi`.

**Step 4: Document and run tests**

Run: `Rscript -e "roxygen2::roxygenise(); testthat::test_local(filter = 'p0-synthesize')"`
Expected: PASS.

**Step 5: Commit**

```bash
git add R/synthesize.R NAMESPACE man/ tests/testthat/test-p0-synthesize.R
git commit -m "feat(synth): add dicom_synthesize() multi-modality geometry and PHI phantom generator"
```

---

### Task 3: `dicom_volume` S3 Class & LPS/RAS World Coordinate Transforms

**Files:**
- Create: `R/dicom-volume.R`
- Test: `tests/testthat/test-p0-dicom-volume.R`

**Step 1: Write the failing test**

Create `tests/testthat/test-p0-dicom-volume.R` verifying:
- `new_dicom_volume()` constructs and validates a `dicom_volume` object (`voxels`, `affine`, `coord_system = "LPS"`, `spacing`, `direction`, `frame_meta`, `uids`, `modality`, `units`, `diagnostics`, `provenance`).
- `dim(vol)`, `as.array(vol)`, `print(vol)` work cleanly.
- `to_ras(vol)` negates rows 1 & 2 of `affine` and sets `coord_system = "RAS"` (idempotent if already `"RAS"`); `to_lps(to_ras(vol))` recovers `vol$affine` within `1e-12`.
- `voxel_to_world(vol, c(1, 1, 1), index_base = 1L)` equals `vol$affine[1:3, 4]`, and `world_to_voxel(vol, voxel_to_world(vol, ijk))` round-trips `ijk` within `1e-10`.
- Subsetting `vol[2:10, 3:12, 2:5]` returns a valid `dicom_volume` whose new origin equals `voxel_to_world(vol, c(2, 3, 2), index_base = 1L)` and slices `frame_meta` to rows `2:5`.
- `plot(vol)` returns a `ggplot` object (via `render_volume()` for 3D or `ggdicom()` for single-slice).

**Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_local(filter = 'p0-dicom-volume')"`
Expected: FAIL (`new_dicom_volume` / `to_ras` not defined).

**Step 3: Implement `R/dicom-volume.R`**

Implement:
- `new_dicom_volume()`, `is_dicom_volume()`
- S3 methods: `print.dicom_volume`, `dim.dicom_volume`, `as.array.dicom_volume`, `[.dicom_volume`, `plot.dicom_volume`
- Exported coordinate helpers: `to_ras()`, `to_lps()`, `voxel_to_world()`, `world_to_voxel()`
- Internal provenance helper `make_provenance_entry(action, params = list())` recording timestamp, `dicomtk` version, action, and parameters.

**Step 4: Document and run tests**

Run: `Rscript -e "roxygen2::roxygenise(); testthat::test_local(filter = 'p0-dicom-volume')"`
Expected: PASS.

**Step 5: Commit**

```bash
git add R/dicom-volume.R NAMESPACE man/ tests/testthat/test-p0-dicom-volume.R
git commit -m "feat(volume): add dicom_volume S3 class, subsetting, and LPS/RAS transforms"
```

---

### Task 4: Geometry-Aware `read_dicom_volume()`, Multi-Frame & Backward-Compatible `read_dicom_series()`

**Files:**
- Modify: `DESCRIPTION` (add `lifecycle (>= 1.0.3)` to `Imports`)
- Create: `R/volume-read.R`
- Modify: `R/read.R` (`read_dicom_series()` delegates to `read_dicom_volume()` with `lifecycle::deprecate_soft`)
- Modify: `R/volume.R` (`render_volume()` accepts `dicom_volume` natively and uses physical aspect ratios!)
- Test: `tests/testthat/test-p0-read-volume.R`

**Step 1: Write the failing test**

Create `tests/testthat/test-p0-read-volume.R` testing:
1. Shuffled / `reverse_order = TRUE` classic CT/MR series: `read_dicom_volume()` sorts by `IPP . normal` (NOT `InstanceNumber`!), recovering `phantom$truth_affine_lps` within `1e-5` and `phantom$truth_voxels` identically!
2. Oblique series (`orientation = "oblique"`): `vol$affine` matches `phantom$truth_affine_lps` within `1e-5`.
3. Enhanced multi-frame `"ENHCT"`, `"ENHMR"`, `"DBT"` single-file inputs: extracts per-frame IPP, orientation, pixel spacing, and per-frame rescale slope/intercept, matching ground truth.
4. Cine multi-frame (`"XA_CINE"`, `"US_CINE"`): preserves all frames without dropping frames `2..N`.
5. Diagnostics & warnings:
   - `irregular_z = TRUE` -> emits warning (`irregular_spacing = TRUE` in `vol$diagnostics`).
   - `gantry_tilt_deg = 15` -> emits warning (`gantry_tilt_deg` ~ 15 in `vol$diagnostics`, sheared column 3 in `vol$affine` matches tilted IPP).
   - `mixed_series = TRUE` -> splits into multiple sub-volumes and warns when `subseries = NULL` (or returns list of `dicom_volume`s when `split = TRUE`, or primary volume with warning when `split = FALSE`).
6. Backward compatibility: `read_dicom_series()` still passes all existing `test-dicomtk.R` checks, includes `$affine`, sorts reversed slices properly, and triggers `lifecycle` soft deprecation warning when `lifecycle_verbosity = "warning"`.

**Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_local(filter = 'p0-read-volume')"`
Expected: FAIL (`read_dicom_volume` not found).

**Step 3: Implement `read_dicom_volume()` and wire `read_dicom_series()` / `render_volume()`**

In `R/volume-read.R`:
- Implement `dicom_split_series(path, recursive = TRUE)` returning a tidy tibble of discovered sub-series (`series_uid`, `subseries_id`, `modality`, `rows`, `cols`, `n_files`, `n_frames`, `orientation_key`, `files`).
- Implement `read_dicom_volume(path, series_uid = NULL, subseries = 1L, rescale = TRUE, split = FALSE)`:
  - Handles single Enhanced Multi-Frame files by reading `include_sequences = TRUE` headers + `cpp_read_dicom_pixels(f, frame = 0L, rescale = FALSE)` and applying per-frame `RescaleSlope`/`RescaleIntercept` from `PerFrameFunctionalGroupsSequence` (falling back to `SharedFunctionalGroupsSequence` / top-level tags).
  - Handles classic multi-file series by reading headers, splitting mixed series (by `SeriesInstanceUID`, `Rows`, `Columns`, rounded `IOP`, and `EchoNumbers`), projecting `IPP` onto `n = cross(d_row, d_col)`, sorting ascending, checking duplicate IPPs (multi-echo / dynamic 4D stack -> reshape to `[rows, cols, n_unique_z, n_timepoints]`!), computing true z-spacing `diff(proj)`, and populating `diagnostics = list(irregular_spacing, max_spacing_dev_mm, has_gap_or_overlap, gantry_tilt_deg, duplicate_positions)`.
  - Notice existing `test-dicomtk.R` calls `read_dicom_series(c(dcm_file, dcm_file))` where `example.dcm` is duplicated (identical IPP or missing IPP): handle missing IPP gracefully (preserve input / `InstanceNumber` order, `spacing_z = SliceThickness %||% 1.0`, `affine = diag(c(dr, dc, dz, 1))`) and when `read_dicom_series()` is called on duplicate files without temporal tags, stack them along dim 3 as before while flagging `duplicate_positions = TRUE` so all 95 legacy tests remain 100% green!

**Step 4: Document and run full test suite**

Run: `Rscript -e "roxygen2::roxygenise(); testthat::test_local()"`
Expected: PASS (0 failures, 0 unexpected warnings).

**Step 5: Commit**

```bash
git add DESCRIPTION NAMESPACE R/volume-read.R R/read.R R/volume.R man/ tests/testthat/test-p0-read-volume.R
git commit -m "feat(volume): add geometry-aware read_dicom_volume() with multi-frame and series splitting"
```

---

### Task 5: Modality-Specific Quantitative Transforms (PET SUV, MG/DX VOI LUT, MR Private Scaling)

**Files:**
- Create: `R/modality-transforms.R`
- Test: `tests/testthat/test-p0-modality-transforms.R`

**Step 1: Write the failing test**

Create `tests/testthat/test-p0-modality-transforms.R` testing:
1. `dicom_pet_suv(vol, method = "bw")` on a synthesized `"PT"` volume with known activity concentration (`10,000 Bq/mL`), `PatientWeight = 70` kg (`70,000 g`), `RadionuclideTotalDose = 350e6` Bq, `RadionuclideHalfLife = 6586.2` s (F-18), and `elapsed = 6586.2` s (exact 1 half-life -> decayed dose = `175e6` Bq -> `SUVbw = 10000 / (175e6 / 70000) = 4.0 g/mL`!): verify voxel SUV equals `4.0` within `1e-4`! Also test `"lbm"` and `"bsa"`.
2. `dicom_apply_voi_lut(vol)` on `"MG"` / `"DX"` (`FOR PROCESSING` + `MONOCHROME1` + `SIGMOID` vs `LINEAR` VOI LUT).
3. `dicom_mr_rescale(vol)` on MR dataset with Philips private tags `(2005,100D)` ScaleIntercept and `(2005,100E)` ScaleSlope.

**Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_local(filter = 'p0-modality-transforms')"`
Expected: FAIL (`dicom_pet_suv` not found).

**Step 3: Implement `R/modality-transforms.R`**

Implement and export:
- `dicom_pet_suv(x, method = c("bw", "lbm", "bsa"), decay_correct = c("auto", "none", "force"))`:
  - Parses DICOM TM strings (`HHMMSS.FFFFFF`) accurately including midnight rollover check.
  - Reads `RadiopharmaceuticalInformationSequence (0054,0016)` tags from `read_dicom(f, include_sequences = TRUE)`.
  - If `Units (0054,1001) == "BQML"` and `CorrectedImage (0028,0051)` contains `"DECY"` (standard clinical PET: pixels are already decay-corrected to `SeriesTime` or `AcquisitionTime`), decays `RadionuclideTotalDose` from `RadiopharmaceuticalStartTime` to scan reference time (`dose_at_scan = dose * 2^(-dt / halflife)`).
  - Computes `SUVbw`, `SUVlbm` (Janmahasatian 2005 when height & sex available), or `SUVbsa` (DuBois & DuBois), updates `vol$units` and appends provenance.
- `dicom_apply_voi_lut(x, index = 1L)`
- `dicom_mr_rescale(x, philips_float = TRUE)`

**Step 4: Document and run tests**

Run: `Rscript -e "roxygen2::roxygenise(); testthat::test_local(filter = 'p0-modality-transforms')"`
Expected: PASS.

**Step 5: Commit**

```bash
git add R/modality-transforms.R NAMESPACE man/ tests/testthat/test-p0-modality-transforms.R
git commit -m "feat(modality): add PET SUV (bw/lbm/bsa), MG/DX VOI LUT, and Philips MR scaling"
```

---

### Task 6: `write_nifti()` with Exact `qform`/`sform` + BIDS JSON Sidecar (`dcm2niix` Parity)

**Files:**
- Create: `R/nifti.R`
- Modify: `R/convert.R` (`dicom_to_nifti()` delegates to `write_nifti()`)
- Test: `tests/testthat/test-p0-nifti.R`

**Step 1: Write the failing test**

Create `tests/testthat/test-p0-nifti.R` testing:
1. Across all 4 orientations (`"axial"`, `"coronal"`, `"sagittal"`, `"oblique"`), synthesize a phantom with fiducial markers at known LPS coordinates `P_lps`:
   - Read with `vol <- read_dicom_volume(...)`
   - Export with `write_nifti(vol, nii_path, json_sidecar = TRUE)` (test BOTH `backend = "rnifti"` and `backend = "builtin"` so the pure-R binary writer is identically verified!).
   - Read back with `RNifti::readNifti(nii_path)`:
     - Verify `sform` (`RNifti::xform(nii, useQuaternionFirst = FALSE)`) matches the analytical `dcm2niix` RAS affine within `1e-4`!
     - Verify `qform` (`RNifti::xform(nii, useQuaternionFirst = TRUE)`) matches `sform` within `1e-4` for orthogonal scans!
     - Verify that every fiducial voxel `(i, j, k)` in `nii` maps via `RNifti::voxelToWorld()` to the exact RAS physical coordinates `c(-P_lps[1], -P_lps[2], P_lps[3])` within `1e-4` mm!
2. Gantry-tilted CT (`gantry_tilt_deg = 15`): emits warning that `qform` orthogonalizes shear while `sform` preserves exact tilted geometry; verify `sform` maps slice `k` fiducial to exact tilted RAS coordinate within `1e-4` mm!
3. BIDS `.json` sidecar exists alongside `.nii` / `.nii.gz` and contains `Modality`, `ImageOrientationPatientDICOM`, `SliceThickness`, `ConversionSoftware = "dicomtk"`.

**Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_local(filter = 'p0-nifti')"`
Expected: FAIL (`write_nifti` not found).

**Step 3: Implement `R/nifti.R` and update `dicom_to_nifti()`**

In `R/nifti.R`:
- Implement `mat44_to_nifti_quatern(R_mat)` implementing the exact NIfTI-1 `nifti_mat44_to_quatern` algorithm (polar/column normalization, `qfac = sign(det(R33))`, `if (qfac < 0) R33[,3] <- -R33[,3]`, numerically stable branch selection across `trace` and diagonal maxima so `quatern_a >= 0` always holds).
- Implement `write_nifti(x, out_path = NULL, json_sidecar = TRUE, backend = c("auto", "rnifti", "builtin"))`:
  - Accepts `dicom_volume`, `dicom_series`, or path.
  - Permutes voxels to NIfTI `[i = c, j = rows:1, k = s]` and constructs exact 4x4 RAS `sform` + quaternion `qform`.
  - When `backend == "rnifti"` (or `"auto"` with `RNifti` available), sets both `RNifti::sform(nii) <- structure(sform_mat, code = 1L)` and `RNifti::qform(nii) <- structure(qform_mat, code = 1L)` and calls `RNifti::writeNifti(nii, out_path)`.
  - When `backend == "builtin"`, writes the exact 352-byte NIfTI-1 header with `qform_code = 1L`, `sform_code = 1L`, `pixdim[1] = qfac`, `quatern_b/c/d`, `qoffset_x/y/z`, and `srow_x/y/z` + float32 voxels.
  - Writes `<stem>.json` sidecar when `json_sidecar = TRUE`.
- Update `dicom_to_nifti()` in `R/convert.R` to call `write_nifti(path, out_path = out_path, json_sidecar = FALSE)`.

**Step 4: Document and run tests**

Run: `Rscript -e "roxygen2::roxygenise(); testthat::test_local()"`
Expected: PASS.

**Step 5: Commit**

```bash
git add R/nifti.R R/convert.R NAMESPACE man/ tests/testthat/test-p0-nifti.R
git commit -m "feat(nifti): add write_nifti() with dcm2niix-compatible qform/sform and BIDS sidecar"
```

---

### Task 7: External CI Fixture Downloader & Live `dcm2niix` Cross-Check

**Files:**
- Create: `tools/download_fixtures.R`
- Create: `tests/testthat/helper-fixtures.R`
- Create: `tests/testthat/test-p0-dcm2niix-parity.R`
- Modify: `.github/workflows/R-CMD-check.yaml`

**Step 1: Write the failing test**

Create `tests/testthat/test-p0-dcm2niix-parity.R`:
- Always runs analytical `dcm2niix` parity checks on CRAN-safe synthesized phantoms (axial, coronal, sagittal, oblique, negative spacing/reversed slices).
- When `dcm2niix` CLI is on `PATH` (or via Docker `DICOMTK_DOCKER_DCM2NIIX=true`), runs real `dcm2niix` on synthesized axial/coronal/sagittal/oblique series and asserts:
  - `max(abs(sform_dicomtk - sform_dcm2niix)) < 1e-4`
  - `max(abs(as.array(nii_dicomtk) - as.array(nii_dcm2niix))) < 1e-4`
- When cached external fixtures exist (`dicomtk_fixture_dir()`, populated by `Rscript tools/download_fixtures.R`), loads every fixture across modalities (`CT`, `MR`, `PT`, `ENHCT`, `MG`, `US`, `XA`) via `read_dicom_volume()` and verifies non-singular affine and valid dimensions.

**Step 2: Run test to verify failure before helper exists**

Run: `Rscript -e "testthat::test_local(filter = 'p0-dcm2niix-parity')"`
Expected: FAIL (`dicomtk_fixture_dir` not found).

**Step 3: Implement `tools/download_fixtures.R`, `helper-fixtures.R`, and CI step**

- `tools/download_fixtures.R`: downloads small, open-license reference DICOM files from `pydicom/pydicom-data` and `neurolabusc/dcm_qa_nih` into `tools::R_user_dir("dicomtk", "cache")/fixtures` (never bundled in the CRAN tarball!).
- `tests/testthat/helper-fixtures.R`: provides `dicomtk_fixture_dir()` and `find_dcm2niix_cmd()`.
- Update `.github/workflows/R-CMD-check.yaml` to install `dcm2niix` on Ubuntu runner (`sudo apt-get install -y dcm2niix`) and cache downloaded fixtures when `NOT_CRAN=true`.

**Step 4: Run `tools/download_fixtures.R` and run parity test suite**

Run: `Rscript tools/download_fixtures.R; Rscript -e "testthat::test_local(filter = 'p0-dcm2niix-parity')"`
Expected: PASS.

**Step 5: Commit**

```bash
git add tools/download_fixtures.R tests/testthat/helper-fixtures.R tests/testthat/test-p0-dcm2niix-parity.R .github/workflows/R-CMD-check.yaml
git commit -m "test(parity): add CI fixture downloader and dcm2niix affine parity suite"
```

---

### Task 8: `dicomtk-lab` Repository (`core` Profile) & PACS Container Smoke Test

**Files:**
- Create in new repo `C:/Users/lauye/.gemini/antigravity/scratch/dicomtk-lab`:
  - `docker-compose.yml` (`core` profile: `orthanc` with DICOMweb enabled, `dcm4chee-arc` + `ldap` + `db`, `keycloak`; documented profile stubs for `ai`, `ehr`, `ohdsi`, `ttp`, `fl`)
  - `.env.example`, `.gitignore`, `README.md`
  - `scripts/wait-healthy.ps1`, `scripts/wait-healthy.sh`
- Create in `dicomtk`:
  - `tests/testthat/test-p0-lab-core.R` (gated on `DICOMTK_TEST_LAB == "true"`, skipped on CRAN)

**Step 1: Write the failing integration test in `dicomtk`**

Create `tests/testthat/test-p0-lab-core.R`:
- Skips unless `identical(Sys.getenv("DICOMTK_TEST_LAB"), "true")`.
- Connects to `dicomtk-lab` Orthanc (`127.0.0.1:4242`, AE `ORTHANC`) via `dicom_connect()`, verifies `dicom_echo()`, synthesizes a 4-slice oblique CT phantom via `dicom_synthesize()`, verifies Orthanc REST/DICOMweb health (`http://127.0.0.1:8042/system`), uploads the synthesized series, downloads it back, and verifies `read_dicom_volume()` recovers the exact 4x4 LPS affine within `1e-4`!

**Step 2: Create `dicomtk-lab` repository and compose stack**

Initialize git repo at `C:/Users/lauye/.gemini/antigravity/scratch/dicomtk-lab`, write `docker-compose.yml` with `profiles: ["core"]` for `orthanc` (`jodogne/orthanc-plugins` / `orthancteam/orthanc`), `keycloak` (`quay.io/keycloak/keycloak`), and `dcm4chee` (`dcm4che/dcm4chee-arc-psql` + `dcm4che/slapd-dcm4chee` + `dcm4che/postgres-dcm4chee`), plus healthchecks and wait scripts.

**Step 3: Boot Orthanc in `dicomtk-lab` and verify `test-p0-lab-core.R` passes**

Run:
```powershell
cd C:\Users\lauye\.gemini\antigravity\scratch\dicomtk-lab
docker compose --profile core up -d orthanc
```
Then in `.worktrees/p0-geometry`:
```powershell
$env:DICOMTK_TEST_LAB="true"
Rscript -e "testthat::test_local(filter = 'p0-lab-core')"
```
Expected: PASS, then `docker compose --profile core stop` (clean shutdown).

**Step 4: Commit both `dicomtk-lab` and `dicomtk`**

Commit initial `main` commit in `dicomtk-lab`, and commit `tests/testthat/test-p0-lab-core.R` in `dicomtk` worktree.

---

### Task 9: Version Bump (`0.2.0`), Vignette, & Full `R CMD check --as-cran` Verification

**Files:**
- Modify: `DESCRIPTION` (`Version: 0.2.0`)
- Modify: `NEWS.md` (add `dicomtk 0.2.0` release notes)
- Create: `vignettes/volume-geometry.Rmd`
- Modify: `_pkgdown.yml` (add new functions & vignette reference)
- Modify: `MEMORY.md` (record Phase 0 completion milestones)

**Step 1: Write vignette & update package metadata**

Create `vignettes/volume-geometry.Rmd` demonstrating:
- `dicom_synthesize()` -> `read_dicom_volume()` -> `to_ras()` / `voxel_to_world()`
- Enhanced multi-frame reading & PET SUV calculation (`dicom_pet_suv()`)
- `write_nifti()` with `qform`/`sform` + BIDS JSON sidecar

**Step 2: Regenerate docs and run full test suite**

Run:
```powershell
Rscript -e "Rcpp::compileAttributes(); roxygen2::roxygenise(); testthat::test_local()"
```
Expected: 0 failures, 0 warnings.

**Step 3: Build tarball and run `R CMD check --as-cran`**

Run:
```powershell
R CMD build .
R CMD check dicomtk_0.2.0.tar.gz --no-manual
```
Expected: `Status: OK` (0 errors, 0 warnings). Clean up `.tar.gz` and `.Rcheck` directory afterward.

**Step 4: Commit**

```bash
git add DESCRIPTION NAMESPACE NEWS.md MEMORY.md _pkgdown.yml vignettes/volume-geometry.Rmd man/
git commit -m "chore(release): prepare dicomtk 0.2.0 Phase 0 Foundations release"
```
