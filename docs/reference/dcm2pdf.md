# Extract Encapsulated PDF from a DICOM File

Extracts the binary PDF document stored in tag
`(0042,0011) EncapsulatedDocument`.

## Usage

``` r
dcm2pdf(file, out_path = tempfile(fileext = ".pdf"), opts = "", ...)
```

## Arguments

- file:

  Path to an Encapsulated PDF DICOM file.

- out_path:

  Output `.pdf` path. Defaults to a temporary `.pdf` file.

- opts:

  Optional arguments (kept for legacy compatibility).

- ...:

  Additional unused arguments.

## Value

Character string of the output `.pdf` file path.
