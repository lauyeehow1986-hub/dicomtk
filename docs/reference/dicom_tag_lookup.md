# Search or Query the DICOM Data Dictionary

Searches the 5,354-entry DCMTK 3.7.1 DICOM data dictionary by substring
or tag `(GGGG,EEEE)`. When an `llm` object (created by
[`dicom_llm()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_llm.md))
is supplied, natural-language questions (e.g.,
`"What tag stores tube current?"`) are also answered using the
configured LLM.

## Usage

``` r
dicom_tag_lookup(query, llm = NULL)
```

## Arguments

- query:

  Search string, tag `"(GGGG,EEEE)"`, keyword, or natural-language
  question.

- llm:

  Optional `"dicom_llm"` configuration object from
  [`dicom_llm()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/dicom_llm.md)
  for natural-language tag interpretation.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
of matching DICOM dictionary entries (with an optional
`"llm_explanation"` attribute if `llm` is provided).

## Examples

``` r
dicom_tag_lookup("WindowCenter")
#> # A tibble: 3 × 5
#>   tag         name                              keyword              vr    vm   
#>   <chr>       <chr>                             <chr>                <chr> <chr>
#> 1 (0028,1050) Window Center                     WindowCenter         DS    1-n  
#> 2 (0028,1055) Window Center & Width Explanation WindowCenterWidthEx… LO    1-n  
#> 3 (0018,0032) Energy Window Centerline          RETIRED_EnergyWindo… DS    1    
dicom_tag_lookup("(0028,1050)")
#> # A tibble: 1 × 5
#>   tag         name          keyword      vr    vm   
#>   <chr>       <chr>         <chr>        <chr> <chr>
#> 1 (0028,1050) Window Center WindowCenter DS    1-n  
dicom_tag_lookup("Patient")
#> # A tibble: 131 × 5
#>    tag         name                                         keyword  vr    vm   
#>    <chr>       <chr>                                        <chr>    <chr> <chr>
#>  1 (0008,1120) Referenced Patient Sequence                  Referen… SQ    1    
#>  2 (0010,0010) Patient's Name                               Patient… PN    1    
#>  3 (0010,0020) Patient ID                                   Patient… LO    1    
#>  4 (0010,0021) Issuer of Patient ID                         IssuerO… LO    1    
#>  5 (0010,0022) Type of Patient ID                           TypeOfP… CS    1    
#>  6 (0010,0024) Issuer of Patient ID Qualifiers Sequence     IssuerO… SQ    1    
#>  7 (0010,0026) Source Patient Group Identification Sequence SourceP… SQ    1    
#>  8 (0010,0027) Group Of Patients Identification Sequence    GroupOf… SQ    1    
#>  9 (0010,0030) Patient's Birth Date                         Patient… DA    1    
#> 10 (0010,0032) Patient's Birth Time                         Patient… TM    1    
#> # ℹ 121 more rows
```
