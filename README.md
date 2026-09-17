# shinysnap <a href="https://nanx.me/shinysnap/"><img src="man/figures/logo.png" align="right" height="139" alt="shinysnap website" /></a>

<!-- badges: start -->
[![R-CMD-check](https://github.com/nanxstats/shinysnap/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/nanxstats/shinysnap/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

shinysnap saves and restores the state of a running Shiny app. It takes a
*snapshot* (the input values plus any server-side values you register),
writes it to a plain JSON file that users can keep, share, and diff, and
restores it later into a different session, without a page reload and
without `enableBookmarking()`. Inputs inside `renderUI()` that appear
during the restore receive their values as soon as they exist, so no
timing code is needed, and a report says what was applied, what never
appeared, and what failed.

The word "snapshot" is used in the sense of a virtual machine or file
system snapshot: a saved state you can write to a file and restore later.
It has nothing to do with snapshot *testing* (`expect_snapshot` in
testthat and shinytest2) or with screenshots.

## Installation

You can install the development version of shinysnap from GitHub with:

``` r
# install.packages("pak")
pak::pak("nanxstats/shinysnap")
```

## Example

A complete app with a save button and a restore upload:

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

The saved file is readable:

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

Uploading it puts the app back into that state: the select is applied,
the dynamic UI it controls re-renders, and the slider inside it gets its
value the moment it exists.

## Before and after

Apps that do this by hand collect `reactiveValuesToList(input)` into an
`.rds` file and, on upload, loop over `session$sendInputMessage()`, add a
special case for matrix inputs, guard every server-side value with
`is.null()` for files saved by older versions, and send the values of
dynamic inputs in waves of `shinyjs::delay()`, because messages for inputs
that are not on the page yet are dropped silently. With shinysnap the
server side of such an app becomes:

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

## What is in the box

* `snap_take()`, `snap_restore()`: the snapshot and the restore
  transaction, with a report.
* `snap_write()`, `snap_read()`: JSON files, zip bundles that keep uploaded
  files, and (behind `trust = TRUE`) `.rds`.
* `snap_track()`, `snap_on_save()`, `snap_on_restore()`,
  `snap_on_restored()`: server-side values and hooks shaped like shiny's
  bookmarking hooks.
* `snap_restorer()`: how an input's value becomes the message its binding
  understands; built-ins for shiny, bslib, and shinyMatrix inputs.
* `snap_download_button()`, `snap_download_handler()`,
  `snap_file_input()`, `snap_file_restore()`: the UI boilerplate.
* `snap_as_bookmark_url()`, `snap_as_test_inputs()`, `snap_diff()`:
  interop with bookmarking, `testServer()`, and version control.

## License

MIT
