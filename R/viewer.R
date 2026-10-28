#' Launch Interactive Shiny DICOM Viewer
#'
#' Launches a Shiny web application for interactive exploration of DICOM files
#' and multi-slice series, featuring slice scrolling, CT window/level presets,
#' custom Window Center & Width sliders, colormap toggling, and a searchable
#' DICOM header tag inspector.
#'
#' @param path Optional file or directory path to preload in the viewer. Defaults
#'   to the bundled example DICOM file.
#' @param launch.browser Logical. Launch in browser/viewer pane. Default is
#'   `interactive()`.
#' @param ... Additional arguments passed to [shiny::runApp()].
#'
#' @return Invisibly returns the Shiny application object (or runs the app if
#'   interactive).
#' @export
#' @examples
#' if (interactive()) {
#'   dicom_viewer()
#' }
dicom_viewer <- function(path = NULL, launch.browser = interactive(), ...) {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    rlang::abort("Package `shiny` is required for `dicom_viewer()`. Install it with `install.packages('shiny')`.")
  }
  if (is.null(path)) {
    path <- system.file("extdata", "example.dcm", package = "dicomtk")
  }
  app_dir <- system.file("shiny", "viewer", package = "dicomtk")
  if (!nzchar(app_dir) || !dir.exists(app_dir)) {
    app_dir <- file.path("inst", "shiny", "viewer")
  }
  old_opt <- options(dicomtk.viewer.path = normalizePath(path, mustWork = FALSE))
  on.exit(options(old_opt), add = TRUE)
  shiny::runApp(app_dir, launch.browser = launch.browser, ...)
}
