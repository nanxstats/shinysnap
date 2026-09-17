# Configure shinysnap for a session

Sets the app identity and the defaults used by
[`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md) and
[`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
for the current session. Calling it is optional: every `snap_*()` server
function creates the per-session state on first use with the defaults
below. Call it again to change the settings.

## Usage

``` r
snap_enable(
  app = NULL,
  version = NULL,
  exclude = NULL,
  include = NULL,
  live_only = TRUE,
  use_restore_context = TRUE,
  verbose = FALSE,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- app, version:

  The name and version of the app, written into every snapshot file.
  They default to the options `shinysnap.app` and `shinysnap.version`,
  which packaged apps can set once in `.onLoad()`.

- exclude, include:

  Character vectors of regular expressions matched against fully
  namespaced input ids. Matching `exclude` patterns are never captured;
  when `include` is given, only matching ids are. Ids excluded with
  shiny's
  [`setBookmarkExclude()`](https://rdrr.io/pkg/shiny/man/setBookmarkExclude.html)
  are always honoured too.

- live_only:

  Capture only inputs that are currently on the page (as reported by the
  client script), dropping values of inputs whose UI has been removed.
  Set to `FALSE` to capture every value shiny remembers.

- use_restore_context:

  Prime shiny's
  [`restoreInput()`](https://rdrr.io/pkg/shiny/man/restoreInput.html)
  mechanism during a restore, so that dynamic UI re-rendered during the
  restore is built with the restored values. Turn off only to debug.

- verbose:

  Print messages about what is captured, dropped, and restored.

- session:

  The Shiny session. Defaults to the current session.

## Value

The per-session controller, invisibly.

## Examples

``` r
if (interactive()) {
  library(shiny)

  server <- function(input, output, session) {
    snap_enable(app = "myapp", version = "2.4.0", exclude = c("^btn_", "^nav_"))
  }
}
```
