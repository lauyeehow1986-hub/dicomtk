# Configure an LLM Provider for DICOM Analysis

Creates a `"dicom_llm"` configuration object connecting `dicomtk` to:

- **Local Ollama** (`provider = "ollama"`, default
  `http://localhost:11434`)

- **OpenAI / OpenAI-compatible APIs** (`provider = "openai"` or
  `"custom"`, supporting OpenAI, OpenRouter, LM Studio, vLLM, Azure, or
  local proxy subscriptions)

- **Anthropic Claude** (`provider = "anthropic"`, supporting native
  `/v1/messages` as well as OpenAI-compatible endpoints)

- **Offline rule-based engine** (`provider = "offline"`, for
  deterministic local metadata & pixel-statistics summaries without
  external API calls)

## Usage

``` r
dicom_llm(
  provider = c("ollama", "openai", "anthropic", "custom", "offline"),
  model = NULL,
  base_url = NULL,
  api_key = NULL,
  temperature = 0.2,
  max_tokens = 1024L,
  anonymize = TRUE,
  offline_fallback = TRUE
)
```

## Arguments

- provider:

  Character provider type: `"ollama"`, `"openai"`, `"anthropic"`,
  `"custom"`, or `"offline"`. Default is `"ollama"`.

- model:

  Model identifier (e.g., `"llava:13b"`, `"llama3.2-vision"`,
  `"gpt-4o"`, `"claude-sonnet-4-20250514"`).

- base_url:

  Optional API base URL. Defaults to `"http://localhost:11434"` for
  Ollama, `"https://api.openai.com/v1"` for OpenAI, and
  `"https://api.anthropic.com/v1"` for Anthropic.

- api_key:

  API key or bearer token. Automatically reads from `OPENAI_API_KEY` or
  `ANTHROPIC_API_KEY` environment variables if not supplied.

- temperature:

  Sampling temperature. Default is `0.2`.

- max_tokens:

  Maximum response tokens. Default is `1024L`.

- anonymize:

  Logical. Automatically strip HIPAA PHI tags before sending metadata to
  non-local endpoints. Default is `TRUE`.

- offline_fallback:

  Logical. If `TRUE` (default), falls back to a deterministic local
  clinical summary if the remote/local server is unreachable.

## Value

An S3 object of class `"dicom_llm"`.

## Examples

``` r
# Local Ollama configuration
local_llm <- dicom_llm("ollama", model = "llava:13b")

# OpenAI-compatible configuration
openai_llm <- dicom_llm("openai", model = "gpt-4o")

# Anthropic Claude configuration
claude_llm <- dicom_llm("anthropic", model = "claude-sonnet-4-20250514")
```
