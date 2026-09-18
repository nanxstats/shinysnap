# Print, format, and coerce snapshots and restore results

[`print()`](https://rdrr.io/r/base/print.html) shows a compact summary:
app name and version, creation time, and the number and names of inputs,
values, and attachments.
[`format()`](https://rdrr.io/r/base/format.html) returns the same lines
as a character vector. [`as.list()`](https://rdrr.io/r/base/list.html)
drops the class and returns the underlying list.

## Usage

``` r
# S3 method for class 'shinysnap_restore'
print(x, ...)

# S3 method for class 'shinysnap_report'
print(x, ...)

# S3 method for class 'shinysnap'
print(x, ...)

# S3 method for class 'shinysnap'
format(x, ...)

# S3 method for class 'shinysnap'
as.list(x, ...)

# S3 method for class 'shinysnap_diff'
print(x, ...)
```

## Arguments

- x:

  A snapshot object, a snapshot comparison from
  [`snap_diff()`](https://nanx.me/shinysnap/reference/snap_diff.md), or
  a restore handle or report from
  [`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md).
  [`format()`](https://rdrr.io/r/base/format.html) and
  [`as.list()`](https://rdrr.io/r/base/list.html) accept snapshot
  objects only.

- ...:

  Passed to
  [`print.data.frame()`](https://rdrr.io/r/base/print.dataframe.html)
  when printing a snapshot comparison or restore report; ignored
  otherwise.

## Value

[`print()`](https://rdrr.io/r/base/print.html) returns `x` invisibly;
[`format()`](https://rdrr.io/r/base/format.html) a character vector;
[`as.list()`](https://rdrr.io/r/base/list.html) a plain list.

## Details

For a [`snap_diff()`](https://nanx.me/shinysnap/reference/snap_diff.md)
result, [`print()`](https://rdrr.io/r/base/print.html) shows the changed
entries and their old and new values. For a
[`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
handle, it shows the transaction id; for a completed restore report, it
shows the input statuses and the elapsed time.

## Examples

``` r
snap <- snap_unserialize('{
  "format": 1,
  "app": {"name": "myapp", "version": "2.4.1"},
  "created": "2026-09-16T18:22:03Z",
  "inputs": {"n": 100, "rate": 0.025}
}')
print(snap)
#> <shinysnap>
#>   app:         myapp (version 2.4.1)
#>   created:     2026-09-16T18:22:03Z
#>   inputs:      2 (n, rate)
#>   values:      0
#>   attachments: 0
format(snap)
#> [1] "<shinysnap>"                         
#> [2] "  app:         myapp (version 2.4.1)"
#> [3] "  created:     2026-09-16T18:22:03Z" 
#> [4] "  inputs:      2 (n, rate)"          
#> [5] "  values:      0"                    
#> [6] "  attachments: 0"                    
names(as.list(snap))
#> [1] "format"      "app"         "created"     "producer"    "inputs"     
#> [6] "values"      "bindings"    "attachments" "meta"       
print(snap_diff(snap, list(inputs = list(n = 50, rate = 0.025))))
#> <shinysnap_diff> 1 difference(s)
#>  id section  status  old new
#>   n  inputs changed 100L  50

if (interactive()) {
  library(shiny)
  ui <- fluidPage(
    numericInput("n", "n", 0),
    actionButton("restore", "Restore state")
  )
  server <- function(input, output, session) {
    observeEvent(input$restore, {
      handle <- snap_restore(list(inputs = list(n = 100)), on_done = print)
      print(handle)
    })
  }
  shinyApp(ui, server)
}
```
