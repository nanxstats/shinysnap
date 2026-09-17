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
#' @returns A function that removes the hook again, invisibly.
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
