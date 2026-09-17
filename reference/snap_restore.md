# Restore a snapshot into the running app

Writes the snapshot's tracked values back into the registered
`reactiveValues`, runs the restore hooks, and sends the input values to
the browser, where the client script applies each one as soon as its
input is on the page. Inputs inside dynamic UI that appears (or
re-renders) during the restore receive their values without any timing
configuration; while the restore is in flight, shiny's
[`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html)
mechanism is primed so that dynamic UI is built with the restored values
directly.

## Usage

``` r
snap_restore(
  x,
  session = shiny::getDefaultReactiveDomain(),
  ...,
  inputs = TRUE,
  values = TRUE,
  include = NULL,
  exclude = NULL,
  validate = NULL,
  migrate = NULL,
  check_app = TRUE,
  unknown = c("warn", "skip", "error"),
  timeout = 10,
  settle = 0.3,
  use_restore_context = NULL,
  on_done = NULL
)
```

## Arguments

- x:

  A snapshot object, a file path, or JSON text.

- session:

  The Shiny session. Defaults to the current session.

- ...:

  Not used; arguments after `session` must be named.

- inputs, values:

  Restore the inputs / the tracked values? Set one to `FALSE` to restore
  only the other.

- include, exclude:

  Regular expressions matched against fully namespaced ids, in addition
  to those configured with
  [`snap_enable()`](https://nanx.me/shinysnap/reference/snap_enable.md).

- validate:

  A function of the snapshot that should
  [`stop()`](https://rdrr.io/r/base/stop.html) with a user-facing
  message when the file is not acceptable. Runs first.

- migrate:

  A function `function(snapshot, from_version)` returning a modified
  snapshot, for example filling in defaults for values introduced after
  `from_version` (the app version recorded in the file, or `NULL`). Runs
  after `validate`, before anything is touched.

- check_app:

  Refuse files whose app name differs from the one configured with
  [`snap_enable()`](https://nanx.me/shinysnap/reference/snap_enable.md)
  (only when both are known).

- unknown:

  What to do when inputs never appeared or failed: `"warn"` (one
  consolidated warning, the default), `"skip"` (nothing), or `"error"`
  (reject the promise).

- timeout:

  Seconds after which the browser stops waiting for inputs that have not
  appeared.

- settle:

  Seconds of quiet (no busy state, no new UI) after which the browser
  considers the restore complete.

- use_restore_context:

  Prime shiny's
  [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html)
  mechanism during the restore. Defaults to the value configured with
  [`snap_enable()`](https://nanx.me/shinysnap/reference/snap_enable.md).

- on_done:

  A function of the report, called when the restore settles; a
  convenience for code that does not want to work with promises.

## Value

A handle of class `shinysnap_restore`, invisibly: a list with the
transaction id in `txn` and a
[`promises::promise()`](https://rstudio.github.io/promises/reference/promise.html)
that resolves to the restore report in `promise`. The handle is
deliberately not a promise itself: shiny waits for a promise returned
from an observer before it flushes, and the report can only arrive after
the browser has finished applying the restore, so returning the promise
from an observer would stall the restore. Use `on_done`,
[`snap_on_restored()`](https://nanx.me/shinysnap/reference/snap_on_restore.md),
or `promises::then(handle$promise, ...)` to work with the report.

## Details

The function never blocks. It returns a promise that resolves to a
*restore report* once the browser reports that the page has settled (no
activity for `settle` seconds) or `timeout` seconds have passed. The
report is a data frame with one row per input and the columns `id`,
`status`, `binding`, and `detail`, plus the attributes `txn`, `elapsed`
(seconds), `settled`, and `timed_out`. Statuses:

- `applied`: sent to an input that was on the page.

- `constructed`: the input appeared during the restore already carrying
  the value, thanks to
  [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html).

- `reapplied`: the input re-rendered during the restore and received the
  value again.

- `missing`: the input never appeared before the restore settled.

- `failed`: the input's binding raised an error.

- `mismatched`: applied, but the input reports a different value
  afterwards (for example a select whose choices do not contain it).

- `skipped`: excluded, or its restorer chose not to restore it.

Preparation errors (an unreadable file, a failing `validate` or
`migrate` hook, a file from a different app) are raised immediately.
Problems during the transaction reject the promise: a second
`snap_restore()` cancels the first (condition class
`shinysnap_cancelled`), a failing hook, and, with `unknown = "error"`,
inputs that never appeared or failed.

## Examples

``` r
if (interactive()) {
  library(shiny)

  server <- function(input, output, session) {
    observeEvent(input$restore_from_text, {
      snap_restore(input$json, on_done = function(report) print(report))
    })
  }
}
```
