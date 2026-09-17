# Snapshots and bookmarks

Shiny’s bookmarking
([`enableBookmarking()`](https://rdrr.io/pkg/shiny/man/enableBookmarking.html))
and shinysnap solve neighbouring problems, and an app can use both. This
vignette compares them, shows how they coexist, and lists what to change
when moving an app’s save-and-restore feature from one to the other.

## What each one does

|  | bookmarking | shinysnap |
|----|----|----|
| state lives in | a URL (`"url"`) or a server directory (`"server"`) | a file the user downloads and uploads |
| restore happens | by loading the URL: a new session, a page reload | into the running session, no reload |
| dynamic UI | restored at construction through [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html) | restored at construction *and* by the client as inputs appear |
| requires | a UI function, [`enableBookmarking()`](https://rdrr.io/pkg/shiny/man/enableBookmarking.html) | nothing in the UI |
| readable by people | no (URL-encoded JSON, or `.rds` files) | yes (JSON) |
| survives app changes | no built-in help | app name and version in the file, `validate` and `migrate` hooks, a report of what did not apply |

Bookmarking is the right tool for “send a colleague a link to what I am
looking at”. shinysnap is the right tool for “save my work to a file,
come back next month, possibly on a newer version of the app”.

## Coexistence

shinysnap reuses the parts of bookmarking’s machinery that make sense
mid-session, so an app that already bookmarks keeps working:

- Ids excluded with
  [`setBookmarkExclude()`](https://rdrr.io/pkg/shiny/man/setBookmarkExclude.html)
  are excluded from snapshots too.
- Values that shiny’s serializers mark as unserializable (passwords, and
  anything registered with
  [`setSerializer()`](https://rdrr.io/pkg/shiny/man/setSerializer.html))
  are never captured.
- During a restore, shinysnap primes the session’s restore context, the
  object behind
  [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html),
  with the snapshot’s values, and puts the previous context back when
  the restore settles.
- shinysnap’s own internal inputs are marked unserializable, so they
  never show up in a bookmark URL.

The hooks mirror each other. `onBookmark(function(state) ...)` writes
into `state$values`; so does
[`snap_on_save()`](https://nanx.me/shinysnap/reference/snap_on_save.md).
[`onRestore()`](https://rdrr.io/pkg/shiny/man/onBookmark.html) reads
`state$values`;
[`snap_on_restore()`](https://nanx.me/shinysnap/reference/snap_on_restore.md)
reads the file’s `values`, and
[`snap_track()`](https://nanx.me/shinysnap/reference/snap_track.md)
writes them back into your `reactiveValues` for you.

## Turning a snapshot into a bookmark

[`snap_as_bookmark_url()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md)
encodes a snapshot the way URL bookmarking does, so that a saved state
can also be opened as a link, provided the app has
`enableBookmarking("url")` and a UI function:

``` r

library(shinysnap)
snap <- list(
  inputs = list(n = 100L, model = "complex", weights = c(0.5, 0.75)),
  values = list(note = "baseline")
)
snap_as_bookmark_url(snap, base_url = "https://example.org/app/")
#> [1] "https://example.org/app/?_inputs_&n=100&model=%22complex%22&weights=%5B0.5%2C0.75%5D&_values_&note=%22baseline%22"
```

Inside a server function, pass `session` instead of `base_url` and the
protocol, host, port, and path the browser used are filled in. The query
string carries the same `_inputs_` and `_values_` keys, with the same
encoding, as the URL `session$doBookmark()` produces for the same state.

## Migrating an app

1.  Replace
    [`enableBookmarking()`](https://rdrr.io/pkg/shiny/man/enableBookmarking.html)
    and the
    [`bookmarkButton()`](https://rdrr.io/pkg/shiny/man/bookmarkButton.html)
    with
    [`snap_download_button()`](https://nanx.me/shinysnap/reference/snap_download_button.md)
    and
    [`snap_file_input()`](https://nanx.me/shinysnap/reference/snap_file_input.md)
    in the UI, and
    [`snap_download_handler()`](https://nanx.me/shinysnap/reference/snap_download_button.md)
    and
    [`snap_file_restore()`](https://nanx.me/shinysnap/reference/snap_file_input.md)
    in the server. The UI no longer needs to be a function.
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
5.  For tests,
    [`snap_as_test_inputs()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md)
    turns a saved file into the `session$setInputs()` call of a
    [`shiny::testServer()`](https://rdrr.io/pkg/shiny/man/testServer.html)
    test.
