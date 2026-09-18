# shinysnap design

shinysnap lets users save their work in a Shiny app and return to it later,
perhaps in a newer version of the app. A *snapshot* contains the input
values and any values the app chooses to keep from the server. The package
writes these to a JSON file and restores them in a running session without
reloading the page or requiring `enableBookmarking()`.

Apps with many inputs often develop their own code for this. Saving starts
with `reactiveValuesToList(input)` and an `.rds` file. Restoring requires
`session$sendInputMessage()` calls, special handling for inputs that expect
different messages, and defaults for fields added since the file was saved.
Dynamic inputs add another difficulty: messages sent before `renderUI()`
creates an input are lost, so apps often add `shinyjs::delay()` calls.

shinysnap handles these tasks in one place. Its design priorities are:

1. Make saving and restoring straightforward for an R developer.
2. Use Shiny's public interfaces wherever possible.
3. Keep snapshot files readable and consistently formatted.
4. Support app identification, validation, migration, and restore reports.
5. Keep dependencies few.

## Package structure

1. **Reading and writing.** `encode_value()` and `decode_value()` convert
   R values to and from a structure that JSON can represent. The package
   writes this structure as JSON and reads it with `jsonlite::parse_json()`.
   Bundles store the same JSON in a zip archive. This code does not depend
   on Shiny. Tests check that typical Shiny values survive writing and reading.
2. **Session state.** The first call to a `snap_*()` server function
   creates a `SnapController`, an R6 object stored in
   `session$rootScope()$userData$.shinysnap`. It keeps the configuration,
   tracked `reactiveValues`, hooks, registered restorers, current restore,
   and reactive `restoring` flag. All modules share one controller per session.
3. **Taking snapshots.** `snap_take()` reads the root session's inputs
   inside `isolate()`, selects inputs using the browser's list and the
   exclusion rules, and collects tracked values and additions from save
   hooks. It returns a snapshot without writing a file.
4. **Restoring snapshots.** `snap_restore()` on the server works with
   `inst/www/shinysnap.js` in the browser to restore values and report what
   happened. The steps are explained below.
5. **Helpers.** Download and upload helpers provide the
   `downloadHandler()` and `observeEvent()` code. `snap_as_bookmark_url()`,
   `snap_as_test_inputs()`, `snap_attachment()`, and `snap_diff()` let apps
   use snapshots with bookmarking, tests, uploaded files, and version control.

The controller and the environment for the current restore hold changing
state. Snapshots, reports, comparisons, and restore handles are ordinary
S3 lists. Users can inspect a snapshot with `str()` and edit it directly.

## The snapshot object and the file

A snapshot is a list of class `shinysnap` with the fields `format`, `app`
(`name`, `version`), `created`, `producer`, `inputs`, `values`, `bindings`,
`attachments`, and `meta`. `inputs` and `values` hold ordinary R values,
like those returned by `input$x`. They are encoded only when writing a
file and decoded when reading it. `bindings` records the name of each
input's JavaScript binding so the restore can send the message it expects.

JSON is the main file format. Three choices keep it readable and preserve
the values it stores:

- **Numbers keep their precision.** Doubles are written with
  `zmij::format_double()`, using the shortest decimal that reads back to
  the same double. They always contain a `.` or an `e`; integers use digits
  without a decimal point.
  jsonlite parses `1` as an integer and `1.0` as a double, so the two
  storage types survive without a wrapper. The writer never passes numbers
  through `jsonlite::toJSON()`, whose digit handling is lossy.
- **Extra type information preserves R values.** JSON objects with a
  `$type` field describe empty vectors, missing values, infinite values,
  `NaN`, names, dates, times, durations, factors, matrices, data frames,
  and lists that are not fully named. Matrix values are stored by column.
  Attributes not covered by these rules are dropped.
  `vignettes/format-spec.Rmd` defines the encoding rules.
