#' Retrieve DICOM Tags from a File or the Standard Dictionary
#'
#' If `path` is provided, reads and returns the DICOM header tags present in
#' `path` as a tidy tibble. If `path` is `NULL`, returns the complete built-in
#' OFFIS DCMTK 3.7.1 DICOM data dictionary (5,354 tags).
#'
#' @param path Optional file or directory path to read DICOM tags from. If `NULL`
#'   (default), returns the standard DICOM data dictionary.
#' @param ... Additional arguments passed to [read_dicom()] when `path` is not
#'   `NULL`.
#'
#' @return A [tibble::tibble] of DICOM tags.
#' @export
#' @examples
#' # View standard DICOM dictionary
#' dicom_tags()
#'
#' # Read tags from a DICOM file
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' dicom_tags(dcm_file)
dicom_tags <- function(path = NULL, ...) {
  if (is.null(path)) {
    return(tibble::as_tibble(cpp_dict_lookup("")))
  }
  read_dicom(path = path, ...)
}

#' Quickly Extract Specific Tag Values from a DICOM File
#'
#' Retrieves one or more tag values by tag code (e.g., `"(0010,0010)"`) or
#' standard keyword (e.g., `"PatientName"`, `"Modality"`, `"Rows"`).
#'
#' @param path Path to a single DICOM file.
#' @param tags Character vector of tag IDs (`"(GGGG,EEEE)"`) or DICOM keywords.
#'
#' @return A named character vector of tag values (`NA_character_` if absent).
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' dicom_tag_value(dcm_file, c("Modality", "Rows", "Columns", "(0008,0070)"))
dicom_tag_value <- function(path, tags) {
  if (length(path) != 1L || !file.exists(path)) {
    rlang::abort("`path` must be a single existing DICOM file path.")
  }
  cpp_get_tag_values(normalizePath(path, mustWork = TRUE), as.character(tags))
}

#' Modify, Insert, or Delete DICOM Header Tags
#'
#' Updates, inserts, or deletes specified tags in a DICOM file using the native
#' C++ engine and writes the modified dataset to `out_path`.
#'
#' @param path Input DICOM file path.
#' @param tags Named list or named character vector of tags (by `"(GGGG,EEEE)"`
#'   or keyword such as `"PatientName"`) and their new string values.
#' @param out_path Output DICOM file path. Defaults to modifying `path` in-place.
#' @param delete_tags Character vector of tags or keywords to remove.
#' @param erase_private Logical. Remove all odd-group private tags. Default is
#'   `FALSE`.
#' @param regenerate_uids Logical. Generate fresh `SOPInstanceUID`,
#'   `StudyInstanceUID`, and `SeriesInstanceUID`. Default is `FALSE`.
#'
#' @return Invisibly returns `out_path`.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' tmp <- tempfile(fileext = ".dcm")
#' dicom_modify(dcm_file, tags = list(PatientName = "ANON^PATIENT"), out_path = tmp)
#' dicom_tag_value(tmp, "PatientName")
dicom_modify <- function(path,
                         tags = list(),
                         out_path = path,
                         delete_tags = character(),
                         erase_private = FALSE,
                         regenerate_uids = FALSE) {
  if (length(path) != 1L || !file.exists(path)) {
    rlang::abort("`path` must be a single existing DICOM file path.")
  }
  mod_tags <- character(0)
  mod_vals <- character(0)
  if (length(tags) > 0) {
    if (is.null(names(tags)) || any(!nzchar(names(tags)))) {
      rlang::abort("`tags` must be a named list or named character vector.")
    }
    mod_tags <- names(tags)
    mod_vals <- vapply(tags, as.character, character(1))
  }

  ok <- cpp_modify_dicom(
    in_path = normalizePath(path, mustWork = TRUE),
    out_path = out_path,
    mod_tags = mod_tags,
    mod_values = mod_vals,
    del_tags = as.character(delete_tags),
    erase_private = isTRUE(erase_private),
    regenerate_uids = isTRUE(regenerate_uids)
  )
  if (!isTRUE(ok)) {
    rlang::abort(paste0("Failed modifying DICOM file: ", path))
  }
  invisible(normalizePath(out_path, mustWork = FALSE))
}

#' Search or Query the DICOM Data Dictionary
#'
#' Searches the 5,354-entry DCMTK 3.7.1 DICOM data dictionary by substring or
#' tag `(GGGG,EEEE)`. When an `llm` object (created by [dicom_llm()]) is
#' supplied, natural-language questions (e.g., `"What tag stores tube current?"`)
#' are also answered using the configured LLM.
#'
#' @param query Search string, tag `"(GGGG,EEEE)"`, keyword, or natural-language
#'   question.
#' @param llm Optional `"dicom_llm"` configuration object from [dicom_llm()] for
#'   natural-language tag interpretation.
#'
#' @return A [tibble::tibble] of matching DICOM dictionary entries (with an
#'   optional `"llm_explanation"` attribute if `llm` is provided).
#' @export
#' @examples
#' dicom_tag_lookup("WindowCenter")
#' dicom_tag_lookup("(0028,1050)")
#' dicom_tag_lookup("Patient")
dicom_tag_lookup <- function(query, llm = NULL) {
  if (missing(query) || !is.character(query) || length(query) != 1L) {
    rlang::abort("`query` must be a single character string.")
  }

  res <- tibble::as_tibble(cpp_dict_lookup(query))

  # If query has multiple words and no exact substring match, try token matching
  if (nrow(res) == 0L && grepl("\\s+", trimws(query))) {
    stop_words <- c("what", "which", "where", "tag", "tags", "stores", "store",
                    "is", "the", "for", "in", "dicom", "of", "a", "an", "to", "how")
    tokens <- tolower(unlist(strsplit(gsub("[^[:alnum:] ]", " ", query), "\\s+")))
    tokens <- setdiff(tokens[nzchar(tokens)], stop_words)
    if (length(tokens) > 0) {
      all_dict <- tibble::as_tibble(cpp_dict_lookup(""))
      scores <- rep(0L, nrow(all_dict))
      haystack <- tolower(paste(all_dict$keyword, all_dict$name))
      for (tok in tokens) {
        scores <- scores + as.integer(grepl(tok, haystack, fixed = TRUE))
      }
      keep <- which(scores > 0L)
      if (length(keep) > 0L) {
        ord <- keep[order(scores[keep], decreasing = TRUE)]
        res <- all_dict[utils::head(ord, 25L), , drop = FALSE]
      }
    }
  }

  if (!is.null(llm)) {
    explanation <- llm_explain_tag_query(query, res, llm)
    attr(res, "llm_explanation") <- explanation
  }

  res
}
