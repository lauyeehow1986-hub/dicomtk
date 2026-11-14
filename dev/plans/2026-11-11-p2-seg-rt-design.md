# Phase 2 Design: Segmentation, Radiation Therapy (RTSTRUCT/RTDOSE), Quantitative SR & Deep Learning Prep (`v0.4.0`)

## 1. Executive Summary & Goals

Phase 2 transitions `dicomtk` into an end-to-end clinical imaging and deep learning preparation powerhouse. It introduces:
1. **Unified Segmentation (`dicom_seg`)**: A first-class S3 subclass of `dicom_volume` supporting binary, fractional, and Sup 243 label-map DICOM-SEG IODs with full 4x4 spatial affine alignment and standard coded anatomic concepts.
2. **Radiation Therapy Integration (`RTSTRUCT` & `RTDOSE`)**:
   - Bi-directional conversion between `RTSTRUCT` planar polygonal contours and 3D voxel segmentation masks via high-performance C++17 winding-number scanline rasterization and marching squares contour tracing.
   - Spatial integration of `RTDOSE` grids with `dicom_seg` to compute cumulative and differential Dose-Volume Histograms (DVH) with key clinical metrics ($D_{95}$, $D_{50}$, $V_{20}$, max/mean dose).
3. **Structured Reporting & Annotations**:
   - Native reader and builder for **SR TID 1500** (Measurement Report) for quantitative imaging biomarkers.
   - Grayscale Softcopy Presentation State (**GSPS**) parser.
   - Safe derived burned-annotation exporter (`ImageType = DERIVED\SECONDARY`) for conferences and teaching files without compromising source data.
4. **Deep Learning Preprocessing & Dataset Standardization**:
   - High-performance C++17 3D volume resampling (trilinear for continuous voxel intensities, nearest-neighbor for segmentations/labels).
   - Leakage-free patient-level split generator (`train`, `val`, `test`).
   - Standardized zero-copy exporters for **nnU-Net v2** and **MONAI**.
   - Dataset catalog provenance schemas via **RO-Crate** and **MLCommons Croissant** JSON-LD.
5. **Automated Image Quality Control (QC)**:
   - Automated detection of acquisition artifacts, field-of-view truncation, and motion artifacts.
   - Quantitative SNR and CNR metrics (MRIQC-style).

---

## 2. Architecture & Data Structures

### 2.1 Unified `dicom_seg` S3 Class
`dicom_seg` inherits directly from `dicom_volume`:
```r
class(x) <- c("dicom_seg", "dicom_volume")
```
- **Fields**:
  - `array`: 3D integer array `[x, y, z]` for mutually exclusive label-maps, or 4D logical/numeric array `[x, y, z, k]` for overlapping or fractional probability maps.
  - `affine`: $4 \times 4$ LPS coordinate affine matrix identical to reference volume.
  - `spacing`: Voxel dimensions `c(dx, dy, dz)`.
  - `segments`: A tidy `tibble` of segment metadata:
    - `segment_id` (integer)
    - `label` (character, e.g. "Liver", "GTV")
    - `category` (character, e.g. "Anatomy", "Tumor")
    - `type` (`"binary"` | `"fractional"` | `"labelmap"`)
    - `algorithm_type` (`"MANUAL"` | `"AUTOMATIC"` | `"SEMIAUTOMATIC"`)
    - `anatomic_region` (code and meaning)
    - `property_category` (coded concept)
  - `source_volume_uid`: Series/Study Instance UID of the referenced anatomical image.
  - `provenance`: Modification history and algorithm metadata.

### 2.2 Coordinate Mapping & Spatial Fidelity
- World coordinates in DICOM are LPS (Left, Posterior, Superior).
- Given LPS point $\mathbf{p} = [x, y, z, 1]^T$, the voxel index $\mathbf{v} = [i, j, k, 1]^T$ is obtained via:
  $$\mathbf{v} = \mathbf{A}^{-1} \mathbf{p}$$
  where $\mathbf{A}$ is the $4 \times 4$ affine matrix from `dicom_volume`.
- In-plane polygon rasterization is performed slice-by-slice:
  1. Contours in `RTSTRUCT` with $z \approx z_{\text{slice}}$ are mapped onto the 2D pixel coordinate frame $(i, j)$ using the inverse in-plane direction cosines and origin.
  2. A C++17 even-odd / non-zero winding number scanline algorithm fills interior pixels.
  3. Reverse conversion (mask to contours) uses 2D marching squares to extract closed boundary loops.

---

## 3. High-Throughput C++17 Computational Cores

1. **`src/rcpp_rasterize.cpp`**:
   - `cpp_rasterize_polygon_2d`: Scanline polygon rasterization into 2D bitmask.
   - `cpp_trace_contours_2d`: Marching squares / boundary traversal to produce ordered polygon vertices.
   - `cpp_resample_volume_3d`: 3D trilinear interpolation (for image volumes) and nearest-neighbor (for integer/label masks).
2. **`src/rcpp_seg.cpp`**:
   - Bit-packed DICOM-SEG frame encoding and decoding (`1-bit` binary mask packing per PS3.5 / PS3.3 C.8.20).
   - Fractional probability quantization (`8-bit` normalized to $0..255$).

---

## 4. Worktree & Git Strategy

- Worktree: `C:/Users/lauye/.gemini/antigravity/scratch/dicomtk/.worktrees/p2-seg-rt`
- Branch: `feature/p2-seg-rt`
- Target base: `main` (`c6a3bee`)
