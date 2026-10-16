# Prompt builders and privacy-preserving metadata serializer for dicomtk LLM tasks

prepare_llm_metadata_context <- function(path, anonymize = TRUE) {
  hdr <- read_dicom(path)
  if (isTRUE(anonymize)) {
    rem_env <- new.env(parent = emptyenv())
    utils::data("removal_tags", package = "dicomtk", envir = rem_env)
    phi_tags <- toupper(rem_env$removal_tags$tag)
    hdr <- hdr[!toupper(hdr$tag) %in% phi_tags & (as.hexmode(hdr$group) %% 2L == 0L), , drop = FALSE]
  }
  hdr <- hdr[hdr$depth == 0L & nzchar(hdr$value) & hdr$keyword != "PixelData", , drop = FALSE]
  lines <- sprintf("%s %s (%s): %s", hdr$tag, hdr$keyword, hdr$vr, hdr$value)
  paste(lines, collapse = "\n")
}

compute_pixel_summary_stats <- function(path, frame = 1L) {
  tryCatch({
    px <- read_dicom_pixels(path, frame = frame, rescale = TRUE)
    qs <- stats::quantile(px, probs = c(0.05, 0.25, 0.5, 0.75, 0.95), na.rm = TRUE)
    list(
      dims = dim(px),
      min = round(min(px, na.rm = TRUE), 2),
      max = round(max(px, na.rm = TRUE), 2),
      mean = round(mean(px, na.rm = TRUE), 2),
      sd = round(stats::sd(as.double(px), na.rm = TRUE), 2),
      q05 = round(qs[[1L]], 2),
      median = round(qs[[3L]], 2),
      q95 = round(qs[[5L]], 2),
      modality = attr(px, "modality"),
      photometric = attr(px, "photometric"),
      window_center = attr(px, "window_center"),
      window_width = attr(px, "window_width")
    )
  }, error = function(e) NULL)
}

llm_explain_tag_query <- function(query, matches_tbl, llm) {
  sys_prompt <- paste(
    "You are a DICOM standard (PS3.6) expert.",
    "Given a user query and candidate tags from the DCMTK 3.7.1 dictionary,",
    "identify the most relevant DICOM tag(s), their VR, and how they are used clinically."
  )
  cand_txt <- if (nrow(matches_tbl) > 0L) {
    paste(
      sprintf("%s %s (VR=%s): %s",
              utils::head(matches_tbl$tag, 15L),
              utils::head(matches_tbl$keyword, 15L),
              utils::head(matches_tbl$vr, 15L),
              utils::head(matches_tbl$name, 15L)),
      collapse = "\n"
    )
  } else {
    "No direct substring matches found."
  }
  usr_prompt <- sprintf("User Query: %s\n\nCandidate DICOM Dictionary Entries:\n%s", query, cand_txt)
  ans <- llm_chat_completion(llm, sys_prompt, usr_prompt)
  if (is.null(ans)) {
    if (nrow(matches_tbl) > 0L) {
      top <- matches_tbl[1L, ]
      ans <- sprintf("Top matching DICOM tag for '%s' is %s (%s, VR=%s: %s).",
                     query, top$tag, top$keyword, top$vr, top$name)
    } else {
      ans <- sprintf("No standard DICOM tag matched '%s'.", query)
    }
  }
  ans
}
