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
