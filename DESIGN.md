# shinysnap design

shinysnap lets the users of a Shiny app save their work to a file and
pick it up later, in another session, possibly on a newer version of the
app. It takes a *snapshot* of the running app (the input values plus the
server-side values the app registers), writes it to a plain JSON file,
and restores it into a running session without a page reload and without
`enableBookmarking()`. The word is used in the sense of a virtual
machine or file system snapshot; the package has nothing to do with
snapshot testing or screenshots.

The package replaces a pattern that parameter-heavy apps grow by hand:
`reactiveValuesToList(input)` into an `.rds` file, then, on upload, a
loop of `session$sendInputMessage()` calls, a special case for inputs
whose message is not `{value: x}`, a per-field
[`is.null()`](https://rdrr.io/r/base/NULL.html) fallback for values
added in later versions, and waves of `shinyjs::delay()` because inputs
inside `renderUI()` do not exist yet when the first messages are sent.
The design goals, in priority order, are: minimal developer work in an
R-native way; reuse of Shiny’s own machinery through public surface
only; a canonical, readable format; lifecycle (app identity, validation,
migration, a report) as a first-class concern; and a small dependency
footprint.

## Layers

1.  **Codec and format.** `encode_value()` and `decode_value()` turn R
    values into a JSON-ready tree and back; a hand-written JSON writer
    and a reader built on
    [`jsonlite::parse_json()`](https://jeroen.r-universe.dev/jsonlite/reference/read_json.html)
    serialize that tree; the bundle writer and reader wrap the same JSON
    in a zip archive. This layer does not depend on Shiny. Its unit
    tests are a round-trip corpus of Shiny-realistic values.
2.  **Session state.** `SnapController` is an R6 object created lazily
    by the first `snap_*()` server call and stored in
    `session$rootScope()$userData$.shinysnap`. It holds the
    configuration, the tracked `reactiveValues`, the hook managers, the
    session-level restorer registry, the transaction in flight, and a
    reactive `restoring` flag. There is one per session, shared by all
    modules.
3.  **Capture.**
    [`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md)
    reads the root session’s inputs in isolation, filters them against
    the client inventory and the exclusion rules, collects the tracked
    values and the save hooks’ additions, and returns a snapshot object.
    It never writes files.
4.  **Restore transaction.**
    [`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
    on the server and the restore half of `inst/www/shinysnap.js` in the
    browser cooperate to apply a snapshot and report the outcome. This
    is the layer with the most design in it and is described in detail
    below.
5.  **Helpers and interop.** Download and upload helpers remove the
    `downloadHandler()`/`observeEvent()` boilerplate;
    [`snap_as_bookmark_url()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md),
    [`snap_as_test_inputs()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md),
    [`snap_attachment()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md),
    and
    [`snap_diff()`](https://nanx.me/shinysnap/reference/snap_diff.md)
    connect snapshots to URL bookmarking, `testServer()`, bundles, and
    version control.

Stateful things use R6: the controller and the transaction environment.
Declarative things are plain S3 lists: the snapshot, the restore report,
the diff, and the restore handle. Users may
[`str()`](https://rdrr.io/r/utils/str.html) a snapshot and hand-edit it.

## The snapshot object and the file

A snapshot is a list of class `shinysnap` with the fields `format`,
`app` (`name`, `version`), `created`, `producer`, `inputs`, `values`,
`bindings`, `attachments`, and `meta`. `inputs` and `values` hold
ordinary R values, exactly what `input$x` returns; the codec applies
only at write and read time. `bindings` records, per input id, the name
of the client-side binding that produced the value, because the restore
needs to know which payload a binding understands.

The JSON file is the canonical format and is meant to be read by people.
Three decisions shape it:

- **Exact and minimal numbers.** Doubles are written with
  [`zmij::format_double()`](https://nanx.me/zmij/reference/format_double.html),
  the shortest decimal that reads back to the same double, and always
  contain a `.` or an `e`; integers are plain digit runs. jsonlite
  parses `1` as an integer and `1.0` as a double, so the two storage
  types survive without a wrapper. The writer never passes numbers
  through
  [`jsonlite::toJSON()`](https://jeroen.r-universe.dev/jsonlite/reference/fromJSON.html),
  whose digit handling is lossy.
- **A small set of typed wrappers** for what JSON cannot say: the
  storage type of an empty vector, `NA` as opposed to `NULL`, non-finite
  doubles, names, `Date`, `POSIXct`, `difftime`, factors, matrices
  (column-major), data frames, and lists that are not fully named. The
  format describes values, not R objects; other attributes are dropped.
  The rules are normative in `vignettes/format-spec.Rmd`.
- **Determinism.** Fixed key order, sorted input ids, and a layout rule
  (inline when a container fits in 80 columns, one element per line
  otherwise) make identical states byte-identical, so files diff well
  under version control.

Two smaller points. `POSIXct` is written at millisecond precision,
rounded rather than truncated (R’s `%OS3` truncates), and read back as
whole seconds plus a decimal fraction, which is how R itself constructs
such values, so millisecond instants round-trip exactly. And the writer
always stamps `producer` with the versions of shinysnap, shiny, and R
doing the writing, while `created` records when the state was captured.

The `format` field belongs to the package and is bumped only for
incompatible changes; readers accept every earlier format. The
`app$version` field belongs to the app and drives its `migrate` hook.

### Bundles and trust

The zip bundle exists because two things do not fit in JSON: uploaded
files and R objects the codec cannot describe. A bundle holds
`manifest.json` (the same JSON, with an `attachments` section of
`{"$type": "file"}` records), `attachments/<id>/<name>` for each
`fileInput()` value captured, and `objects/<n>-<path>.rds` for values
written with `unsupported = "rds"`. The snapshot’s `inputs` never
contain file input values, because a browser’s file input cannot be set
programmatically; restore hooks read the attachment instead.

Anything that unserializes R data is gated behind `trust = TRUE`:
embedded `{"$type": "rds"}` wrappers, bundled objects, and the `.rds`
file format itself. Without it, such values decode to `NULL` with one
warning that lists them, so a JSON file or a bundle is always safe to
open. A bundle is validated before extraction, since
[`zip::unzip()`](https://r-lib.github.io/zip/reference/unzip.html)
follows `../` entries and writes outside its target directory: entries
with parent-directory components or absolute paths are refused, the
uncompressed total is capped by
`getOption("shinysnap.max_bundle_bytes")`, and every path named in the
manifest must resolve to a regular file inside the extraction directory,
under `attachments/` or `objects/`.

## Data flow: save

    button click -> snap_download_handler() -> snap_take() -> snap_write() -> file

[`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md) works
from the root session so that ids are always fully namespaced, and reads
everything inside `isolate()` so that a call from a reactive context
never creates dependencies. What it keeps:

- **Live inputs only.** Shiny never deletes an input value, so
  `reactiveValuesToList(input)` still holds values of inputs whose
  dynamic UI has been removed. The client script maintains an
  *inventory*, a map from bound input id to binding name, and re-sends
  it (debounced) on every `shiny:bound`/`shiny:unbound` event and after
  a reconnect. The inventory is the truth about what is on the page; ids
  absent from it are dropped, and their binding names are recorded in
  `bindings`. Inputs that are not bound elements (values set from
  JavaScript, plot events) are absent from the inventory by
  construction, which is the right signal that they cannot be restored
  through a binding.
- **Shiny’s own exclusions.** Values that a serializer registered with
  `setSerializer()` marks as unserializable (passwords) are dropped and
  other serializers are applied; ids in `session$getBookmarkExclude()`
  are dropped; action button values are dropped by class; file inputs
  are moved to `attachments` (recognized through the inventory binding,
  with the data frame shape as fallback, because an empty file input’s
  value is `NULL`).
- **Patterns.** `exclude` and `include` regular expressions from
  [`snap_enable()`](https://nanx.me/shinysnap/reference/snap_enable.md),
  [`snap_exclude()`](https://nanx.me/shinysnap/reference/snap_exclude.md),
  [`snap_include()`](https://nanx.me/shinysnap/reference/snap_exclude.md),
  and the call itself, matched against full ids.
- **Values.** For each `reactiveValues` registered with
  [`snap_track()`](https://nanx.me/shinysnap/reference/snap_track.md),
  the listed fields; then the
  [`snap_on_save()`](https://nanx.me/shinysnap/reference/snap_on_save.md)
  hooks run with a `state` whose `values` is an environment, the same
  idiom as shiny’s `onBookmark()`, so hooks from several modules cannot
  overwrite each other. Inside a module the hook sees the module’s
  inputs without the prefix and its values are stored under namespaced
  names.

## Data flow: restore

    upload -> snap_file_restore() -> snap_read()
      -> validate(snapshot) -> migrate(snapshot, from_version) -> built-in checks
      -> plan: exclusions, restorer per input -> records {id, binding, message, expect}
      -> cancel the transaction in flight, if any
      -> tracked values written back (isolate) -> on_restore hooks
      -> restoreContext primed with the snapshot's inputs
      -> sendCustomMessage("shinysnap:restore", records)         [server -> client]
           client: apply bound inputs now; keep the rest pending;
                   on shiny:bound, apply (deferred one macrotask);
                   settle after a quiet period or at the timeout
      -> .shinysnap_result input {txn, elapsed, timedOut, results}  [client -> server]
      -> restoreContext put back -> report -> on_restored hooks
      -> warning/error policy for missing and failed -> promise resolves

Everything before “cancel” is preparation and raises errors
synchronously: an unreadable file, a failing `validate` or `migrate`, a
file from a different app (when both names are known), or ids that are
not plausible. Nothing has been touched at that point. Everything after
it belongs to the transaction and reports problems through the promise.

### Why two delivery mechanisms

The root cause of the delay waves is in Shiny’s `inputMessages` handler:
for each message it looks for a bound element with that id and drops the
message silently when there is none. shinysnap never routes restore
values through `sendInputMessage()`. It uses two mechanisms that
complement each other:

- **The apply-on-bind queue** (client). The server sends all records at
  once. The client applies those whose input is on the page through the
  binding’s own `receiveMessage()`, the documented contract that
  `update*()` functions use, and keeps the rest pending for the lifetime
  of the transaction. A document-level `shiny:bound` handler applies a
  pending record when its input appears, and applies it again when an
  input with the same id is re-rendered, so the cascade select -\>
  branch -\> nested branch needs no timing configuration and a same-id
  re-render ends with the restored value.
- **The `restoreInput()` accelerator** (server). Every built-in input
  constructor calls `restoreInput(id, default)`, which returns a value
  from the session’s `RestoreContext` when one is available.
  [`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
  sets that context to the snapshot’s inputs for the duration of the
  transaction, so dynamic UI that renders during the restore is built
  with the restored values already in the HTML: no flash of defaults,
  and observers watching those inputs fire once. The context’s previous
  contents are captured first and put back when the transaction ends, so
  an app that itself started from a native bookmark is not disturbed.
  The client recognizes an element that already carries the expected
  value when it binds and reports it as `constructed` without applying
  it again.

The accelerator is feature-detected (`MockShinySession` has no restore
context) and can be turned off with `use_restore_context = FALSE`; the
queue alone still ends in the right state, with dynamic inputs reported
as `applied` or `reapplied`.

### The ordering trap

Shiny reads a newly bound element’s initial value before it triggers
`shiny:bound`, and sends those initial values to the server after
`bindAll()` resumes. A value applied synchronously from the bound event
is therefore overwritten by the default a moment later. The client
defers every apply from that event with `setTimeout(fn, 0)`; a microtask
is not late enough because `bindAll()` itself resumes in a microtask.

### Payloads and restorers

Bindings do not share one message format. A *restorer* is a function
`function(id, value, binding, session)` that returns the message a
binding understands, or `NULL` to skip the input. The default is
`list(value = value)` with attributes stripped; built-in restorers cover
the exceptions verified in the bindings’ source: selection inputs clear
with `[]` (radio buttons want a scalar otherwise, because `setValue()`
escapes the value as a string), date ranges want `{start, end}`, date
and date-time sliders want milliseconds, bslib’s accordion and sidebar
want `{method, values}` and `{method}`, and shinyMatrix wants
`{data, rownames, colnames}`. Restorers must not call `update*()`
functions, which would route through the dropping handler. Resolution
goes from a session restorer for the id, to a session restorer for the
binding, to the global registry, to the built-ins, to the default.

Because a binding’s `getValue()` does not always return the shape its
message carries (a date slider reports `"YYYY-MM-DD"` strings), each
record also carries an `expect` value, by default the message’s `value`,
which a restorer can override through an attribute. After applying, the
client compares `getValue()` with `expect` (scalar and one-element array
equal, `null` and `[]` equal, object keys sorted) and reports
`mismatched` when they differ. Messages without a `value` key are
applied without comparison.

Payloads are serialized by `sendCustomMessage()` with shiny’s own
`toJSON()` settings, exactly as `sendInputMessage()` would serialize
them.

Component authors who own the JavaScript can register an *adapter*
(`window.shinysnap.registerAdapter(name, fn)`) that transforms the
message in the browser instead. Adapters run after the restorer, before
the `shiny:updateinput` event, which is triggered the way Shiny’s own
handler triggers it so that existing listeners keep working.

shinyMatrix registers its binding without a name, so `binding.name` is
undefined for it. The inventory falls back to the input type the binding
reports for the element, which is stable (`shinyMatrix.matrixNumeric`,
`shinyMatrix.matrixCharacter`), and the built-in restorers are keyed on
those names.

### Settling and the report

`shiny:idle` is sent when the server’s busy count returns to zero, which
is before the flush that carries new output HTML, so “idle” alone does
not mean the page is settled. The client keeps a last-activity
timestamp, touched by every apply and by `shiny:busy`, `shiny:message`,
`shiny:value`, and `shiny:bound`, and settles when the page is not busy,
no apply is in flight, and nothing has happened for `settle` seconds
(0.3 by default). A `timeout` (10 seconds by default) bounds the wait
when the app stays busy. On settle, records that were never applied are
`missing`.

The report is a data frame with one row per input and the statuses
`applied`, `constructed`, `reapplied`, `missing`, `failed`,
`mismatched`, and `skipped` (excluded, or skipped by the restorer), plus
the attributes `txn`, `elapsed`, `settled`, and `timed_out`. `missing`
and `failed` inputs produce one consolidated warning by default
(`unknown = "warn"`), nothing with `"skip"`, or a rejection with
`"error"`. Nothing is dropped silently.

### Cancellation and lifetime

A transaction is identified by a short random id echoed in every
message. A second
[`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
while one is in flight cancels the first: the client drops its pending
map, the previous restore context is put back, and the first promise
rejects with a condition of class `shinysnap_cancelled`. A result that
arrives for a cancelled transaction is ignored. When the client script
has not reported ready yet (it loads asynchronously when injected by the
server), the transaction waits for `.shinysnap_ready` with a one-shot
observer, and a cancellation while deferred destroys that observer. A
pending promise is rejected when the session ends.

### The handle instead of a promise

[`snap_restore()`](https://nanx.me/shinysnap/reference/snap_restore.md)
returns a `shinysnap_restore` handle, a list with the transaction id and
the promise, rather than the promise. Shiny checks the return value of
an observer with `is.promising()` and holds the flush cycle until a
returned promise resolves; our promise can only resolve after the
browser has seen the page go quiet, which requires that flush. An
observer that returned the promise would therefore stall its own
restore. A plain list is not promising, so the common pattern
`observeEvent(input$go, snap_restore(file))` is safe. `on_done` covers
callers who do not want promises,
[`snap_on_restored()`](https://nanx.me/shinysnap/reference/snap_on_restore.md)
covers hooks, and `handle$promise` is there for
[`promises::then()`](https://rstudio.github.io/promises/reference/then.html).
The package attaches a silent no-op handler to the promise so that a
caller who ignores the handle never triggers an unhandled promise error
for an expected cancellation.

[`snap_is_restoring()`](https://nanx.me/shinysnap/reference/snap_is_restoring.md)
reads a reactive flag when called inside a reactive context and an
isolated value otherwise, so it can be used both in observers that fire
because of the restore and in plain code.

## The client script

`inst/www/shinysnap.js` is plain ES2017 with no build step; jQuery is
available because Shiny loads it. It has two halves: the inventory
(`.shinysnap_inventory`, re-sent only when its content changes, and
`.shinysnap_ready`, sent with event priority so a reconnect re-triggers
the server’s observers) and the restore transaction (`shinysnap:restore`
and `shinysnap:cancel` message handlers, `.shinysnap_result`, also sent
with event priority). Applies are serialized through a promise chain so
that `receiveMessage()` calls never interleave. It exposes
`window.shinysnap` with `inventory()`, `transaction()` for debugging,
`registerAdapter()`, and a `debug` flag that
`snap_enable(verbose = TRUE)` turns on.

The script is attached explicitly by the UI helpers
([`snap_download_button()`](https://nanx.me/shinysnap/reference/snap_download_button.md),
[`snap_file_input()`](https://nanx.me/shinysnap/reference/snap_file_input.md),
or
[`snap_dependency()`](https://nanx.me/shinysnap/reference/snap_dependency.md)),
and otherwise injected on demand with
`insertUI("head", immediate = TRUE)` when the controller is created, the
pattern the rewind package uses. Injection is idempotent on the client,
and the script waits for both jQuery and Shiny to exist because it may
run before Shiny (in the head) or after it (injected).

The hidden inputs are prefixed `.shinysnap_`, which keeps them out of
`reactiveValuesToList(input)` and, because the controller marks them
unserializable through `setSerializer()`, out of native bookmark URLs.

## Modules

Ids in files and in messages are always the fully namespaced ids as they
appear in the DOM; messages to the client go through
`session$rootScope()` because `sendCustomMessage()`, unlike
`sendInputMessage()`, does not namespace.
[`snap_take()`](https://nanx.me/shinysnap/reference/snap_take.md) from
inside a module captures the whole app by default (`scope = "root"`) or
the module’s ids (`scope = "module"`), still as full ids. Tracked values
registered inside a module are stored under namespaced names, and hooks
registered inside a module see a scoped `state` (inputs and values with
the prefix removed, report rows filtered to the prefix), the same
shaping shiny applies to bookmark callbacks. A module is detected by
`inherits(session, "session_proxy")`, not by its namespace string,
because `MockShinySession` reports a prefix even at the root.

## Reuse of Shiny’s bookmarking machinery

The package deliberately builds on the public parts of
`enableBookmarking()` without needing it enabled:
`session$restoreContext` and `restoreInput()` for the accelerator,
`getBookmarkExclude()` for exclusions, `setSerializer()` metadata for
unserializable values and for hiding the internal inputs, the
`state$values` environment idiom for hooks, and the
`_inputs_&...&_values_&...` query encoding for
[`snap_as_bookmark_url()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md),
which reproduces `encodeShinySaveState()` including its JavaScript-style
percent-encoding (shiny’s encoder is
[`httpuv::encodeURIComponent`](https://rstudio.github.io/httpuv/reference/encodeURI.html),
which differs from
[`utils::URLencode`](https://rdrr.io/r/utils/URLencode.html)). What it
does not reuse is the `.rds` storage and the reload-based restore.

Nothing in the package uses `shiny:::`. Where a feature depends on an
object that may be absent (the restore context under
`MockShinySession`), it is feature-detected and the package degrades to
the queue alone.

## Confirmed scope

- Version 0.1 stores files on the local file system only. A store
  interface (for `pins`, for example) is future work.
- There is no input journal, no undo/redo, and no time travel.
- Cold restore by page reload is limited to the
  [`snap_as_bookmark_url()`](https://nanx.me/shinysnap/reference/snap_as_bookmark_url.md)
  helper; the package itself restores warm, into the running session.
- File inputs are captured as attachments, never restored into `input$`.
- Restorers ship for shiny, bslib, and shinyMatrix inputs. Inputs of
  other packages use the default `{value}` payload unless the app
  registers a restorer; shinyWidgets candidates are listed in
  [`vignette("custom-inputs")`](https://nanx.me/shinysnap/articles/custom-inputs.md)
  and are not guessed.
- Shiny for Python is out of scope.

## Open questions

- [`snap_restorer()`](https://nanx.me/shinysnap/reference/snap_restorer.md)
  registers globally by default (`session = NULL`), which is what a
  package or `global.R` wants, but a call inside a server function that
  forgets `session` also registers for every session. Should the default
  follow `getDefaultReactiveDomain()` and require an explicit `NULL` for
  global registration?
- Putting the previous restore context back rebuilds its input set,
  which forgets which values a native bookmark restore had already used.
  An app that started from a bookmark, restored a snapshot mid-session,
  and then re-rendered an input from the bookmark could pick up the
  bookmark’s value a second time. Is that edge case worth tracking the
  used marks?
- `restore_values()` assigns every field present in the file, including
  fields the tracked `reactiveValues` does not have yet. That is
  convenient for files from newer versions but means a stray key in a
  hand-edited file creates a field. Should tracked fields be the upper
  bound?
- Outputs on hidden tabs are suspended, so a `renderUI()` on an inactive
  tab does not render and its inputs are reported `missing` unless the
  app sets `suspendWhenHidden = FALSE` or the snapshot restores the tab.
  Could the transaction temporarily un-suspend outputs it needs, or is
  the documented workaround enough?
- Server-side selectize (`{url}` messages) is not handled; a value whose
  option has not been loaded is reported `mismatched`. A restorer that
  sends `{url}` plus the value would need the selectize configuration.
- The timeout branch of the client settle logic is covered only by
  server-side tests; a deterministic browser test would need a way to
  keep Shiny busy on purpose.
