# Convert a snapshot to and from JSON text

`snap_serialize()` writes a snapshot as JSON text in the canonical
shinysnap format; `snap_unserialize()` reads it back. These are the
in-memory counterparts of
[`snap_write()`](https://nanx.me/shinysnap/reference/snap_write.md) and
[`snap_read()`](https://nanx.me/shinysnap/reference/snap_write.md).

## Usage

``` r
snap_serialize(
  x,
  format = "json",
  pretty = TRUE,
  unsupported = c("error", "rds"),
  verbose = FALSE
)

snap_unserialize(
  text,
  format = "json",
  trust = FALSE,
  unknown_types = c("error", "keep")
)
```

## Arguments

- x:

  A snapshot object, as returned by
  [`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md) or
  `snap_unserialize()`, or a list with (some of) a snapshot's fields,
  for example `list(inputs = list(n = 5))`.

- format:

  The text format. Only `"json"` is available.

- pretty:

  Pretty-print with two-space indentation (the default) or emit compact
  JSON on one line.

- unsupported:

  What to do with values the JSON format cannot describe: `"error"` (the
  default) or `"rds"` to embed them as serialized R objects.

- verbose:

  Print a message about what was converted or dropped.

- text:

  JSON text: a single string or a character vector of lines.

- trust:

  Decode embedded serialized R objects (`"$type": "rds"`)? Only set this
  to `TRUE` for files from a source you trust.

- unknown_types:

  What to do with a `"$type"` the reader does not know: `"error"` (the
  default) or `"keep"` to keep the raw parsed value.

## Value

`snap_serialize()` returns a single string. `snap_unserialize()` returns
a snapshot object of class `shinysnap`.

## Details

The JSON format is designed to be read and edited by people: doubles are
written with the fewest digits that read back to the same value,
integers as plain digit runs, and everything JSON cannot express
directly (the type of an empty vector, `NA`, `Inf`, names, dates,
matrices, factors, data frames) as a small object with a `"$type"` key.

Values that the format cannot describe (environments, functions, S4 and
R6 objects, unknown classes) are an error by default. With
`unsupported = "rds"` they are embedded as base64 serialized R objects
instead; because unserializing arbitrary data is unsafe, reading them
back requires `trust = TRUE`, otherwise they decode to `NULL` with a
warning.

## Examples

``` r
text <- '{
  "format": 1,
  "app": {"name": "myapp", "version": "2.4.1"},
  "inputs": {
    "dates": {"$type": "Date", "value": ["2024-01-01", "2024-03-01"]},
    "method": "b",
    "n": 100,
    "rate": 0.025,
    "weights": [0.5, 0.75]
  }
}'
snap <- snap_unserialize(text)
snap
#> <shinysnap>
#>   app:         myapp (version 2.4.1)
#>   created:     <unset>
#>   inputs:      5 (dates, method, n, rate, weights)
#>   values:      0
#>   attachments: 0
str(snap_inputs(snap))
#> List of 5
#>  $ dates  : Date[1:2], format: "2024-01-01" "2024-03-01"
#>  $ method : chr "b"
#>  $ n      : int 100
#>  $ rate   : num 0.025
#>  $ weights: num [1:2] 0.5 0.75
cat(snap_serialize(snap))
#> {
#>   "format": 1,
#>   "app": {"name": "myapp", "version": "2.4.1"},
#>   "created": "2026-09-17T05:50:52Z",
#>   "producer": {"shinysnap": "0.1.0", "shiny": "1.14.0", "r": "4.6.1"},
#>   "inputs": {
#>     "dates": {"$type": "Date", "value": ["2024-01-01", "2024-03-01"]},
#>     "method": "b",
#>     "n": 100,
#>     "rate": 0.025,
#>     "weights": [0.5, 0.75]
#>   },
#>   "values": {},
#>   "bindings": {},
#>   "meta": {}
#> }
```
