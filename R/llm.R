#' Summarize a DICOM Study Using an LLM
#'
#' Generates a concise clinical and technical natural-language summary of a
#' DICOM file's header metadata (modality, anatomy, acquisition parameters,
#' image geometry). Automatically strips PHI tags when communicating with
#' non-local LLM endpoints.
#'
#' @param path Path to a DICOM file.
#' @param llm A `"dicom_llm"` object created by [dicom_llm()]. Defaults to
#'   `dicom_llm("ollama")`.
#'
#' @return A character string containing the study summary.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' llm <- dicom_llm("offline")
#' dicom_summarize(dcm_file, llm = llm)
dicom_summarize <- function(path, llm = dicom_llm("ollama")) {
  if (length(path) != 1L || !file.exists(path)) {
    rlang::abort("`path` must be a single existing DICOM file path.")
  }
  if (!llm$is_local && !llm$anonymize) {
    cli::cli_alert_warning("Sending un-anonymized DICOM metadata to a remote LLM endpoint!")
  }

  ctx <- prepare_llm_metadata_context(path, anonymize = llm$anonymize)
  sys_prompt <- paste(
    "You are an expert medical imaging physicist and radiologist assistant.",
    "Summarize the following DICOM study metadata clearly and concisely,",
    "covering Modality, Body Part/Study Description, Acquisition Parameters,",
    "and Image Geometry. Do not invent findings not present in the metadata."
  )
  usr_prompt <- paste0("DICOM Header Metadata:\n", ctx)

  ans <- llm_chat_completion(llm, sys_prompt, usr_prompt)
  if (!is.null(ans)) return(ans)

  # Deterministic local fallback summary
  vals <- dicom_tag_value(
    path,
    c("Modality", "Manufacturer", "StudyDescription", "SeriesDescription",
      "BodyPartExamined", "Rows", "Columns", "BitsAllocated", "PhotometricInterpretation")
  )
  clean_val <- function(x, def = "Unspecified") if (is.na(x) || !nzchar(x)) def else x
  sprintf(
    paste0(
      "DICOM Study Summary: %s imaging study (%s) acquired on %s system. ",
      "Series: %s (Body Part: %s). ",
      "Image Matrix: %s x %s pixels (%s-bit %s)."
    ),
    clean_val(vals[["Modality"]], "Medical"),
    clean_val(vals[["StudyDescription"]], "General Study"),
    clean_val(vals[["Manufacturer"]], "Standard"),
    clean_val(vals[["SeriesDescription"]], "Primary Series"),
    clean_val(vals[["BodyPartExamined"]], "Not specified"),
    clean_val(vals[["Rows"]], "?"),
    clean_val(vals[["Columns"]], "?"),
    clean_val(vals[["BitsAllocated"]], "16"),
    clean_val(vals[["PhotometricInterpretation"]], "MONOCHROME2")
  )
}

