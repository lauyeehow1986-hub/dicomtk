#' Pluggable Cryptographic Key Provider for DICOM De-Identification
#'
#' Manages cryptographic master keys, password-based key derivation (PBKDF2),
#' domain-separated subkey expansion (HKDF-SHA256), and pluggable enterprise key
#' broker/trusted-third-party (TTP) resolution.
#'
#' Subkeys are stored in a private environment closure to ensure that secret key
#' bytes and passphrases are never leaked through `print()`, `format()`, or `str()`.
#'
#' @param mode Character string specifying key management mode:
#'   \code{"local"} for local key derivation via PBKDF2/HKDF,
#'   \code{"broker"} for an enterprise cryptographic key broker callback,
#'   \code{"ttp"} for a trusted third party pseudonym resolution service.
#' @param key Optional 32-byte raw vector containing a pre-shared master key.
#' @param passphrase Optional character string or raw vector containing a passphrase
#'   used to derive the master key via PBKDF2-HMAC-SHA256.
#' @param salt Optional character string or raw vector containing salt for PBKDF2.
#'   Defaults to an internal versioned salt if omitted.
#' @param keyfile Optional file path pointing to a binary file containing the 32-byte key.
#' @param resolver_fn Optional function callback used when \code{mode} is \code{"broker"}
#'   or \code{"ttp"}. Must accept a domain name string and return raw key bytes.
#'
#' @return An S3 object of class \code{dicom_key_provider}.
#' @export
#'
#' @examples
#' kp <- dicom_key_provider(passphrase = "clinical-trial-secret", salt = "site-001")
#' is_dicom_key_provider(kp)
#' print(kp)
dicom_key_provider <- function(mode = c("local", "broker", "ttp"),
                               key = NULL,
                               passphrase = NULL,
                               salt = NULL,
                               keyfile = NULL,
                               resolver_fn = NULL) {
  mode <- match.arg(mode)

  # Private closure environment to protect secrets from str() and print()
  env <- new.env(parent = emptyenv())
  env$mode <- mode

  if (identical(mode, "local")) {
    if (!is.null(keyfile)) {
      if (!file.exists(keyfile)) {
        cli::cli_abort("Key file does not exist: {keyfile}")
      }
      file_bytes <- readBin(keyfile, what = "raw", n = file.info(keyfile)$size)
      key <- file_bytes
    }

    if (!is.null(passphrase)) {
      if (is.character(passphrase)) {
        pass_raw <- charToRaw(passphrase)
      } else if (is.raw(passphrase)) {
        pass_raw <- passphrase
      } else {
        cli::cli_abort("Passphrase must be a string or raw vector.")
      }

      if (is.null(salt)) {
        salt_raw <- charToRaw("dicomtk-deid-default-salt-v1")
      } else if (is.character(salt)) {
        salt_raw <- charToRaw(salt)
      } else if (is.raw(salt)) {
        salt_raw <- salt
      } else {
        cli::cli_abort("Salt must be a string or raw vector.")
      }

      master_key <- cpp_pbkdf2_sha256(pass_raw, salt_raw, 210000L, 32L)
    } else if (!is.null(key)) {
      if (is.character(key)) {
        key <- charToRaw(key)
      }
      if (!is.raw(key) || length(key) != 32L) {
        cli::cli_abort("Master key must be exactly 32 raw bytes.")
      }
      master_key <- key
    } else {
      # Fallback to random 32-byte key
      if (requireNamespace("openssl", quietly = TRUE)) {
        master_key <- openssl::rand_bytes(32L)
      } else {
        master_key <- as.raw(sample(0:255, 32L, replace = TRUE))
      }
    }

    # Derive 5 domain-separated subkeys via HKDF-SHA256
    env$uid_key    <- cpp_hkdf_sha256(master_key, raw(0), charToRaw("dicomtk-deid-uid-v1"), 32L)
    env$pid_key    <- cpp_hkdf_sha256(master_key, raw(0), charToRaw("dicomtk-deid-pid-v1"), 32L)
    env$date_key   <- cpp_hkdf_sha256(master_key, raw(0), charToRaw("dicomtk-deid-date-v1"), 32L)
    env$aead_key   <- cpp_hkdf_sha256(master_key, raw(0), charToRaw("dicomtk-deid-aead-v1"), 32L)
    env$attest_key <- cpp_hkdf_sha256(master_key, raw(0), charToRaw("dicomtk-deid-attest-v1"), 32L)
  } else {
    # broker or ttp mode
    if (is.null(resolver_fn) || !is.function(resolver_fn)) {
      cli::cli_abort("Mode '{mode}' requires a valid 'resolver_fn' callback.")
    }
    env$resolver_fn <- resolver_fn
  }

  structure(
    list(
      mode = mode,
      status = "active",
      created = Sys.time()
    ),
    secret_env = env,
    class = "dicom_key_provider"
  )
}

#' Check if Object is a DICOM Key Provider
#'
#' @param x An R object.
#' @return Logical scalar indicating if \code{x} is a valid key provider.
#' @export
is_dicom_key_provider <- function(x) {
  inherits(x, "dicom_key_provider") && !is.null(attr(x, "secret_env"))
}

