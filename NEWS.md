# shinysnap (development version)

## Documentation

- The README, changelog, vignettes, `AGENTS.md`, and `DESIGN.md` now
  use plainer language, shorter sentences, and clearer explanations (#8).

# shinysnap 0.1.0

## Snapshots

- `snap_take()` saves the inputs currently on the page, the
  `reactiveValues` registered with `snap_track()`, and any values added
  by `snap_on_save()` hooks. It leaves out inputs whose UI has been
  removed, action buttons, passwords, and values that Shiny marks as
  unserializable. It also respects `setBookmarkExclude()` and the
  selection rules in `snap_enable()`, `snap_exclude()`, and `snap_include()`.
- Snapshots are lists of class `shinysnap`. Use `snap_inputs()`,
  `snap_values()`, and `snap_meta()` to inspect them, and `snap_diff()`
  to compare them.

## Files

- Snapshots use JSON, with enough digits to preserve numeric values and
  extra type information for values such as dates and matrices. A
  consistent layout makes changes easy to review in version control.
  `snap_serialize()` and `snap_unserialize()` convert snapshots to and from
  JSON text; `snap_write()` and `snap_read()` write and read files.
- `snap_write(format = "zip")` creates a bundle that includes uploaded
  files. With `unsupported = "rds"`, it can also store R objects that the
  JSON format does not support. Bundles are checked before extraction.
  Reading embedded R objects or `.rds` files requires `trust = TRUE`.
- `snap_download_button()`, `snap_download_handler()`, `snap_file_input()`, and
  `snap_file_restore()` add controls for downloading and uploading snapshot files.

## Restore

- `snap_restore()` restores a snapshot in the current session. It restores
  tracked values, runs `snap_on_restore()` hooks, and sends the input
  values to the browser. Each input receives its value as soon as it is
  on the page. Shiny's `restoreInput()` supplies saved values to dynamic
  inputs as they are created. Starting another restore cancels the first.
- The restore report lists every input as `applied`, `constructed`,
  `reapplied`, `missing`, `failed`, `mismatched`, or `skipped`.
  `snap_on_restored()` runs code when the restore finishes, and
  `snap_is_restoring()` tells you whether a restore is in progress.
- `snap_restorer()` registers a function that converts a saved value into
  the message an input expects. You can register it for a binding name or
  an input id. shinysnap includes restorers for shiny, bslib, and
  shinyMatrix. Use `window.shinysnap.registerAdapter()` to convert messages
  in JavaScript.

## Interoperability

- `snap_as_bookmark_url()` turns a snapshot into a Shiny bookmark URL.
- `snap_as_test_inputs()` prepares saved inputs for `shiny::testServer()`.
- `snap_attachment()` returns paths to the files stored in a bundle.
