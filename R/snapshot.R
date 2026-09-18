# The current version of the file format written by this package.
snap_format_version <- 1L

#' Construct a snapshot object
#'
#' Internal constructor; every field is normalized so that two snapshots with
#' the same content are `identical()`.
#'
#' @noRd
new_snapshot <- function(inputs = list(), values = list(), bindings = NULL,
                         attachments = list(), meta = list(), app = NULL,
                         created = NULL, producer = NULL,
                         format = snap_format_version) {
  x <- structure(
    list(
      format = as.integer(format),
      app = list(name = app$name, version = app$version),
      created = created,
      producer = producer,
      inputs = as_section(inputs),
      values = as_section(values),
      bindings = as_bindings(bindings),
      attachments = as_section(attachments),
      meta = as_section(meta)
    ),
    class = "shinysnap"
  )
  validate_snapshot(x)
}

#' Normalize a section: `NULL` or empty becomes `list()`
#'
#' @noRd
as_section <- function(x) {
  if (length(x) == 0L) list() else x
}

#' Normalize bindings: `NULL` or empty becomes `character()`
#'
#' @noRd
as_bindings <- function(x) {
  if (length(x) == 0L) character() else x
}

#' Check the structure of a snapshot object
#'
#' @noRd
validate_snapshot <- function(x) {
  fail <- function(...) {
    snap_abort(paste0("Invalid snapshot: ", ...), class = "shinysnap_invalid")
  }
  if (!is.list(x) || !inherits(x, "shinysnap")) {
    fail("expected a list of class \"shinysnap\".")
  }
  required <- c(
    "format", "app", "created", "producer", "inputs", "values", "bindings",
    "attachments", "meta"
  )
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    fail("missing field(s) ", quote_ids(missing), ".")
  }
  fmt <- x$format
  if (!is.numeric(fmt) || length(fmt) != 1L || is.na(fmt)) {
    fail("`format` must be a single integer.")
  }
  if (!is.list(x$app)) {
    fail("`app` must be a list.")
  }
  for (field in c("name", "version")) {
    v <- x$app[[field]]
    if (!is.null(v) && !is_string(v)) {
      fail("`app$", field, "` must be NULL or a single string.")
    }
  }
  if (!is.null(x$created) && !is_string(x$created)) {
    fail("`created` must be NULL or a single string.")
  }
  if (!is.null(x$producer) && !is.list(x$producer)) {
    fail("`producer` must be NULL or a list.")
  }
  for (field in c("inputs", "values", "attachments", "meta")) {
    v <- x[[field]]
    if (!is.list(v)) {
      fail("`", field, "` must be a list.")
    }
    if (length(v) > 0L && (!has_full_names(v) || anyDuplicated(names(v)))) {
      fail("`", field, "` must have unique, non-empty names.")
    }
  }
  b <- x$bindings
  if (!is.character(b)) {
    fail("`bindings` must be a character vector.")
  }
  if (length(b) > 0L && (!has_full_names(b) || anyDuplicated(names(b)) || anyNA(b))) {
    fail("`bindings` must be a named character vector with unique names.")
  }
  invisible(x)
}

#' Coerce to a snapshot
#'
#' Accepts a snapshot, a plain list with (some of) the snapshot fields, or
#' JSON text.
#'
#' @noRd
as_snapshot <- function(x) {
  if (inherits(x, "shinysnap")) {
    return(validate_snapshot(x))
  }
  if (is_string(x)) {
    if (looks_like_json(x)) {
      return(snap_unserialize(x))
    }
    if (file.exists(x)) {
      return(snap_read(x))
    }
    snap_abort(
      sprintf("`%s` is neither JSON text nor an existing file.", x),
      class = "shinysnap_invalid"
    )
  }
  if (is.list(x) && (length(x) == 0L || has_full_names(x))) {
    known <- intersect(names(x), names(formals(new_snapshot)))
    unknown <- setdiff(names(x), known)
    if (length(unknown)) {
      snap_abort(
        paste0("Unknown snapshot field(s): ", quote_ids(unknown), "."),
        class = "shinysnap_invalid"
      )
    }
    return(do.call(new_snapshot, x[known]))
  }
  snap_abort(
    "Expected a snapshot object, a list of snapshot fields, or JSON text.",
    class = "shinysnap_invalid"
  )
}

#' Does the string start with a JSON object?
#'
#' @noRd
looks_like_json <- function(x) {
  grepl("^\\s*\\{", x)
}