- **Consistent layout makes changes easy to compare.** Keys have a fixed
  order and `snap_take()` sorts input ids. Objects and arrays stay on one
  line if they fit in 80 columns; otherwise, each element gets its own line.

`POSIXct` values are rounded to milliseconds before writing. R's `%OS3`
truncates, so the package handles rounding itself. Reading reconstructs
whole seconds plus a decimal fraction, as R does, to preserve values at
millisecond precision. The writer updates `producer` with the versions of
shinysnap, shiny, and R doing the writing. `created` records when the
snapshot was taken.

The package increases `format` only for incompatible changes and can read
every earlier format. The app controls `app$version`, which is passed to
its `migrate` hook.

### Bundles and trust

Zip bundles include uploaded files and R objects that the JSON format
does not support. A bundle contains:

- `manifest.json`: the snapshot JSON, with an `attachments` section of
  `{"$type": "file"}` records.
- `attachments/<id>/<name>`: each file saved from a `fileInput()`.
- `objects/<n>-<path>.rds`: values written with `unsupported = "rds"`.

Browsers do not allow code to set a file input, so its value is never
stored in `inputs`. Restore hooks read the saved attachment instead.

Reading serialized R data requires `trust = TRUE`. This applies to
embedded `{"$type": "rds"}` values, bundled objects, and `.rds` files.
Without it, embedded values become `NULL` with one warning listing them,
and `.rds` files are refused. JSON files and bundles can therefore be
opened without unserializing R objects.

Bundles are checked before extraction because `zip::unzip()` follows
`../` paths outside its target directory. Entries with `..` path components
or absolute paths are rejected. The total uncompressed size is limited by
`getOption("shinysnap.max_bundle_bytes")`. Every path in the manifest must
resolve to a regular file under `attachments/` or `objects/` inside the
extraction directory.

## Data flow: save

```
button click -> snap_download_handler() -> snap_take() -> snap_write() -> file
```

`snap_take()` uses the root session so ids include all module prefixes.
It reads values inside `isolate()` to avoid creating reactive dependencies.
It selects values as follows:

- **Inputs currently on the page.** Shiny never deletes an input value, so
  `reactiveValuesToList(input)` still holds values of inputs whose dynamic UI
  has been removed. The client script maintains an *inventory*, a map from
  bound input id to binding name. It sends an update after
  `shiny:bound` or `shiny:unbound` events and after reconnecting, combining
  events that occur close together. Inputs absent from this list are left
  out of the snapshot; retained inputs have their binding names recorded
  in `bindings`. Values without bound elements, such as values set from
  JavaScript and plot events, are absent from the list because they cannot
  be restored through a binding.
- **Shiny's own exclusions.** Serializers registered with `setSerializer()`
  are applied, and values they mark as unserializable, such as passwords,
  are left out. Inputs listed by `session$getBookmarkExclude()` are also
  excluded. Action buttons are identified by class and excluded. File
  inputs are saved as attachments, using their binding names to identify
  them or their data frame structure as a fallback. The binding name also
  identifies empty file inputs, whose value is `NULL`.
- **Selection patterns.** `exclude` and `include` regular expressions from
  `snap_enable()`, `snap_exclude()`, `snap_include()`, and the call itself,
  matched against full ids.
- **Values from the server.** The selected fields from each
  `reactiveValues` registered with `snap_track()` are collected. Then
  `snap_on_save()` hooks run with a `state` whose `values` is an environment,
  as in Shiny's `onBookmark()`. Hooks can add values to this shared
  environment. A hook registered in a module sees input ids without the
  module prefix, and its values are stored with that prefix.

## Data flow: restore

