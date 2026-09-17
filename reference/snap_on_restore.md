# Register hooks that run around a restore

`snap_on_restore()` registers a function that
[`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
calls after the tracked values have been written back and before the
input values are sent to the browser. `snap_on_restored()` registers a
function that runs once the browser reports that the restore has
settled. Both receive a `state` list with `inputs` (the named list of
input values being restored), `values` (the `values` section of the
file), `snapshot` (the whole snapshot), and `txn` (the transaction id);
the `restored` hook also receives the restore report.

## Usage

``` r
snap_on_restore(fn, session = shiny::getDefaultReactiveDomain())

snap_on_restored(fn, session = shiny::getDefaultReactiveDomain())
```

## Arguments

- fn:

  A function taking `state` (and, for `snap_on_restored()`, `report`).

- session:

  The Shiny session. Defaults to the current session.

## Value

A function that removes the hook again, invisibly.

## Details

Inside a module, the hooks see only the module's inputs and values, with
the namespace prefix removed, and only the module's rows of the report.

Errors raised by a hook abort the restore and reject its promise.

## Examples

``` r
if (interactive()) {
  library(shiny)

  server <- function(input, output, session) {
    snap_on_restore(function(state) {
      message("restoring ", length(state$inputs), " inputs")
    })
    snap_on_restored(function(state, report) {
      print(report)
    })
  }
}
```