#' Access the parts of a snapshot
#'
#' `snap_inputs()` returns the captured input values (a named list keyed by
#' fully namespaced input ids), `snap_values()` the server-side values, and
#' `snap_meta()` the user-supplied metadata. See
#' [shinysnap-package][shinysnap] for the layout of the object.
#'
#' @param x A snapshot object.
#'
#' @returns A named list, possibly empty.
#'
#' @examples
#' snap <- snap_unserialize('{
#'   "format": 1,
#'   "inputs": {"n": 100, "rate": 0.025},
#'   "values": {"prefs": {"digits": 3, "scientific": false}},
#'   "meta": {"note": "baseline scenario"}
#' }')
#' snap_inputs(snap)
#' snap_values(snap)
#' snap_meta(snap)
#' @export
snap_inputs <- function(x) {
  as_snapshot(x)$inputs
}

#' @rdname snap_inputs
#' @export
snap_values <- function(x) {
  as_snapshot(x)$values
}

#' @rdname snap_inputs
#' @export
snap_meta <- function(x) {
  as_snapshot(x)$meta
}

#' Print, format, and coerce snapshots and restore results
#'
#' `print()` shows a compact summary: app name and version, creation time,
#' and the number and names of inputs, values, and attachments. `format()`
#' returns the same lines as a character vector. `as.list()` drops the class
#' and returns the underlying list.
#'
#' For a [snap_diff()] result, `print()` shows the changed entries and their
#' old and new values. For a [snap_restore()] handle, it shows the transaction
#' id; for a completed restore report, it shows the input statuses and the
#' elapsed time.
#'
#' @param x A snapshot object, a snapshot comparison from [snap_diff()], or
#'   a restore handle or report from [snap_restore()]. `format()` and
#'   `as.list()` accept snapshot objects only.
#' @param ... Passed to [print.data.frame()] when printing a snapshot
#'   comparison or restore report; ignored otherwise.
#'
#' @returns `print()` returns `x` invisibly; `format()` a character vector;
#'   `as.list()` a plain list.
#'
#' @examples
#' snap <- snap_unserialize('{
#'   "format": 1,
#'   "app": {"name": "myapp", "version": "2.4.1"},
#'   "created": "2026-09-16T18:22:03Z",
#'   "inputs": {"n": 100, "rate": 0.025}
#' }')
#' print(snap)
#' format(snap)
#' names(as.list(snap))
#' print(snap_diff(snap, list(inputs = list(n = 50, rate = 0.025))))
#'
#' if (interactive()) {
#'   library(shiny)
#'   ui <- fluidPage(
#'     numericInput("n", "n", 0),
#'     actionButton("restore", "Restore state")
#'   )
#'   server <- function(input, output, session) {
#'     observeEvent(input$restore, {
#'       handle <- snap_restore(list(inputs = list(n = 100)), on_done = print)
#'       print(handle)
#'     })
#'   }
#'   shinyApp(ui, server)
#' }
#' @export
print.shinysnap <- function(x, ...) {
  cat(format(x), sep = "\n")
  invisible(x)
}

#' @rdname print.shinysnap
#' @export
format.shinysnap <- function(x, ...) {
  app <- if (is.null(x$app$name)) "<none>" else x$app$name
  if (!is.null(x$app$version)) {
    app <- paste0(app, " (version ", x$app$version, ")")
  }
  c(
    "<shinysnap>",
    paste0("  app:         ", app),
    paste0("  created:     ", x$created %||% "<unset>"),
    paste0("  inputs:      ", summarize_ids(names(x$inputs))),
    paste0("  values:      ", summarize_ids(names(x$values))),
    paste0("  attachments: ", summarize_ids(names(x$attachments))),
    if (length(x$meta)) paste0("  meta:        ", summarize_ids(names(x$meta)))
  )
}

#' @rdname print.shinysnap
#' @export
as.list.shinysnap <- function(x, ...) {
  unclass(x)
}

#' "n (id1, id2, ...)" for a print summary
#'
#' @noRd
summarize_ids <- function(ids, max = 8L) {
  n <- length(ids)
  if (n == 0L) {
    return("0")
  }
  shown <- paste(utils::head(ids, max), collapse = ", ")
  if (n > max) shown <- paste0(shown, ", ...")
  sprintf("%d (%s)", n, shown)
}

