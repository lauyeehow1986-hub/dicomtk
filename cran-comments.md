## Resubmission

This is a resubmission of the new package `dicomtk` 0.1.0 addressing feedback from CRAN reviewer Konstanze Lauseker:

* Added a detailed `\value` documentation tag in `man/legacy-dcmtk.Rd` describing the return values, structure, and classes of all exported legacy wrapper functions.
* Ensured graphical parameters in `R/convert.R` (`dicom_to_png`) properly save `oldpar <- graphics::par(no.readonly = TRUE)` and restore them via an immediate `on.exit(graphics::par(oldpar), add = TRUE)`.
* Ensured options changed in `R/viewer.R` (`dicom_viewer`) properly save `old_opt <- options(...)` and restore them via an immediate `on.exit(options(old_opt), add = TRUE)`.
* Ensured working directory changes in `R/utils.R` preserve and immediately reset state via `on.exit(setwd(old_wd), add = TRUE)`.

## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

* Local Windows 11 x64, R 4.5.2 (ucrt), Rtools45 (GCC 14.3.0, C++17)
* GitHub Actions:
  * `windows-latest` (R release)
  * `macos-latest` (R release, arm64)
  * `ubuntu-latest` (R release)
  * `ubuntu-latest` (R devel)

## Downstream dependencies

This is a new package (`dicomtk` 0.1.0), modernizing and expanding the legacy `dcmtk` R wrapper with a bundled C++17 / Rcpp DICOM engine synchronized with OFFIS DCMTK 3.7.1 (`PS 3.6-2026d`), requiring zero external system installation.
