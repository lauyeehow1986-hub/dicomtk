# Internal: apply Bearer / Basic / OAuth2 client-credentials auth to httr2 request
.dw_apply_auth <- function(req, conn) {
  if (length(conn$headers) > 0L) {
    req <- do.call(httr2::req_headers, c(list(.req = req), as.list(conn$headers)))
  }
  auth <- conn$auth %||% list(type = "none")
  atype <- tolower(as.character(auth$type %||% "none"))

  if (identical(atype, "bearer") && !is.null(auth$token) && nzchar(auth$token)) {
    req <- httr2::req_auth_bearer_token(req, auth$token)
  } else if (identical(atype, "basic") && !is.null(auth$username)) {
    req <- httr2::req_auth_basic(req, auth$username, auth$password %||% "")
  } else if (identical(atype, "oauth2_client_credentials") &&
             !is.null(auth$token_url) && !is.null(auth$client_id)) {
    client <- httr2::oauth_client(
      id = auth$client_id,
      token_url = auth$token_url,
      secret = auth$client_secret %||% NULL
    )
    req <- httr2::req_oauth_client_credentials(
      req,
      client = client,
      scope = auth$scope %||% NULL
    )
  }
  req
}

# Internal: normalize "(0010,0010)" -> "00100010" and back
.dw_tag_to_hex8 <- function(tag) {
  toupper(gsub("[^0-9A-Fa-f]", "", as.character(tag)))
}

.dw_hex8_to_tag <- function(hex8) {
  h <- toupper(gsub("[^0-9A-Fa-f]", "", as.character(hex8)))
  sprintf("(%s,%s)", substr(h, 1L, 4L), substr(h, 5L, 8L))
}

#' Convert DICOM Header Tibble to PS3.18 DICOM JSON Model
#'
#' Serializes a tidy header tibble from [read_dicom_header()] into a DICOM
#' PS3.18 JSON Model list (`{"gggggggg": {"vr": ..., "Value": [...]}}`).
#'
#' @param hdr A data frame returned by [read_dicom_header()].
#' @return A named list conforming to the DICOM PS3.18 JSON Model.
#' @examples
#' dcm <- system.file("extdata", "example.dcm", package = "dicomtk")
#' if (nzchar(dcm)) {
#'   dj <- as_dicom_json(read_dicom_header(dcm))
#'   names(dj)[1:3]
#' }
#' @export
as_dicom_json <- function(hdr) {
  if (!is.data.frame(hdr) || !all(c("tag", "vr", "value") %in% names(hdr))) {
    cli::cli_abort("{.arg hdr} must be a data.frame with {.field tag}, {.field vr}, and {.field value} columns.")
  }

  num_vrs <- c("DS", "IS", "FL", "FD", "SL", "SS", "UL", "US", "AT")
  out <- list()

  for (i in seq_len(nrow(hdr))) {
    hex8 <- .dw_tag_to_hex8(hdr$tag[i])
    if (nchar(hex8) != 8L || endsWith(hex8, "0000")) next
    vr <- toupper(trimws(as.character(hdr$vr[i] %||% "LO")))
    if (!nzchar(vr) || is.na(vr)) vr <- "LO"
    val <- hdr$value[i]

    if (is.na(val) || !nzchar(as.character(val))) {
      out[[hex8]] <- list(vr = vr)
      next
    }

    sval <- as.character(val)
    if (identical(vr, "PN")) {
      out[[hex8]] <- list(vr = vr, Value = list(list(Alphabetic = sval)))
    } else if (vr %in% num_vrs) {
      parts <- strsplit(sval, "\\\\", fixed = FALSE)[[1L]]
      nums <- suppressWarnings(as.numeric(parts))
      if (all(is.finite(nums))) {
        out[[hex8]] <- list(vr = vr, Value = as.list(nums))
      } else {
        out[[hex8]] <- list(vr = vr, Value = as.list(parts))
      }
    } else {
      parts <- strsplit(sval, "\\\\", fixed = FALSE)[[1L]]
      out[[hex8]] <- list(vr = vr, Value = as.list(parts))
    }
  }
  out
}

#' Convert PS3.18 DICOM JSON Model to a Tidy Header Tibble
#'
#' @param dj A named list (one DICOM JSON dataset) from [as_dicom_json()] or
#'   a QIDO-RS/WADO-RS metadata response.
#' @return A [tibble::tibble] with columns `tag`, `vr`, and `value`.
#' @examples
#' dj <- list("00080060" = list(vr = "CS", Value = list("CT")))
#' from_dicom_json(dj)
#' @export
from_dicom_json <- function(dj) {
  if (!is.list(dj) || length(dj) == 0L) {
    return(tibble::tibble(tag = character(0), vr = character(0), value = character(0)))
  }
  keys <- names(dj)
  rows <- lapply(keys, function(k) {
    entry <- dj[[k]]
    vr <- as.character(entry$vr %||% "LO")
    vals <- entry$Value
    val_str <- if (is.null(vals) || length(vals) == 0L) {
      NA_character_
    } else if (identical(vr, "PN") && is.list(vals[[1L]])) {
      as.character(vals[[1L]]$Alphabetic %||% paste(unlist(vals[[1L]]), collapse = " "))
    } else {
      paste(vapply(vals, as.character, character(1L)), collapse = "\\")
    }
    tibble::tibble(
      tag = .dw_hex8_to_tag(k),
      vr = vr,
      value = val_str
    )
  })
  do.call(rbind, rows)
}