#' Take a snapshot of the running app
#'
#' Captures the current input values and the registered server-side values
#' of the session into a snapshot object, ready for [snap_write()] or
#' [snap_serialize()]. Nothing is written to disk.
#'
#' @details
#' What is captured:
#'
#' * Inputs, by fully namespaced id, exactly as `input$id` returns them.
#'   With `live_only`, only inputs that are currently on the page are
#'   kept, so values of inputs whose dynamic UI has been removed are not
#'   carried along. Action buttons, password inputs, and values that shiny's
#'   own serializers mark as unserializable are never captured; ids excluded
#'   with `setBookmarkExclude()`, [snap_exclude()], or the `exclude` patterns
#'   are dropped. File inputs are moved to the snapshot's `attachments`.
#' * The name of the client-side input binding of each captured input, in
#'   `bindings`.
#' * Values: the fields of every `reactiveValues` registered with
#'   [snap_track()], then whatever the [snap_on_save()] hooks add.
#'
#' The function isolates every read, so it never creates reactive
#' dependencies. Inputs with a rate policy (text inputs debounce, sliders
#' throttle) may lag the browser by a few hundred milliseconds; a snapshot
#' taken from a download handler runs after the click has reached the
#' server, which in practice is later than that.
#'
#' @param session The Shiny session. Defaults to the current session.
#' @param ... Not used; arguments after `session` must be named.
#' @param include,exclude Regular expressions matched against fully
#'   namespaced ids, in addition to those configured with [snap_enable()].
#' @param live_only Keep only inputs currently on the page. Defaults to the
#'   value configured with [snap_enable()] (`TRUE`).
#' @param values Capture tracked values and run the save hooks? `FALSE`
#'   captures inputs only.
#' @param scope `"root"` (the default) captures the whole app with full ids,
#'   even when called inside a module; `"module"` keeps only ids under the
#'   calling module's namespace (still as full ids).
#' @param meta A named list of free-form metadata stored in the snapshot.
#'
#' @returns A snapshot object of class `shinysnap`.
#'
#' @examples
#' if (interactive()) {
#'   library(shiny)
#'
#'   server <- function(input, output, session) {
#'     observeEvent(input$show, {
#'       print(snap_take())
#'     })
#'   }
#' }
#' @export
snap_take <- function(session = shiny::getDefaultReactiveDomain(), ...,
                      include = NULL, exclude = NULL, live_only = NULL,
                      values = TRUE, scope = c("root", "module"),
                      meta = list()) {
  if (...length() > 0L) {
    snap_abort("Arguments of `snap_take()` after `session` must be named.")
  }
  session <- require_session(session, "snap_take")
  scope <- match.arg(scope)
  include <- check_patterns(include, "include")
  exclude <- check_patterns(exclude, "exclude")
  if (!is.list(meta) || (length(meta) > 0L && !has_full_names(meta))) {
    snap_abort("`meta` must be a named list.")
  }
  ctrl <- snap_controller(session)
  root <- session$rootScope()
  live_only <- if (is.null(live_only)) ctrl$live_only else isTRUE(live_only)

  all <- shiny::isolate(shiny::reactiveValuesToList(root$input))
  ids <- names(all)
  if (is.null(ids)) ids <- character()
  keep <- !startsWith(ids, ".")
  if (scope == "module" && is_module_session(session)) {
    keep <- keep & startsWith(ids, session_prefix(session))
  }

  inv <- ctrl$inventory()
  if (live_only) {
    if (is.null(inv)) {
      ctrl$note("the client has not reported which inputs are on the page yet; capturing all inputs")
    } else {
      stale <- ids[keep & !(ids %in% names(inv))]
      if (length(stale)) {
        ctrl$note("dropping inputs that are not on the page: ", quote_ids(stale))
      }
      keep <- keep & ids %in% names(inv)
    }
  }
  all <- all[keep]
  ids <- ids[keep]

  # File inputs cannot be pushed back into a browser: uploaded files become
  # attachments, and an empty file input (whose value is NULL) is skipped. The
  # inventory identifies file inputs by binding; the value shape is the
  # fallback when the client has not reported.
  is_file <- vapply(all, is_file_input_value, logical(1))
  if (!is.null(inv)) {
    is_file <- is_file | (inv[ids] %in% "shiny.fileInputBinding")
  }
  attachments <- lapply(all[is_file], function(v) {
    if (!is_file_input_value(v)) {
      return(NULL)
    }
    list(name = v$name, size = v$size, type = v$type, datapath = v$datapath)
  })
  attachments <- attachments[!vapply(attachments, is.null, logical(1))]
  all <- all[!is_file]
  ids <- ids[!is_file]

  impl <- .subset2(root$input, "impl")
  keep <- rep(TRUE, length(ids))
  for (i in seq_along(ids)) {
    v <- all[[i]]
    if (is_action_button_value(v)) {
      keep[i] <- FALSE
      next
    }
    fun <- impl$getMeta(ids[i], "shiny.serializer")
    if (is.function(fun)) {
      v <- fun(v, NULL)
      if (identical(attr(v, "serializable", exact = TRUE), FALSE)) {
        keep[i] <- FALSE
        next
      }
      all[i] <- list(v)
    }
  }
  keep <- keep & select_ids(ids, ctrl, include, exclude)
  dropped <- ids[!keep]
  if (length(dropped)) {
    ctrl$note("not capturing: ", quote_ids(dropped))
  }
  all <- all[keep]
  ids <- ids[keep]

  ord <- order(ids, method = "radix")
  inputs <- all[ord]
  ids <- ids[ord]
  bindings <- if (is.null(inv)) character() else inv[intersect(ids, names(inv))]

  vals <- list()
  if (isTRUE(values)) {
    env <- new.env(parent = emptyenv())
    for (nm in names(ctrl$tracked)) {
      tracked <- ctrl$tracked[[nm]]
      lst <- shiny::isolate(shiny::reactiveValuesToList(tracked$values))
      if (!is.null(tracked$fields)) {
        lst <- lst[intersect(tracked$fields, names(lst))]
      }
      assign(nm, lst, envir = env)
    }
    ctrl$on_save$invoke(list(inputs = inputs, values = env))
    nms <- sort(ls(env, all.names = TRUE), method = "radix")
    vals <- mget(nms, envir = env)
  }

  new_snapshot(
    inputs = inputs,
    values = vals,
    bindings = bindings,
    attachments = attachments,
    meta = meta,
    app = list(name = ctrl$app, version = ctrl$version),
    created = iso_now(),
    producer = snap_producer()
  )
}