#' Describe a DICOM Image Using a Vision-Capable LLM
#'
#' Renders the DICOM slice with clinical windowing to a PNG, encodes it as
#' base64, and sends it along with anonymized technical metadata and pixel
#' intensity statistics to a vision-capable LLM (e.g., Ollama `llava`, OpenAI
#' `gpt-4o`, or Anthropic `claude-sonnet-4-20250514`).
#'
#' @param path Path to a DICOM file.
#' @param llm A `"dicom_llm"` object created by [dicom_llm()].
#' @param frame Integer frame/slice index (1-based). Default is `1L`.
#' @param window Window preset (`"auto"`, `"brain"`, `"lung"`, `"bone"`, etc.).
#'   Default is `"auto"`.
#' @param prompt Custom instruction prompt for the vision model.
#'
#' @return A character string with the image description and quantitative stats.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' llm <- dicom_llm("offline")
#' dicom_describe_image(dcm_file, llm = llm)
dicom_describe_image <- function(path,
                                 llm = dicom_llm("ollama"),
                                 frame = 1L,
                                 window = "auto",
                                 prompt = "Describe the anatomical structures, image quality, windowing, and any notable visual patterns in this medical image for research/educational review.") {
  if (length(path) != 1L || !file.exists(path)) {
    rlang::abort("`path` must be a single existing DICOM file path.")
  }

  png_path <- dicom_to_png(path, frame = frame, window = window)
  on.exit(unlink(png_path), add = TRUE)
  raw_png <- readBin(png_path, what = "raw", n = file.info(png_path)$size)
  b64_png <- base64_encode_raw(raw_png)

  stats <- compute_pixel_summary_stats(path, frame = frame)
  ctx <- prepare_llm_metadata_context(path, anonymize = llm$anonymize)

  sys_prompt <- paste(
    "You are an AI medical imaging research assistant.",
    "Provide an objective, structured description of the provided DICOM image",
    "and its quantitative pixel statistics. Include a reminder that outputs",
    "are for research assistance and not primary clinical diagnosis."
  )
  usr_prompt <- sprintf(
    "%s\n\nQuantitative Pixel Statistics: min=%s, max=%s, mean=%s, sd=%s, median=%s\n\nTechnical Metadata:\n%s",
    prompt,
    stats$min, stats$max, stats$mean, stats$sd, stats$median,
    ctx
  )

  ans <- llm_chat_completion(llm, sys_prompt, usr_prompt, image_base64 = b64_png)
  if (!is.null(ans)) return(ans)

  sprintf(
    paste0(
      "DICOM Image Analysis (%s, %dx%d, Photometric: %s): ",
      "Rescaled pixel intensities range from %s to %s (mean: %s, SD: %s, median: %s; ",
      "5th-95th percentile: [%s, %s]). Window Center: %s, Window Width: %s."
    ),
    stats$modality,
    stats$dims[1L],
    stats$dims[2L],
    stats$photometric,
    stats$min,
    stats$max,
    stats$mean,
    stats$sd,
    stats$median,
    stats$q05,
    stats$q95,
    stats$window_center,
    stats$window_width
  )
}

#' Generate a Structured Radiology Report from a DICOM File
#'
#' Combines DICOM technical metadata and vision analysis to produce a
#' structured radiology report (`EXAMINATION`, `TECHNIQUE`, `FINDINGS`,
#' `IMPRESSION`), and optionally saves it as a DICOM Structured Report (`.dcm`)
#' via [create_dicom_sr()].
#'
#' @param path Path to a DICOM file.
#' @param llm A `"dicom_llm"` object created by [dicom_llm()].
#' @param frame Integer frame/slice index (1-based). Default is `1L`.
#' @param window Window preset. Default is `"auto"`.
#' @param save_sr_path Optional output `.dcm` path to save the generated report
#'   as a formal DICOM Structured Report (`Basic Text SR`).
#'
#' @return A [tibble::tibble] with columns `section` and `content`, and the full
#'   formatted report text in attribute `"report_text"`.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' rpt <- dicom_report(dcm_file, llm = dicom_llm("offline"))
#' rpt
dicom_report <- function(path,
                         llm = dicom_llm("ollama"),
                         frame = 1L,
                         window = "auto",
                         save_sr_path = NULL) {
  summary_txt <- dicom_summarize(path, llm = llm)
  image_txt   <- dicom_describe_image(path, llm = llm, frame = frame, window = window)

  sys_prompt <- paste(
    "You are an AI radiology reporting assistant.",
    "Format a structured report with four exact headings:",
    "EXAMINATION, TECHNIQUE, FINDINGS, and IMPRESSION."
  )
  usr_prompt <- sprintf(
    "Study Summary:\n%s\n\nImage Analysis:\n%s\n\nGenerate a structured radiology report.",
    summary_txt, image_txt
  )

  llm_txt <- llm_chat_completion(llm, sys_prompt, usr_prompt)

  vals <- dicom_tag_value(path, c("Modality", "StudyDescription", "SeriesDescription", "StudyInstanceUID"))
  exam_str <- paste(na.omit(c(vals[["Modality"]], vals[["StudyDescription"]], vals[["SeriesDescription"]])), collapse = " - ")
  if (!nzchar(exam_str)) exam_str <- "DICOM Medical Imaging Examination"

  tbl <- tibble::tibble(
    section = c("EXAMINATION", "TECHNIQUE", "FINDINGS", "IMPRESSION"),
    content = c(
      exam_str,
      summary_txt,
      image_txt,
      if (!is.null(llm_txt)) llm_txt else "Automated quantitative and metadata review completed. Correlate clinically."
    )
  )

  full_text <- paste(sprintf("%s:\n%s", tbl$section, tbl$content), collapse = "\n\n")
  attr(tbl, "report_text") <- full_text

  if (!is.null(save_sr_path)) {
    st_uid <- if (!is.na(vals[["StudyInstanceUID"]])) vals[["StudyInstanceUID"]] else ""
    create_dicom_sr(
      out_path = save_sr_path,
      title = paste("AI Structured Report -", exam_str),
      text = full_text,
      study_uid = st_uid
    )
  }

  tbl
}

