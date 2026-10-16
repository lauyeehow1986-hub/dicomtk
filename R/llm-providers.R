#' Configure an LLM Provider for DICOM Analysis
#'
#' Creates a `"dicom_llm"` configuration object connecting `dicomtk` to:
#' - **Local Ollama** (`provider = "ollama"`, default `http://localhost:11434`)
#' - **OpenAI / OpenAI-compatible APIs** (`provider = "openai"` or `"custom"`,
#'   supporting OpenAI, OpenRouter, LM Studio, vLLM, Azure, or local proxy
#'   subscriptions)
#' - **Anthropic Claude** (`provider = "anthropic"`, supporting native
#'   `/v1/messages` as well as OpenAI-compatible endpoints)
#' - **Offline rule-based engine** (`provider = "offline"`, for deterministic
#'   local metadata & pixel-statistics summaries without external API calls)
#'
#' @param provider Character provider type: `"ollama"`, `"openai"`,
#'   `"anthropic"`, `"custom"`, or `"offline"`. Default is `"ollama"`.
#' @param model Model identifier (e.g., `"llava:13b"`, `"llama3.2-vision"`,
#'   `"gpt-4o"`, `"claude-sonnet-4-20250514"`).
#' @param base_url Optional API base URL. Defaults to `"http://localhost:11434"`
#'   for Ollama, `"https://api.openai.com/v1"` for OpenAI, and
#'   `"https://api.anthropic.com/v1"` for Anthropic.
#' @param api_key API key or bearer token. Automatically reads from
#'   `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` environment variables if not
#'   supplied.
#' @param temperature Sampling temperature. Default is `0.2`.
#' @param max_tokens Maximum response tokens. Default is `1024L`.
#' @param anonymize Logical. Automatically strip HIPAA PHI tags before sending
#'   metadata to non-local endpoints. Default is `TRUE`.
#' @param offline_fallback Logical. If `TRUE` (default), falls back to a
#'   deterministic local clinical summary if the remote/local server is
#'   unreachable.
#'
#' @return An S3 object of class `"dicom_llm"`.
#' @export
#' @examples
#' # Local Ollama configuration
#' local_llm <- dicom_llm("ollama", model = "llava:13b")
#'
#' # OpenAI-compatible configuration
#' openai_llm <- dicom_llm("openai", model = "gpt-4o")
#'
#' # Anthropic Claude configuration
#' claude_llm <- dicom_llm("anthropic", model = "claude-sonnet-4-20250514")
dicom_llm <- function(provider = c("ollama", "openai", "anthropic", "custom", "offline"),
                      model = NULL,
                      base_url = NULL,
                      api_key = NULL,
                      temperature = 0.2,
                      max_tokens = 1024L,
                      anonymize = TRUE,
                      offline_fallback = TRUE) {
  provider <- match.arg(provider)

  if (is.null(model)) {
    model <- switch(provider,
      ollama    = "llava:latest",
      openai    = "gpt-4o",
      anthropic = "claude-sonnet-4-20250514",
      custom    = "gpt-4o",
      offline   = "local-deterministic"
    )
  }

  if (is.null(base_url)) {
    base_url <- switch(provider,
      ollama    = Sys.getenv("OLLAMA_HOST", unset = "http://localhost:11434"),
      openai    = Sys.getenv("OPENAI_BASE_URL", unset = "https://api.openai.com/v1"),
      anthropic = Sys.getenv("ANTHROPIC_BASE_URL", unset = "https://api.anthropic.com/v1"),
      custom    = Sys.getenv("OPENAI_BASE_URL", unset = "http://localhost:8000/v1"),
      offline   = "offline://local"
    )
  }

  if (is.null(api_key)) {
    api_key <- switch(provider,
      ollama    = Sys.getenv("OLLAMA_API_KEY", unset = ""),
      openai    = Sys.getenv("OPENAI_API_KEY", unset = ""),
      anthropic = Sys.getenv("ANTHROPIC_API_KEY", unset = ""),
      custom    = Sys.getenv("OPENAI_API_KEY", unset = ""),
      offline   = ""
    )
  }

  is_local <- provider %in% c("ollama", "offline") ||
              grepl("^https?://(localhost|127\\.0\\.0\\.1)", base_url, ignore.case = TRUE)

  structure(
    list(
      provider = provider,
      model = as.character(model),
      base_url = sub("/+$", "", as.character(base_url)),
      api_key = as.character(api_key),
      temperature = as.double(temperature),
      max_tokens = as.integer(max_tokens),
      anonymize = isTRUE(anonymize),
      is_local = is_local,
      offline_fallback = isTRUE(offline_fallback)
    ),
    class = "dicom_llm"
  )
}

#' @export
print.dicom_llm <- function(x, ...) {
  cli::cli_alert_info(
    "DICOM LLM Provider: {x$provider} (model: {x$model}, endpoint: {x$base_url}, local: {x$is_local})"
  )
  invisible(x)
}