#' Compare two snapshots
#'
#' Lists the inputs, values, and metadata entries that differ between two
#' snapshots. Values are flattened one level, so a tracked `reactiveValues`
#' stored as `prefs` with a changed `digits` field shows up as
#' `prefs$digits`.
#'
#' @param a,b Snapshot objects, lists of snapshot fields, file paths, or
#'   JSON text.
#'
#' @returns A data frame of class `shinysnap_diff` with one row per
#'   difference and the columns `id`, `section` (`"inputs"`, `"values"`, or
#'   `"meta"`), `status` (`"added"`, `"removed"`, or `"changed"`, seen from
#'   `a` to `b`), and the list columns `old` and `new` holding the values
#'   (`NULL` for the side where the entry is absent).
#'
#' @examples
#' a <- snap_unserialize('{"format": 1, "inputs": {"n": 1, "x": "old"},
#'   "values": {"prefs": {"digits": 3}}}')
#' b <- snap_unserialize('{"format": 1, "inputs": {"n": 1, "y": true},
#'   "values": {"prefs": {"digits": 4}}}')
#' snap_diff(a, b)
#' @export
snap_diff <- function(a, b) {
  a <- as_snapshot(a)
  b <- as_snapshot(b)
  rows <- list()
  add <- function(section, id, status, old, new) {
    rows[[length(rows) + 1L]] <<- list(
      id = id, section = section, status = status, old = old, new = new
    )
  }
  diff_section <- function(section, xa, xb) {
    ids <- union(names(xa), names(xb))
    for (id in ids) {
      in_a <- id %in% names(xa)
      in_b <- id %in% names(xb)
      if (in_a && !in_b) {
        add(section, id, "removed", xa[[id]], NULL)
      } else if (!in_a && in_b) {
        add(section, id, "added", NULL, xb[[id]])
      } else if (!identical(xa[[id]], xb[[id]])) {
        add(section, id, "changed", xa[[id]], xb[[id]])
      }
    }
  }
  diff_section("inputs", a$inputs, b$inputs)
  diff_section("values", flatten_values(a$values), flatten_values(b$values))
  diff_section("meta", a$meta, b$meta)
  col <- function(field) vapply(rows, function(r) r[[field]], character(1))
  out <- data.frame(
    id = col("id"), section = col("section"), status = col("status"),
    stringsAsFactors = FALSE
  )
  out$old <- lapply(rows, function(r) r$old)
  out$new <- lapply(rows, function(r) r$new)
  class(out) <- c("shinysnap_diff", "data.frame")
  out
}

#' Flatten fully named list values one level (`prefs` -> `prefs$digits`)
#'
#' @noRd
flatten_values <- function(values) {
  out <- list()
  for (nm in names(values)) {
    v <- values[[nm]]
    if (is.list(v) && length(v) > 0L && has_full_names(v) && !anyDuplicated(names(v))) {
      for (f in names(v)) out[paste0(nm, "$", f)] <- list(v[[f]])
    } else {
      out[nm] <- list(v)
    }
  }
  out
}

#' @rdname print.shinysnap
#' @export
print.shinysnap_diff <- function(x, ...) {
  if (nrow(x) == 0L) {
    cat("<shinysnap_diff> no differences\n")
    return(invisible(x))
  }
  cat(sprintf("<shinysnap_diff> %d difference(s)\n", nrow(x)))
  show <- function(v) {
    if (is.null(v)) {
      return("")
    }
    s <- paste(deparse(v, width.cutoff = 60L), collapse = " ")
    if (nchar(s) > 40L) s <- paste0(substr(s, 1L, 37L), "...")
    s
  }
  df <- data.frame(
    id = x$id, section = x$section, status = x$status,
    old = vapply(x$old, show, character(1)),
    new = vapply(x$new, show, character(1)),
    stringsAsFactors = FALSE
  )
  print(df, row.names = FALSE, ...)
  invisible(x)
}
