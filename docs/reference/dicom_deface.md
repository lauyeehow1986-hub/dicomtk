# 3D Coordinate-Aware Head CT/MR Defacing

Removes recognizable facial features (nose, jaw, facial profile) from 3D
cranial CT and MR volumes using orientation-invariant physical RAS
coordinates, while guaranteeing that deep intracranial brain parenchyma
remains completely untouched.

## Usage

``` r
dicom_deface(
  x,
  out_dir = NULL,
  fill = c("auto", "air", "zero"),
  surface_depth_mm = 35,
  nasion_fraction = 0.55,
  tragus_fraction = 0.5,
  ...
)
```

## Arguments

- x:

  A
  [`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
  object, or a character string / vector specifying a DICOM directory or
  slice file paths.

- out_dir:

  Optional directory path where defaced DICOM slice files will be
  written. If `NULL` (default), no files are written.

- fill:

  Method or numeric scalar to fill masked facial voxels: `"auto"` (-1000
  HU for CT, 0 for MR), `"air"` (-1000), `"zero"` (0), or a numeric
  scalar value.

- surface_depth_mm:

  Numeric scalar. Maximum superficial depth (in millimeters) from the
  anterior air-skin surface to mask. Tissue deeper than this limit is
  guaranteed untouched. Default is 35 mm.

- nasion_fraction:

  Numeric scalar between 0 and 1. Fraction of the head's
  inferior-to-superior span defining the superior boundary of facial
  defacing (nasion plane). Default is 0.55.

- tragus_fraction:

  Numeric scalar between 0 and 1. Fraction of the head's
  anterior-to-posterior span defining the posterior boundary of the
  facial bevel (tragus plane). Default is 0.50.

- ...:

  Additional arguments passed to internal methods.

## Value

A modified
[`dicom_volume`](https://lauyeehow1986-hub.github.io/dicomtk/reference/new_dicom_volume.md)
object with facial voxels replaced by the fill value, and a provenance
record appended. When `out_dir` is provided, written DICOM slice files
carry:

- `RecognizableVisualFeatures (0028,0302) == "NO"`

- `ImageType (0008,0008)` starting with `"DERIVED\SECONDARY"`

- Fresh `SOPInstanceUID (0008,0018)` and
  `MediaStorageSOPInstanceUID (0002,0003)`

- CID 7050 code `"113102"` (*Clean Recognizable Visual Features Option*)
  stamped in `DeidentificationMethodCodeSequence (0012,0064)`.

## Details

The defacing algorithm operates in physical RAS world coordinates
derived via
[`to_ras`](https://lauyeehow1986-hub.github.io/dicomtk/reference/to_ras.md)`(vol)$affine`,
ensuring that facial geometry is computed consistently regardless of
whether the volume was acquired axially, sagittally, or coronally. The
algorithm defines an anterior-inferior facial bevel half-space bounded
by the nasion and tragus planes, restricted to superficial tissue within
`surface_depth_mm` of the anterior air-skin boundary.

## Examples

``` r
if (FALSE) { # \dontrun{
vol <- read_dicom_volume("path/to/head_ct")
defaced <- dicom_deface(vol, out_dir = "path/to/defaced_ct")
} # }
```
