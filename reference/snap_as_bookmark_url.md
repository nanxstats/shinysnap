# Interoperate with bookmarks, tests, and bundles

- `snap_as_bookmark_url()` encodes a snapshot the way shiny's URL
  bookmarking (`enableBookmarking("url")`) does, so that the state can
  be opened by reloading the app at that URL. The app must have URL
  bookmarking enabled and a UI *function* for the URL to restore; the
  query string carries the same `_inputs_` and `_values_` keys that
  `session$doBookmark()` writes, with input ids in the order stored in
  the snapshot.

- `snap_as_test_inputs()` returns the input values as a named list for
  [`shiny::testServer()`](https://rdrr.io/pkg/shiny/man/testServer.html):
  `session$setInputs(!!!snap_as_test_inputs(x))`.

- `snap_attachment()` returns the local path(s) of the file(s) a
  [`fileInput()`](https://rdrr.io/pkg/shiny/man/fileInput.html) held
  when the snapshot was taken, if the snapshot came from a bundle (see
  [`snap_write()`](https://nanx.me/shinysnap/reference/snap_write.md))
  or from the same session.

## Usage

``` r
snap_as_bookmark_url(x, session = NULL, base_url = NULL)

snap_as_test_inputs(x)

snap_attachment(x, id)
```

## Arguments

- x:

  A snapshot object, a list of snapshot fields, a file path, or JSON
  text.

- session:

  A Shiny session whose `clientData` provides the base URL (protocol,
  host, port, and path), or `NULL`.

- base_url:

  The base URL to prepend, for example `"https://example.org/app/"`.
  When neither `session` nor `base_url` is given, only the query string
  (starting with `?`) is returned.

- id:

  An input id.

## Value

`snap_as_bookmark_url()` returns a string. `snap_as_test_inputs()`
returns a named list. `snap_attachment()` returns a character vector of
file paths (one per uploaded file), or `NULL` when the snapshot has no
attachment for `id`.

## Examples

``` r
snap <- snap_unserialize('{
  "format": 1,
  "inputs": {"n": 100, "method": "b", "weights": [0.5, 0.75]},
  "values": {"note": "baseline"}
}')
snap_as_bookmark_url(snap, base_url = "https://example.org/app/")
#> [1] "https://example.org/app/?_inputs_&n=100&method=%22b%22&weights=%5B0.5%2C0.75%5D&_values_&note=%22baseline%22"
str(snap_as_test_inputs(snap))
#> List of 3
#>  $ n      : int 100
#>  $ method : chr "b"
#>  $ weights: num [1:2] 0.5 0.75
snap_attachment(snap, "upload")
#> NULL
```
