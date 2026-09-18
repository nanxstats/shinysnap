# AGENTS.md

This file explains how to work on shinysnap, what to check, and which
mistakes to watch for.

Read `DESIGN.md` before changing how values are encoded, how a restore
works, or how the browser script behaves. It explains the package's
structure and the reasons for its design.

The original brief is in `deps-src/bootstrap.md`. The `deps-src/`
directory also contains copies of package sources, including shiny,
bslib, shinyMatrix, zmij, jsonlite, zip, and related packages. It is
excluded from git and regenerated with `okr sync`. Check these sources
when making claims about Shiny internals.

## Rules for changes

- Never use `shiny:::` in package code. Check whether a feature is
  available and provide a fallback when it is missing. For example,
  `MockShinySession$restoreContext` is `NULL`.
- Never call `unserialize()` or `readRDS()` on data supplied by a user
  unless the caller passed `trust = TRUE`. JSON and bundles must be safe
  to open. Check archive entries before extracting them.
- No timers or sleeps on the R side to wait for the UI.
- Wrap every read of `input` inside `snap_*()` functions in
  `shiny::isolate()`.
- Send messages to the client through `session$rootScope()` with fully
  namespaced ids; detect modules with `inherits(session, "session_proxy")`.
- Keep hidden internal inputs prefixed `.shinysnap_` and marked
  unserializable.
- Include every input considered for a restore in the report, with a
  status. Do not drop inputs silently.
- Never return a promise from an example or helper observer; end with
  `NULL` when the last expression is a `promises::then()`/`catch()`. See
  "Why the return value is a handle" in `DESIGN.md`.
- `vignettes/format-spec.Rmd` defines the JSON format. Update it whenever
  the encoding or decoding rules change. Increase `format` for an
  incompatible change.
- Back every claim about a binding's message format with a browser test
  that runs the actual binding. When adding a restorer to the package,
  add the input to an example app and test that saving and restoring it
  preserves its value in the browser.
- Never export anything named `snapshot*` (shiny's test machinery owns that
  family); all exports use the `snap_` prefix. `tests/testthat/test-namespace.R`
  enforces it.

## Workflow

For each unit of work, run `devtools::document()`, `devtools::test()`,
`devtools::check()`, and `styler::style_pkg()`, then make one commit.
Checks must finish with 0 errors, 0 warnings, and 0 notes. The only
exception is the "New submission" note under `--as-cran`.
Run the check with browser tests enabled at least once:

```r
rcmdcheck::rcmdcheck(".", args = c("--no-manual", "--as-cran"),
  check_dir = "/tmp/shinysnap-check", env = c(NOT_CRAN = "true"))
```

Practicalities:

- `Rscript -e '...'` mangles backslashes in R string literals on this
  machine. Feed scripts through `Rscript - <<'EOF' ... EOF`.
- Standalone shinytest2 scripts need `NOT_CRAN=true` in the environment or
  `AppDriver$new()` refuses to start. Chrome is found via
  `chromote::find_chrome()`.
- Browser tests must use `start_app()`, which registers app cleanup and
  starts the suite's shared browser with `TMPDIR`, `TMP`, and `TEMP` inside
  a temporary directory managed by the suite. Cleanup closes Chrome before
  removing that directory. `AppDriver$stop()` only closes a browser session
  and can leave `com.google.Chrome.*` files in the check's temporary directory.
  Keep the directory prefix short: the nested check path plus Chrome's
  `SingletonSocket` path must fit the Linux limit of 108 bytes for a Unix
  domain socket address. Normalize file paths before comparing them in
  tests that run on multiple platforms.
- When the R side sends a message but nothing happens in the browser,
  inspect `window.shinysnap.transaction()` and set
  `window.shinysnap.debug = true` (or `snap_enable(verbose = TRUE)`) to get
  console logs for each input; `app$get_logs()` shows them. A page stuck in
  `shiny-busy` after a restore usually means an observer returned a promise.
