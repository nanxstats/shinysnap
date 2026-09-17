# Is a restore in flight?

`TRUE` from the moment
[`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
is called until the browser reports that the restore has settled (or
timed out), `FALSE` otherwise. Inside a reactive context the result is
reactive, so observers and outputs can react to the end of a restore;
outside one it is a plain value.

## Usage

``` r
snap_is_restoring(session = shiny::getDefaultReactiveDomain())
```

## Arguments

- session:

  The Shiny session. Defaults to the current session.

## Value

A logical scalar.

## Details

Use it to keep expensive observers from running on every intermediate
value during a restore, and to run something once the state is complete.

## Examples

``` r
if (interactive()) {
  library(shiny)

  server <- function(input, output, session) {
    observeEvent(input$n, {
      if (snap_is_restoring()) {
        return()
      }
      message("user changed n to ", input$n)
    })
  }
}
```
