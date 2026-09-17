# Changelog

## shinysnap 0.1.0

Initial release.

### Snapshots

- [`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md)
  captures the inputs that are on the page (as reported by the client
  script, so values of removed dynamic UI are dropped), the
  `reactiveValues` registered with
  [`snap_track()`](https://nanx.me/shinysnap/reference/snap_track.md),
  and the values written by
  [`snap_on_save()`](https://nanx.me/shinysnap/reference/snap_on_save.md)
  hooks. Action buttons, passwords, values that shiny’s serializers mark
  as unserializable, ids excluded with
  [`setBookmarkExclude()`](https://rdrr.io/pkg/shiny/man/setBookmarkExclude.html),
  and the patterns given to
  [`snap_enable()`](https://nanx.me/shinysnap/reference/snap_enable.md),
  [`snap_exclude()`](https://nanx.me/shinysnap/reference/snap_exclude.md),
  and
  [`snap_include()`](https://nanx.me/shinysnap/reference/snap_exclude.md)
  are left out.
- The snapshot object is a plain list of class `shinysnap`, with
  [`snap_inputs()`](https://nanx.me/shinysnap/reference/snap_inputs.md),
  [`snap_values()`](https://nanx.me/shinysnap/reference/snap_inputs.md),
  [`snap_meta()`](https://nanx.me/shinysnap/reference/snap_inputs.md),
  and [`snap_diff()`](https://nanx.me/shinysnap/reference/snap_diff.md).

### Files

- The canonical format is JSON: doubles written with the fewest digits
  that round-trip, typed wrappers for what JSON cannot say,
  deterministic layout.
  [`snap_serialize()`](https://nanx.me/shinysnap/reference/snap_serialize.md),
  [`snap_unserialize()`](https://nanx.me/shinysnap/reference/snap_serialize.md),
  [`snap_write()`](https://nanx.me/shinysnap/reference/snap_write.md),
  and [`snap_read()`](https://nanx.me/shinysnap/reference/snap_write.md)
  convert; `snap_write(format = "zip")` writes a bundle that keeps
  uploaded files and, with `unsupported = "rds"`, opaque R objects.
  Bundles are validated before extraction; embedded objects and `.rds`
  files need `trust = TRUE`.
- [`snap_download_button()`](https://nanx.me/shinysnap/reference/snap_download_button.md),
  [`snap_download_handler()`](https://nanx.me/shinysnap/reference/snap_download_button.md),
  [`snap_file_input()`](https://nanx.me/shinysnap/reference/snap_file_input.md),
  and
  [`snap_file_restore()`](https://nanx.me/shinysnap/reference/snap_file_input.md)
  replace the download and upload boilerplate.

### Restore

- [`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
  restores a snapshot into the running session: tracked values are
  written back,
  [`snap_on_restore()`](https://nanx.me/shinysnap/reference/snap_on_restore.md)
  hooks run, and the input values are sent to the browser at once, where
  the client script applies each one as soon as its input is on the
  page. shiny’s
  [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html)
  mechanism is primed during the restore so dynamic UI is built with the
  restored values. A second restore cancels the first.
- The restore report lists every input as `applied`, `constructed`,
  `reapplied`, `missing`, `failed`, `mismatched`, or `skipped`;
  [`snap_on_restored()`](https://nanx.me/shinysnap/reference/snap_on_restore.md)
  hooks and
  [`snap_is_restoring()`](https://nanx.me/shinysnap/reference/snap_is_restoring.md)
  complete the server-side API.
- [`snap_restorer()`](https://nanx.me/shinysnap/reference/snap_restorer.md)
  registers how an input’s value becomes the message its binding
  understands, per binding name or per input id; built-in restorers
  cover shiny, bslib, and shinyMatrix inputs, and
  `window.shinysnap.registerAdapter()` is the JavaScript-side
  equivalent.

### Interop

- [`snap_as_bookmark_url()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md)
  encodes a snapshot like URL bookmarking does,
  [`snap_as_test_inputs()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md)
  feeds
  [`shiny::testServer()`](https://rdrr.io/pkg/shiny/man/testServer.html),
  and
  [`snap_attachment()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md)
  returns the files kept in a bundle.
