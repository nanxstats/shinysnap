# Get started with shinysnap

shinysnap lets users save their work in a Shiny app and return to it
later. A *snapshot* contains the app’s input values and any values you
choose to keep from the server. Users can download it as a JSON file,
share it, and upload it to restore their work in another session. The
app stays open throughout the restore. You don’t need
[`shiny::enableBookmarking()`](https://rdrr.io/pkg/shiny/man/enableBookmarking.html).

Here, a snapshot means a copy of the app’s state. Snapshot tests in
testthat and shinytest2 serve a different purpose: they record output to
check for unexpected changes. shinysnap does not take screenshots.

## A minimal app

Add a download button and a file input to the UI, then connect them to
handlers in the server function:

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

Click **Save state** to download a `.json` file with the current input
values. Upload it later to restore those values in the same app. For
example, a snapshot with `model = "complex"` selects that model, which
creates the `k` slider. The slider then receives its saved value. You
don’t need to add delays to wait for it to appear.

## The file

You can read snapshot files in a text editor. Numbers use the fewest
digits needed to preserve their value. Values that JSON cannot represent
directly, such as dates, matrices, `NA`, and empty vectors, include
extra fields that record their type. Here’s an example:

``` r

library(shinysnap)

snap <- list(
  app = list(name = "demo", version = "1.0.0"),
  created = "2026-09-16T18:22:03Z",
  inputs = list(
    dates = as.Date(c("2024-01-01", "2024-03-01")),
    model = "complex",
    n = 100L,
    rate = 0.025,
    weights = c(0.5, 0.75)
  ),
  values = list(prefs = list(digits = 3L, scientific = FALSE))
)
cat(snap_serialize(snap))
#> {
#>   "format": 1,
#>   "app": {"name": "demo", "version": "1.0.0"},
#>   "created": "2026-09-16T18:22:03Z",
#>   "producer": {"shinysnap": "0.1.0", "shiny": "1.14.0", "r": "4.6.1"},
#>   "inputs": {
#>     "dates": {"$type": "Date", "value": ["2024-01-01", "2024-03-01"]},
#>     "model": "complex",
#>     "n": 100,
#>     "rate": 0.025,
#>     "weights": [0.5, 0.75]
#>   },
#>   "values": {"prefs": {"digits": 3, "scientific": false}},
#>   "bindings": {},
#>   "meta": {}
#> }
```

Reading the file gives you the same R values. You can also edit the file
in a text editor before restoring it:

``` r

text <- snap_serialize(snap)
back <- snap_unserialize(text)
str(snap_inputs(back))
#> List of 5
#>  $ dates  : Date[1:2], format: "2024-01-01" "2024-03-01"
#>  $ model  : chr "complex"
#>  $ n      : int 100
#>  $ rate   : num 0.025
#>  $ weights: num [1:2] 0.5 0.75
```

## What gets saved

- **Inputs** that are on the page, identified by their full ids,
  including any module prefixes. Inputs whose UI has been removed are
  left out. Action buttons, passwords, and file uploads are never stored
  as input values. You can include uploaded files in a zip bundle with
  [`snap_write()`](https://nanx.me/shinysnap/reference/snap_write.md).
- **Values** from the `reactiveValues` you register with
  [`snap_track()`](https://nanx.me/shinysnap/reference/snap_track.md),
  plus whatever your
  [`snap_on_save()`](https://nanx.me/shinysnap/reference/snap_on_save.md)
  hooks add.
- The **app name and version**, so shinysnap can reject files from
  another app and run your migration code for files from an older
  version.

## Replacing your own restore code

If you already save your app’s state with `reactiveValuesToList(input)`
and an `.rds` file, your restore code may look something like this. It
sends each saved value back to its input, handles matrices separately,
and provides defaults for fields added since the file was saved. It also
adds delays to wait for inputs created by
[`renderUI()`](https://rdrr.io/pkg/shiny/man/renderUI.html).

``` r

# Before: restoring values manually (some code omitted)
observeEvent(input$restore_file, {
  saved <- readRDS(input$restore_file$datapath)
  is_matrix <- vapply(saved$inputs, is.matrix, logical(1))
  for (id in names(saved$inputs)[!is_matrix]) {
    session$sendInputMessage(id, list(value = saved$inputs[[id]]))
  }
  for (id in names(saved$inputs)[is_matrix]) {
    updateMatrixInput(session, id, saved$inputs[[id]])
  }
  prefs$digits <- saved$prefs$digits
  prefs$scientific <- if (is.null(saved$prefs$scientific)) FALSE else saved$prefs$scientific
  # Inputs inside renderUI() do not exist yet: guess how long they take.
  shinyjs::delay(500, {
    for (id in c("detail_k", "detail_note")) {
      if (!is.null(saved$inputs[[id]])) {
        session$sendInputMessage(id, list(value = saved$inputs[[id]]))
      }
    }
  })
  shinyjs::delay(1500, {
    # ... another wave for the inputs that appear after those ...
  })
})
```

With shinysnap, you register the values to save and provide functions to
check files and update values from older versions:

``` r

# After
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

shinysnap handles the remaining work:

- It waits for dynamic inputs to appear before restoring their values.
  Inputs created during a restore can also start with their saved values
  already in place. See
  [`vignette("dynamic-ui")`](https://nanx.me/shinysnap/articles/dynamic-ui.md).
- It converts each saved value into the message its input expects. The
  functions that do this are called *restorers*. shinysnap includes them
  for shiny, bslib, and shinyMatrix. See
  [`vignette("custom-inputs")`](https://nanx.me/shinysnap/articles/custom-inputs.md).
- It calls your `migrate` function so you can supply defaults for fields
  added since the file was saved. This keeps those checks in one place.
- It writes JSON files that you can read, compare in version control,
  and open safely. See
  [`vignette("format-spec")`](https://nanx.me/shinysnap/articles/format-spec.md).

## Learn more

- [`vignette("dynamic-ui")`](https://nanx.me/shinysnap/articles/dynamic-ui.md):
  how a restore reaches inputs inside dynamic UI, and how to read the
  restore report.
- [`vignette("custom-inputs")`](https://nanx.me/shinysnap/articles/custom-inputs.md):
  restoring inputs from other packages.
- [`vignette("format-spec")`](https://nanx.me/shinysnap/articles/format-spec.md):
  the file format.
- [`vignette("migrating-from-bookmarks")`](https://nanx.me/shinysnap/articles/migrating-from-bookmarks.md):
  using shinysnap with Shiny bookmarks.
