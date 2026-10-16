# inst/shiny/viewer/app.R
# Interactive Shiny DICOM Viewer for dicomtk

ui <- shiny::fluidPage(
  shiny::titlePanel("dicomtk — Interactive DICOM Viewer"),
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
        choices = c("Radiological Gray" = "gray", "Viridis" = "viridis",
                    "Inferno" = "inferno", "Magma" = "magma", "Plasma" = "plasma"),
        selected = "gray"
      ),
      shiny::checkboxInput("annotate", "Show HUD Overlay", value = TRUE),
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
          "DICOM Header Inspector",
          shiny::tableOutput("header_table")
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
    init_path <- getOption("dicomtk.viewer.path",
                           system.file("extdata", "example.dcm", package = "dicomtk"))
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
}

shiny::shinyApp(ui = ui, server = server)
