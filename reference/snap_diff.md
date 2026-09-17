# Compare two snapshots

Lists the inputs, values, and metadata entries that differ between two
snapshots. Values are flattened one level, so a tracked `reactiveValues`
stored as `prefs` with a changed `digits` field shows up as
`prefs$digits`.

## Usage

``` r
snap_diff(a, b)
```

## Arguments

- a, b:

  Snapshot objects, lists of snapshot fields, file paths, or JSON text.

## Value

A data frame of class `shinysnap_diff` with one row per difference and
the columns `id`, `section` (`"inputs"`, `"values"`, or `"meta"`),
`status` (`"added"`, `"removed"`, or `"changed"`, seen from `a` to `b`),
and the list columns `old` and `new` holding the values (`NULL` for the
side where the entry is absent).

## Examples

``` r
a <- snap_unserialize('{"format": 1, "inputs": {"n": 1, "x": "old"},
  "values": {"prefs": {"digits": 3}}}')
b <- snap_unserialize('{"format": 1, "inputs": {"n": 1, "y": true},
  "values": {"prefs": {"digits": 4}}}')
snap_diff(a, b)
#> <shinysnap_diff> 3 difference(s)
#>            id section  status   old  new
#>             x  inputs removed "old"     
#>             y  inputs   added       TRUE
#>  prefs$digits  values changed    3L   4L
```
