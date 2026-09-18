# shinysnap

shinysnap lets users save their work in a Shiny app and return to it
later. It saves the app’s input values, along with any values you choose
to keep from the server, in a *snapshot file*. Users can download this
JSON file, share it, and upload it to restore their work in another
session.

Restoring a snapshot keeps the app running without reloading the page or
requiring
[`enableBookmarking()`](https://rdrr.io/pkg/shiny/man/enableBookmarking.html).
Inputs created by
[`renderUI()`](https://rdrr.io/pkg/shiny/man/renderUI.html) receive
their saved values as they appear. A report tells you which inputs were
restored, which were missing, and which failed.

Here, a snapshot means a copy of the app’s state. Snapshot tests in
testthat and shinytest2 serve a different purpose: they record output to
check for unexpected changes. shinysnap does not take screenshots.

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

You may already save your app’s state with `reactiveValuesToList(input)`
and an `.rds` file. Restoring it usually takes more work: you need to
send each value back to its input, handle inputs such as matrices, and
provide defaults for fields added since the file was saved. Dynamic
inputs add another problem because Shiny drops messages sent before an
input exists.

shinysnap handles these steps for you. You register the values to save
and provide functions to check files and update values from older
versions:

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

See
[`vignette("shinysnap")`](https://nanx.me/shinysnap/articles/shinysnap.md)
for the full comparison and
[`vignette("dynamic-ui")`](https://nanx.me/shinysnap/articles/dynamic-ui.md)
for how the restore works.

## Main functions

- [`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md) and
  [`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
  save and restore the app’s state. Each restore produces a report.
- [`snap_write()`](https://nanx.me/shinysnap/reference/snap_write.md)
  and [`snap_read()`](https://nanx.me/shinysnap/reference/snap_write.md)
  write and read JSON files, zip bundles that include uploaded files,
  and `.rds` files with `trust = TRUE`.
- [`snap_track()`](https://nanx.me/shinysnap/reference/snap_track.md),
  [`snap_on_save()`](https://nanx.me/shinysnap/reference/snap_on_save.md),
  [`snap_on_restore()`](https://nanx.me/shinysnap/reference/snap_on_restore.md),
  and
  [`snap_on_restored()`](https://nanx.me/shinysnap/reference/snap_on_restore.md)
  let you save values from the server and run code when a snapshot is
  taken or restored.
- [`snap_restorer()`](https://nanx.me/shinysnap/reference/snap_restorer.md)
  adds support for custom inputs. shinysnap includes support for inputs
  from shiny, bslib, and shinyMatrix.
- [`snap_download_button()`](https://nanx.me/shinysnap/reference/snap_download_button.md),
  [`snap_download_handler()`](https://nanx.me/shinysnap/reference/snap_download_button.md),
  [`snap_file_input()`](https://nanx.me/shinysnap/reference/snap_file_input.md),
  and
  [`snap_file_restore()`](https://nanx.me/shinysnap/reference/snap_file_input.md)
  add controls for saving and restoring snapshot files.
- [`snap_as_bookmark_url()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md),
  [`snap_as_test_inputs()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md),
  and [`snap_diff()`](https://nanx.me/shinysnap/reference/snap_diff.md)
  let you use snapshots with bookmarking,
  [`testServer()`](https://rdrr.io/pkg/shiny/man/testServer.html), and
  version control.

## License

MIT
