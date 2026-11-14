# Read a DICOM SR TID 1500 Measurement Report

Parses a DICOM Structured Report following **TID 1500 (Measurement
Report)** and extracts all quantitative `NUM` measurements along with
their `TrackingIdentifier (112039, DCM)`,
`TrackingUniqueIdentifier (112040, DCM)`, concept codes, and UCUM
measurement units into a tidy
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html).

## Usage

``` r
read_sr_tid1500(path)
```

## Arguments

- path:

  Path to a DICOM SR `.dcm` file.

## Value

An S3 object of class `"dicom_sr_tid1500"` containing `measurements`
(tidy tibble), `header` (top-level DICOM tags), and `raw_sr` (full
sequence hierarchy tibble).

## Examples

``` r
synth <- dicom_synthesize(modality = "CT", dims = c(16L, 16L, 4L))
vol <- read_dicom_volume(synth[["out_dir"]])
m <- array(0L, dim = c(16L, 16L, 4L))
m[5:10, 5:10, 2L] <- 1L
seg <- dicom_seg(m, vol, tibble::tibble(segment_id = 1L, label = "Node_1"))
tmp_sr <- tempfile(fileext = ".dcm")
dicom_sr_tid1500(vol, seg, out_path = tmp_sr)
#> <dicom_sr_tid1500 [5 measurement(s)]>
#> # A tibble: 1 × 10
#>   segment_id label  volume_mm3 volume_cm3 recist_diameter_mm mean_intensity
#>        <int> <chr>       <dbl>      <dbl>              <dbl>          <dbl>
#> 1          1 Node_1         90       0.09               8.07           36.4
#> # ℹ 4 more variables: sd_intensity <dbl>, min_intensity <dbl>,
#> #   max_intensity <dbl>, units <chr>
sr_in <- read_sr_tid1500(tmp_sr)
sr_in$measurements
#> # A tibble: 5 × 9
#>   tracking_id tracking_uid    concept_code concept_scheme concept_meaning   
#>   <chr>       <chr>           <chr>        <chr>          <chr>             
#> 1 Node_1      2.25.1.32226548 118565006    SCT            Volume            
#> 2 Node_1      2.25.1.32226548 118565006    SCT            Volume cm3        
#> 3 Node_1      2.25.1.32226548 103339001    SCT            Long Axis         
#> 4 Node_1      2.25.1.32226548 373098007    SCT            Mean Value        
#> 5 Node_1      2.25.1.32226548 386136009    SCT            Standard Deviation
#> # ℹ 4 more variables: numeric_value <dbl>, unit_code <chr>, unit_scheme <chr>,
#> #   unit_meaning <chr>
unlink(tmp_sr)
```
