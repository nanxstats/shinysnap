# Save-state button and its download handler

`snap_download_button()` is a
[`downloadButton()`](https://rdrr.io/pkg/shiny/man/downloadButton.html)
with the client script attached. `snap_download_handler()` defines the
matching download: it takes a snapshot with
[`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md) when
the button is clicked and writes it with
[`snap_write()`](https://nanx.me/shinysnap/reference/snap_write.md).
Together they replace the usual
[`downloadHandler()`](https://rdrr.io/pkg/shiny/man/downloadHandler.html)
boilerplate.

## Usage

``` r
snap_download_button(
  id,
  label = "Save state",
  icon = shiny::icon("download"),
  class = NULL,
  ...
)

snap_download_handler(
  id,
  filename = "state",
  format = c("json", "zip"),
  ...,
  snapshot = NULL,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- id:

  The output id of the button. `snap_download_handler()` accepts a
  vector of ids, so that several buttons (for example one per tab) share
  one definition.

- label, icon, class, ...:

  Passed on to
  [`shiny::downloadButton()`](https://rdrr.io/pkg/shiny/man/downloadButton.html).
  In `snap_download_handler()`, `...` is passed on to
  [`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md).

- filename:

  The file name without extension: a string, a function, or a reactive
  (for example a text input where the user names the file). It is
  reduced to the characters `A-Z a-z 0-9 . _ -`, falls back to `"state"`
  when empty, and gets the format's extension appended.

- format:

  The file format: `"json"` (the default) or `"zip"` for a bundle that
  includes uploaded files (see
  [`snap_write()`](https://nanx.me/shinysnap/reference/snap_write.md)).

- snapshot:

  `NULL` to take a snapshot when the button is clicked (the default), a
  snapshot object, or a function or reactive returning one.

- session:

  The Shiny session. Defaults to the current session.

## Value

`snap_download_button()` returns a tag. `snap_download_handler()`
returns the ids invisibly.

## Examples

``` r
if (interactive()) {
  library(shiny)

  ui <- fluidPage(
    sliderInput("n", "n", 1, 100, 50),
    textInput("filename", "File name", "state"),
    snap_download_button("save")
  )

  server <- function(input, output, session) {
    snap_enable(app = "demo", version = "1.0.0", exclude = "^filename$")
    snap_download_handler("save", filename = reactive(input$filename))
  }

  shinyApp(ui, server)
}
```
