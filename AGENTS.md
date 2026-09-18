# AGENTS.md

Guidelines for AI agents (and humans) working on shinysnap: how to work in
this repository, what to verify, and the traps that cost real debugging time
while the package was built.

The architecture, the data flows, and the reasons behind the design
decisions are in `DESIGN.md`. Read it before changing the codec, the
restore transaction, or the client script; this file does not repeat it.
The brief that produced the package is `deps-src/bootstrap.md`. The whole
`deps-src/` tree (the brief, vendored CRAN sources of shiny, bslib,
shinyMatrix, zmij, jsonlite, zip, prior-art packages) is gitignored and
regenerated with `okr sync`. Verify claims about Shiny internals against
those sources, not against memory.

## Rules for changes

- Never use `shiny:::` in package code. Feature-detect and degrade when
  something is missing (`MockShinySession$restoreContext` is `NULL`).
- Never `unserialize()`/`readRDS()` user-supplied data unless the caller
  passed `trust = TRUE`. JSON and bundles must be safe to open; validate
  archive entries before extracting.
- No timers or sleeps on the R side to wait for the UI.
- Wrap every read of `input` inside `snap_*()` functions in
  `shiny::isolate()`.
- Send messages to the client through `session$rootScope()` with fully
  namespaced ids; detect modules with `inherits(session, "session_proxy")`.
- Keep hidden internal inputs prefixed `.shinysnap_` and marked
  unserializable.
- Every input that enters a restore ends up in the report with a status;
  nothing is dropped silently.
- Never return a promise from an example or helper observer; end with
  `NULL` when the last expression is a `promises::then()`/`catch()`. See
  "The handle instead of a promise" in `DESIGN.md`.
- The JSON format is normative in `vignettes/format-spec.Rmd`. A change to
  the codec is a change to that vignette, and an incompatible change bumps
  `format`.
- Every claim about a binding's wire format is backed by a browser test
  that runs the real binding. When adding a binding to the built-in restorer
  table, add it to an example app and assert its round trip in a browser
  test.
- Never export anything named `snapshot*` (shiny's test machinery owns that
  family); all exports use the `snap_` prefix. `tests/testthat/test-namespace.R`
  enforces it.

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
- Browser tests must use `start_app()`, which registers app cleanup and
  starts the suite's shared browser with `TMPDIR`, `TMP`, and `TEMP` inside
  an owned temporary directory. Suite teardown closes Chrome before removing
  that directory; `AppDriver$stop()` alone only closes a browser session and
  can leave `com.google.Chrome.*` detritus in the check's temporary directory.
- When the R side sends a message but nothing happens in the browser,
  inspect `window.shinysnap.transaction()` and set
  `window.shinysnap.debug = true` (or `snap_enable(verbose = TRUE)`) to get
  per-input console logs; `app$get_logs()` shows them. A page stuck in
  `shiny-busy` after a restore usually means an observer returned a promise.
- `devtools::test()` runs the browser suites (about a minute each); use
  `filter =` for a fast loop. Names: `codec`, `io`, `snapshot`, `take`,
  `ui`, `restore-server`, `restorers`, `interop`, `namespace`,
  `browser-0N-*`. Beware that `filter = "ui"` also matches
  `browser-02-dynamic-ui`.
- Under `covr`, `identical()` against `restorer_*` functions fails because
  `builtin_restorers` captured the closures at build time; compare
  behavior, not identity. `restorers-builtin.R` shows falsely low coverage
  for the same reason; real coverage is about 96 percent.
- `pkgdown::check_pkgdown()` must pass after adding an exported topic; the
  reference index in `_pkgdown.yml` lists topics by group.

## Testing conventions

- `testServer()` tests simulate the client: replace the controller's
  `send` field to capture outgoing messages, set `.shinysnap_ready` and
  `.shinysnap_inventory` with `session$setInputs()`, and answer a restore by
  setting `.shinysnap_result` to `list(txn, elapsed, timedOut, results)`.
  `settle_promise()` in `helper-promise.R` drives the event loop until a
  promise (or a restore handle) settles.
- Browser tests use the example apps under `inst/examples/` through
  shinytest2 with `variant = NULL` and read state with
  `exportTestValues()` (`snapshot` as JSON text, `reports` as lists) rather
  than screenshots. Wait with `wait_for_value()` on a value that changes
  (`ignore = list(<previous value>)`); never `Sys.sleep()`. Helpers live in
  `helper-browser.R` (`start_app()`, `wait_for_inventory()`,
  `restore_json()`, `restore_upload()`, `expect_all_restored()`).
- A restore settles on the client's quiet period, which normally beats the
  timeout, so a never-appearing input is `missing` with `timed_out = FALSE`.
  Do not write a browser test that expects a timeout; the timeout branch is
  covered server-side.

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

## Traps that are easy to reintroduce

Each of these is explained in `DESIGN.md`; this is the checklist.

- `radioButtons` wants a scalar value; `checkboxGroupInput` and
  `selectInput` accept arrays. The wrong shape shows up in the browser as
  `n.replace is not a function`.
- Applies from the `shiny:bound` handler must be deferred with
  `setTimeout(fn, 0)`, or the element's initial value overwrites the
  restored one.
- `typed(type, ...)` has a formal named `type`; a wrapper with a `type`
  field (the attachment record) must be built by hand.
- `zip::zip(mode = "cherry-pick")` stores nested files under their base
  names; the bundle writer uses `mode = "mirror"`.
- shiny's `toJSON()` turns named atomic vectors into objects (with a
  warning); restorer payloads strip names.
- `MockShinySession$clientData` reports a numeric `url_port`, and its
  namespace prefix is `mock-session-` even at the root.
- R's `%OS3` truncates; the codec rounds POSIXct to milliseconds itself.