- `devtools::test()` runs the browser suites (about a minute each); use
  `filter =` to run a smaller selection. Names: `codec`, `io`, `snapshot`, `take`,
  `ui`, `restore-server`, `restorers`, `interop`, `namespace`,
  `browser-0N-*`. Beware that `filter = "ui"` also matches
  `browser-02-dynamic-ui`.
- Under `covr`, `identical()` against `restorer_*` functions fails because
  `builtin_restorers` captured the closures at build time; compare
  behavior instead. `restorers-builtin.R` shows falsely low coverage for
  the same reason; actual coverage is about 96 percent.
- `pkgdown::check_pkgdown()` must pass after adding an exported topic; the
  reference index in `_pkgdown.yml` lists topics by group.

## Testing conventions

- `testServer()` tests simulate the client: replace the controller's
  `send` field to capture outgoing messages, set `.shinysnap_ready` and
  `.shinysnap_inventory` with `session$setInputs()`, and answer a restore by
  setting `.shinysnap_result` to `list(txn, elapsed, timedOut, results)`.
  `settle_promise()` in `helper-promise.R` drives the event loop until a
  promise or restore handle completes.
- Browser tests use the example apps under `inst/examples/` through
  shinytest2 with `variant = NULL` and read state with
  `exportTestValues()` (`snapshot` as JSON text, `reports` as lists) rather
  than screenshots. Wait with `wait_for_value()` on a value that changes
  (`ignore = list(<previous value>)`); never `Sys.sleep()`. Helpers live in
  `helper-browser.R` (`start_app()`, `wait_for_inventory()`,
  `restore_json()`, `restore_upload()`, `expect_all_restored()`).
- A restore normally finishes after a quiet period in the browser, before
  the timeout. An input that never appears is therefore `missing` with
  `timed_out = FALSE`. Do not write a browser test that expects a timeout;
  tests on the server cover that case.

## Coding and documentation conventions

- Prefer base R and keep dependencies few. Add an import only when it is
  first used; an unused import causes a check note. Use `pkg::fun()`.
  The only `@importFrom` is `R6Class`.
- Use roxygen2 with markdown. Every export needs `@returns` and
  `@examples`. Guard examples for server functions with
  `if (interactive())`. Use `@noRd` for internal functions.
- Errors are classed: everything inherits `shinysnap_error`, with specific
  classes such as `shinysnap_format_error`, `shinysnap_unsupported_value`,
  `shinysnap_unknown_type`, `shinysnap_untrusted` (a warning),
  `shinysnap_cancelled`, `shinysnap_restore_error`,
  `shinysnap_unsafe_bundle`, `shinysnap_no_session`. Raise them with
  `snap_abort()`/`snap_warn()` and test with `expect_error(class = )`.
- Prose: "snapshot file", "saved state", "take/restore a snapshot"; avoid
  "snap" as a noun. Example apps and documentation use generic terms
  (models, weights, preferences).
- Write direct sentences that explain what the reader can do. Define
  technical terms when they are needed. Avoid jargon such as "normative"
  and "contract", and rewrite hyphenated phrases in prose. Keep exact
  names, paths, code, and standard identifiers as written. The docs in
  `deps-src/ellmer`, `deps-src/testthat`, and `deps-src/shinychat` are
  useful examples of the intended style.

## Common mistakes

`DESIGN.md` explains the reasons for these rules.

- `radioButtons` wants a scalar value; `checkboxGroupInput` and
  `selectInput` accept arrays. The wrong shape shows up in the browser as
  `n.replace is not a function`.
- Defer values applied from the `shiny:bound` handler with
  `setTimeout(fn, 0)`. Otherwise, the element's initial value overwrites
  the restored one.
- `typed(type, ...)` has a formal named `type`; a wrapper with a `type`
  field (the attachment record) must be built by hand.
- `zip::zip(mode = "cherry-pick")` stores nested files under their base
  names; the bundle writer uses `mode = "mirror"`.
- shiny's `toJSON()` turns named atomic vectors into objects (with a
  warning). Remove names from values in restorer messages.
- `MockShinySession$clientData` reports a numeric `url_port`, and its
  namespace prefix is `mock-session-` even at the root.
- R's `%OS3` truncates; the codec rounds POSIXct to milliseconds itself.
