# Re-Identification Risk Scoring and K-Anonymity Assessment

Evaluates re-identification risk metrics across a cohort of DICOM
studies by grouping subjects into quasi-identifier equivalence classes.
Computes \\k\\-anonymity, \\\ell\\-diversity, maximum prosecutor risk,
journalist risk, and marketer risk in compliance with HIPAA Expert
Determination and privacy engineering standards.

## Usage

``` r
dicom_deid_risk(
  path,
  quasi_ids = c("PatientSex", "PatientAge", "Modality", "StudyYear"),
  sensitive_attr = "BodyPartExamined",
  k_threshold = 5L
)
```

## Arguments

- path:

  Character vector of DICOM file paths, or a directory path.

- quasi_ids:

  Character vector of DICOM keywords or attributes acting as
  quasi-identifiers (e.g.
  `c("PatientSex", "PatientAge", "Modality", "StudyYear")`).

- sensitive_attr:

  Character string specifying the sensitive clinical attribute used for
  \\\ell\\-diversity calculation (default is `"BodyPartExamined"`).

- k_threshold:

  Integer minimum acceptable cell size \\k\\ (default is `5L`).
  Equivalence classes with \\k \< k\\threshold\\ are flagged.

## Value

An S3 object of class `"dicom_deid_risk"` containing:

- k_min:

  Integer minimum equivalence class size (\\k\\-anonymity).

- l_min:

  Integer minimum number of distinct sensitive values
  (\\\ell\\-diversity).

- max_prosecutor_risk:

  Numeric maximum prosecutor re-identification risk (\\1 / k\_{min}\\).

- journalist_risk:

  Numeric journalist risk (proportion of singleton subjects with \\k =
  1\\).

- marketer_risk:

  Numeric marketer risk (average re-identification probability across
  cohort).

- k_threshold:

  Integer threshold applied.

- n_subjects:

  Total number of unique subjects in the cohort.

- n_equivalence_classes:

  Total number of distinct equivalence classes.

- equivalence_classes:

  Tibble detailing each equivalence class, its \\k\\ size, \\\ell\\
  diversity, and member subjects.

- flagged_subjects:

  Character vector of subject IDs belonging to under-protected
  equivalence classes (\\k \< k\\threshold\\).

- flagged_patients:

  Alias for `flagged_subjects`.

- quasi_ids:

  Character vector of active quasi-identifiers.

- sensitive_attr:

  Active sensitive attribute.

## Examples

``` r
if (FALSE) { # \dontrun{
rk <- dicom_deid_risk("path/to/cohort", k_threshold = 5L)
print(rk)
if (rk$k_min < 5L) {
  message("Cohort requires generalization for: ", paste(rk$flagged_subjects, collapse = ", "))
}
} # }
```
