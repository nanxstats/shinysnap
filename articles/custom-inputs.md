# Restoring custom inputs

Each Shiny input has an *input binding*: JavaScript code that connects
the HTML element to Shiny. shinysnap restores an input by sending its
binding the same message that the input’s `update*()` function would
send.

The default message is `{value: x}`, which works for most inputs. If an
input expects a different message, you can write a *restorer*: an R
function that converts the saved value into that message. This vignette
uses shinyMatrix to show how. It also shows how to convert messages in
JavaScript with an *adapter*.

## Supported inputs

Use
[`snap_restorers()`](https://nanx.me/shinysnap/reference/snap_restorer.md)
to list the bindings that have a restorer:

``` r

library(shinysnap)
snap_restorers()
#>                           name   scope
#> 1     shiny.checkboxGroupInput builtin
#> 2             shiny.radioInput builtin
#> 3            shiny.selectInput builtin
#> 4              shiny.dateInput builtin
#> 5         shiny.dateRangeInput builtin
#> 6            shiny.sliderInput builtin
#> 7          shiny.passwordInput builtin
#> 8      shiny.actionButtonInput builtin
#> 9       shiny.fileInputBinding builtin
#> 10             bslib.accordion builtin
#> 11               bslib.sidebar builtin
#> 12           bslib.task-button builtin
#> 13                  bslib.card builtin
#> 14   shinyMatrix.matrixNumeric builtin
#> 15 shinyMatrix.matrixCharacter builtin
```

Bindings not listed here receive `list(value = value)`. This includes
inputs from shinyWidgets and other packages. Check the binding’s
`receiveMessage()` method to see whether it accepts that message. If it
expects something else, follow the steps below to write a restorer.

## Writing a restorer

A restorer is a function of four arguments that returns the message to
send as a list, or `NULL` to skip the input:

``` r

function(id, value, binding, session) list(value = value)
```

- `id` is the full input id, including any module prefixes.
- `value` is the value stored in the snapshot, exactly what `input$id`
  returned when the snapshot was taken.
- `binding` is the name the JavaScript binding was registered under
  (`"shiny.sliderInput"`, `"shinyMatrix.matrixNumeric"`, …), as recorded
  in the snapshot’s `bindings` section.
- `session` is the session being restored.

Use
[`snap_restorer()`](https://nanx.me/shinysnap/reference/snap_restorer.md)
to register the function for a binding name or an input id. By default,
`session = NULL` makes the restorer available to all sessions. This is
useful in a package or an app’s `global.R`. Pass a session to limit the
restorer to that session.

shinysnap uses the first restorer it finds in this order:

1.  A restorer for the input id in the current session.
2.  A restorer for the binding in the current session.
3.  A global restorer for the input id, then for the binding.
4.  A restorer included with shinysnap.
5.  The default, `list(value = value)`.

A restorer must return the message so shinysnap can deliver it when the
input exists. Do not call `update*()` functions inside it: those use
`session$sendInputMessage()`, which drops messages for inputs that are
not on the page yet.

## Example: shinyMatrix

1.  Read the input’s `update*()` function and find the part that carries
    the value. For
    [`shinyMatrix::updateMatrixInput()`](https://inwtlab.github.io/shinyMatrix/reference/updateMatrixInput.html)
    that is:

    ``` r

    message <- list(value = list(
      data = value,
      rownames = rownames(value),
      colnames = colnames(value)
    ))
    session$sendInputMessage(inputId, message)
    ```

2.  Read the binding’s `receiveMessage()` method in the package’s
    JavaScript to check the fields it expects. shinyMatrix reads
    `data.value.data`, `data.value.rownames`, and `data.value.colnames`,
    and treats missing names as empty arrays.

3.  Check the binding’s `getValue()` method. After applying the message,
    shinysnap compares its result with the expected value and reports
    `mismatched` if they differ. shinyMatrix returns
    `{data, rownames, colnames}` with the names as arrays. When that
    shape differs from the message’s `value`, attach the expected value
    as the `expect` attribute of the returned list; when the message has
    no `value` key at all, no comparison is made.

4.  Write the restorer. Here is the one shinysnap uses for shinyMatrix:

    ``` r

    restore_matrix <- function(id, value, binding, session) {
      if (is.null(value)) {
     return(NULL)
      }
      if (!is.matrix(value)) value <- as.matrix(value)
      rn <- rownames(value)
      cn <- colnames(value)
      data <- value
      dimnames(data) <- NULL
      payload <- list(value = list(data = data, rownames = rn, colnames = cn))
      attr(payload, "expect") <- list(list(
     data = data,
     rownames = as.list(if (is.null(rn)) character() else rn),
     colnames = as.list(if (is.null(cn)) character() else cn)
      ))
      payload
    }

    snap_restorer("shinyMatrix.matrixNumeric", restore_matrix)
    snap_restorer("shinyMatrix.matrixCharacter", restore_matrix)
    ```

    Note the binding names: shinyMatrix registers its binding without a
    name, so the client script falls back to the type the binding
    reports for the element. Look at the `bindings` section of a
    snapshot taken from your app to see the name to register for.

5.  Restore a snapshot and read the report. `applied` means the input
    accepted the message and passed any value comparison. For
    `mismatched`, the `detail` column shows the value the input reported
    instead. For `failed`, it contains the JavaScript error.

Messages are converted to JSON with the same settings as
`session$sendInputMessage()`. Vectors of length one become scalars,
`NULL` becomes `null`, dates become `"YYYY-MM-DD"` strings, and matrices
become nested arrays, one per row. Use `as.list(value)` if the binding
needs an array even for a single value. For example, `radioButtons`
expects a scalar, while `checkboxGroupInput` accepts either form.

## Converting messages in JavaScript

If you maintain an input’s JavaScript code, you can convert the message
in the browser with an adapter. It receives the message, the HTML
element, the binding, and the full restore record. It returns the
message to pass to `receiveMessage()`, or `null` to skip the input:

``` js
window.shinysnap.registerAdapter("mypkg.fancyInput", function (message, el, binding, record) {
  // fancyInput's receiveMessage() wants {selected: [...]}, and its
  // getValue() returns the same array.
  return { selected: [].concat(message.value) };
});
```

Adapters run after the R restorer and before the `shiny:updateinput`
event. shinysnap triggers this event in the same way as Shiny’s message
handler. If an event handler calls `preventDefault()`, the input is
reported as `skipped`.

## Inputs that need more work

The following inputs need a restorer or adapter that shinysnap does not
yet provide. Contributions that check the expected message format are
welcome: `shinyWidgets::pickerInput()`,
`shinyWidgets::airDatepickerInput()`,
`shinyWidgets::numericRangeInput()`, `shinyWidgets::sliderTextInput()`,
and `shinyWidgets::virtualSelectInput()`.

Some input values have no bound HTML element. Examples include `plotly`
events, `DT` row selections, and values set from JavaScript with
`Shiny.setInputValue()`. shinysnap cannot restore these through a
binding and leaves them out of snapshots.
