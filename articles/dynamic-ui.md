# Restoring dynamic UI

This vignette explains why restoring state into an app with
[`renderUI()`](https://rdrr.io/pkg/shiny/man/renderUI.html) is hard,
what shinysnap does about it, and how to read the report that every
restore produces.

## Why hand-rolled restores need delays

`session$sendInputMessage(id, list(value = v))` is what every
`update*Input()` function calls. On the client, Shiny looks for a
*bound* input with that id and, if it finds none, drops the message.
Nothing is logged on either side. An input that lives inside a
[`renderUI()`](https://rdrr.io/pkg/shiny/man/renderUI.html) which has
not rendered yet is exactly such an input, so a restore that sends every
value at once loses the values of all dynamic inputs. The usual
workaround is to send those values later, after a guessed delay, one
wave per level of dynamic UI. The guesses are fragile, and a wave that
arrives too early is still dropped silently.

## What shinysnap does instead

A restore is a *transaction* between the server and the client script
that shinysnap adds to the page.

1.  The server writes the tracked values back into your
    `reactiveValues`, runs the
    [`snap_on_restore()`](https://nanx.me/shinysnap/reference/snap_on_restore.md)
    hooks, and sends **all** input values to the browser in one message,
    each already turned into the payload its input binding understands.
2.  The client applies every value whose input is on the page right
    away, through the binding’s `receiveMessage()`, and keeps the others
    pending.
3.  Whenever Shiny binds a new input (because a `uiOutput` rendered or
    re-rendered), the client checks the pending list and applies the
    value for that id. The value of the select that controls a branch is
    applied first, the branch renders, its inputs bind, their values are
    applied, a nested branch renders, and so on, without any timing
    configuration.
4.  While the transaction is in flight, the server also primes shiny’s
    own
    [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html)
    mechanism with the snapshot’s values. Every built-in input
    constructor calls
    [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html),
    so dynamic UI that renders during the restore is built with the
    restored value *in the HTML*: no flash of defaults, and observers
    watching those inputs fire once, with the right value. The client
    recognises such inputs and reports them as `constructed` rather than
    applying the value a second time.
5.  The transaction settles once the page has been quiet for a moment
    (no busy state, no new UI, no new values, 0.3 seconds by default) or
    after the timeout (10 seconds by default). The client then reports
    one status per input.

One detail matters for anyone who has tried to do this themselves: Shiny
sends a newly bound input’s *initial* value to the server right after it
fires the bound event. A value applied synchronously from that event is
overwritten by the default a moment later. shinysnap defers each apply
past that point.

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
| `reapplied` | the input re-rendered during the restore and received the value again (only without the accelerator) |
| `missing` | the input never appeared before the restore settled |
| `failed` | the binding raised an error; `detail` has the message |
| `mismatched` | applied, but the input reports a different value afterwards, for example a select whose choices do not contain it |
| `skipped` | excluded, or its restorer chose not to restore it (passwords, buttons, uploads) |

The attributes `txn`, `elapsed`, `settled`, and `timed_out` describe the
transaction. `missing` and `failed` inputs produce one consolidated
warning by default; `snap_restore(unknown = "skip")` silences it and
`unknown = "error"` rejects the promise instead.

A `missing` row is the normal outcome for an input that a newer version
of the app no longer has, or for an input whose UI is not reachable in
the restored state. Two situations are worth knowing about:

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

[`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
returns immediately with a handle; the report arrives later. Three ways
to use it:

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

The handle is deliberately *not* a promise. Shiny waits for a promise
that an observer returns before it flushes, and the report can only
arrive once the browser has seen the page go quiet, so an observer that
returned the promise would stall its own restore. Keep promises inside
the observer, or end the observer with `NULL` as above when its last
expression is a
[`promises::then()`](https://rstudio.github.io/promises/reference/then.html)
call.

## Reacting during a restore

[`snap_is_restoring()`](https://nanx.me/shinysnap/reference/snap_is_restoring.md)
is `TRUE` from the moment
[`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
is called until the report arrives. Use it to keep expensive observers
quiet while intermediate values stream in, and to run something once the
state is complete:

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

- Inputs with a rate policy (text inputs debounce, sliders throttle) may
  lag the browser by a few hundred milliseconds. A snapshot taken from a
  download handler runs after the click has reached the server, which in
  practice is later than that; do not add delays.
- A second
  [`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
  while one is in flight cancels the first, whose promise rejects with a
  condition of class `shinysnap_cancelled`.
- `snap_restore(use_restore_context = FALSE)` turns the
  [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html)
  accelerator off. Everything still ends in the right state; dynamic
  inputs are then `applied` or `reapplied` instead of `constructed`, and
  their observers see the default value before the restored one. It
  exists to isolate problems, not for regular use.
