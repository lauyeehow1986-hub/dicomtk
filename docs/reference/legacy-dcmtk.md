# Legacy Compatibility Functions from `dcmtk`

Backward-compatible wrappers for functions in the original `dcmtk` R
package (`dcmdump`, `dcmdump_full`, `dcmhd`, `wide_hdr`, `burned_annot`,
`dcmodify`, `dcm_anon`, `dcm_subtract_date`, `dcmj2pnm`, `dcmdjpeg`,
`dcmdrle`, `dcmcrle`, `check_dcmtk_cmd`), now powered by the native
`dicomtk` C++17 engine without requiring external CLI binaries.

## Usage

``` r
dcmdump(file, ...)

dcmdump_full(file, ...)

dcmhd(file, ...)

wide_hdr(hdr, ...)

burned_annot(file, ...)

dcmodify(file, tags = list(), outfile = file, ...)

dcm_anon(file, outfile = NULL, ...)

dcm_subtract_date(file, outfile = NULL, shift_days = -365L, ...)

dcmj2pnm(file, outfile = tempfile(fileext = ".png"), opts = "--write-png", ...)

dcmdjpeg(file, outfile = tempfile(fileext = ".dcm"), ...)

dcmdrle(file, outfile = tempfile(fileext = ".dcm"), ...)

dcmcrle(file, outfile = tempfile(fileext = ".dcm"), ...)

check_dcmtk_cmd(cmd = "dcmdump")
```

## Arguments

- file:

  Path to DICOM file(s).

- ...:

  Additional arguments passed to modern `dicomtk` equivalents.

- hdr:

  A header data frame or tibble returned by
  [`read_dicom_header()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom_header.md).

- tags:

  Named list of tags and values to modify.

- outfile:

  Optional output file path.

- shift_days:

  Integer number of days to shift dates (default `-365L`).

- opts:

  Optional command-line style options (ignored in native C++ mode).

- cmd:

  Command name.