#' Pack DICOM Files Into an RFC 2387 `multipart/related` Binary Payload
#'
#' @param files Character vector of `.dcm` file paths.
#' @param boundary Multipart boundary string.
#' @return A list with `body` (raw vector), `content_type`, and `boundary`.
#' @examples
#' dcm <- system.file("extdata", "example.dcm", package = "dicomtk")
#' if (nzchar(dcm)) {
#'   mp <- pack_multipart_dicom(dcm)
#'   length(mp$body)
#' }
#' @export
pack_multipart_dicom <- function(files, boundary = paste0("dicomtk_", as.integer(Sys.time()))) {
  files <- resolve_dicom_paths(files)
  parts <- list()
  for (f in files) {
    sz <- file.info(f)$size
    raw_dcm <- readBin(f, what = "raw", n = sz)
    hdr_txt <- paste0(
      "--", boundary, "\r\n",
      "Content-Type: application/dicom\r\n\r\n"
    )
    parts[[length(parts) + 1L]] <- charToRaw(hdr_txt)
    parts[[length(parts) + 1L]] <- raw_dcm
    parts[[length(parts) + 1L]] <- charToRaw("\r\n")
  }
  parts[[length(parts) + 1L]] <- charToRaw(paste0("--", boundary, "--\r\n"))

  list(
    body = unlist(parts, use.names = FALSE),
    content_type = sprintf('multipart/related; type="application/dicom"; boundary="%s"', boundary),
    boundary = boundary
  )
}

#' Unpack an RFC 2387 `multipart/related` DICOM Payload to Disk
#'
#' @param raw_bytes Raw vector containing a `multipart/related` HTTP body.
#' @param boundary Multipart boundary string (without leading `--`).
#' @param out_dir Output directory for extracted `.dcm` files.
#' @return Character vector of extracted file paths.
#' @examples
#' dcm <- system.file("extdata", "example.dcm", package = "dicomtk")
#' if (nzchar(dcm)) {
#'   mp <- pack_multipart_dicom(dcm, boundary = "B1")
#'   out <- tempfile("unpack_")
#'   on.exit(unlink(out, recursive = TRUE), add = TRUE)
#'   unpack_multipart_dicom(mp$body, boundary = "B1", out_dir = out)
#' }
#' @export
unpack_multipart_dicom <- function(raw_bytes, boundary, out_dir = tempfile("dw_wado_")) {
  if (!is.raw(raw_bytes)) {
    cli::cli_abort("{.arg raw_bytes} must be a raw vector.")
  }
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  b_pat <- charToRaw(paste0("--", boundary))
  b_pos <- grepRaw(b_pat, raw_bytes, all = TRUE, fixed = TRUE)
  if (length(b_pos) < 2L) {
    return(character(0))
  }

  sep_crlf <- charToRaw("\r\n\r\n")
  sep_lf <- charToRaw("\n\n")
  out_files <- character(0)

  for (i in seq_len(length(b_pos) - 1L)) {
    part_start <- b_pos[i] + length(b_pat)
    part_end <- b_pos[i + 1L] - 1L
    if (part_end <= part_start) next
    chunk <- raw_bytes[part_start:part_end]

    # Check if closing boundary "--"
    if (length(chunk) >= 2L && identical(chunk[1:2], charToRaw("--"))) next

    h_end <- grepRaw(sep_crlf, chunk, fixed = TRUE)
    sep_len <- 4L
    if (length(h_end) == 0L) {
      h_end <- grepRaw(sep_lf, chunk, fixed = TRUE)
      sep_len <- 2L
    }
    if (length(h_end) == 0L) next

    body_start <- h_end[1L] + sep_len
    body_end <- length(chunk)
    # Strip trailing \r\n or \n before next boundary
    if (body_end >= body_start + 1L && identical(chunk[(body_end - 1L):body_end], charToRaw("\r\n"))) {
      body_end <- body_end - 2L
    } else if (body_end >= body_start && identical(chunk[body_end], charToRaw("\n"))) {
      body_end <- body_end - 1L
    }
    if (body_end < body_start) next

    payload <- chunk[body_start:body_end]
    out_path <- file.path(out_dir, sprintf("instance_%04d.dcm", length(out_files) + 1L))
    writeBin(payload, out_path)
    out_files <- c(out_files, out_path)
  }
  out_files
}

