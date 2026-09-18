# shinysnap <a href="https://nanx.me/shinysnap/"><img src="man/figures/logo.png" align="right" height="139" alt="shinysnap website" /></a>

<!-- badges: start -->
[![R-CMD-check](https://github.com/nanxstats/shinysnap/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/nanxstats/shinysnap/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

shinysnap lets users save their work in a Shiny app and return to it later.
It saves the app's input values, along with any values you choose to keep
from the server, in a *snapshot file*. Users can download this JSON file,
share it, and upload it to restore their work in another session.

Restoring a snapshot keeps the app running without reloading the page or
requiring `enableBookmarking()`. Inputs created by `renderUI()` receive
their saved values as they appear. A report tells you which inputs were
restored, which were missing, and which failed.

Here, a snapshot means a copy of the app's state. Snapshot tests in
testthat and shinytest2 serve a different purpose: they record output
to check for unexpected changes. shinysnap does not take screenshots.

## Installation

You can install the development version of shinysnap from GitHub with:

``` r
# install.packages("pak")
pak::pak("nanxstats/shinysnap")
```

## Example

This app lets users download a snapshot file and upload it to restore
their work:

``` r
library(shiny)
library(shinysnap)

ui <- fluidPage(
  sliderInput("n", "Sample size", 10, 500, 100),
  selectInput("model", "Model", c("simple", "complex")),
  uiOutput("model_inputs"),
  snap_download_button("save"),
  snap_file_input("restore")
)

server <- function(input, output, session) {
  snap_enable(app = "demo", version = "1.0.0")

  output$model_inputs <- renderUI({
    if (input$model == "simple") {
      numericInput("rate", "Rate", 0.05)
    } else {
      sliderInput("k", "k", 1, 10, 3)
    }
  })

  snap_download_handler("save")
  snap_file_restore("restore")
}

shinyApp(ui, server)
```

You can open the saved file in a text editor:

``` json
{
  "format": 1,
  "app": {"name": "demo", "version": "1.0.0"},
  "created": "2026-09-16T18:22:03Z",
  "producer": {"shinysnap": "0.1.0", "shiny": "1.14.0", "r": "4.6.1"},
  "inputs": {
    "k": 3,
    "model": "complex",
    "n": 100
  },
  "values": {},
  "bindings": {
    "k": "shiny.sliderInput",
    "model": "shiny.selectInput",
    "n": "shiny.sliderInput"
  },
  "meta": {}
}
```

Uploading this file selects the complex model, which creates the `k`
slider. The slider then receives its saved value.

## Before and after

You may already save your app's state with `reactiveValuesToList(input)`
and an `.rds` file. Restoring it usually takes more work: you need to send
each value back to its input, handle inputs such as matrices, and provide
defaults for fields added since the file was saved. Dynamic inputs add
another problem because Shiny drops messages sent before an input exists.

shinysnap handles these steps for you. You register the values to save
and provide functions to check files and update values from older versions:

``` r
snap_enable(app = "myapp", version = "2.4.0", exclude = c("^btn_", "^nav$"))
snap_track(prefs)
snap_track(main_options)

snap_download_handler(c("btn_save_main", "btn_save_details"))

snap_file_restore(
  c("btn_restore_main", "btn_restore_details"),
  validate = function(snap) {
    if (is.null(snap$inputs$model)) stop("This file was not saved by this app.")
  },
  migrate = function(snap, from) {
    if (is.null(snap$values$prefs$scientific)) snap$values$prefs$scientific <- FALSE
    snap
  }
)
```

See `vignette("shinysnap")` for the full comparison and
`vignette("dynamic-ui")` for how the restore works.

## Main functions

- `snap_take()` and `snap_restore()` save and restore the app's state.
  Each restore produces a report.
- `snap_write()` and `snap_read()` write and read JSON files, zip bundles
  that include uploaded files, and `.rds` files with `trust = TRUE`.
- `snap_track()`, `snap_on_save()`, `snap_on_restore()`,
  and `snap_on_restored()` let you save values from the server and run
  code when a snapshot is taken or restored.
- `snap_restorer()` adds support for custom inputs. shinysnap includes
  support for inputs from shiny, bslib, and shinyMatrix.
- `snap_download_button()`, `snap_download_handler()`,
  `snap_file_input()`, and `snap_file_restore()` add controls for saving
  and restoring snapshot files.
- `snap_as_bookmark_url()`, `snap_as_test_inputs()`, and `snap_diff()`
  let you use snapshots with bookmarking, `testServer()`, and version control.

## License

MIT
