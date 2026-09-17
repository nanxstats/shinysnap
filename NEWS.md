# shinysnap 0.1.0

Initial release.

## Snapshots

- `snap_take()` captures the inputs that are on the page (as reported by
  the client script, so values of removed dynamic UI are dropped), the
  `reactiveValues` registered with `snap_track()`, and the values written
  by `snap_on_save()` hooks. Action buttons, passwords, values that shiny's
  serializers mark as unserializable, ids excluded with
  `setBookmarkExclude()`, and the patterns given to `snap_enable()`,
  `snap_exclude()`, and `snap_include()` are left out.
- The snapshot object is a plain list of class `shinysnap`, with
  `snap_inputs()`, `snap_values()`, `snap_meta()`, and `snap_diff()`.

## Files

- The canonical format is JSON: doubles written with the fewest digits that
  round-trip, typed wrappers for what JSON cannot say, deterministic
  layout. `snap_serialize()`, `snap_unserialize()`, `snap_write()`, and
  `snap_read()` convert; `snap_write(format = "zip")` writes a bundle that
  keeps uploaded files and, with `unsupported = "rds"`, opaque R objects.
  Bundles are validated before extraction; embedded objects and `.rds`
  files need `trust = TRUE`.
- `snap_download_button()`, `snap_download_handler()`,
  `snap_file_input()`, and `snap_file_restore()` replace the download and
  upload boilerplate.

## Restore

- `snap_restore()` restores a snapshot into the running session: tracked
  values are written back, `snap_on_restore()` hooks run, and the input
  values are sent to the browser at once, where the client script applies
  each one as soon as its input is on the page. shiny's `restoreInput()`
  mechanism is primed during the restore so dynamic UI is built with the
  restored values. A second restore cancels the first.
- The restore report lists every input as `applied`, `constructed`,
  `reapplied`, `missing`, `failed`, `mismatched`, or `skipped`;
  `snap_on_restored()` hooks and `snap_is_restoring()` complete the
  server-side API.
- `snap_restorer()` registers how an input's value becomes the message its
  binding understands, per binding name or per input id; built-in
  restorers cover shiny, bslib, and shinyMatrix inputs, and
  `window.shinysnap.registerAdapter()` is the JavaScript-side equivalent.

## Interop

- `snap_as_bookmark_url()` encodes a snapshot like URL bookmarking does,
  `snap_as_test_inputs()` feeds `shiny::testServer()`, and
  `snap_attachment()` returns the files kept in a bundle.
