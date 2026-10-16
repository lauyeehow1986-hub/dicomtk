# inst/shiny/viewer/app.R
# Interactive Shiny DICOM Workstation & AI Assistant for dicomtk

ollama_models <- tryCatch(dicomtk::ollama_list_models()$name, error = function(e) character(0))
if (length(ollama_models) == 0L) {
  ollama_models <- c("llava:latest", "llama3.2:3b", "qwen3-vl:8b")
}

ui <- shiny::fluidPage(
  shiny::titlePanel("dicomtk — Interactive DICOM Workstation & AI Assistant"),
  shiny::sidebarLayout(
    shiny::sidebarPanel(
      width = 4,
      shiny::fileInput(
        "dcm_upload",
        "Upload DICOM File(s)",
        multiple = TRUE,
        accept = c(".dcm", ".dicom", "application/dicom")
      ),
      shiny::uiOutput("slice_slider_ui"),
      shiny::selectInput(
        "preset",
        "Window Preset",
        choices = c(
          "Auto (DICOM Header / Robust)" = "auto",
          "Brain (WL: 40, WW: 80)" = "brain",
          "Stroke (WL: 32, WW: 8)" = "stroke",
          "Subdural (WL: 75, WW: 215)" = "subdural",
          "Lung (WL: -600, WW: 1500)" = "lung",
          "Mediastinum (WL: 50, WW: 350)" = "mediastinum",
          "Abdomen (WL: 40, WW: 400)" = "abdomen",
          "Liver (WL: 60, WW: 150)" = "liver",
          "Bone (WL: 400, WW: 1800)" = "bone",
          "Angio (WL: 300, WW: 600)" = "angio",
          "Custom Sliders" = "custom"
        ),
        selected = "auto"
      ),
      shiny::conditionalPanel(
        condition = "input.preset == 'custom'",
        shiny::sliderInput("win_center", "Window Center (WL)", min = -1024, max = 3071, value = 40),
        shiny::sliderInput("win_width", "Window Width (WW)", min = 1, max = 4096, value = 400)
      ),
      shiny::selectInput(
        "palette",
        "Color Map",
        choices = c(
          "Radiological Gray" = "gray",
          "Viridis" = "viridis",
          "Inferno" = "inferno",
          "Magma" = "magma",
          "Plasma" = "plasma"
        ),
        selected = "gray"
      ),
      shiny::checkboxInput("annotate", "Show HUD Overlay", value = TRUE),
      shiny::hr(),
      shiny::h4("AI / LLM Configuration"),
      shiny::selectInput(
        "llm_provider",
        "LLM Provider",
        choices = c(
          "Local Ollama" = "ollama",
          "OpenAI / Compatible API" = "openai",
          "Anthropic Claude" = "anthropic",
          "Offline Deterministic" = "offline"
        ),
        selected = "ollama"
      ),
      shiny::conditionalPanel(
        condition = "input.llm_provider == 'ollama'",
        shiny::selectizeInput(
          "ollama_model",
          "Ollama Model",
          choices = ollama_models,
          selected = ollama_models[1L],
          options = list(create = TRUE)
        )
      ),
      shiny::conditionalPanel(
        condition = "input.llm_provider != 'ollama' && input.llm_provider != 'offline'",
        shiny::textInput("cloud_model", "Model Name", value = "gpt-4o"),
        shiny::textInput("cloud_base_url", "API Base URL (optional)", value = ""),
        shiny::passwordInput("cloud_api_key", "API Key (leave blank for env var)", value = "")
      ),
      shiny::checkboxInput("llm_anonymize", "Auto-Anonymize PHI Before AI Calls", value = TRUE),
      shiny::hr(),
      shiny::textInput("tag_search", "Filter DICOM Header Tags", placeholder = "e.g. Patient, Modality, 0028")
    ),
    shiny::mainPanel(
      width = 8,
      shiny::tabsetPanel(
        shiny::tabPanel(
          "Image Viewport",
          shiny::plotOutput("dicom_plot", height = "560px")
        ),
        shiny::tabPanel(
          "3D MPR / MIP View",
          shiny::radioButtons(
            "vol_method",
            "3D Projection Mode",
            choices = c("Orthogonal 3-Plane MPR" = "mpr", "Maximum Intensity Projection (MIP)" = "mip"),
            selected = "mpr",
            inline = TRUE
          ),
          shiny::plotOutput("volume_plot", height = "420px")
        ),
        shiny::tabPanel(
          "DICOM Header Inspector",
          shiny::tableOutput("header_table")
        ),
        shiny::tabPanel(
          "AI Radiology Assistant",
          shiny::br(),
          shiny::fluidRow(
            shiny::column(4, shiny::actionButton("btn_summarize", "Summarize Study Metadata", class = "btn-primary", width = "100%")),
            shiny::column(4, shiny::actionButton("btn_describe", "Analyze Image (Vision)", class = "btn-info", width = "100%")),
            shiny::column(4, shiny::actionButton("btn_report", "Generate Structured Report", class = "btn-success", width = "100%"))
          ),
          shiny::br(),
          shiny::fluidRow(
            shiny::column(9, shiny::textInput("ai_question", "Ask a Question About This Study/Image:", width = "100%", placeholder = "e.g. What is the slice thickness and tube current?")),
            shiny::column(3, shiny::br(), shiny::actionButton("btn_ask", "Ask AI", width = "100%"))
          ),
          shiny::hr(),
          shiny::verbatimTextOutput("ai_output")
        )
      )
    )
  )
)

