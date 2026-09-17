# AGENTS.md

Guidelines for AI agents (and humans) working on shinysnap. Read this
before changing code; it records the decisions and the traps that cost
real debugging time while the package was built.

## What this package is

shinysnap takes a *snapshot* of a running Shiny app (input values plus
registered server-side values), writes it to a readable JSON file, and
restores it later into another session without a page reload and without
`enableBookmarking()`. The central noun is the snapshot in the virtual
machine sense. Never confuse it, in code or prose, with snapshot testing
(`expect_snapshot`, `_snaps/`) or screenshots; never export anything named
`snapshot*` (that family belongs to shiny's test machinery). All exports
use the `snap_` prefix, snake_case.

The design brief that produced the package is `deps-src/bootstrap.md`.
The whole `deps-src/` tree (the brief, vendored CRAN sources of shiny,
bslib, shinyMatrix, zmij, jsonlite, zip, prior-art packages) is gitignored
and regenerated with `okr sync`. Verify claims about Shiny internals against
those sources, not against memory.

## Ground rules

- Never use `shiny:::` in package code. Everything needed is public:
  `session$sendCustomMessage()`, `session$restoreContext`, `setSerializer()`,
  `getBookmarkExclude()`, input bindings and `receiveMessage()`, the
  `shiny:bound` event. Feature-detect and degrade when something is missing
  (`MockShinySession$restoreContext` is `NULL`).
- Never `unserialize()`/`readRDS()` user-supplied data unless the caller
  passed `trust = TRUE`. JSON must be safe to open.
- No timers or sleeps on the R side to wait for the UI. Ordering is solved
  by the client-side apply-on-bind queue and by `restoreInput()`.
- Every read of `input` inside `snap_*()` functions is wrapped in
  `shiny::isolate()`; callers must never pick up reactive dependencies.
- Messages to the client go through `session$rootScope()` with fully
  namespaced ids. `sendInputMessage()` namespaces ids inside modules;
  `sendCustomMessage()` does not.
- Hidden internal inputs are prefixed `.shinysnap_` (`.shinysnap_ready`,
  `.shinysnap_inventory`, `.shinysnap_result`). They are marked
  unserializable so they never leak into native bookmark URLs.
- Never silently drop anything on restore: every input ends up in the
  report with a status.
- Every claim about a binding's wire format is backed by a browser test
  that runs the real binding, not by reading docs.

## Architecture map

| file | role |
|---|---|
| `R/codec.R` | `encode_value()`/`decode_value()`: R values to a JSON-ready tree and back; typed wrappers; bundle object and file records |
| `R/io-json.R` | hand-written JSON writer (doubles via `zmij::format_double()`, deterministic layout) and reader (`jsonlite::parse_json`) |
| `R/io.R`, `R/io-bundle.R` | `snap_serialize()`/`snap_unserialize()`, `snap_write()`/`snap_read()`, the zip bundle |
| `R/snapshot.R` | the `shinysnap` object, `snap_take()`, accessors, `snap_diff()` |
| `R/controller.R`, `R/enable.R` | per-session R6 controller in `session$rootScope()$userData$.shinysnap`; `snap_enable()`; dependency injection |
| `R/restore.R` | `snap_restore()`: the transaction, report class, cancellation, `restoreInput()` priming |
| `R/restorers.R`, `R/restorers-builtin.R` | restorer registry and the built-in payload table |
| `R/hooks.R`, `R/track.R`, `R/exclude.R` | callback manager, save/restore hooks (module-scoped), tracked `reactiveValues`, exclusion rules |
| `R/ui.R` | download/upload helpers |
| `R/interop.R` | bookmark URL, `testServer()` inputs, attachments |
| `inst/www/shinysnap.js` | the client script: inventory half and restore half; plain ES2017, no build step |
| `inst/examples/0*-*/app.R` | runnable apps used by the browser tests; keep their terminology generic |

## Verified facts that differ from the brief or from intuition

- **shinyMatrix registers its binding without a name**, so `binding.name`
  is undefined. The inventory falls back to `binding.getType(el)`, which
  yields `shinyMatrix.matrixNumeric` / `shinyMatrix.matrixCharacter`;
  restorers are keyed on those.
- **`MockShinySession` reports the namespace prefix `mock-session-` at the
  root.** Module detection must use `inherits(session, "session_proxy")`,
  never `nzchar(session$ns(""))`.
- **An empty `fileInput()` has value `NULL`.** File inputs are recognised
  through the inventory binding `shiny.fileInputBinding`, with the data
  frame shape (`name, size, type, datapath`) as fallback.
- **Shiny sends a newly bound input's initial value after the `shiny:bound`
  event** (`bindAll()` awaits `_bindAll()` then calls `setInput()`). Applies
  from the bound handler must be deferred with `setTimeout(fn, 0)`; a
  microtask is too early.
- **Returning a promise from an observer stalls the restore.** Shiny uses
  `is.promising()` on an observer's return value and holds the flush until
  it resolves; our promise resolves only after the client sees the page go
  quiet, which needs the flush. `snap_restore()` therefore returns a
  `shinysnap_restore` handle (`$txn`, `$promise`), not a promise, and
  example observers end with `NULL` when their last expression is a
  `promises::then()`/`catch()`.
- **`radioButtons` wants a scalar** (`setValue()` calls `$escape(value)`,
  which needs a string); `checkboxGroupInput`/`selectInput` accept arrays.
  The wrong shape shows up as a browser `n.replace is not a function`
  failure.
- **Date sliders take milliseconds and report `"YYYY-MM-DD"` strings**, so
  restore records carry an explicit `expect` value for the client-side
  comparison; the default `expect` is the message's `value`.
- **shiny's `toJSON()` turns named atomic vectors into objects** (with a
  jsonlite warning); restorer payloads strip names.
