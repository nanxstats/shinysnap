# shinysnap 0.1.0

- Initial version.
- The `shinysnap` object, the JSON codec with typed wrappers, and
  `snap_serialize()` / `snap_unserialize()`.
- `snap_take()` captures the live inputs (as reported by the client script),
  tracked `reactiveValues` (`snap_track()`), and the values written by
  `snap_on_save()` hooks; `snap_enable()`, `snap_exclude()`, and
  `snap_include()` configure what is captured.
- `snap_write()` / `snap_read()` for `.json` and (behind `trust = TRUE`)
  `.rds` files; `snap_download_button()` / `snap_download_handler()` replace
  the download boilerplate.
- `snap_restore()` restores a snapshot into the running session without a
  page reload: tracked values are written back, input values are applied by
  the client script as soon as each input is on the page (including inputs
  inside dynamic UI that appears during the restore), shiny's
  `restoreInput()` mechanism is primed so re-rendered UI is built with the
  restored values, and a report says what was applied, what never appeared,
  and what failed. `snap_on_restore()`, `snap_on_restored()`,
  `snap_is_restoring()`, `snap_restorer()` / `snap_restorers()` with built-in
  restorers for shiny, bslib, and shinyMatrix inputs, and
  `snap_file_input()` / `snap_file_restore()` complete the restore side.
