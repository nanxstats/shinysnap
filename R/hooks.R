#' A tiny callback manager
#'
#' Callbacks are stored under integer keys and invoked in registration
#' order. `add()` returns a function that removes the callback again. This
#' mirrors shiny's internal `Callbacks` class without depending on it.
#'
#' @noRd
new_callbacks <- function() {
  env <- new.env(parent = emptyenv())
  env$fns <- list()
  env$next_id <- 1L
  list(
    add = function(fn) {
      id <- as.character(env$next_id)
      env$next_id <- env$next_id + 1L
      env$fns[[id]] <- fn
      function() {
        env$fns[[id]] <- NULL
        invisible(NULL)
      }
    },
    invoke = function(...) {
      for (fn in env$fns) fn(...)
      invisible(NULL)
    },
    count = function() length(env$fns)
  )
}

#' Register a hook that runs when a snapshot is taken
#'
#' `snap_on_save()` registers a function that [snap_take()] calls after the
#' inputs and tracked values have been collected. It receives a `state`
#' object: `state$inputs` is the named list of captured input values and
#' `state$values` is an environment. Anything the hook assigns into
#' `state$values` is stored in the snapshot's `values` section, so several
#' hooks (and several modules) can contribute without overwriting each other,
#' just like shiny's `onBookmark()`.
#'
#' Inside a module, the hook sees only the module's inputs (with the
#' namespace prefix removed) and its values are stored under namespaced
#' names automatically.
#'
#' @param fn A function taking one argument, `state`.
#' @param session The Shiny session. Defaults to the current session.
#'
#' @returns A function with no arguments that removes the hook when called.
#'
#' @examples
#' if (interactive()) {
#'   library(shiny)
#'
#'   server <- function(input, output, session) {
#'     snap_on_save(function(state) {
#'       state$values$fitted_at <- format(Sys.time())
#'     })
#'   }
#' }
#' @export
snap_on_save <- function(fn, session = shiny::getDefaultReactiveDomain()) {
  session <- require_session(session, "snap_on_save")
  if (!is.function(fn)) {
    snap_abort("`fn` must be a function taking one argument, `state`.")
  }
  ctrl <- snap_controller(session)
  ctrl$on_save$add(scope_save_hook(fn, session))
}

#' Wrap a module's save hook so that it works on its own scope
#'
#' The wrapped hook sees the module's inputs without the namespace prefix
#' and writes into a fresh environment whose entries are copied into the
#' root state under namespaced names.
#'
#' @noRd
scope_save_hook <- function(fn, session) {
  if (!is_module_session(session)) {
    return(fn)
  }
  prefix <- session_prefix(session)
  function(state) {
    scoped <- state
    keep <- startsWith(names(state$inputs), prefix)
    scoped$inputs <- state$inputs[keep]
    names(scoped$inputs) <- substring(names(state$inputs)[keep], nchar(prefix) + 1L)
    scoped$values <- new.env(parent = emptyenv())
    fn(scoped)
    for (nm in ls(scoped$values, all.names = TRUE)) {
      assign(session$ns(nm), get(nm, envir = scoped$values), envir = state$values)
    }
    invisible(NULL)
  }
}

#' Register hooks that run around a restore
#'
#' `snap_on_restore()` registers a function that [snap_restore()] calls after
#' the tracked values have been written back and before the input values are
#' sent to the browser. `snap_on_restored()` registers a function that runs
#' once the browser reports that the restore has settled. Both receive a
#' `state` list with `inputs` (the named list of input values being restored),
#' `values` (the `values` section of the file), `snapshot` (the whole
#' snapshot), and `txn` (the transaction id); the `restored` hook also
#' receives the restore report.
#'
#' Inside a module, the hooks see only the module's inputs and values, with
#' the namespace prefix removed, and only the module's rows of the report.
#'
#' Errors raised by a hook abort the restore and reject its promise.
#'
#' @param fn A function taking `state` (and, for `snap_on_restored()`,
#'   `report`).
#' @param session The Shiny session. Defaults to the current session.
#'
#' @returns A function with no arguments that removes the hook when called.
#'
#' @examples
#' if (interactive()) {
#'   library(shiny)
#'
#'   server <- function(input, output, session) {
#'     snap_on_restore(function(state) {
#'       message("restoring ", length(state$inputs), " inputs")
#'     })
#'     snap_on_restored(function(state, report) {
#'       print(report)
#'     })
#'   }
#' }
#' @export
snap_on_restore <- function(fn, session = shiny::getDefaultReactiveDomain()) {
  session <- require_session(session, "snap_on_restore")
  if (!is.function(fn)) {
    snap_abort("`fn` must be a function taking one argument, `state`.")
  }
  ctrl <- snap_controller(session)
  ctrl$on_restore$add(scope_restore_hook(fn, session))
}

#' @rdname snap_on_restore
#' @export
snap_on_restored <- function(fn, session = shiny::getDefaultReactiveDomain()) {
  session <- require_session(session, "snap_on_restored")
  if (!is.function(fn)) {
    snap_abort("`fn` must be a function taking two arguments, `state` and `report`.")
  }
  ctrl <- snap_controller(session)
  ctrl$on_restored$add(scope_restored_hook(fn, session))
}

#' Filter and un-namespace a named list
#'
#' @noRd
scope_list <- function(x, prefix) {
  if (length(x) == 0L) {
    return(list())
  }
  keep <- startsWith(names(x), prefix)
  out <- x[keep]
  names(out) <- substring(names(x)[keep], nchar(prefix) + 1L)
  out
}

#' A restore `state` as seen from a module
#'
#' @noRd
scope_restore_state <- function(state, prefix) {
  state$inputs <- scope_list(state$inputs, prefix)
  state$values <- scope_list(state$values, prefix)
  state
}

#' @noRd
scope_restore_hook <- function(fn, session) {
  if (!is_module_session(session)) {
    return(fn)
  }
  prefix <- session_prefix(session)
  function(state) fn(scope_restore_state(state, prefix))
}

#' @noRd
scope_restored_hook <- function(fn, session) {
  if (!is_module_session(session)) {
    return(fn)
  }
  prefix <- session_prefix(session)
  function(state, report) {
    fn(
      scope_restore_state(state, prefix),
      subset_report(report, startsWith(report$id, prefix))
    )
  }
}
