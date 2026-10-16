# Convert DICOM File(s) or Series to NIfTI-1 Format

Converts a single DICOM file, vector of DICOM files, directory of DICOM
slices, or `"dicom_series"` object into a standard NIfTI-1 (`.nii` or
`.nii.gz`) volumetric file. Uses `RNifti` when installed or a built-in
native NIfTI-1 binary writer with zero external dependencies.

## Usage

``` r
dicom_to_nifti(path, out_path = NULL)
```

## Arguments

- path:

  Path to a DICOM file, directory, vector of files, or a
  `"dicom_series"` object.

- out_path:

  Output `.nii` (or `.nii.gz`) path. If `NULL`, creates a temporary
  `.nii` file.

## Value

Invisibly returns `out_path`.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
nii_file <- dicom_to_nifti(dcm_file)
file.exists(nii_file)
#> [1] TRUE
```
