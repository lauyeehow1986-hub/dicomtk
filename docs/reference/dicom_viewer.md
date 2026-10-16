# Launch Interactive Shiny DICOM Viewer

Launches a Shiny web application for interactive exploration of DICOM
files and multi-slice series, featuring slice scrolling, CT window/level
presets, custom Window Center & Width sliders, colormap toggling, and a
searchable DICOM header tag inspector.

## Usage

``` r
dicom_viewer(path = NULL, launch.browser = interactive(), ...)
```

## Arguments

- path:

  Optional file or directory path to preload in the viewer. Defaults to
  the bundled example DICOM file.

- launch.browser:

  Logical. Launch in browser/viewer pane. Default is
  [`interactive()`](https://rdrr.io/r/base/interactive.html).

- ...:

  Additional arguments passed to
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html).

## Value

Invisibly returns the Shiny application object (or runs the app if
interactive).

## Examples

``` r
if (interactive()) {
  dicom_viewer()
}
```
