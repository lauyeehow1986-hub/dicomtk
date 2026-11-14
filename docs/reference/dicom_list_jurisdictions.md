# List Built-In Statutory De-Identification Jurisdictions

Returns the identifiers of all built-in statutory privacy jurisdiction
profiles available in dicomtk.

## Usage

``` r
dicom_list_jurisdictions()
```

## Value

A character vector of jurisdiction identifiers.

## Examples

``` r
dicom_list_jurisdictions()
#> [1] "au_privacy_nhmrc"           "gdpr"                      
#> [3] "hipaa_expert_determination" "hipaa_safe_harbor"         
#> [5] "my_pdpa_2024"               "sg_pdpa_hib"               
#> [7] "tcia_ctp"                   "uk_gdpr"                   
```
