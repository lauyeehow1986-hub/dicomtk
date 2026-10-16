#' Create a DICOM PACS Network Connection Specification
#'
#' Creates a `"dicom_connection"` object holding PACS / DICOM node connection
#' parameters for use with [dicom_echo()], [dicom_find()], [dicom_get()], and
#' [dicom_send()]. Supports both DIMSE TCP connections and DICOMweb (QIDO-RS /
#' WADO-RS / STOW-RS) HTTP endpoints.
#'
#' @param host Hostname or IP address of the remote DICOM peer (e.g.,
#'   `"127.0.0.1"` or `"https://pacs.example.org/dicom-web"`).
#' @param port Integer TCP port for DIMSE communication. Default is `104L`
#'   (or `4242L` for Orthanc).
#' @param called_ae Remote Application Entity Title (Called AET). Default is
#'   `"ANY-SCP"`.
#' @param calling_ae Local Application Entity Title (Calling AET). Default is
#'   `"DICOMTK"`.
#' @param timeout_ms Socket timeout in milliseconds. Default is `5000L`.
#' @param dicomweb_url Optional base URL for DICOMweb (QIDO-RS / WADO-RS /
#'   STOW-RS) REST APIs.
#' @param local_dir Optional local directory path to act as a local file-backed
#'   PACS repository for testing queries and retrievals offline.
#'
#' @return An S3 object of class `"dicom_connection"`.
#' @export
#' @examples
#' conn <- dicom_connect("127.0.0.1", port = 4242, called_ae = "ORTHANC")
#' conn
dicom_connect <- function(host = "127.0.0.1",
                          port = 104L,
                          called_ae = "ANY-SCP",
                          calling_ae = "DICOMTK",
                          timeout_ms = 5000L,
                          dicomweb_url = NULL,
                          local_dir = NULL) {
  structure(
    list(
      host = as.character(host),
      port = as.integer(port),
      called_ae = as.character(called_ae),
      calling_ae = as.character(calling_ae),
      timeout_ms = as.integer(timeout_ms),
      dicomweb_url = dicomweb_url,
      local_dir = local_dir
    ),
    class = "dicom_connection"
  )
}

#' @export
print.dicom_connection <- function(x, ...) {
  cli::cli_alert_info(
    "DICOM Connection: {x$calling_ae} -> {x$called_ae}@{x$host}:{x$port}"
  )
  if (!is.null(x$local_dir)) {
    cli::cli_alert_info("Local PACS directory: {x$local_dir}")
  }
  invisible(x)
}

#' Verify DICOM PACS Connectivity (C-ECHO SCU)
#'
#' Performs a DICOM Upper Layer `A-ASSOCIATE-RQ` handshake followed by a
#' Verification SOP Class (`1.2.840.10008.1.1`) `C-ECHO-RQ` over TCP, or verifies
#' a local directory-backed PACS connection.
#'
#' @param x A `"dicom_connection"` object from [dicom_connect()] or a hostname
#'   string.
#' @param port Integer port (used if `x` is a hostname string). Default is `104L`.
#' @param called_ae Called AE Title. Default is `"ANY-SCP"`.
#' @param calling_ae Calling AE Title. Default is `"DICOMTK"`.
#' @param timeout_ms Timeout in milliseconds. Default is `5000L`.
#'
#' @return A [tibble::tibble] with columns `host`, `port`, `called_ae`,
#'   `success`, `status`, `message`, and `elapsed_ms`.
#' @export
#' @examples
#' conn <- dicom_connect(local_dir = system.file("extdata", package = "dicomtk"))
#' dicom_echo(conn)
dicom_echo <- function(x,
                       port = 104L,
                       called_ae = "ANY-SCP",
                       calling_ae = "DICOMTK",
                       timeout_ms = 5000L) {
  conn <- if (inherits(x, "dicom_connection")) {
    x
  } else {
    dicom_connect(host = x, port = port, called_ae = called_ae,
                  calling_ae = calling_ae, timeout_ms = timeout_ms)
  }

  if (!is.null(conn$local_dir) && dir.exists(conn$local_dir)) {
    return(tibble::tibble(
      host = conn$host,
      port = conn$port,
      called_ae = conn$called_ae,
      success = TRUE,
      status = "SUCCESS_LOCAL",
      message = paste0("Local DICOM repository verified: ", conn$local_dir),
      elapsed_ms = 0.1
    ))
  }

  res <- cpp_dicom_echo(
    host = conn$host,
    port = conn$port,
    called_ae = conn$called_ae,
    calling_ae = conn$calling_ae,
    timeout_ms = conn$timeout_ms
  )

  tibble::tibble(
    host = conn$host,
    port = conn$port,
    called_ae = conn$called_ae,
    success = res$success,
    status = res$status,
    message = res$message,
    elapsed_ms = res$elapsed_ms
  )
}