server <- function(input, output, session) {
  active_files <- shiny::reactive({
    up <- input$dcm_upload
    if (!is.null(up) && nrow(up) > 0) {
      return(up$datapath)
    }
    init_path <- getOption(
      "dicomtk.viewer.path",
      system.file("extdata", "example.dcm", package = "dicomtk")
    )
    if (dir.exists(init_path)) {
      list.files(init_path, full.names = TRUE, recursive = TRUE)
    } else {
      init_path
    }
  })

  output$slice_slider_ui <- shiny::renderUI({
    fls <- active_files()
    if (length(fls) <= 1L) return(NULL)
    shiny::sliderInput("slice_idx", "Slice", min = 1L, max = length(fls), value = 1L, step = 1L)
  })

  current_file <- shiny::reactive({
    fls <- active_files()
    idx <- if (!is.null(input$slice_idx)) as.integer(input$slice_idx) else 1L
    idx <- max(1L, min(idx, length(fls)))
    fls[idx]
  })

  active_llm <- shiny::reactive({
    prov <- input$llm_provider
    if (identical(prov, "ollama")) {
      dicomtk::dicom_llm("ollama", model = input$ollama_model, anonymize = input$llm_anonymize)
    } else if (identical(prov, "offline")) {
      dicomtk::dicom_llm("offline", anonymize = input$llm_anonymize)
    } else {
      burl <- if (nzchar(trimws(input$cloud_base_url))) trimws(input$cloud_base_url) else NULL
      akey <- if (nzchar(trimws(input$cloud_api_key))) trimws(input$cloud_api_key) else NULL
      dicomtk::dicom_llm(
        provider = prov,
        model = input$cloud_model,
        base_url = burl,
        api_key = akey,
        anonymize = input$llm_anonymize
      )
    }
  })

  output$dicom_plot <- shiny::renderPlot({
    f <- current_file()
    shiny::req(file.exists(f))
    if (identical(input$preset, "custom")) {
      dicomtk::plot_dicom(
        f,
        center = input$win_center,
        width = input$win_width,
        palette = input$palette,
        annotate = input$annotate
      )
    } else {
      dicomtk::plot_dicom(
        f,
        window = input$preset,
        palette = input$palette,
        annotate = input$annotate
      )
    }
  }, bg = "black")

  output$volume_plot <- shiny::renderPlot({
    fls <- active_files()
    shiny::req(length(fls) > 0)
    series <- dicomtk::read_dicom_series(fls)
    win_arg <- if (identical(input$preset, "custom")) {
      c(input$win_center, input$win_width)
    } else {
      input$preset
    }
    dicomtk::render_volume(series, method = input$vol_method, window = win_arg, palette = input$palette)
  }, bg = "black")

  output$header_table <- shiny::renderTable({
    f <- current_file()
    shiny::req(file.exists(f))
    hdr <- dicomtk::read_dicom(f)
    q <- trimws(input$tag_search)
    if (nzchar(q)) {
      keep <- grepl(q, hdr$tag, ignore.case = TRUE) |
              grepl(q, hdr$keyword, ignore.case = TRUE) |
              grepl(q, hdr$name, ignore.case = TRUE) |
              grepl(q, hdr$value, ignore.case = TRUE)
      hdr <- hdr[keep, , drop = FALSE]
    }
    hdr[, c("tag", "vr", "keyword", "name", "value"), drop = FALSE]
  })

  ai_text <- shiny::reactiveVal("Select an AI action above to analyze the active DICOM slice.")

  shiny::observeEvent(input$btn_summarize, {
    f <- current_file()
    shiny::req(file.exists(f))
    ai_text("Running LLM study metadata summary...")
    res <- dicomtk::dicom_summarize(f, llm = active_llm())
    ai_text(res)
  })

  shiny::observeEvent(input$btn_describe, {
    f <- current_file()
    shiny::req(file.exists(f))
    ai_text("Running multimodal vision analysis...")
    win_arg <- if (identical(input$preset, "custom")) c(input$win_center, input$win_width) else input$preset
    res <- dicomtk::dicom_describe_image(f, llm = active_llm(), window = win_arg)
    ai_text(res)
  })

  shiny::observeEvent(input$btn_report, {
    f <- current_file()
    shiny::req(file.exists(f))
    ai_text("Generating structured radiology report...")
    win_arg <- if (identical(input$preset, "custom")) c(input$win_center, input$win_width) else input$preset
    rpt <- dicomtk::dicom_report(f, llm = active_llm(), window = win_arg)
    ai_text(attr(rpt, "report_text"))
  })

  shiny::observeEvent(input$btn_ask, {
    f <- current_file()
    shiny::req(file.exists(f), nzchar(trimws(input$ai_question)))
    ai_text("Querying LLM...")
    res <- dicomtk::dicom_ask(f, question = input$ai_question, llm = active_llm())
    ai_text(res)
  })

  output$ai_output <- shiny::renderText({
    ai_text()
  })
}

shiny::shinyApp(ui = ui, server = server)
