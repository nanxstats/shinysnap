# Take a snapshot of the running app

Captures the current input values and the registered server-side values
of the session into a snapshot object, ready for
[`snap_write()`](https://nanx.me/shinysnap/reference/snap_write.md) or
[`snap_serialize()`](https://nanx.me/shinysnap/reference/snap_serialize.md).
Nothing is written to disk.

## Usage

``` r
snap_take(
  session = shiny::getDefaultReactiveDomain(),
  ...,
  include = NULL,
  exclude = NULL,
  live_only = NULL,
  values = TRUE,
  scope = c("root", "module"),
  meta = list()
)
```

## Arguments

- session:

  The Shiny session. Defaults to the current session.

- ...:

  Not used; arguments after `session` must be named.

- include, exclude:

  Regular expressions matched against fully namespaced ids, in addition
  to those configured with
  [`snap_enable()`](https://nanx.me/shinysnap/reference/snap_enable.md).

- live_only:

  Keep only inputs currently on the page. Defaults to the value
  configured with
  [`snap_enable()`](https://nanx.me/shinysnap/reference/snap_enable.md)
  (`TRUE`).

- values:

  Capture tracked values and run the save hooks? `FALSE` captures inputs
  only.

- scope:

  `"root"` (the default) captures the whole app with full ids, even when
  called inside a module; `"module"` keeps only ids under the calling
  module's namespace (still as full ids).

- meta:

  A named list of free-form metadata stored in the snapshot.

## Value

A snapshot object of class `shinysnap`.

## Details

What is captured:

- Inputs, by fully namespaced id, exactly as `input$id` returns them.
  With `live_only`, only inputs that are currently on the page are kept,
  so values of inputs whose dynamic UI has been removed are not carried
  along. Action buttons, password inputs, and values that shiny's own
  serializers mark as unserializable are never captured; ids excluded
  with
  [`setBookmarkExclude()`](https://rdrr.io/pkg/shiny/man/setBookmarkExclude.html),
  [`snap_exclude()`](https://nanx.me/shinysnap/reference/snap_exclude.md),
  or the `exclude` patterns are dropped. File inputs are moved to the
  snapshot's `attachments`.

- The name of the client-side input binding of each captured input, in
  `bindings`.

- Values: the fields of every `reactiveValues` registered with
  [`snap_track()`](https://nanx.me/shinysnap/reference/snap_track.md),
  then whatever the
  [`snap_on_save()`](https://nanx.me/shinysnap/reference/snap_on_save.md)
  hooks add.

The function isolates every read, so it never creates reactive
dependencies. Inputs with a rate policy (text inputs debounce, sliders
throttle) may lag the browser by a few hundred milliseconds; a snapshot
taken from a download handler runs after the click has reached the
server, which in practice is later than that.

## Examples

``` r
if (interactive()) {
  library(shiny)

  server <- function(input, output, session) {
    observeEvent(input$show, {
      print(snap_take())
    })
  }
}
```
