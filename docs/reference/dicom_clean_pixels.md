# Clean Burned-In Pixel PHI via Blackout or Telea Inpainting

Cleans burned-in annotation regions in DICOM pixel data using either
complete blackout (filling with background zero/raw min) or guard-railed
C++17 Telea (2004) Fast Marching Method inpainting.

## Usage

``` r
dicom_clean_pixels(
  path,
  out_path = NULL,
  pixel_method = c("blackout", "inpaint"),
  boxes = NULL,
  mask_sidecar = TRUE,
  radius = 5L,
  ...
)
```

## Arguments

- path:

  Character path to the input DICOM file.

- out_path:

  Optional character path for the cleaned DICOM file. If `NULL`,
  overwrites `path` in-place.

- pixel_method:

  Character string specifying cleaning method: `"blackout"` (default) or
  `"inpaint"`.

- boxes:

  Optional data frame or matrix with bounding boxes
  `(ymin, xmin, ymax, xmax)`. If `NULL`, candidate boxes are detected
  automatically via
  [`dicom_detect_burned_phi()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_detect_burned_phi.md).

- mask_sidecar:

  Logical. Whether to write `<out_stem>_inpaint_mask.rds` when
  `pixel_method = "inpaint"`. Default is `TRUE`.

- radius:

  Integer radius for Telea inpainting narrow band. Default is `5L`.

- ...:

  Additional arguments passed to
  [`dicom_detect_burned_phi()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_detect_burned_phi.md).

## Value

Invisibly returns the normalized `out_path`.

## Details

When `pixel_method = "inpaint"` is selected, all 4 mandatory guardrails
are enforced:

1.  `ImageType (0008,0008)` starts with `"DERIVED\SECONDARY"`.

2.  `SOPInstanceUID (0008,0018)` is regenerated to a new UID.

3.  `DeidentificationMethodCodeSequence (0012,0064)` records code
    `"113101"` (`"Clean Pixel Data Option"`) and `"INPAINT_TELEA"`
    description.

4.  An RDS sidecar mask `<out_stem>_inpaint_mask.rds` is written to disk
    with the exact logical mask of modified pixels.

## Examples

``` r
if (FALSE) { # \dontrun{
dicom_clean_pixels("ultrasound.dcm", "clean_us.dcm", pixel_method = "blackout")
} # }
```