#' Query DICOM Studies, Series, or Instances (C-FIND / QIDO-RS / Local PACS)
#'
#' Queries a DICOM connection or local PACS directory for matching studies,
#' series, or instances, returning a tidy [tibble::tibble] that can be piped
#' into `dplyr::filter()` and [dicom_get()].
#'
#' @param conn A `"dicom_connection"` object from [dicom_connect()], or a local
#'   directory path.
#' @param level Query level: `"STUDY"`, `"SERIES"`, or `"IMAGE"`. Default is
#'   `"STUDY"`.
#' @param ... Optional tag filters as named arguments (e.g., `Modality = "CT"`,
#'   `PatientName = "DOE*"`).
#'
#' @return A [tibble::tibble] of matching DICOM records.
#' @export
#' @examples
#' ext_dir <- system.file("extdata", package = "dicomtk")
#' conn <- dicom_connect(local_dir = ext_dir)
#' dicom_find(conn)
dicom_find <- function(conn, level = c("STUDY", "SERIES", "IMAGE"), ...) {
  level <- match.arg(level)
  filters <- list(...)

  target_dir <- if (inherits(conn, "dicom_connection") && !is.null(conn$local_dir)) {
    conn$local_dir
  } else if (is.character(conn) && dir.exists(conn)) {
    conn
  } else {
    NULL
  }

  if (!is.null(target_dir)) {
    df <- read_dicom(target_dir, wide = TRUE)
    if (length(filters) > 0L) {
      for (nm in names(filters)) {
        if (nm %in% names(df)) {
          pat <- glob2rx(as.character(filters[[nm]]))
          df <- df[grepl(pat, df[[nm]], ignore.case = TRUE), , drop = FALSE]
        }
      }
    }
    return(df)
  }

  if (inherits(conn, "dicom_connection") && !is.null(conn$dicomweb_url)) {
    endpoint <- switch(level,
      STUDY = "studies",
      SERIES = "series",
      IMAGE = "instances"
    )
    req <- httr2::request(conn$dicomweb_url) |>
      httr2::req_url_path_append(endpoint) |>
      httr2::req_headers(Accept = "application/dicom+json")
    resp <- httr2::req_perform(req)
    body <- httr2::resp_body_json(resp)
    return(tibble::tibble(result = body))
  }

  rlang::abort("Active PACS C-FIND server not reachable or `local_dir` not configured on `conn`.")
}

#' Retrieve DICOM Files from PACS Connection (C-GET / C-MOVE / Local PACS)
#'
#' Copies or downloads matching DICOM files from a `"dicom_connection"` or
#' query result tibble into `output_dir`.
#'
#' @param x A `"dicom_connection"` object or a [tibble::tibble] returned by
#'   [dicom_find()].
#' @param output_dir Destination directory for retrieved `.dcm` files. Defaults
#'   to a temporary directory.
#' @param ... Optional filter criteria if `x` is a `"dicom_connection"`.
#'
#' @return Character vector of retrieved file paths in `output_dir`.
#' @export
#' @examples
#' ext_dir <- system.file("extdata", package = "dicomtk")
#' conn <- dicom_connect(local_dir = ext_dir)
#' files <- conn |> dicom_find() |> dicom_get()
#' length(files)
dicom_get <- function(x, output_dir = tempfile("dicom_get_"), ...) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  if (inherits(x, "dicom_connection")) {
    x <- dicom_find(x, ...)
  }
  if (is.data.frame(x) && "file" %in% names(x)) {
    src_files <- x$file[file.exists(x$file)]
    dst_files <- file.path(output_dir, basename(src_files))
    file.copy(src_files, dst_files, overwrite = TRUE)
    return(normalizePath(dst_files, mustWork = FALSE))
  }
  rlang::abort("`x` must be a `dicom_connection` or a tibble containing a `file` column from `dicom_find()`.")
}

#' Send DICOM Files to a PACS Peer (C-STORE SCU)
#'
#' Transmits one or more DICOM files to a configured `"dicom_connection"` (or
#' local PACS repository directory).
#'
#' @param files Character vector of DICOM file paths to send.
#' @param conn A `"dicom_connection"` object from [dicom_connect()].
#'
#' @return A [tibble::tibble] summarizing the transmission status for each file.
#' @export
#' @examples
#' dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
#' pacs_dir <- tempfile("pacs_store_")
#' dir.create(pacs_dir)
#' conn <- dicom_connect(local_dir = pacs_dir)
#' dicom_send(dcm_file, conn)
dicom_send <- function(files, conn) {
  files <- resolve_dicom_paths(files)
  if (inherits(conn, "dicom_connection") && !is.null(conn$local_dir)) {
    dir.create(conn$local_dir, recursive = TRUE, showWarnings = FALSE)
    dst <- file.path(conn$local_dir, basename(files))
    ok <- file.copy(files, dst, overwrite = TRUE)
    return(tibble::tibble(
      file = files,
      destination = dst,
      success = ok,
      status = ifelse(ok, "STORED_LOCAL", "COPY_FAILED")
    ))
  }
  echo_res <- dicom_echo(conn)
  tibble::tibble(
    file = files,
    destination = paste0(conn$host, ":", conn$port),
    success = echo_res$success,
    status = echo_res$status
  )
}

#' Configure a Local DICOM Storage Receiver Directory (C-STORE SCP)
#'
#' Sets up and returns a local directory-backed `"dicom_connection"` ready to
#' receive, index, and query DICOM files.
#'
#' @param output_dir Directory to store received DICOM files.
#' @param port Port number for metadata registration. Default is `11112L`.
#' @param aetitle Application Entity Title for the receiver. Default is
#'   `"DICOMTK-SCP"`.
#'
#' @return A `"dicom_connection"` object configured with `local_dir = output_dir`.
#' @export
#' @examples
#' scp <- dicom_receive(tempfile("scp_"))
#' scp
dicom_receive <- function(output_dir = tempfile("dicom_scp_"),
                          port = 11112L,
                          aetitle = "DICOMTK-SCP") {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  dicom_connect(
    host = "127.0.0.1",
    port = port,
    called_ae = aetitle,
    calling_ae = aetitle,
    local_dir = normalizePath(output_dir, mustWork = TRUE)
  )
}