#' Query a DICOMweb Endpoint Using QIDO-RS
#'
#' @param conn A `"dicom_connection"` object with `dicomweb_url` (or `local_dir`).
#' @param level Query resource level: `"studies"`, `"series"`, or `"instances"`.
#' @param study_uid Optional `StudyInstanceUID` when querying `"series"` or `"instances"`.
#' @param series_uid Optional `SeriesInstanceUID` when querying `"instances"`.
#' @param ... Optional query parameters (e.g., `Modality = "CT"`, `PatientID = "123"`).
#' @return A [tibble::tibble] of matching records.
#' @export
dicomweb_qido <- function(conn,
                          level = c("studies", "series", "instances"),
                          study_uid = NULL,
                          series_uid = NULL,
                          ...) {
  level <- match.arg(level)
  filters <- list(...)

  if (!is.null(conn$local_dir) && dir.exists(conn$local_dir)) {
    df <- read_dicom(conn$local_dir, wide = TRUE)
    if (!is.null(study_uid) && "StudyInstanceUID" %in% names(df)) {
      df <- df[df$StudyInstanceUID == study_uid, , drop = FALSE]
    }
    if (!is.null(series_uid) && "SeriesInstanceUID" %in% names(df)) {
      df <- df[df$SeriesInstanceUID == series_uid, , drop = FALSE]
    }
    for (nm in names(filters)) {
      if (nm %in% names(df)) {
        pat <- utils::glob2rx(as.character(filters[[nm]]))
        df <- df[grepl(pat, df[[nm]], ignore.case = TRUE), , drop = FALSE]
      }
    }
    return(tibble::as_tibble(df))
  }

  if (is.null(conn$dicomweb_url) || !nzchar(conn$dicomweb_url)) {
    cli::cli_abort("{.arg conn} must specify {.field dicomweb_url} or {.field local_dir}.")
  }

  path_parts <- switch(level,
    studies = "studies",
    series = if (!is.null(study_uid)) c("studies", study_uid, "series") else "series",
    instances = if (!is.null(study_uid) && !is.null(series_uid)) {
      c("studies", study_uid, "series", series_uid, "instances")
    } else if (!is.null(study_uid)) {
      c("studies", study_uid, "instances")
    } else {
      "instances"
    }
  )

  req <- httr2::request(conn$dicomweb_url)
  for (p in path_parts) {
    req <- httr2::req_url_path_append(req, p)
  }
  if (length(filters) > 0L) {
    req <- do.call(httr2::req_url_query, c(list(.req = req), filters))
  }
  req <- req |>
    httr2::req_headers(Accept = "application/dicom+json") |>
    .dw_apply_auth(conn) |>
    httr2::req_timeout(max(5, conn$timeout_ms / 1000))

  resp <- httr2::req_perform(req)
  items <- httr2::resp_body_json(resp, simplifyVector = FALSE)
  if (length(items) == 0L) {
    return(tibble::tibble())
  }

  rows <- lapply(items, function(dj) {
    hdr <- from_dicom_json(dj)
    vals <- stats::setNames(as.list(hdr$value), hdr$tag)
    tibble::tibble(
      StudyInstanceUID = as.character(vals[["(0020,000D)"]] %||% NA_character_),
      SeriesInstanceUID = as.character(vals[["(0020,000E)"]] %||% NA_character_),
      SOPInstanceUID = as.character(vals[["(0008,0018)"]] %||% NA_character_),
      Modality = as.character(vals[["(0008,0060)"]] %||% NA_character_),
      PatientID = as.character(vals[["(0010,0020)"]] %||% NA_character_),
      PatientName = as.character(vals[["(0010,0010)"]] %||% NA_character_),
      StudyDate = as.character(vals[["(0008,0020)"]] %||% NA_character_),
      SeriesDescription = as.character(vals[["(0008,103E)"]] %||% NA_character_)
    )
  })
  do.call(rbind, rows)
}

