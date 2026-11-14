# Post a FHIR Resource to a FHIR REST Server or Local Mock Directory

Post a FHIR Resource to a FHIR REST Server or Local Mock Directory

## Usage

``` r
fhir_post(resource, base_url, token = NULL, headers = character(0))
```

## Arguments

- resource:

  A named list representing a FHIR resource (must contain
  `resourceType`).

- base_url:

  Base URL of the FHIR server (e.g., `"http://localhost:8080/fhir"`) or
  a local directory path for offline mock storage.

- token:

  Optional Bearer/SMART access token.

- headers:

  Optional named character vector of HTTP headers.

## Value

The created/stored FHIR resource list (with `id` populated).
