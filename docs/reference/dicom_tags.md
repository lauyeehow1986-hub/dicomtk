# Standard DICOM Data Dictionary (DCMTK 3.7.1 / PS 3.6-2026d)

A data frame containing 5,354 standard DICOM tags from the OFFIS DCMTK
3.7.1 data dictionary (`dicom.dic`).

If `path` is provided, reads and returns the DICOM header tags present
in `path` as a tidy tibble. If `path` is `NULL`, returns the complete
built-in OFFIS DCMTK 3.7.1 DICOM data dictionary (5,354 tags).

## Usage

``` r
dicom_tags

dicom_tags(path = NULL, ...)
```

## Format

A `data.frame` with 5,354 rows and 6 columns:

- tag:

  Tag identifier formatted as `"(GGGG,EEEE)"`

- name:

  Human-readable tag description

- keyword:

  DICOM standard keyword without spaces

- vr:

  Value Representation (e.g., `"PN"`, `"DA"`, `"UI"`, `"US"`)

- vm:

  Value Multiplicity (e.g., `"1"`, `"1-n"`)

- retired:

  `"RET"` if the tag is retired, `""` otherwise

## Arguments

- path:

  Optional file or directory path to read DICOM tags from. If `NULL`
  (default), returns the standard DICOM data dictionary.

- ...:

  Additional arguments passed to
  [`read_dicom()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_dicom.md)
  when `path` is not `NULL`.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
of DICOM tags.

## Examples

``` r
# View standard DICOM dictionary
dicom_tags()
#> # A tibble: 5,277 × 5
#>    tag         name                          keyword                 vr    vm   
#>    <chr>       <chr>                         <chr>                   <chr> <chr>
#>  1 (0000,0000) Command Group Length          CommandGroupLength      UL    1    
#>  2 (0000,0002) Affected SOP Class UID        AffectedSOPClassUID     UI    1    
#>  3 (0000,0003) Requested SOP Class UID       RequestedSOPClassUID    UI    1    
#>  4 (0000,0100) Command Field                 CommandField            US    1    
#>  5 (0000,0110) Message ID                    MessageID               US    1    
#>  6 (0000,0120) Message ID Being Responded To MessageIDBeingResponde… US    1    
#>  7 (0000,0600) Move Destination              MoveDestination         AE    1    
#>  8 (0000,0700) Priority                      Priority                US    1    
#>  9 (0000,0800) Command Data Set Type         CommandDataSetType      US    1    
#> 10 (0000,0900) Status                        Status                  US    1    
#> # ℹ 5,267 more rows

# Read tags from a DICOM file
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
dicom_tags(dcm_file)
#> # A tibble: 190 × 12
#>    file         tag   group element vr    length vm    keyword name  value depth
#>    <chr>        <chr> <chr> <chr>   <chr>  <int> <chr> <chr>   <chr> <chr> <int>
#>  1 "C:\\Users\… (000… 0002  0000    UL         4 1     FileMe… File… "192"     0
#>  2 "C:\\Users\… (000… 0002  0001    OB         2 1     FileMe… File… "00\…     0
#>  3 "C:\\Users\… (000… 0002  0002    UI        26 1     MediaS… Medi… "1.2…     0
#>  4 "C:\\Users\… (000… 0002  0003    UI        48 1     MediaS… Medi… "1.3…     0
#>  5 "C:\\Users\… (000… 0002  0010    UI        20 1     Transf… Tran… "1.2…     0
#>  6 "C:\\Users\… (000… 0002  0012    UI        18 1     Implem… Impl… "1.3…     0
#>  7 "C:\\Users\… (000… 0002  0013    SH        10 1     Implem… Impl… "DCT…     0
#>  8 "C:\\Users\… (000… 0002  0016    AE         8 1     Source… Sour… "CLU…     0
#>  9 "C:\\Users\… (000… 0008  0005    CS        10 1-n   Specif… Spec… "ISO…     0
#> 10 "C:\\Users\… (000… 0008  0008    CS        22 2-n   ImageT… Imag… "ORI…     0
#> # ℹ 180 more rows
#> # ℹ 1 more variable: sequence_path <chr>
```