- **`%OS3` truncates, not rounds**: the codec rounds POSIXct to
  milliseconds itself and rebuilds instants as `whole + fraction`, the way
  R does, so millisecond instants round-trip exactly.
- **`zip::zip(mode = "cherry-pick")` stores nested files under their base
  names**; the bundle writer uses `mode = "mirror"`. **`zip::unzip()`
  follows `../` entries and writes outside `exdir`**, so entries are
  validated via `zip_list()` before extraction.
- **`typed(type, ...)` has a formal named `type`**; a wrapper with a `type`
  field (the attachment record's MIME type) must be built by hand.
- **Shiny's URL encoder is `httpuv::encodeURIComponent`** (JavaScript
  rules); `utils::URLencode` differs. `MockShinySession$clientData` reports
  a numeric `url_port`.
- **The restore settles on the client's quiet period**, which normally beats
  the timeout; `timed_out` is `TRUE` only when the app stays busy. A
  never-appearing input is `missing` at the normal settle. A deterministic
  browser test of the timeout branch is not practical; it is covered
  server-side.
- **Outputs on hidden tabs are suspended**, so dynamic UI on an inactive tab
  does not render and its inputs stay `missing` unless the app sets
  `outputOptions(suspendWhenHidden = FALSE)` or the snapshot includes the
  tab id.

## Workflow

Each unit of work ends with `devtools::document()`, `devtools::test()`,
`devtools::check()` at 0 errors / 0 warnings / 0 notes (the "New
submission" note under `--as-cran` is the only accepted one),
`styler::style_pkg()`, and one commit. Run the check with the browser tests
enabled at least once:

```r
rcmdcheck::rcmdcheck(".", args = c("--no-manual", "--as-cran"),
  check_dir = "/tmp/shinysnap-check", env = c(NOT_CRAN = "true"))
```

Practicalities:

- `Rscript -e '...'` mangles backslashes in R string literals on this
  machine. Feed scripts through `Rscript - <<'EOF' ... EOF`.
- Ad-hoc shinytest2 scripts need `NOT_CRAN=true` in the environment or
  `AppDriver$new()` refuses to start. Chrome is found via
  `chromote::find_chrome()`.
- When the R side sends a message but nothing happens in the browser,
  inspect `window.shinysnap.transaction()` and set
  `window.shinysnap.debug = true` (or `snap_enable(verbose = TRUE)`) to get
  per-input console logs; `app$get_logs()` shows them.
- `devtools::test()` runs the browser suites (about a minute each); use
  `filter =` for a fast loop. Names: `codec`, `io`, `snapshot`, `take`,
  `ui`, `restore-server`, `restorers`, `interop`, `namespace`,
  `browser-0N-*`. Beware that `filter = "ui"` also matches
  `browser-02-dynamic-ui`.
- Under `covr`, `identical()` against `restorer_*` functions fails because
  `builtin_restorers` captured the closures at build time; compare
  behavior, not identity. `restorers-builtin.R` shows falsely low coverage
  for the same reason; real coverage is about 96 percent.

## Testing conventions

- `testServer()` tests simulate the client: replace the controller's
  `send` field to capture outgoing messages, set `.shinysnap_ready` and
  `.shinysnap_inventory` with `session$setInputs()`, and answer a restore by
  setting `.shinysnap_result` to `list(txn, elapsed, timedOut, results)`.
  `settle_promise()` in `helper-promise.R` drives the event loop until a
  promise settles.
- Browser tests use the example apps under `inst/examples/` through
  shinytest2 with `variant = NULL` and read state with
  `exportTestValues()` (`snapshot` as JSON text, `reports` as lists) rather
  than screenshots. Wait with `wait_for_value()` on a value that changes
  (`ignore = list(<previous value>)`); never `Sys.sleep()`. Helpers live in
  `helper-browser.R` (`start_app()`, `wait_for_inventory()`,
  `restore_json()`, `restore_upload()`, `expect_all_restored()`).
- When adding a binding to the built-in restorer table, add it to an example
  app and assert its round trip in a browser test; the payload shape is not
  something to reason about from docs.

## Coding and documentation conventions

- Base-R-leaning, dependency-light. Imports are added only when first used
  (a declared but unused import is a check note). Use `pkg::fun()`; the one
  `@importFrom` is `R6Class`.
- roxygen2 with markdown; every export has `@returns` and `@examples`
  (server-side functions guard examples with `if (interactive())`);
  internal functions use `@noRd`.
- Errors are classed: everything inherits `shinysnap_error`, with specific
  classes such as `shinysnap_format_error`, `shinysnap_unsupported_value`,
  `shinysnap_unknown_type`, `shinysnap_untrusted` (a warning),
  `shinysnap_cancelled`, `shinysnap_restore_error`,
  `shinysnap_unsafe_bundle`, `shinysnap_no_session`. Raise them with
  `snap_abort()`/`snap_warn()` and test with `expect_error(class = )`.
- Prose: "snapshot file", "saved state", "take/restore a snapshot"; avoid
  "snap" as a noun. Example apps and documentation use generic terms
  (models, weights, preferences).
- The JSON format is normative in `vignettes/format-spec.Rmd`; a change to
  the codec is a change to that vignette, and an incompatible one bumps
  `format`.
