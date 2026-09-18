# Snapshots and bookmarks

Shiny’s bookmarking
([`enableBookmarking()`](https://rdrr.io/pkg/shiny/man/enableBookmarking.html))
and shinysnap both let users return to a saved state. This vignette
helps you choose between them, use them together, or switch an app from
bookmarks to snapshot files.

## What each one does

|  | bookmarking | shinysnap |
|----|----|----|
| where state is saved | a URL (`"url"`) or a server directory (`"server"`) | a file the user downloads and uploads |
| how it restores | opens the URL in a new session | restores the current session without reloading |
| dynamic inputs | receive saved values when created, through [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html) | receive saved values when created or when they appear in the browser |
| setup | a UI function and [`enableBookmarking()`](https://rdrr.io/pkg/shiny/man/enableBookmarking.html) | no required UI changes |
| file contents | JSON encoded in a URL, or `.rds` files | JSON you can read in a text editor |
| support for app changes | no migration helpers | app name and version, `validate` and `migrate` hooks, and a restore report |

Use bookmarking when you want to send a colleague a link to what you’re
looking at. Use shinysnap when you want to save your work to a file and
return to it later, perhaps after the app has been updated.

## Using both

You can add shinysnap to an app that already uses bookmarking:

- Ids excluded with
  [`setBookmarkExclude()`](https://rdrr.io/pkg/shiny/man/setBookmarkExclude.html)
  are excluded from snapshots too.
- Values that Shiny marks as unserializable, such as passwords, are
  never saved. This includes values excluded by a serializer registered
  with
  [`setSerializer()`](https://rdrr.io/pkg/shiny/man/setSerializer.html).
- During a restore, shinysnap makes the snapshot’s values available to
  [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html),
  which supplies initial values to new inputs. It restores the previous
  settings when the restore finishes.
- shinysnap’s own internal inputs are marked unserializable, so they
  never show up in a bookmark URL.

The callbacks, or *hooks*, work similarly in both packages.
`onBookmark(function(state) ...)` and
[`snap_on_save()`](https://nanx.me/shinysnap/reference/snap_on_save.md)
write to `state$values`.
[`onRestore()`](https://rdrr.io/pkg/shiny/man/onBookmark.html) and
[`snap_on_restore()`](https://nanx.me/shinysnap/reference/snap_on_restore.md)
read the saved values. If you use `reactiveValues`,
[`snap_track()`](https://nanx.me/shinysnap/reference/snap_track.md) can
save and restore them for you.

## Turning a snapshot into a bookmark

Use
[`snap_as_bookmark_url()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md)
to turn a snapshot into a link. The app must use
`enableBookmarking("url")` and a UI function to open it:

``` r

library(shinysnap)
snap <- list(
  inputs = list(n = 100L, model = "complex", weights = c(0.5, 0.75)),
  values = list(note = "baseline")
)
snap_as_bookmark_url(snap, base_url = "https://example.org/app/")
#> [1] "https://example.org/app/?_inputs_&n=100&model=%22complex%22&weights=%5B0.5%2C0.75%5D&_values_&note=%22baseline%22"
```

Inside a server function, pass `session` instead of `base_url` to use
the app’s current address. The result uses the same `_inputs_` and
`_values_` keys and encoding as a URL created by `session$doBookmark()`.

## Migrating an app

1.  Remove
    [`enableBookmarking()`](https://rdrr.io/pkg/shiny/man/enableBookmarking.html)
    and
    [`bookmarkButton()`](https://rdrr.io/pkg/shiny/man/bookmarkButton.html).
    Add
    [`snap_download_button()`](https://nanx.me/shinysnap/reference/snap_download_button.md)
    and
    [`snap_file_input()`](https://nanx.me/shinysnap/reference/snap_file_input.md)
    to the UI, and
    [`snap_download_handler()`](https://nanx.me/shinysnap/reference/snap_download_button.md)
    and
    [`snap_file_restore()`](https://nanx.me/shinysnap/reference/snap_file_input.md)
    to the server function. The UI no longer needs to be a function.
2.  Replace
    [`onBookmark()`](https://rdrr.io/pkg/shiny/man/onBookmark.html)
    hooks with
    [`snap_on_save()`](https://nanx.me/shinysnap/reference/snap_on_save.md),
    and [`onRestore()`](https://rdrr.io/pkg/shiny/man/onBookmark.html)
    hooks with
    [`snap_track()`](https://nanx.me/shinysnap/reference/snap_track.md)
    for `reactiveValues` (they are written back for you) or
    [`snap_on_restore()`](https://nanx.me/shinysnap/reference/snap_on_restore.md)
    for anything else.
3.  Keep
    [`setBookmarkExclude()`](https://rdrr.io/pkg/shiny/man/setBookmarkExclude.html)
    calls; add `snap_enable(exclude = ...)` patterns for ids that should
    never be saved.
4.  Give the app a name and a version with
    [`snap_enable()`](https://nanx.me/shinysnap/reference/snap_enable.md),
    and write a `migrate` hook the first time a saved value changes
    meaning.
5.  In
    [`shiny::testServer()`](https://rdrr.io/pkg/shiny/man/testServer.html)
    tests, use
    [`snap_as_test_inputs()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md)
    to prepare the saved inputs for a `session$setInputs()` call.