```
upload -> snap_file_restore() -> snap_read()
  -> validate(snapshot) -> migrate(snapshot, from_version) -> package checks
  -> select inputs and restorers -> records {id, binding, message, expect}
  -> cancel the current restore, if any
  -> tracked values written back (isolate) -> on_restore hooks
  -> restoreContext receives the snapshot's inputs
  -> sendCustomMessage("shinysnap:restore", records)         [server -> client]
       client: apply bound inputs now; keep the rest pending;
               on shiny:bound, apply after setTimeout(fn, 0);
               finish after a quiet period or at the timeout
  -> .shinysnap_result input {txn, elapsed, timedOut, results}  [client -> server]
  -> restoreContext put back -> report -> on_restored hooks
  -> warning/error policy for missing and failed -> promise resolves
```

Before cancelling any existing restore, `snap_restore()` checks the file,
runs `validate` and `migrate`, checks the app name when both names are
known, and checks input ids. Errors at this stage are raised immediately,
before changing the app. The remaining steps form a *restore transaction*,
which reports problems through a promise as the restore proceeds.

### How values reach dynamic inputs

Shiny's `inputMessages` handler looks for a bound element with the given
id. If there is none, it silently drops the message. To avoid losing
values this way, shinysnap delivers them in two ways:

- **The browser waits for inputs.** The server sends all records at once.
  The browser applies values to inputs already on the page through each
  binding's `receiveMessage()` method, which also handles messages from
  Shiny's `update*()` functions. It keeps the remaining records until the
  restore ends. A `shiny:bound` handler on the document applies values when
  their inputs appear, including when an input with the same id is created
  again. This lets nested dynamic UI restore without configured delays.
- **The server supplies initial values.** Shiny's input constructors call
  `restoreInput(id, default)`, which reads from the session's
  `RestoreContext` when a saved value is available. `snap_restore()` puts
  the snapshot's inputs in that context for the duration of the restore.
  New inputs then have their saved values in the HTML, avoiding a brief
  display of defaults and extra observer runs. The browser reports these
  inputs as `constructed` without applying their values again. When the
  restore ends, the previous context is put back so the app can continue
  using its bookmark state.

shinysnap checks whether the restore context is available;
`MockShinySession`, for example, has none. You can also disable it with
`use_restore_context = FALSE`. The browser still restores dynamic inputs,
which are then reported as `applied` or `reapplied`.

### Why the bound handler waits

Shiny reads a newly bound element's initial value before it triggers
`shiny:bound`, and sends those initial values to the server after
`bindAll()` resumes. A value applied synchronously from the bound event is
therefore overwritten by the default a moment later. The browser defers
each value applied from that event with `setTimeout(fn, 0)`. A microtask
is not late enough because `bindAll()` itself resumes in a microtask.

### Messages and restorers

Bindings accept different message formats. A *restorer* is a function
`function(id, value, binding, session)` that returns the expected message,
or `NULL` to skip the input. The default is `list(value = value)` with
attributes removed. The package includes restorers for exceptions checked
against the bindings' source:

- Selection inputs clear with `[]`. Otherwise, radio buttons need a scalar
  because `setValue()` escapes the value as a string.
- Date ranges expect `{start, end}`.
- Sliders for dates and times expect milliseconds.
- bslib accordions and sidebars expect `{method, values}` and `{method}`.
- shinyMatrix expects `{data, rownames, colnames}`.

Restorers must return messages without calling `update*()` functions,
which would send them through Shiny's handler and lose them if an input
is absent. shinysnap looks for a restorer in the current session by input
id, then by binding name. It next checks global registrations in the same
order, then restorers included in the package, and finally the default.

A binding's `getValue()` may return a different form from the message it
receives. For example, a date slider returns `"YYYY-MM-DD"` strings. Each
restore record therefore includes `expect`, which defaults to the
message's `value` but can be overridden by an attribute from the restorer.
After applying the message, the browser compares `getValue()` with `expect`
and reports `mismatched` if they differ. This comparison treats a scalar
and an array of length one as equal, treats `null` and `[]` as equal, and
sorts object keys. Messages without a `value` key are applied without a
comparison.

Messages are serialized by `sendCustomMessage()` with Shiny's `toJSON()`
settings, exactly as `sendInputMessage()` would serialize them.

