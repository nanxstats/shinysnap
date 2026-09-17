# The snapshot file format

This is the normative description of the files shinysnap writes and
reads. The current format version is 1. Readers accept every earlier
version and convert on read; the number is bumped only for incompatible
changes. The `app$version` field is for the *app’s* migrations (the
`migrate` hook of
[`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md));
the `format` field is for the package’s.

## The snapshot object

In R, a snapshot is a plain list of class `shinysnap`:

``` r

library(shinysnap)
snap <- snap_unserialize('{
  "format": 1,
  "app": {"name": "myapp", "version": "2.4.1"},
  "created": "2026-09-16T18:22:03Z",
  "inputs": {"n": 100, "rate": 0.025},
  "values": {"prefs": {"digits": 3}},
  "bindings": {"n": "shiny.sliderInput", "rate": "shiny.numberInput"}
}')
str(unclass(snap))
#> List of 9
#>  $ format     : int 1
#>  $ app        :List of 2
#>   ..$ name   : chr "myapp"
#>   ..$ version: chr "2.4.1"
#>  $ created    : chr "2026-09-16T18:22:03Z"
#>  $ producer   : NULL
#>  $ inputs     :List of 2
#>   ..$ n   : int 100
#>   ..$ rate: num 0.025
#>  $ values     :List of 1
#>   ..$ prefs:List of 1
#>   .. ..$ digits: int 3
#>  $ bindings   : Named chr [1:2] "shiny.sliderInput" "shiny.numberInput"
#>   ..- attr(*, "names")= chr [1:2] "n" "rate"
#>  $ attachments: list()
#>  $ meta       : list()
```

| field         | content                                                  |
|---------------|----------------------------------------------------------|
| `format`      | the format version, an integer                           |
| `app`         | `name` and `version` of the app; either may be `NULL`    |
| `created`     | when the state was captured, ISO 8601 in UTC             |
| `producer`    | versions of shinysnap, shiny, and R that wrote the file  |
| `inputs`      | named list of input values, keyed by fully namespaced id |
| `values`      | named list of server-side values                         |
| `bindings`    | named character vector, input id to client binding name  |
| `attachments` | file records, present in bundles only                    |
| `meta`        | free-form, user-supplied                                 |

`inputs` and `values` hold ordinary R values, exactly what `input$x`
returns. The encoding below is applied at write and read time only.

## The JSON file

A file is one JSON object with the keys above, in that order,
pretty-printed with two-space indentation and a trailing newline, in
UTF-8. Input ids are written in the order captured, which
[`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md) sorts,
so files of the same state are byte-identical and diffs in version
control are meaningful. A container is written on one line when it fits
in 80 columns and one element per line otherwise.

### Encoding rules

1.  `NULL` is `null`.
2.  An atomic vector of length one without names is a JSON scalar;
    longer vectors are arrays. Since R has no scalar type, a scalar and
    a one-element array read back to the same value. A vector of length
    zero is a typed wrapper, `{"$type": "<storage>", "value": []}`,
    because a bare `[]` has no type.
3.  Logicals are `true`/`false`, strings are escaped per RFC 8259 with
    non-ASCII kept as UTF-8, integers are plain digit runs, and doubles
    are written with the fewest digits that read back to the same value
    ([`zmij::format_double()`](https://nanx.me/zmij/reference/format_double.html)).
    A finite double always contains a `.` or an `e`, so `1` is an
    integer and `1.0` a double.
4.  `NA` inside a vector of length greater than one is `null` at that
    position; the other elements fix the type. A vector that is entirely
    `NA`, including a single `NA`, is a typed wrapper with `null`
    values, so that `NULL`, `NA`, and `NA_character_` stay distinct.
5.  Non-finite doubles use the strings `"inf"`, `"-inf"`, and `"NaN"`
    inside a `double` wrapper, which is used only when such a value is
    present.
6.  Named atomic vectors are
    `{"$type": "<storage>", "names": [...], "value": [...]}`.
7.  `Date` is `{"$type": "Date", "value": ["2024-01-01", null]}`;
    `POSIXct` is
    `{"$type": "POSIXct", "tz": "UTC", "value": ["2024-01-01T10:00:00.000Z"]}`,
    written in the stored time zone at millisecond precision (the `tz`
    key is absent when the value has no time zone attribute, and the
    offset is `Z` for UTC and for the session time zone, which is
    formatted in UTC); `difftime` is
    `{"$type": "difftime", "units": "secs", "value": [...]}`; a factor
    is `{"$type": "factor", "levels": [...], "value": ["a", null]}` with
    an `"ordered": true` flag when ordered.
8.  A matrix or array is
    `{"$type": "array", "storage": "double", "dim": [2, 3], "dimnames": [["a", "b"], null], "value": [...]}`
    with the values in column-major order (`"matrix"` is accepted as an
    alias on read).
9.  A data frame is
    `{"$type": "data.frame", "nrow": 3, "columns": {"x": ..., "y": ...}}`,
    with a `"row.names"` array when the row names are not the automatic
    ones. Tibbles are written as data frames.
10. A list whose names are all present and unique is a JSON object. Any
    other list (unnamed, partially named, or empty) is
    `{"$type": "list", "names": [...], "value": [...]}` with `names`
    omitted when absent, except that an unnamed list with at least one
    element that is not a scalar is written as a bare array, which reads
    back as a list.
11. Anything else (environments, functions, S4 and R6 objects, unknown
    classes) is an error by default. With `unsupported = "rds"` it
    becomes `{"$type": "rds", "class": [...], "base64": "..."}` (in a
    bundle,
    `{"$type": "rds", "class": [...], "path": "objects/1-values_fit.rds"}`).
    Reading these requires `trust = TRUE`; otherwise they decode to
    `NULL` with one warning that lists them.
12. Attributes other than the ones above are dropped on write. The
    format describes values, not R objects.

Keys starting with `$` are reserved.

### Examples

``` r

cat(snap_serialize(list(inputs = list(
  n = 1L, x = 1, sum = 0.1 + 0.2, flag = c(TRUE, NA),
  empty = character(0), missing = NA, extremes = c(0.5, Inf),
  named = c(a = 1L, b = 2L),
  when = as.Date("2024-01-15"),
  stamp = as.POSIXct("2024-01-01 10:00:00.5", tz = "UTC"),
  level = factor("b", levels = c("a", "b")),
  M = matrix(1:6, 2, dimnames = list(c("r1", "r2"), NULL)),
  df = data.frame(x = 1:2, y = c("a", "b")),
  mixed = list(1, "a"),
  nested = list(a = 1, b = list(c = NULL))
))))
#> {
#>   "format": 1,
#>   "app": {"name": null, "version": null},
#>   "created": "2026-09-17T22:38:52Z",
#>   "producer": {"shinysnap": "0.1.0", "shiny": "1.14.0", "r": "4.6.1"},
#>   "inputs": {
#>     "n": 1,
#>     "x": 1.0,
#>     "sum": 0.30000000000000004,
#>     "flag": [true, null],
#>     "empty": {"$type": "character", "value": []},
#>     "missing": {"$type": "logical", "value": [null]},
#>     "extremes": {"$type": "double", "value": [0.5, "inf"]},
#>     "named": {"$type": "integer", "names": ["a", "b"], "value": [1, 2]},
#>     "when": {"$type": "Date", "value": ["2024-01-15"]},
#>     "stamp": {
#>       "$type": "POSIXct",
#>       "tz": "UTC",
#>       "value": ["2024-01-01T10:00:00.500Z"]
#>     },
#>     "level": {"$type": "factor", "levels": ["a", "b"], "value": ["b"]},
#>     "M": {
#>       "$type": "array",
#>       "storage": "integer",
#>       "dim": [2, 3],
#>       "dimnames": [["r1", "r2"], null],
#>       "value": [1, 2, 3, 4, 5, 6]
#>     },
#>     "df": {
#>       "$type": "data.frame",
#>       "nrow": 2,
#>       "columns": {"x": [1, 2], "y": ["a", "b"]}
#>     },
#>     "mixed": {"$type": "list", "value": [1.0, "a"]},
#>     "nested": {"a": 1.0, "b": {"c": null}}
#>   },
#>   "values": {},
#>   "bindings": {},
#>   "meta": {}
#> }
```

### Reading

The reader parses the text with jsonlite (`simplifyVector = FALSE`) and
walks the tree. Arrays whose elements are all scalars or `null` become
atomic vectors, typed from the non-null elements (integer when every
number parsed as an integer, double otherwise); mixing kinds is an
error. Objects with a `$type` key go through the typed decoders; other
objects become named lists; arrays with a non-scalar element become
unnamed lists. A `$type` the reader does not know is an error naming the
id, unless `unknown_types = "keep"` keeps the raw value. Duplicate keys
are an error.

The round-trip contract: for every supported type, writing and reading
gives a value [`identical()`](https://rdrr.io/r/base/identical.html) to
the original, and `snap_read(snap_write(x))` is identical to `x` except
for `producer`, which the writer always stamps.

``` r

x <- list(inputs = list(
  sum = 0.1 + 0.2, tiny = 1e-300, dates = as.Date(c("2024-01-01", NA)),
  M = matrix(c(1.5, NA, Inf, 2), 2), f = factor(c("a", NA), levels = c("a", "b"))
))
back <- snap_unserialize(snap_serialize(x))
identical(snap_inputs(back), x$inputs)
#> [1] TRUE
```

## The bundle (`.zip`)

A bundle is a zip archive with:

- `manifest.json`: exactly the JSON above, with an `attachments`
  section. Each entry is a file record:
  `{"$type": "file", "name": "data.csv", "size": 1234, "type": "text/csv", "path": "attachments/upload/data.csv"}`;
  the fields are arrays when a
  [`fileInput()`](https://rdrr.io/pkg/shiny/man/fileInput.html) held
  several files.
- `attachments/<id>/<file name>`: the uploaded files. Names are reduced
  to `A-Z a-z 0-9 . _ -` and disambiguated with a counter when they
  repeat.
- `objects/<n>-<path>.rds`: values written with `unsupported = "rds"`.

On read, the archive is checked before extraction: entries with `..` or
absolute paths are refused, and the uncompressed total must stay under
`getOption("shinysnap.max_bundle_bytes", 100 * 1024^2)`. It is then
extracted into a fresh temporary directory; the manifest’s paths must
point inside it, under `attachments/` or `objects/`, at regular files.
`snap_attachment(x, id)` returns the extracted paths. The snapshot’s
`inputs` never contain file input values, because a browser’s file input
cannot be set programmatically; restore hooks can read the attachment
instead.

``` r

upload <- tempfile(fileext = ".csv")
writeLines(c("x,y", "1,2"), upload)
snap <- list(
  inputs = list(n = 1L),
  attachments = list(data = list(
    name = "data.csv", size = file.size(upload), type = "text/csv", datapath = upload
  ))
)
bundle <- tempfile(fileext = ".zip")
snap_write(snap, bundle)
back <- snap_read(bundle)
readLines(snap_attachment(back, "data"))
#> [1] "x,y" "1,2"
```

## The `.rds` format

`snap_write(format = "rds")` stores the R object with
[`saveRDS()`](https://rdrr.io/r/base/readRDS.html). It is neither
readable nor safe across versions, and
[`snap_read()`](https://nanx.me/shinysnap/reference/snap_write.md)
refuses it unless `trust = TRUE`, because unserializing a file runs
arbitrary code paths. It exists for people who really want it.