# Internal dispatcher to call Ollama, OpenAI-compatible, or Anthropic APIs
llm_chat_completion <- function(llm,
                                system_prompt,
                                user_prompt,
                                image_base64 = NULL) {
  if (!inherits(llm, "dicom_llm")) {
    rlang::abort("`llm` must be a `dicom_llm` object created by `dicom_llm()`.")
  }

  if (identical(llm$provider, "offline")) {
    return(NULL)
  }

  tryCatch({
    if (identical(llm$provider, "ollama")) {
      # Ollama /api/chat endpoint
      msg <- list(role = "user", content = user_prompt)
      if (!is.null(image_base64) && nzchar(image_base64)) {
        msg$images <- list(image_base64)
      }
      payload <- list(
        model = llm$model,
        messages = list(
          list(role = "system", content = system_prompt),
          msg
        ),
        stream = FALSE,
        options = list(temperature = llm$temperature)
      )
      req <- httr2::request(paste0(llm$base_url, "/api/chat")) |>
        httr2::req_body_json(payload, auto_unbox = TRUE)
      if (nzchar(llm$api_key)) {
        req <- httr2::req_headers(req, Authorization = paste("Bearer", llm$api_key))
      }
      resp <- httr2::req_perform(req)
      body <- httr2::resp_body_json(resp)
      return(as.character(body$message$content))
    }

    if (identical(llm$provider, "anthropic")) {
      # Anthropic /v1/messages endpoint
      content_blocks <- list()
      if (!is.null(image_base64) && nzchar(image_base64)) {
        content_blocks <- c(content_blocks, list(list(
          type = "image",
          source = list(
            type = "base64",
            media_type = "image/png",
            data = image_base64
          )
        )))
      }
      content_blocks <- c(content_blocks, list(list(
        type = "text",
        text = user_prompt
      )))

      payload <- list(
        model = llm$model,
        max_tokens = llm$max_tokens,
        temperature = llm$temperature,
        system = system_prompt,
        messages = list(
          list(role = "user", content = content_blocks)
        )
      )
      req <- httr2::request(paste0(llm$base_url, "/messages")) |>
        httr2::req_headers(
          `x-api-key` = llm$api_key,
          `anthropic-version` = "2023-06-01",
          `content-type` = "application/json"
        ) |>
        httr2::req_body_json(payload, auto_unbox = TRUE)
      resp <- httr2::req_perform(req)
      body <- httr2::resp_body_json(resp)
      return(as.character(body$content[[1L]]$text))
    }

    # OpenAI or custom OpenAI-compatible /chat/completions endpoint
    user_content <- if (!is.null(image_base64) && nzchar(image_base64)) {
      list(
        list(type = "text", text = user_prompt),
        list(
          type = "image_url",
          image_url = list(url = paste0("data:image/png;base64,", image_base64))
        )
      )
    } else {
      user_prompt
    }

    payload <- list(
      model = llm$model,
      temperature = llm$temperature,
      max_tokens = llm$max_tokens,
      messages = list(
        list(role = "system", content = system_prompt),
        list(role = "user", content = user_content)
      )
    )

    req <- httr2::request(paste0(llm$base_url, "/chat/completions")) |>
      httr2::req_body_json(payload, auto_unbox = TRUE)
    if (nzchar(llm$api_key)) {
      req <- httr2::req_headers(req, Authorization = paste("Bearer", llm$api_key))
    }
    resp <- httr2::req_perform(req)
    body <- httr2::resp_body_json(resp)
    as.character(body$choices[[1L]]$message$content)
  }, error = function(e) {
    if (isTRUE(llm$offline_fallback)) {
      return(NULL)
    }
    rlang::abort(paste0("LLM API request failed (", llm$provider, "): ", conditionMessage(e)))
  })
}

#' List Available Local Ollama Models
#'
#' Queries the local Ollama daemon (`GET /api/tags`) and returns a tidy
#' [tibble::tibble] of installed models (`name`, `size_gb`, `modified_at`).
#' Returns an empty tibble if Ollama is not running.
#'
#' @param base_url Ollama base URL. Defaults to `"http://localhost:11434"`.
#'
#' @return A [tibble::tibble] with columns `name`, `size_gb`, and `modified_at`.
#' @export
#' @examples
#' ollama_list_models()
ollama_list_models <- function(base_url = Sys.getenv("OLLAMA_HOST", unset = "http://localhost:11434")) {
  tryCatch({
    req <- httr2::request(paste0(sub("/+$", "", base_url), "/api/tags"))
    resp <- httr2::req_perform(req)
    body <- httr2::resp_body_json(resp)
    models <- body$models
    if (length(models) == 0L) {
      return(tibble::tibble(name = character(), size_gb = numeric(), modified_at = character()))
    }
    tibble::tibble(
      name = vapply(models, function(m) as.character(m$name %||% ""), character(1)),
      size_gb = round(vapply(models, function(m) as.numeric(m$size %||% 0), numeric(1)) / 1e9, 2),
      modified_at = vapply(models, function(m) as.character(m$modified_at %||% ""), character(1))
    )
  }, error = function(e) {
    tibble::tibble(name = character(), size_gb = numeric(), modified_at = character())
  })
}
