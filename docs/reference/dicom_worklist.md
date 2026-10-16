# Query or Create Modality Worklist Entries (`dcmwlm`)

Reads or constructs a tidy Modality Worklist (`MWL`) schedule table
containing `ScheduledProcedureStepSequence (0040,0100)` attributes
(`Modality`, `ScheduledStationAETitle`,
`ScheduledProcedureStepStartDate`, `PatientName`, `PatientID`,
`AccessionNumber`).

## Usage

``` r
dicom_worklist(path = NULL)
```

## Arguments

- path:

  Optional path to a DICOM worklist `.dcm`/`.wl` file or directory. If
  `NULL`, returns an empty template worklist tibble.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
representing Modality Worklist scheduled items.

## Examples

``` r
dicom_worklist()
#> # A tibble: 0 × 7
#> # ℹ 7 variables: AccessionNumber <chr>, PatientID <chr>, PatientName <chr>,
#> #   Modality <chr>, ScheduledStationAETitle <chr>,
#> #   ScheduledProcedureStepStartDate <chr>,
#> #   ScheduledProcedureStepDescription <chr>
```
