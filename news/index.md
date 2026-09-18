# Changelog

## shinysnap (development version)

### Documentation

- The README, changelog, vignettes, `AGENTS.md`, and `DESIGN.md` now use
  plainer language, shorter sentences, and clearer explanations
  ([\#8](https://github.com/nanxstats/shinysnap/issues/8)).

## shinysnap 0.1.0

### Snapshots

- [`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md)
  saves the inputs currently on the page, the `reactiveValues`
  registered with
  [`snap_track()`](https://nanx.me/shinysnap/reference/snap_track.md),
  and any values added by
  [`snap_on_save()`](https://nanx.me/shinysnap/reference/snap_on_save.md)
  hooks. It leaves out inputs whose UI has been removed, action buttons,
  passwords, and values that Shiny marks as unserializable. It also
  respects
  [`setBookmarkExclude()`](https://rdrr.io/pkg/shiny/man/setBookmarkExclude.html)
  and the selection rules in
  [`snap_enable()`](https://nanx.me/shinysnap/reference/snap_enable.md),
  [`snap_exclude()`](https://nanx.me/shinysnap/reference/snap_exclude.md),
  and
  [`snap_include()`](https://nanx.me/shinysnap/reference/snap_exclude.md).
- Snapshots are lists of class `shinysnap`. Use
  [`snap_inputs()`](https://nanx.me/shinysnap/reference/snap_inputs.md),
  [`snap_values()`](https://nanx.me/shinysnap/reference/snap_inputs.md),
  and
  [`snap_meta()`](https://nanx.me/shinysnap/reference/snap_inputs.md) to
  inspect them, and
  [`snap_diff()`](https://nanx.me/shinysnap/reference/snap_diff.md) to
  compare them.

### Files

- Snapshots use JSON, with enough digits to preserve numeric values and
  extra type information for values such as dates and matrices. A
  consistent layout makes changes easy to review in version control.
  [`snap_serialize()`](https://nanx.me/shinysnap/reference/snap_serialize.md)
  and
  [`snap_unserialize()`](https://nanx.me/shinysnap/reference/snap_serialize.md)
  convert snapshots to and from JSON text;
  [`snap_write()`](https://nanx.me/shinysnap/reference/snap_write.md)
  and [`snap_read()`](https://nanx.me/shinysnap/reference/snap_write.md)
  write and read files.
- `snap_write(format = "zip")` creates a bundle that includes uploaded
  files. With `unsupported = "rds"`, it can also store R objects that
  the JSON format does not support. Bundles are checked before
  extraction. Reading embedded R objects or `.rds` files requires
  `trust = TRUE`.
- [`snap_download_button()`](https://nanx.me/shinysnap/reference/snap_download_button.md),
  [`snap_download_handler()`](https://nanx.me/shinysnap/reference/snap_download_button.md),
  [`snap_file_input()`](https://nanx.me/shinysnap/reference/snap_file_input.md),
  and
  [`snap_file_restore()`](https://nanx.me/shinysnap/reference/snap_file_input.md)
  add controls for downloading and uploading snapshot files.

### Restore

- [`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
  restores a snapshot in the current session. It restores tracked
  values, runs
  [`snap_on_restore()`](https://nanx.me/shinysnap/reference/snap_on_restore.md)
  hooks, and sends the input values to the browser. Each input receives
  its value as soon as it is on the page. Shiny’s
  [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html)
  supplies saved values to dynamic inputs as they are created. Starting
  another restore cancels the first.
- The restore report lists every input as `applied`, `constructed`,
  `reapplied`, `missing`, `failed`, `mismatched`, or `skipped`.
  [`snap_on_restored()`](https://nanx.me/shinysnap/reference/snap_on_restore.md)
  runs code when the restore finishes, and
  [`snap_is_restoring()`](https://nanx.me/shinysnap/reference/snap_is_restoring.md)
  tells you whether a restore is in progress.
- [`snap_restorer()`](https://nanx.me/shinysnap/reference/snap_restorer.md)
  registers a function that converts a saved value into the message an
  input expects. You can register it for a binding name or an input id.
  shinysnap includes restorers for shiny, bslib, and shinyMatrix. Use
  `window.shinysnap.registerAdapter()` to convert messages in
  JavaScript.

### Interoperability

- [`snap_as_bookmark_url()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md)
  turns a snapshot into a Shiny bookmark URL.
- [`snap_as_test_inputs()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md)
  prepares saved inputs for
  [`shiny::testServer()`](https://rdrr.io/pkg/shiny/man/testServer.html).
- [`snap_attachment()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md)
  returns paths to the files stored in a bundle.
