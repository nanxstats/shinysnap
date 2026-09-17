# Get started with shinysnap

shinysnap lets users of a Shiny app save their work and pick it up
later: it takes a *snapshot* of the running app (the input values plus
any server-side values you register), writes it to a plain JSON file
that can be shared and kept under version control, and restores it into
another session without a page reload and without
[`shiny::enableBookmarking()`](https://rdrr.io/pkg/shiny/man/enableBookmarking.html).

The word “snapshot” is used in the sense of a virtual machine or file
system snapshot: a saved state you can write to a file, share, and
restore later. It has nothing to do with snapshot *testing*
(`expect_snapshot` in testthat and shinytest2) or with screenshots.

## A minimal app

Two UI helpers and two server calls are all it takes:

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

Clicking **Save state** downloads a `.json` file with every input that
is currently on the page. Uploading that file later, in any session,
puts the app back into that state: the select is applied first, the
dynamic UI it controls re-renders, and the inputs inside it receive
their values as soon as they exist. You never write timing code.

## The file

Snapshot files are meant to be read by people. Numbers are written with
the fewest digits that read back to the same value, and everything JSON
cannot express directly (dates, matrices, `NA`, the type of an empty
vector) uses a small typed wrapper. This is what a file looks like:

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

Reading it back gives the same R values, so hand-editing a file and
restoring it is a supported workflow:

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

- **Inputs** that are on the page, by fully namespaced id. Values of
  inputs whose dynamic UI has been removed are dropped, so the file
  describes the UI as the user saw it. Action buttons, passwords, and
  file uploads are never stored as input values (uploads can travel in a
  zip bundle, see
  [`snap_write()`](https://nanx.me/shinysnap/reference/snap_write.md)).
- **Values** from the `reactiveValues` you register with
  [`snap_track()`](https://nanx.me/shinysnap/reference/snap_track.md),
  plus whatever your
  [`snap_on_save()`](https://nanx.me/shinysnap/reference/snap_on_save.md)
  hooks add.
- The app name and version, so a restore can refuse files from another
  app and migrate files from an older version.

## The before and after

Apps that save state by hand usually end up with something like this:
`reactiveValuesToList(input)` into an `.rds` file, and on upload a loop
of `session$sendInputMessage()` calls, a special case for matrix inputs,
and, because inputs inside
[`renderUI()`](https://rdrr.io/pkg/shiny/man/renderUI.html) do not exist
yet when the first messages are sent, staggered delays.

``` r

# Before: a hand-rolled restore (abridged)
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

With shinysnap the same app needs no delays, no matrix special case, and
no per-field fallbacks:

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

What disappeared and why:

- The delays: values for inputs that are not on the page yet wait in the
  browser and are applied the moment the input is bound, and dynamic UI
  that re-renders during the restore is built with the restored values
  already in place (see
  [`vignette("dynamic-ui")`](https://nanx.me/shinysnap/articles/dynamic-ui.md)).
- The matrix special case: the value of every input is turned into the
  message its binding understands by a *restorer*; shinysnap ships them
  for shiny, bslib, and shinyMatrix inputs (see
  [`vignette("custom-inputs")`](https://nanx.me/shinysnap/articles/custom-inputs.md)).
- The [`is.null()`](https://rdrr.io/r/base/NULL.html) fallbacks: the
  `migrate` hook is the one place where defaults for values introduced
  after a file was saved belong.
- The `.rds` file: JSON is readable, diffable, and safe to open (see
  [`vignette("format-spec")`](https://nanx.me/shinysnap/articles/format-spec.md)).

## Learn more

- [`vignette("dynamic-ui")`](https://nanx.me/shinysnap/articles/dynamic-ui.md):
  how a restore reaches inputs inside dynamic UI, and how to read the
  restore report.
- [`vignette("custom-inputs")`](https://nanx.me/shinysnap/articles/custom-inputs.md):
  restoring inputs from other packages.
- [`vignette("format-spec")`](https://nanx.me/shinysnap/articles/format-spec.md):
  the file format.
- [`vignette("migrating-from-bookmarks")`](https://nanx.me/shinysnap/articles/migrating-from-bookmarks.md):
  shinysnap next to
  [`enableBookmarking()`](https://rdrr.io/pkg/shiny/man/enableBookmarking.html).
