# Restore-state upload and its handler

`snap_file_input()` is a
[`fileInput()`](https://rdrr.io/pkg/shiny/man/fileInput.html) with the
client script attached. `snap_file_restore()` observes it: when a file
is uploaded it reads the snapshot with
[`snap_read()`](https://nanx.me/shinysnap/reference/snap_write.md), runs
`validate` and `migrate`, and calls
[`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md),
reporting problems to the user.

## Usage

``` r
snap_file_input(id, label = "Restore state", accept = c(".json", ".zip"), ...)

snap_file_restore(
  id,
  ...,
  validate = NULL,
  migrate = NULL,
  on_error = c("notify", "modal", "stop"),
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- id:

  The input id. `snap_file_restore()` accepts a vector of ids, so that
  several upload controls share one definition.

- label, accept, ...:

  Passed on to
  [`shiny::fileInput()`](https://rdrr.io/pkg/shiny/man/fileInput.html).
  In `snap_file_restore()`, `...` is passed on to
  [`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md).

- validate:

  A function of the snapshot that should
  [`stop()`](https://rdrr.io/r/base/stop.html) with a user-facing
  message when the file is not acceptable. Runs first.

- migrate:

  A function `function(snapshot, from_version)` returning a modified
  snapshot, for example filling in defaults for values introduced after
  `from_version` (the app version recorded in the file, or `NULL`). Runs
  after `validate`, before anything is touched.

- on_error:

  How to report a file that cannot be restored: a
  [`showNotification()`](https://rdrr.io/pkg/shiny/man/showNotification.html)
  (the default), a
  [`showModal()`](https://rdrr.io/pkg/shiny/man/showModal.html) dialog,
  or [`stop()`](https://rdrr.io/r/base/stop.html).

- session:

  The Shiny session. Defaults to the current session.

## Value

`snap_file_input()` returns a tag. `snap_file_restore()` returns the ids
invisibly.

## Examples

``` r
if (interactive()) {
  library(shiny)

  ui <- fluidPage(
    sliderInput("n", "n", 1, 100, 50),
    snap_download_button("save"),
    snap_file_input("restore")
  )

  server <- function(input, output, session) {
    snap_enable(app = "demo", version = "1.0.0")
    snap_download_handler("save")
    snap_file_restore("restore", validate = function(snap) {
      if (is.null(snap$inputs$n)) stop("This file does not contain `n`.")
    })
  }

  shinyApp(ui, server)
}
```
