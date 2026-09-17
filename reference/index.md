# Package index

## Configure

- [`snap_enable()`](https://nanx.me/shinysnap/reference/snap_enable.md)
  : Configure shinysnap for a session
- [`snap_dependency()`](https://nanx.me/shinysnap/reference/snap_dependency.md)
  : The client-side script as an HTML dependency
- [`snap_exclude()`](https://nanx.me/shinysnap/reference/snap_exclude.md)
  [`snap_include()`](https://nanx.me/shinysnap/reference/snap_exclude.md)
  : Exclude or include inputs by pattern

## Snapshot

- [`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md) :
  Take a snapshot of the running app
- [`snap_inputs()`](https://nanx.me/shinysnap/reference/snap_inputs.md)
  [`snap_values()`](https://nanx.me/shinysnap/reference/snap_inputs.md)
  [`snap_meta()`](https://nanx.me/shinysnap/reference/snap_inputs.md) :
  Access the parts of a snapshot
- [`print(`*`<shinysnap>`*`)`](https://nanx.me/shinysnap/reference/print.shinysnap.md)
  [`format(`*`<shinysnap>`*`)`](https://nanx.me/shinysnap/reference/print.shinysnap.md)
  [`as.list(`*`<shinysnap>`*`)`](https://nanx.me/shinysnap/reference/print.shinysnap.md)
  : Print, format, and coerce snapshot objects
- [`snap_diff()`](https://nanx.me/shinysnap/reference/snap_diff.md) :
  Compare two snapshots

## Files

- [`snap_write()`](https://nanx.me/shinysnap/reference/snap_write.md)
  [`snap_read()`](https://nanx.me/shinysnap/reference/snap_write.md) :
  Write a snapshot to a file and read it back
- [`snap_serialize()`](https://nanx.me/shinysnap/reference/snap_serialize.md)
  [`snap_unserialize()`](https://nanx.me/shinysnap/reference/snap_serialize.md)
  : Convert a snapshot to and from JSON text

## Restore

- [`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
  : Restore a snapshot into the running app
- [`snap_is_restoring()`](https://nanx.me/shinysnap/reference/snap_is_restoring.md)
  : Is a restore in flight?

## Hooks and restorers

- [`snap_track()`](https://nanx.me/shinysnap/reference/snap_track.md) :
  Track server-side values
- [`snap_on_save()`](https://nanx.me/shinysnap/reference/snap_on_save.md)
  : Register a hook that runs when a snapshot is taken
- [`snap_on_restore()`](https://nanx.me/shinysnap/reference/snap_on_restore.md)
  [`snap_on_restored()`](https://nanx.me/shinysnap/reference/snap_on_restore.md)
  : Register hooks that run around a restore
- [`snap_restorer()`](https://nanx.me/shinysnap/reference/snap_restorer.md)
  [`snap_restorers()`](https://nanx.me/shinysnap/reference/snap_restorer.md)
  : Register how an input is restored

## UI helpers

- [`snap_download_button()`](https://nanx.me/shinysnap/reference/snap_download_button.md)
  [`snap_download_handler()`](https://nanx.me/shinysnap/reference/snap_download_button.md)
  : Save-state button and its download handler
- [`snap_file_input()`](https://nanx.me/shinysnap/reference/snap_file_input.md)
  [`snap_file_restore()`](https://nanx.me/shinysnap/reference/snap_file_input.md)
  : Restore-state upload and its handler

## Interoperability

- [`snap_as_bookmark_url()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md)
  [`snap_as_test_inputs()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md)
  [`snap_attachment()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md)
  : Interoperate with bookmarks, tests, and bundles
