# Build curated OHDSI OMOP Medical Imaging CDM (MI-CDM) concept crosswalk
# Run from package root: Rscript data-raw/build_omop_imaging_concepts.R

omop_imaging_concepts <- tibble::tibble(
  concept_id = c(
    # Modalities (SNOMED / DICOM / OMOP)
    4300757L, 4013636L, 40482510L, 4062041L, 4058709L,
    4037672L, 4168421L, 4082616L, 4059142L, 4049218L, 4089756L,
    # Anatomic sites (SNOMED)
    4120624L, 4133034L, 4048395L, 4089748L, 4213162L,
    4217142L, 4031093L, 4000626L, 4009105L, 4271678L,
    4102203L, 4002635L, 4027594L,
    # Quantitative imaging features (LOINC / SNOMED / RadLex)
    3000963L, 3001420L, 3004249L, 3004501L, 3012888L,
    3027018L, 3034630L, 3040812L, 3045792L, 3051825L,
    3053283L, 3061234L, 3062901L, 3065412L, 3067890L,
    # Units (UCUM)
    8588L, 8519L, 8523L, 8554L, 8576L,
    8504L, 8510L, 8547L, 8515L,
    # Feature types (OMOP Type Concept)
    32817L, 32879L, 32856L, 32842L
  ),
  concept_name = c(
    # Modalities
    "Computed tomography", "Magnetic resonance imaging", "Positron emission tomography",
    "Digital radiography", "Mammography", "Ultrasonography", "Angiography",
    "Nuclear medicine imaging", "Computed radiography", "Fluoroscopy", "Other imaging",
    # Anatomic sites
    "Head structure", "Brain structure", "Neck structure", "Thoracic structure", "Lung structure",
    "Heart structure", "Breast structure", "Abdominal structure", "Liver structure", "Kidney structure",
    "Pelvic structure", "Vertebral column structure", "Extremity structure",
    # Quantitative features
    "Lesion volume", "Mean attenuation (HU)", "Maximum SUV (body weight)", "Mean SUV (body weight)", "Maximum 3D diameter",
    "Surface area", "Dice similarity coefficient", "Hausdorff distance 95th percentile", "Shannon entropy", "Signal-to-noise ratio",
    "Contrast-to-noise ratio", "Voxel count", "Mean radiation dose", "Maximum radiation dose", "Segmentation mask",
    # Units
    "millimeter", "cubic millimeter", "cubic centimeter", "Hounsfield unit", "standardized uptake value",
    "Gray", "ratio", "percent", "count",
    # Feature types
    "EHR", "Registry", "Derived value", "AI algorithm output"
  ),
  domain_id = c(
    rep("Procedure", 11L),
    rep("Spec Anatomic Site", 13L),
    rep("Measurement", 15L),
    rep("Unit", 9L),
    rep("Type Concept", 4L)
  ),
  vocabulary_id = c(
    rep("SNOMED", 11L),
    rep("SNOMED", 13L),
    c("LOINC", "LOINC", "LOINC", "LOINC", "LOINC", "LOINC", "RadLex", "RadLex", "RadLex", "RadLex", "RadLex", "OMOP", "LOINC", "LOINC", "SNOMED"),
    rep("UCUM", 9L),
    rep("Type Concept", 4L)
  ),
  concept_class_id = c(
    rep("Procedure", 11L),
    rep("Body Structure", 13L),
    rep("Clinical Observation", 15L),
    rep("Unit", 9L),
    rep("Type Concept", 4L)
  ),
  concept_code = c(
    "77477000", "113091000", "82918005", "363680008", "71651007",
    "16310003", "77343006", "241439007", "168537006", "44491008", "363679005",
    "69536005", "12738006", "45048000", "51185008", "39607008",
    "80891009", "76752008", "818983003", "10200004", "64033007",
    "12921003", "421060004", "66019005",
    "21889-1", "93041-2", "93042-0", "93043-8", "33728-7",
    "8277-6", "RID49851", "RID49852", "RID49853", "RID49854",
    "RID49855", "OMOP-VOX", "73569-6", "73570-4", "129265001",
    "mm", "mm3", "cm3", "[hnsf'U]", "{SUVbw}",
    "Gy", "{ratio}", "%", "{count}",
    "OMOP4976890", "OMOP4976952", "OMOP4976929", "OMOP4976915"
  ),
  dicom_code = c(
    "CT", "MR", "PT", "DX", "MG", "US", "XA", "NM", "CR", "RF", "OT",
    "HEAD", "BRAIN", "NECK", "CHEST", "LUNG", "HEART", "BREAST", "ABDOMEN", "LIVER", "KIDNEY", "PELVIS", "SPINE", "EXTREMITY",
    "volume", "mean_hu", "max_suvbw", "mean_suvbw", "diameter",
    "surface_area", "dice", "hd95", "entropy", "snr",
    "cnr", "voxel_count", "gy_mean", "gy_max", "segmentation",
    "mm", "mm3", "cm3", "HU", "SUVbw", "Gy", "ratio", "percent", "count",
    "ehr", "registry", "derived", "ai_output"
  ),
  category = c(
    rep("modality", 11L),
    rep("anatomic_site", 13L),
    rep("feature", 15L),
    rep("unit", 9L),
    rep("feature_type", 4L)
  )
)

dir.create("data", showWarnings = FALSE, recursive = TRUE)
save(omop_imaging_concepts, file = "data/omop_imaging_concepts.rda", compress = "bzip2")