Authors who maintain an input's JavaScript can register an *adapter*
(`window.shinysnap.registerAdapter(name, fn)`) that transforms the message
in the browser instead. Adapters run after the restorer, before the
`shiny:updateinput` event, which is triggered the way Shiny's own handler
triggers it so that existing listeners keep working.

shinyMatrix registers its binding without a name, so `binding.name` is
undefined for it. The inventory falls back to the input type the binding
reports for the element: `shinyMatrix.matrixNumeric` or
`shinyMatrix.matrixCharacter`. The package registers its restorers under
these names.

### When a restore finishes

`shiny:idle` is sent when the server's busy count returns to zero, which is
before the flush that sends new output HTML. An idle server therefore does
not guarantee that the page has finished updating. The browser records the
time whenever it applies a value or receives `shiny:busy`, `shiny:message`,
`shiny:value`, or `shiny:bound`. It finishes the restore when the page is
not busy, no value is being applied, and no activity has occurred for
`settle` seconds (0.3 by default). The `timeout` argument limits the wait
to 10 seconds by default. Inputs that never received a value are reported
as `missing`.

The report is a data frame with one row per input and the statuses
`applied`, `constructed`, `reapplied`, `missing`, `failed`, `mismatched`, and
`skipped` (excluded, or skipped by the restorer), plus the attributes `txn`,
`elapsed`, `settled`, and `timed_out`. `missing` and `failed` inputs produce
one warning by default (`unknown = "warn"`), nothing with `"skip"`, or a
rejection with `"error"`. Nothing is dropped silently.

### Cancelling a restore

Every restore has a short random id included in each message. Calling
`snap_restore()` during a restore cancels the first one: the browser drops
its pending records, the previous restore context is put back, and the
first promise rejects with class `shinysnap_cancelled`. Results for a
cancelled restore are ignored.

If the browser script is still loading, the restore waits for
`.shinysnap_ready` using an observer that runs once. Cancelling a restore
while it waits destroys this observer. Ending the session also rejects
any pending restore promise.

### Why the return value is a handle

`snap_restore()` returns a `shinysnap_restore` handle: a list containing
the restore id and its promise. This matters because Shiny checks an
observer's return value with `is.promising()`. If it is a promise, Shiny
waits for it before flushing updates to the browser. The restore needs
those updates before it can finish, so returning its promise would leave
both waiting indefinitely.

An ordinary list avoids this problem, making
`observeEvent(input$go, snap_restore(file))` safe. Callers can receive the
report through `on_done`, register a `snap_on_restored()` hook, or use
`promises::then()` with `handle$promise`. An observer that uses
`promises::then()` must still avoid returning that promise, for example by
ending with `NULL`.

The package attaches a handler that silently catches promise errors.
This prevents an expected cancellation from causing an unhandled promise
error when the caller ignores the handle.

`snap_is_restoring()` reads a reactive flag when called inside a reactive
context and an isolated value otherwise, so it can be used both in observers
that fire because of the restore and in plain code.

## The browser script

`inst/www/shinysnap.js` uses ES2017 with no build step and the jQuery
already loaded by Shiny. It has two parts:

- The inventory reports inputs currently on the page through
  `.shinysnap_inventory`, sent only when its contents change.
  `.shinysnap_ready` uses event priority so reconnecting triggers the
  server's observers again.
- The restore code handles `shinysnap:restore` and `shinysnap:cancel`
  messages and sends `.shinysnap_result` with event priority. It applies
  values in a promise chain so each `receiveMessage()` call finishes
  before the next starts.

The script exposes `window.shinysnap` with `inventory()` and
`transaction()` for debugging, `registerAdapter()` for custom inputs,
and a `debug` flag enabled by `snap_enable(verbose = TRUE)`.

