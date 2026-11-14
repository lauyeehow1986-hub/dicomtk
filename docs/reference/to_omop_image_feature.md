# Map Segmentation Masks or TID 1500 SR Reports to OHDSI OMOP `IMAGE_FEATURE`

Map Segmentation Masks or TID 1500 SR Reports to OHDSI OMOP
`IMAGE_FEATURE`

## Usage

``` r
to_omop_image_feature(
  x,
  image_occurrence_id = 1L,
  person_id = 1L,
  alg_system = "dicomtk"
)
```

## Arguments

- x:

  A `dicom_seg` object or a parsed `dicom_sr_tid1500` report from
  [`read_sr_tid1500()`](https://lauyeehow1986-hub.github.io/dicomtk/reference/read_sr_tid1500.md).

- image_occurrence_id:

  Integer foreign key referencing
  `image_occurrence$image_occurrence_id`.

- person_id:

  Integer OMOP `person_id`.

- alg_system:

  Character name of the algorithm or pipeline producing the feature
  (default `"dicomtk"`).

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
conforming to OHDSI `image_feature`.
