test_that("dicomtk-lab ehr and ohdsi endpoints respond when DICOMTK_TEST_INTEROP=true", {
  skip_if_not(
    identical(tolower(Sys.getenv("DICOMTK_TEST_INTEROP", "false")), "true"),
    "dicomtk-lab interop container smoke tests skipped. Set DICOMTK_TEST_INTEROP=true to run."
  )

  hapi_url <- Sys.getenv("DICOMTK_HAPI_FHIR_URL", "http://127.0.0.1:8080/fhir/metadata")
  resp <- httr2::request(hapi_url) |>
    httr2::req_timeout(5) |>
    httr2::req_perform()
  expect_lt(httr2::resp_status(resp), 500L)
})
