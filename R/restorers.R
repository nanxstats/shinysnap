# The package-global registry of user-registered restorers.
global_restorers <- new.env(parent = emptyenv())

#' Register how an input is restored
#'
#' A *restorer* turns the value stored in a snapshot into the message that
#' the input's client-side binding understands, that is, what the matching
#' `update*Input()` function would send. shinysnap ships restorers for the
#' inputs of shiny, bslib, and shinyMatrix (see [snap_restorers()]); the
#' default for everything else is `list(value = value)`. Register your own
#' for an input id or for a binding name (for example `"shinyWidgets.pickerInput"`).
#'
#' `fn` is called as `fn(id, value, binding, session)` and must return the
#' message as a list, or `NULL` to skip the input (reported as `skipped`).
#' It must not call `update*()` functions itself: those go through
#' `session$sendInputMessage()`, which silently drops messages for inputs
#' that are not on the page yet. To find the right payload, read the
#' `update*()` function's source and keep the part that carries the value.
#'
#' Optionally, the returned list may carry an attribute `expect` holding the
#' value the binding's `getValue()` is expected to return after the message
#' was applied; the client uses it to report `mismatched` when the widget
#' shows something else. By default the message's `value` is used.
#'
#' Resolution order when restoring an input: a session restorer for the id,
#' a session restorer for its binding, a global restorer for the id or the
#' binding, the built-in restorer for the binding, the default.
#'
#' @param x An input id or a binding name, as reported in the snapshot's
#'   `bindings` section.
#' @param fn The restorer function, or `NULL` to remove a registration.
#' @param session A Shiny session to register the restorer for that session
#'   only, or `NULL` (the default) to register it globally.
#'
#' @returns `snap_restorer()` returns `fn` invisibly. `snap_restorers()`
#'   returns a data frame with the columns `name` and `scope` (`"builtin"`,
#'   `"global"`, or `"session"`).
#'
#' @examples
#' # A restorer for a hypothetical widget that expects a selected field:
#' snap_restorer("mypkg.myInput", function(id, value, binding, session) {
#'   list(selected = value)
#' })
#' snap_restorers()
#' snap_restorer("mypkg.myInput", NULL)
#' @export
snap_restorer <- function(x, fn, session = NULL) {
  if (!is_string(x) || !nzchar(x)) {
    snap_abort("`x` must be a single input id or binding name.")
  }
  if (!is.null(fn) && !is.function(fn)) {
    snap_abort("`fn` must be a function `function(id, value, binding, session)` or NULL.")
  }
  if (is.null(session)) {
    if (is.null(fn)) {
      if (exists(x, envir = global_restorers, inherits = FALSE)) {
        rm(list = x, envir = global_restorers)
      }
    } else {
      assign(x, fn, envir = global_restorers)
    }
  } else {
    ctrl <- snap_controller(session)
    ctrl$restorers[[x]] <- fn
  }
  invisible(fn)
}

#' @rdname snap_restorer
#' @export
snap_restorers <- function(session = shiny::getDefaultReactiveDomain()) {
  scoped <- function(names, scope) {
    data.frame(
      name = as.character(names), scope = rep(scope, length(names)),
      stringsAsFactors = FALSE
    )
  }
  rows <- list(
    scoped(names(builtin_restorers), "builtin"),
    scoped(sort(ls(global_restorers), method = "radix"), "global")
  )
  if (!is.null(session)) {
    ctrl <- snap_controller(session, create = FALSE)
    if (!is.null(ctrl) && length(ctrl$restorers)) {
      rows <- c(rows, list(scoped(names(ctrl$restorers), "session")))
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' Find the restorer for an input
#'
#' @noRd
resolve_restorer <- function(id, binding, ctrl) {
  lookup <- function(registry, key) {
    if (!nzchar(key)) {
      return(NULL)
    }
    if (is.environment(registry)) {
      if (exists(key, envir = registry, inherits = FALSE)) {
        return(get(key, envir = registry, inherits = FALSE))
      }
      return(NULL)
    }
    registry[[key]]
  }
  lookup(ctrl$restorers, id) %||%
    lookup(ctrl$restorers, binding) %||%
    lookup(global_restorers, id) %||%
    lookup(global_restorers, binding) %||%
    lookup(builtin_restorers, binding) %||%
    restorer_default
}

#' Attach the value the client should see after applying a payload
#'
#' @noRd
with_expect <- function(payload, expect) {
  attr(payload, "expect") <- list(expect)
  payload
}

#' Build the client record for one input
#'
#' @noRd
build_record <- function(id, binding, payload) {
  expect <- attr(payload, "expect", exact = TRUE)
  attr(payload, "expect") <- NULL
  record <- list(id = id, binding = binding, message = payload)
  if (!is.null(expect)) {
    record["expect"] <- expect
  } else if ("value" %in% names(payload)) {
    record["expect"] <- list(payload[["value"]])
  }
  record
}