#' Retrieve DICOMweb Study/Series Metadata (WADO-RS Metadata)
#'
#' @param conn A `"dicom_connection"` object.
#' @param study_uid `StudyInstanceUID` string.
#' @param series_uid Optional `SeriesInstanceUID` string.
#' @return A list of PS3.18 DICOM JSON objects (one per instance).
#' @export
dicomweb_metadata <- function(conn, study_uid, series_uid = NULL) {
  if (!is.null(conn$local_dir) && dir.exists(conn$local_dir)) {
    q <- dicomweb_qido(conn, level = "instances", study_uid = study_uid, series_uid = series_uid)
    if (!("file" %in% names(q)) || nrow(q) == 0L) return(list())
    return(lapply(q$file, function(f) as_dicom_json(read_dicom_header(f))))
  }

  if (is.null(conn$dicomweb_url) || !nzchar(conn$dicomweb_url)) {
    cli::cli_abort("{.arg conn} must specify {.field dicomweb_url} or {.field local_dir}.")
  }

  req <- httr2::request(conn$dicomweb_url) |>
    httr2::req_url_path_append("studies", study_uid)
  if (!is.null(series_uid)) {
    req <- httr2::req_url_path_append(req, "series", series_uid)
  }
  req <- req |>
    httr2::req_url_path_append("metadata") |>
    httr2::req_headers(Accept = "application/dicom+json") |>
    .dw_apply_auth(conn)

  resp <- httr2::req_perform(req)
  httr2::resp_body_json(resp, simplifyVector = FALSE)
}

#' Retrieve DICOM Instances via WADO-RS
#'
#' @param conn A `"dicom_connection"` object.
#' @param study_uid `StudyInstanceUID` string.
#' @param series_uid Optional `SeriesInstanceUID` string.
#' @param out_dir Output directory for retrieved `.dcm` files.
#' @return Character vector of retrieved file paths.
#' @export
dicomweb_wado <- function(conn,
                          study_uid,
                          series_uid = NULL,
                          out_dir = tempfile("dw_wado_")) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  if (!is.null(conn$local_dir) && dir.exists(conn$local_dir)) {
    q <- dicomweb_qido(conn, level = "instances", study_uid = study_uid, series_uid = series_uid)
    if (!("file" %in% names(q)) || nrow(q) == 0L) return(character(0))
    mp <- pack_multipart_dicom(q$file, boundary = "DICOMTK_LOCAL_WADO")
    return(unpack_multipart_dicom(mp$body, boundary = "DICOMTK_LOCAL_WADO", out_dir = out_dir))
  }

  if (is.null(conn$dicomweb_url) || !nzchar(conn$dicomweb_url)) {
    cli::cli_abort("{.arg conn} must specify {.field dicomweb_url} or {.field local_dir}.")
  }

  req <- httr2::request(conn$dicomweb_url) |>
    httr2::req_url_path_append("studies", study_uid)
  if (!is.null(series_uid)) {
    req <- httr2::req_url_path_append(req, "series", series_uid)
  }
  req <- req |>
    httr2::req_headers(Accept = 'multipart/related; type="application/dicom"') |>
    .dw_apply_auth(conn)

  resp <- httr2::req_perform(req)
  ctype <- httr2::resp_header(resp, "content-type") %||% ""
  m <- regmatches(ctype, regexec('boundary="?([^";]+)"?', ctype, ignore.case = TRUE))[[1L]]
  boundary <- if (length(m) >= 2L) m[2L] else stop("Missing multipart boundary in WADO-RS response.")
  unpack_multipart_dicom(httr2::resp_body_raw(resp), boundary = boundary, out_dir = out_dir)
}

#' Store DICOM Instances via STOW-RS
#'
#' @param conn A `"dicom_connection"` object.
#' @param files Character vector of `.dcm` file paths to upload.
#' @param study_uid Optional target `StudyInstanceUID` path suffix.
#' @return A [tibble::tibble] summarizing per-file store status.
#' @export
dicomweb_stow <- function(conn, files, study_uid = NULL) {
  files <- resolve_dicom_paths(files)

  if (!is.null(conn$local_dir)) {
    dir.create(conn$local_dir, recursive = TRUE, showWarnings = FALSE)
    dst <- file.path(conn$local_dir, basename(files))
    ok <- file.copy(files, dst, overwrite = TRUE)
    return(tibble::tibble(
      file = files,
      destination = dst,
      success = ok,
      status = ifelse(ok, "STORED_LOCAL_STOW", "FAILED")
    ))
  }

  if (is.null(conn$dicomweb_url) || !nzchar(conn$dicomweb_url)) {
    cli::cli_abort("{.arg conn} must specify {.field dicomweb_url} or {.field local_dir}.")
  }

  mp <- pack_multipart_dicom(files)
  req <- httr2::request(conn$dicomweb_url) |>
    httr2::req_url_path_append("studies")
  if (!is.null(study_uid)) {
    req <- httr2::req_url_path_append(req, study_uid)
  }
  req <- req |>
    httr2::req_headers(
      "Content-Type" = mp$content_type,
      Accept = "application/dicom+json"
    ) |>
    httr2::req_body_raw(mp$body) |>
    .dw_apply_auth(conn)

  resp <- httr2::req_perform(req)
  code <- httr2::resp_status(resp)
  ok <- code >= 200L && code < 300L
  tibble::tibble(
    file = files,
    destination = conn$dicomweb_url,
    success = rep(ok, length(files)),
    status = rep(paste0("HTTP_", code), length(files))
  )
}