The UI helpers `snap_download_button()`, `snap_file_input()`, and
`snap_dependency()` attach the script. Otherwise, the controller adds it
with `insertUI("head", immediate = TRUE)`, following the approach used by
the rewind package. Adding the script more than once has no effect.
It waits for jQuery and Shiny because it may load before or after them.

The hidden inputs are prefixed `.shinysnap_`, which keeps them out of
`reactiveValuesToList(input)` and, because the controller marks them
unserializable through `setSerializer()`, out of native bookmark URLs.

## Modules

Ids in files and messages include all module prefixes, as they appear
in the browser. Messages use `session$rootScope()` because
`sendCustomMessage()` does not add these prefixes. Inside a module,
`snap_take()` saves the whole app by default (`scope = "root"`). Use
`scope = "module"` to save only the module's inputs, still with full ids.

Tracked values registered inside a module are stored with its prefix.
Hooks registered there receive inputs and values with that prefix removed,
and report rows limited to the module. This follows Shiny's bookmark
callbacks. Modules are detected with `inherits(session, "session_proxy")`
because checking the prefix would misidentify a root `MockShinySession`,
which also reports a prefix.

## How shinysnap uses Shiny bookmarking

shinysnap uses these public parts of Shiny's bookmarking support without
requiring `enableBookmarking()`:

- `session$restoreContext` and `restoreInput()` supply initial values.
- `getBookmarkExclude()` provides input exclusions.
- `setSerializer()` marks values that cannot be saved, including the
  package's internal inputs.
- The `state$values` environment lets hooks add and retrieve saved values.
- The `_inputs_&...&_values_&...` query format is used by
  `snap_as_bookmark_url()`.

The bookmark helper matches `encodeShinySaveState()`, including its use
of `httpuv::encodeURIComponent`. This encoding differs from
`utils::URLencode`. Snapshots use their own file storage and restore in
the running session.

The package never uses `shiny:::`. It checks for features that may be
absent, such as the restore context in `MockShinySession`, and falls back
to restoring through the browser when necessary.

## Current limits

- Version 0.1 stores files on the local file system. Support for other
  storage, such as `pins`, is future work.
- The package does not record a history of input changes or provide undo
  and redo.
- Restores happen in the running session. To restore by opening a new
  page, use `snap_as_bookmark_url()` with Shiny bookmarking.
- File inputs are captured as attachments, never restored into `input$`.
- The package includes restorers for shiny, bslib, and shinyMatrix.
  Inputs from other packages receive the default `{value}` message unless
  the app registers a restorer. `vignette("custom-inputs")` lists
  shinyWidgets inputs that need further work.
- Shiny for Python is not supported.

## Open questions

- `snap_restorer()` registers for all sessions by default (`session = NULL`).
  This suits a package or `global.R`, but a call in a server function can
  accidentally affect other sessions if it omits `session`. Should the
  default use `getDefaultReactiveDomain()` and require an explicit `NULL`
  to register globally?
- Reinstating the previous restore context rebuilds its input set and
  forgets which bookmark values have already been used. An app could open
  a bookmark, restore a snapshot, then recreate an input and receive the
  bookmark value again. Should shinysnap also preserve the record of
  values already used?
- `restore_values()` assigns every field present in the file, including
  fields the tracked `reactiveValues` does not have yet. That is convenient
  for files from newer versions, but an extra key in a manually edited
  file also creates a field. Should the restore be limited to tracked fields?
- Outputs on hidden tabs are suspended, so a `renderUI()` on an inactive
  tab does not render and its inputs are reported `missing` unless the app
  sets `suspendWhenHidden = FALSE` or the snapshot restores the tab. Could
  restore temporarily enable the outputs it needs, or is the
  documented workaround enough?
- Selectize inputs that load choices from the server through `{url}`
  messages are not handled. A value whose choice has not loaded is
  reported as `mismatched`. Sending both `{url}` and the value would
  require access to the selectize configuration.
- Only tests on the server cover the restore timeout. A reliable browser
  test would need a way to keep Shiny busy on purpose.
