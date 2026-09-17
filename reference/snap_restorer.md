# Register how an input is restored

A *restorer* turns the value stored in a snapshot into the message that
the input's client-side binding understands, that is, what the matching
`update*Input()` function would send. shinysnap ships restorers for the
inputs of shiny, bslib, and shinyMatrix (see `snap_restorers()`); the
default for everything else is `list(value = value)`. Register your own
for an input id or for a binding name (for example
`"shinyWidgets.pickerInput"`).

## Usage

``` r
snap_restorer(x, fn, session = NULL)

snap_restorers(session = shiny::getDefaultReactiveDomain())
```

## Arguments

- x:

  An input id or a binding name, as reported in the snapshot's
  `bindings` section.

- fn:

  The restorer function, or `NULL` to remove a registration.

- session:

  A Shiny session to register the restorer for that session only, or
  `NULL` (the default) to register it globally.

## Value

`snap_restorer()` returns `fn` invisibly. `snap_restorers()` returns a
data frame with the columns `name` and `scope` (`"builtin"`, `"global"`,
or `"session"`).

## Details

`fn` is called as `fn(id, value, binding, session)` and must return the
message as a list, or `NULL` to skip the input (reported as `skipped`).
It must not call `update*()` functions itself: those go through
`session$sendInputMessage()`, which silently drops messages for inputs
that are not on the page yet. To find the right payload, read the
`update*()` function's source and keep the part that carries the value.

Optionally, the returned list may carry an attribute `expect` holding
the value the binding's `getValue()` is expected to return after the
message was applied; the client uses it to report `mismatched` when the
widget shows something else. By default the message's `value` is used.

Resolution order when restoring an input: a session restorer for the id,
a session restorer for its binding, a global restorer for the id or the
binding, the built-in restorer for the binding, the default.

## Examples

``` r
# A restorer for a hypothetical widget whose update function sends
# list(selected = value):
snap_restorer("mypkg.myInput", function(id, value, binding, session) {
  list(selected = value)
})
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
#> 16               mypkg.myInput  global
snap_restorer("mypkg.myInput", NULL)
```