#' Retrieve Subkey from Key Provider
#'
#' @param key_provider A \code{dicom_key_provider} object.
#' @param name Character string specifying the subkey name.
#' @return A 32-byte raw vector.
#' @keywords internal
#' @noRd
deid_get_subkey <- function(key_provider, name = c("uid", "pid", "date", "aead", "attest")) {
  name <- match.arg(name)
  if (!is_dicom_key_provider(key_provider)) {
    cli::cli_abort("Object is not a valid dicom_key_provider.")
  }
  env <- attr(key_provider, "secret_env")
  if (is.null(env)) {
    cli::cli_abort("Corrupted dicom_key_provider: secret environment missing.")
  }
  if (identical(env$mode, "local")) {
    var_name <- paste0(name, "_key")
    return(env[[var_name]])
  } else {
    res <- env$resolver_fn(name)
    if (!is.raw(res) || length(res) != 32L) {
      cli::cli_abort("Resolver function must return a 32-byte raw vector for '{name}', got {class(res)[1]} of length {length(res)}.")
    }
    return(res)
  }
}

#' Deterministically Map a DICOM UID
#'
#' Maps a DICOM Unique Identifier (UID) using HMAC-SHA256 and prefix 2.25.
#' Standard DICOM UIDs starting with \code{"1.2.840.10008."} are preserved.
#'
#' @param uid Character vector of DICOM UIDs to map.
#' @param key_provider A \code{dicom_key_provider} object.
#' @return Character vector of pseudonymized UIDs obeying the 64-character limit.
#' @export
#'
#' @examples
#' kp <- dicom_key_provider(passphrase = "secret", salt = "salt")
#' deid_map_uid("1.2.840.10008.5.1.4.1.1.2", kp)
#' deid_map_uid("1.3.6.1.4.1.14519.5.2.1.9999.1001", kp)
deid_map_uid <- function(uid, key_provider) {
  if (!is_dicom_key_provider(key_provider)) {
    cli::cli_abort("'key_provider' must be a valid dicom_key_provider object.")
  }
  if (!is.character(uid)) {
    uid <- as.character(uid)
  }
  if (length(uid) == 0L) {
    return(character(0L))
  }

  uid_key <- deid_get_subkey(key_provider, "uid")

  vapply(uid, function(u) {
    if (is.na(u) || identical(u, "")) {
      return(if (is.na(u)) NA_character_ else "")
    }
    if (grepl("\\", u, fixed = TRUE)) {
      sub_uids <- strsplit(u, "\\", fixed = TRUE)[[1L]]
      mapped <- vapply(sub_uids, function(sub_u) {
        if (identical(sub_u, "")) return("")
        cpp_hmac_uid(uid_key, sub_u)
      }, FUN.VALUE = character(1L), USE.NAMES = FALSE)
      return(paste(mapped, collapse = "\\"))
    }
    cpp_hmac_uid(uid_key, u)
  }, FUN.VALUE = character(1L), USE.NAMES = FALSE)
}

#' Compute Per-Patient Date Shift
#'
#' Computes a deterministic integer day shift for a given patient identifier,
#' bounded within \code{date_range}.
#'
#' @param key_provider A \code{dicom_key_provider} object.
#' @param patient_id Character vector of patient identifiers.
#' @param date_range Integer vector of length 2 giving \code{c(min_days, max_days)}.
#'   Defaults to \code{c(-3650L, -30L)}.
#' @return Integer vector of day shift values.
#' @export
#'
#' @examples
#' kp <- dicom_key_provider(passphrase = "secret", salt = "salt")
#' deid_patient_shift(kp, "PAT001", c(-3650L, -30L))
deid_patient_shift <- function(key_provider, patient_id, date_range = c(-3650L, -30L)) {
  if (!is_dicom_key_provider(key_provider)) {
    cli::cli_abort("'key_provider' must be a valid dicom_key_provider object.")
  }
  if (length(date_range) != 2L) {
    cli::cli_abort("'date_range' must be an integer vector of length 2 (c(min_days, max_days)).")
  }
  min_days <- as.integer(date_range[1])
  max_days <- as.integer(date_range[2])

  date_key <- deid_get_subkey(key_provider, "date")

  if (length(patient_id) == 0L) {
    return(integer(0L))
  }

  vapply(patient_id, function(pid) {
    if (is.na(pid)) return(NA_integer_)
    cpp_hmac_shift_days(date_key, as.character(pid), min_days, max_days)
  }, FUN.VALUE = integer(1L), USE.NAMES = FALSE)
}

#' Derive Patient Shift Days from Key or Provider
#'
#' Convenience helper for date shifting given either a raw 32-byte key
#' or a \code{dicom_key_provider}.
#'
#' @param key A 32-byte raw vector or a \code{dicom_key_provider}.
#' @param patient_id Character string of patient identifier.
#' @param date_range Integer vector of length 2 giving \code{c(min_days, max_days)}.
#' @return Integer day shift.
#' @export
derive_patient_shift_days <- function(key, patient_id, date_range = c(-3650L, -30L)) {
  if (is_dicom_key_provider(key)) {
    return(deid_patient_shift(key, patient_id, date_range))
  }
  if (!is.raw(key) || length(key) != 32L) {
    cli::cli_abort("'key' must be a 32-byte raw vector or a dicom_key_provider object.")
  }
  min_days <- as.integer(date_range[1])
  max_days <- as.integer(date_range[2])
  cpp_hmac_shift_days(key, as.character(patient_id), min_days, max_days)
}

#' @export
format.dicom_key_provider <- function(x, ...) {
  paste0("<dicom_key_provider: ", x$mode, " [REDACTED]>")
}

#' @export
print.dicom_key_provider <- function(x, ...) {
  cat(format(x), "\n")
  cat("  Status: active\n")
  cat("  Keys:   <REDACTED>\n")
  invisible(x)
}

#' @export
str.dicom_key_provider <- function(object, ...) {
  cat(format(object), "\n")
  invisible(NULL)
}
