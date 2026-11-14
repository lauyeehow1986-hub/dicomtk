# Retrieve or Search FHIR Resources From a FHIR Server or Local Mock Directory

Retrieve or Search FHIR Resources From a FHIR Server or Local Mock
Directory

## Usage

``` r
fhir_get(
  resource_type,
  id = NULL,
  query = list(),
  base_url,
  token = NULL,
  headers = character(0)
)
```

## Arguments

- resource_type:

  FHIR resource type (e.g., `"ImagingStudy"`, `"Patient"`).

- id:

  Optional resource ID for direct read.

- query:

  Optional named list of FHIR search parameters.

- base_url:

  Base URL of the FHIR server or a local mock directory path.

- token:

  Optional Bearer/SMART access token.

- headers:

  Optional named character vector of HTTP headers.

## Value

A parsed FHIR resource or Bundle list.
