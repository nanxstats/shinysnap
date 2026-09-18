# Restoring dynamic UI

Inputs created by
[`renderUI()`](https://rdrr.io/pkg/shiny/man/renderUI.html) may not
exist when a restore starts. This vignette explains how shinysnap waits
for them and how to read the report that each restore produces.

## Why dynamic inputs need special handling

Shiny’s `update*Input()` functions send messages through
`session$sendInputMessage()`. In the browser, Shiny looks for an input
with the given id that it has *bound*, or connected to the server. If
there is no such input, Shiny drops the message without logging
anything.

This causes problems when you restore inputs created by
[`renderUI()`](https://rdrr.io/pkg/shiny/man/renderUI.html). Any message
sent before the input is ready is lost. You can try adding delays, but a
delay that works on one machine may be too short on another. Nested
dynamic UI makes this harder because each set of inputs must wait for
the previous set.

## How shinysnap restores inputs

The server and shinysnap’s browser script work together during a
restore:

1.  The server writes the tracked values back into your
    `reactiveValues`, runs the
    [`snap_on_restore()`](https://nanx.me/shinysnap/reference/snap_on_restore.md)
    hooks, and sends **all** input values to the browser in one message.
    Each value is converted to the format its input binding expects.
2.  The client applies every value whose input is on the page right
    away, through the binding’s `receiveMessage()`, and keeps the others
    pending.
3.  Whenever Shiny binds an input, the browser script applies the saved
    value for that id. For example, restoring a select input may create
    another group of inputs. Those inputs receive their values when they
    appear, even if they create further inputs in turn. An input that is
    recreated during the restore also receives its saved value again.
4.  During the restore, the server makes the saved values available to
    Shiny’s
    [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html)
    function. Shiny’s input constructors call this function, so new
    inputs can start with their saved values already in the HTML. This
    avoids briefly showing defaults and triggering observers with those
    defaults. The browser reports these inputs as `constructed` without
    applying their values again.
5.  The restore finishes once the page has been quiet for 0.3 seconds by
    default: Shiny is not busy and no UI or values are changing. It also
    has a timeout of 10 seconds by default. The browser then reports a
    status for every input.

The order of events matters here. Shiny sends a new input’s initial
value to the server just after the `shiny:bound` event. Applying a saved
value inside that event handler would let the initial value overwrite
it. shinysnap waits until that step has finished before applying the
saved value.

## The report

[`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
returns a handle whose promise resolves to a report, and
[`snap_on_restored()`](https://nanx.me/shinysnap/reference/snap_on_restore.md)
hooks receive the same report. It is a data frame with one row per
input:

    #> <shinysnap_report> 6 input(s), settled after 0.41 s
    #>   applied: 2, constructed: 3, missing: 1
    #>      id      status               binding detail
    #>  method     applied     shiny.selectInput
    #>     b_k constructed     shiny.numberInput
    #>  b_text constructed      shiny.textInput
    #>  shared constructed     shiny.numberInput
    #>  a_rate     applied     shiny.sliderInput
    #>   ghost     missing

| status | meaning |
|----|----|
| `applied` | sent to an input that was on the page |
| `constructed` | the input appeared during the restore already carrying the value (via [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html)) |
| `reapplied` | the input was recreated during the restore and received the value again, without help from [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html) |
| `missing` | the input never appeared before the restore settled |
| `failed` | the binding raised an error; `detail` has the message |
| `mismatched` | applied, but the input reports a different value afterwards, for example a select whose choices do not contain it |
| `skipped` | excluded, or its restorer chose not to restore it (passwords, buttons, uploads) |

The attributes `txn`, `elapsed`, `settled`, and `timed_out` record the
restore id, duration, and whether it finished after a quiet period or a
timeout. `missing` and `failed` inputs produce a single warning by
default; `snap_restore(unknown = "skip")` silences it and
`unknown = "error"` rejects the promise instead.

A `missing` row can mean the input was removed in a newer version of the
app, or that the saved state does not display its UI. Two common cases
are:

- Outputs on hidden tabs are suspended by default, so a
  [`renderUI()`](https://rdrr.io/pkg/shiny/man/renderUI.html) on a tab
  the user is not looking at does not render and its inputs stay
  `missing`. Use
  `outputOptions(output, "id", suspendWhenHidden = FALSE)` for outputs a
  restore must reach, or include the tab’s id in the snapshot so the
  restore switches to it.
- Inputs created only from JavaScript with `Shiny.setInputValue()` (plot
  clicks, table selections) are not bound inputs and cannot be restored
  through a binding; they are not captured in the first place.

## Working with the promise

The restore continues after
[`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
returns. Its return value is a *handle*: a list containing the restore
id and a promise for the report. You can receive the report through a
callback, a hook, or the promise:

``` r

observeEvent(input$go, {
  # 1. A callback
  snap_restore(input$json, on_done = function(report) print(report))

  # 2. A hook that sees every restore in the session
  snap_on_restored(function(state, report) message(nrow(report), " inputs"))

  # 3. The promise itself
  handle <- snap_restore(input$json)
  promises::then(handle$promise, function(report) print(report))
  NULL
})
```

If an observer returns a promise, Shiny waits for it to resolve before
sending updates to the browser. But the restore needs those updates to
finish and produce its report. Returning the restore’s promise from an
observer would therefore leave both waiting indefinitely.

Returning the handle is safe because it is an ordinary list. If you use
[`promises::then()`](https://rstudio.github.io/promises/reference/then.html)
inside an observer, end the observer with `NULL` as above so it does not
return a promise.

## Reacting during a restore

[`snap_is_restoring()`](https://nanx.me/shinysnap/reference/snap_is_restoring.md)
is `TRUE` from the moment
[`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
is called until the report arrives. Use it to skip expensive
calculations while inputs are still changing, then run them when the
restore finishes:

``` r

observeEvent(input$n, {
  if (snap_is_restoring()) {
    return()
  }
  fit()
})

observe({
  if (!snap_is_restoring()) fit()
})
```

## Notes on timing

- Some inputs wait briefly before sending changes to the server. Text
  inputs wait for a pause in typing; sliders limit how often they send
  updates. A download handler takes its snapshot after the click reaches
  the server, which in practice gives these updates time to arrive. You
  don’t need to add delays.
- Calling
  [`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
  during a restore cancels the first restore, whose promise rejects with
  a condition of class `shinysnap_cancelled`.
- Use `snap_restore(use_restore_context = FALSE)` when debugging to
  disable the use of
  [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html).
  Dynamic inputs still receive their saved values, but are reported as
  `applied` or `reapplied` instead of `constructed`. Their observers see
  the default value before the saved one.
