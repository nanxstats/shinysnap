# Track server-side values

Registers a `reactiveValues` object so that
[`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md)
captures its fields (all of them, or the ones named in `fields`) under
`name` in the snapshot's `values` section, and so that a restore can
write them back.

## Usage

``` r
snap_track(
  values,
  fields = NULL,
  name = NULL,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- values:

  A `reactiveValues` object.

- fields:

  Names of the fields to capture, or `NULL` for all fields.

- name:

  The name to store the values under. Defaults to the name of the
  variable passed as `values`.

- session:

  The Shiny session. Defaults to the current session.

## Value

The (namespaced) name the values are stored under, invisibly.

## Details

Inside a module, `name` is namespaced automatically.

## Examples

``` r
if (interactive()) {
  library(shiny)

  server <- function(input, output, session) {
    prefs <- reactiveValues(digits = 3L, scientific = FALSE)
    snap_track(prefs)
  }
}
```
