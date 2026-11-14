# List Available Local Ollama Models

Queries the local Ollama daemon (`GET /api/tags`) and returns a tidy
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html) of
installed models (`name`, `size_gb`, `modified_at`). Returns an empty
tibble if Ollama is not running.

## Usage

``` r
ollama_list_models(
  base_url = Sys.getenv("OLLAMA_HOST", unset = "http://localhost:11434")
)
```

## Arguments

- base_url:

  Ollama base URL. Defaults to `"http://localhost:11434"`.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `name`, `size_gb`, and `modified_at`.

## Examples

``` r
ollama_list_models()
#> # A tibble: 26 × 3
#>    name                                             size_gb modified_at         
#>    <chr>                                              <dbl> <chr>               
#>  1 qwen2.5:3b-instruct-q4_K_M                          1.93 2026-10-30T23:37:27…
#>  2 qwen2.5:1.5b-instruct-q4_K_M                        0.99 2026-10-30T23:35:26…
#>  3 slmjev-judge-p5:latest                              1.11 2026-10-10T06:54:41…
#>  4 qwen3:14b                                           9.28 2026-08-24T10:00:37…
#>  5 qwen3-1.7b-base:latest                              1.11 2026-08-08T09:59:43…
#>  6 ajindal/llama3.1-storm:8b                           4.66 2026-08-08T03:48:51…
#>  7 gemma4:e4b                                          9.61 2026-08-08T03:42:15…
#>  8 gemma4:26b                                         18.0  2026-08-08T03:41:24…
#>  9 gemma4:latest                                       9.61 2026-05-14T13:15:45…
#> 10 hf.co/unsloth/Qwen3-4B-Instruct-2507-GGUF:latest    2.5  2025-12-19T15:43:59…
#> # ℹ 16 more rows
```