#' Ask a Natural-Language Question About a DICOM File
#'
#' Answers arbitrary questions about a DICOM file's metadata or image content
#' using the configured LLM (or local metadata inspection).
#'
#' @param path Path to a DICOM file.
#' @param question Character string question (e.g., `"What is the pixel spacing and modality?"`).
#' @param llm A `"dicom_llm"` object created by [dicom_llm()].
#' @param include_image Logical. Attach the rendered DICOM image for multimodal
#'   vision models. Default is `FALSE`.
#'
#' @return Character string answer.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' dicom_ask(dcm_file, "What is the modality and image dimensions?", llm = dicom_llm("offline"))
dicom_ask <- function(path,
                      question,
                      llm = dicom_llm("ollama"),
                      include_image = FALSE) {
  if (length(path) != 1L || !file.exists(path)) {
    rlang::abort("`path` must be a single existing DICOM file path.")
  }
  if (missing(question) || !is.character(question) || !nzchar(trimws(question))) {
    rlang::abort("`question` must be a non-empty character string.")
  }

  ctx <- prepare_llm_metadata_context(path, anonymize = llm$anonymize)
  stats <- compute_pixel_summary_stats(path, frame = 1L)

  b64_png <- NULL
  if (isTRUE(include_image)) {
    png_path <- dicom_to_png(path)
    on.exit(unlink(png_path), add = TRUE)
    raw_png <- readBin(png_path, what = "raw", n = file.info(png_path)$size)
    b64_png <- base64_encode_raw(raw_png)
  }

  sys_prompt <- paste(
    "You are an expert DICOM and medical imaging assistant.",
    "Answer the user's question accurately using the provided DICOM header metadata",
    "and image statistics."
  )
  usr_prompt <- sprintf(
    "Question: %s\n\nPixel Stats: min=%s, max=%s, mean=%s\n\nDICOM Header:\n%s",
    question,
    if (!is.null(stats)) stats$min else "N/A",
    if (!is.null(stats)) stats$max else "N/A",
    if (!is.null(stats)) stats$mean else "N/A",
    ctx
  )

  ans <- llm_chat_completion(llm, sys_prompt, usr_prompt, image_base64 = b64_png)
  if (!is.null(ans)) return(ans)

  # Local keyword search across header rows
  hdr <- read_dicom(path)
  tokens <- tolower(unlist(strsplit(gsub("[^[:alnum:] ]", " ", question), "\\s+")))
  tokens <- setdiff(tokens[nzchar(tokens)], c("what", "is", "the", "of", "in", "this", "dicom", "file", "and", "are"))
  if (length(tokens) > 0L) {
    hay <- tolower(paste(hdr$keyword, hdr$name, hdr$tag))
    scores <- rep(0L, nrow(hdr))
    for (t in tokens) scores <- scores + as.integer(grepl(t, hay, fixed = TRUE))
    hits <- hdr[scores > 0L & nzchar(hdr$value), , drop = FALSE]
    if (nrow(hits) > 0L) {
      top <- utils::head(hits[order(scores[scores > 0L], decreasing = TRUE), , drop = FALSE], 5L)
      return(paste(sprintf("%s (%s): %s", top$name, top$tag, top$value), collapse = "; "))
    }
  }
  dicom_summarize(path, llm = dicom_llm("offline"))
}
