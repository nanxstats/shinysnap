# Exclude or include inputs by pattern

`snap_exclude()` adds regular expressions; inputs whose fully namespaced
id matches any of them are left out of snapshots and ignored on restore.
`snap_include()` adds patterns that an id must match to be captured at
all. Both accumulate over calls within a session and complement the
`exclude`/`include` arguments of
[`snap_enable()`](https://nanx.me/shinysnap/reference/snap_enable.md)
and [`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md).

## Usage

``` r
snap_exclude(patterns, session = shiny::getDefaultReactiveDomain())

snap_include(patterns, session = shiny::getDefaultReactiveDomain())
```

## Arguments

- patterns:

  A character vector of regular expressions, matched against fully
  namespaced input ids (for example `"^mod-btn_"`).

- session:

  The Shiny session. Defaults to the current session.

## Value

The complete vector of patterns registered so far, invisibly.

## Details

Ids excluded with shiny's
[`setBookmarkExclude()`](https://rdrr.io/pkg/shiny/man/setBookmarkExclude.html)
are always honoured too, and action buttons, password inputs, and file
inputs are never captured as input values.

## Examples

``` r
if (interactive()) {
  library(shiny)

  server <- function(input, output, session) {
    snap_exclude(c("^btn_", "^nav_"))
  }
}
```
