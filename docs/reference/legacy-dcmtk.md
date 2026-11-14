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

## Value

Return values depend on the specific legacy wrapper function called:

- `dcmdump`:

  Character vector formatted similarly to CLI `dcmdump` output with tag,
  VR, value, length, VM, and keyword.

- `dcmdump_full`:

  A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
  containing full header and nested sequence items as returned by
  [`read_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom.md).

- `dcmhd`:

  A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
  containing the top-level DICOM header elements.

- `wide_hdr`:

  A wide
  [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
  with one row per file and columns corresponding to DICOM element
  keywords.

- `burned_annot`:

  Character scalar value of the `BurnedInAnnotation (0028,0301)` tag.

- `dcmodify`:

  Character vector of modified DICOM file paths as returned by
  [`dicom_modify()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_modify.md).

- `dcm_anon`, `dcm_subtract_date`:

  Character vector of anonymized DICOM file paths as returned by
  [`dicom_anonymize()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_anonymize.md).

- `dcmj2pnm`:

  Character path to the rendered output PNG file as returned by
  [`dicom_to_png()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_to_png.md).

- `dcmdjpeg`, `dcmdrle`:

  Character path to the decompressed DICOM file as returned by
  [`dicom_decompress()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_decompress.md).

- `dcmcrle`:

  Character path to the compressed DICOM file as returned by
  [`dicom_compress()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_compress.md).

- `check_dcmtk_cmd`:

  Logical `TRUE` indicating the native DCMTK engine is available.
