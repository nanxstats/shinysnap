# Write a snapshot to a file and read it back

`snap_write()` saves a snapshot; `snap_read()` loads one. The canonical
format is JSON (see
[`snap_serialize()`](https://nanx.me/shinysnap/reference/snap_serialize.md)):
plain text, readable, diffable, and safe to open. The `"zip"` format is
a *bundle*: a zip archive holding the same JSON as `manifest.json` plus
the files of any
[`fileInput()`](https://rdrr.io/pkg/shiny/man/fileInput.html) uploads
(under `attachments/`) and, with `unsupported = "rds"`, opaque R objects
(under `objects/`); it needs the zip package. The `"rds"` format stores
the R object with [`saveRDS()`](https://rdrr.io/r/base/readRDS.html); it
is neither readable nor safe across versions, and reading it requires
`trust = TRUE` because unserializing a file runs arbitrary code paths.

## Usage

``` r
snap_write(
  x,
  path,
  format = c("auto", "json", "zip", "rds"),
  pretty = TRUE,
  ...
)

snap_read(
  path,
  format = c("auto", "json", "zip", "rds"),
  trust = FALSE,
  unknown_types = c("error", "keep"),
  ...
)
```

## Arguments

- x:

  A snapshot object, or a list with (some of) a snapshot's fields (see
  [`snap_serialize()`](https://nanx.me/shinysnap/reference/snap_serialize.md)).

- path:

  The file path.

- format:

  `"auto"` picks the format from the extension (`.json`, `.zip`, or
  `.rds`); otherwise the format to use regardless of the extension.

- pretty:

  Pretty-print JSON (the default) or write one compact line.

- ...:

  Passed on to
  [`snap_serialize()`](https://nanx.me/shinysnap/reference/snap_serialize.md)
  (`unsupported`, `verbose`).

- trust:

  Decode embedded serialized R objects and allow the `"rds"` format?
  Only set this to `TRUE` for files from a source you trust.

- unknown_types:

  What to do with a `"$type"` the reader does not know: `"error"` (the
  default) or `"keep"` to keep the raw parsed value.

## Value

`snap_write()` returns `path` invisibly; `snap_read()` returns a
snapshot object.

## Details

Reading a bundle checks the archive for path traversal and caps its
uncompressed size at
`getOption("shinysnap.max_bundle_bytes", 100 * 1024^2)` bytes, then
extracts it into a fresh temporary directory;
[`snap_attachment()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md)
returns the local paths of the extracted uploads and bundled objects are
decoded only with `trust = TRUE`.

## Examples

``` r
snap <- snap_unserialize('{"format": 1, "inputs": {"n": 100, "rate": 0.025}}')
path <- tempfile(fileext = ".json")
snap_write(snap, path)
cat(readLines(path), sep = "\n")
#> {
#>   "format": 1,
#>   "app": {"name": null, "version": null},
#>   "created": "2026-09-17T06:12:17Z",
#>   "producer": {"shinysnap": "0.1.0", "shiny": "1.14.0", "r": "4.6.1"},
#>   "inputs": {"n": 100, "rate": 0.025},
#>   "values": {},
#>   "bindings": {},
#>   "meta": {}
#> }
identical(snap_inputs(snap_read(path)), snap_inputs(snap))
#> [1] TRUE
```
