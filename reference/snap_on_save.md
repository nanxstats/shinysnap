# Register a hook that runs when a snapshot is taken

`snap_on_save()` registers a function that
[`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md) calls
after the inputs and tracked values have been collected. It receives a
`state` object: `state$inputs` is the named list of captured input
values and `state$values` is an environment. Anything the hook assigns
into `state$values` is stored in the snapshot's `values` section, so
several hooks (and several modules) can contribute without overwriting
each other, just like shiny's
[`onBookmark()`](https://rdrr.io/pkg/shiny/man/onBookmark.html).

## Usage

``` r
snap_on_save(fn, session = shiny::getDefaultReactiveDomain())
```

## Arguments

- fn:

  A function taking one argument, `state`.

- session:

  The Shiny session. Defaults to the current session.

## Value

A function that removes the hook again, invisibly.

## Details

Inside a module, the hook sees only the module's inputs (with the
namespace prefix removed) and its values are stored under namespaced
names automatically.

## Examples

``` r
if (interactive()) {
  library(shiny)

  server <- function(input, output, session) {
    snap_on_save(function(state) {
      state$values$fitted_at <- format(Sys.time())
    })
  }
}
```
