# The snapshot file format

This vignette defines the snapshot file format, including how R values
are stored in JSON and how uploaded files are included in zip bundles.

The current format version is 1. The version increases only when a
change is incompatible with earlier readers. shinysnap reads older
formats and converts them to the current one. The `format` field tracks
these package changes. Separately, `app$version` records your app’s
version so that
[`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
can pass it to your `migrate` function.

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

| field | content |
|----|----|
| `format` | the format version, an integer |
| `app` | `name` and `version` of the app; either may be `NULL` |
| `created` | when the state was captured, ISO 8601 in UTC |
| `producer` | versions of shinysnap, shiny, and R that wrote the file |
| `inputs` | named list of input values, using full ids with any module prefixes |
| `values` | named list of values saved from the server |
| `bindings` | named character vector, input id to client binding name |
| `attachments` | file records, present in bundles only |
| `meta` | any additional information supplied by the app |

`inputs` and `values` hold ordinary R values, like those returned by
`input$x`. They are converted to the forms below only when writing a
file, and converted back when reading it.

## The JSON file

A file contains one JSON object with the keys above, in that order. It
uses UTF-8, an indent of two spaces, and a newline at the end. Input ids
are written in their order in the snapshot;
[`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md) sorts
them. This consistent layout makes changes easier to review in version
control. An object or array is written on one line if it fits in 80
columns, or with one element per line otherwise.

### Encoding rules

JSON can represent numbers, strings, booleans, arrays, objects, and
`null`. For R values that need more information, shinysnap uses a JSON
object with a `$type` field. These objects are called *typed wrappers*
below.

1.  `NULL` is `null`.

2.  An atomic vector of length one without names is a JSON scalar;
    longer vectors are arrays. Since R has no scalar type, a scalar and
    an array of length one read back to the same value. A vector of
    length zero is a typed wrapper,
    `{"$type": "<storage>", "value": []}`, because a bare `[]` has no
    type.

3.  Logicals are `true` or `false`. Strings are escaped as required by
    RFC 8259, with characters outside ASCII kept as UTF-8. Integers use
    digits without a decimal point. Doubles use the fewest digits that
    read back to the same value, as given by
    [`zmij::format_double()`](https://nanx.me/zmij/reference/format_double.html).
    A finite double always contains a `.` or an `e`, so `1` is an
    integer and `1.0` a double.

4.  `NA` inside a vector of length greater than one is `null` at that
    position; the other elements determine the type. A vector that is
    entirely `NA`, including a single `NA`, is a typed wrapper with
    `null` values, so that `NULL`, `NA`, and `NA_character_` stay
    distinct.

5.  Infinite values and `NaN` use the strings `"inf"`, `"-inf"`, and
    `"NaN"` inside a `double` wrapper, which is used only when such a
    value is present.

6.  Named atomic vectors are
    `{"$type": "<storage>", "names": [...], "value": [...]}`.

7.  Dates, times, durations, and factors use these wrappers:

    - `Date`: `{"$type": "Date", "value": ["2024-01-01", null]}`.
    - `POSIXct`:
      `{"$type": "POSIXct", "tz": "UTC", "value": ["2024-01-01T10:00:00.000Z"]}`.
      Values are written in the stored time zone and rounded to
      milliseconds. The `tz` key is omitted if there is no time zone
      attribute. UTC values use the offset `Z`; values using the
      session’s time zone are formatted in UTC and also use `Z`.
    - `difftime`:
      `{"$type": "difftime", "units": "secs", "value": [...]}`.
    - Factors:
      `{"$type": "factor", "levels": [...], "value": ["a", null]}`, with
      `"ordered": true` for ordered factors.

8.  A matrix or array is
    `{"$type": "array", "storage": "double", "dim": [2, 3], "dimnames": [["a", "b"], null], "value": [...]}`
    with the values ordered by column, as in R. The reader also accepts
    `"matrix"` as the type.

9.  A data frame is
    `{"$type": "data.frame", "nrow": 3, "columns": {"x": ..., "y": ...}}`,
    with a `"row.names"` array when the row names are not the automatic
    ones. Tibbles are written as data frames.

10. A list whose names are all present and unique is a JSON object. Any
    other list (unnamed, partially named, or empty) is
    `{"$type": "list", "names": [...], "value": [...]}` with `names`
    omitted when absent, except that an unnamed list with at least one
    element that is not a scalar is written as a JSON array, which reads
    back as a list.

11. Anything else (environments, functions, S4 and R6 objects, unknown
    classes) is an error by default. With `unsupported = "rds"` it
    becomes `{"$type": "rds", "class": [...], "base64": "..."}` (in a
    bundle,
    `{"$type": "rds", "class": [...], "path": "objects/1-values_fit.rds"}`).
    Reading these requires `trust = TRUE`; otherwise they decode to
    `NULL` with one warning that lists them.

12. Attributes other than those listed above are dropped when writing.

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
#>   "created": "2026-09-18T07:05:25Z",
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

The reader uses jsonlite with `simplifyVector = FALSE`, then converts
each part of the result to an R value:

- Arrays containing only scalars or `null` become atomic vectors. The
  elements other than `null` determine the type. Numeric arrays become
  integer vectors if every number was parsed as an integer, and double
  vectors otherwise. Mixing other types is an error.
- Objects with a `$type` key are decoded using the rules above. Other
  objects become named lists.
- Arrays containing an object or another array become unnamed lists.

An unknown `$type` raises an error that identifies the value. Use
`unknown_types = "keep"` to keep its raw representation instead.
Duplicate keys are always an error.

Writing and reading a supported value preserves it, subject to the
precision and attribute rules above. The following example checks this
with [`identical()`](https://rdrr.io/r/base/identical.html). When you
write a snapshot, `producer` is updated to record the versions of
shinysnap, shiny, and R doing the writing.

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

A bundle is a zip archive containing:

- `manifest.json`: exactly the JSON above, with an `attachments`
  section. Each entry is a file record:
  `{"$type": "file", "name": "data.csv", "size": 1234, "type": "text/csv", "path": "attachments/upload/data.csv"}`;
  the fields are arrays when a
  [`fileInput()`](https://rdrr.io/pkg/shiny/man/fileInput.html) held
  several files.
- `attachments/<id>/<file name>`: the uploaded files. Names use only
  `A-Z a-z 0-9 . _ -`. A counter distinguishes files whose names repeat.
- `objects/<n>-<path>.rds`: values written with `unsupported = "rds"`.

Before extracting a bundle, shinysnap rejects entries with `..` path
components or absolute paths. The total size of the uncompressed files
must be below `getOption("shinysnap.max_bundle_bytes", 100 * 1024^2)`.
Files are extracted into a new temporary directory. Paths in the
manifest must point to regular files inside its `attachments/` or
`objects/` directories.

Use `snap_attachment(x, id)` to get the extracted file paths. Browsers
do not allow code to set the value of a file input, so uploaded files
are kept in `attachments`, separate from `inputs`. Your restore hooks
can read them from there.

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
[`saveRDS()`](https://rdrr.io/r/base/readRDS.html). These files cannot
be read in a text editor and may not work across versions. Reading
serialized R objects can execute code, so
[`snap_read()`](https://nanx.me/shinysnap/reference/snap_write.md)
requires `trust = TRUE` to open them. Use this format only for files you
trust.
