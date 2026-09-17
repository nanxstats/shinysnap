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
  if (is_string(x) && looks_like_json(x)) {
    return(snap_unserialize(x))
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
#'   "values": {"rv_display": {"digits": 3, "scientific": false}},
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

#' Print, format, and coerce snapshot objects
#'
#' `print()` shows a compact summary: app name and version, creation time,
#' and the number and names of inputs, values, and attachments. `format()`
#' returns the same lines as a character vector. `as.list()` drops the class
#' and returns the underlying list.
#'
#' @param x A snapshot object.
#' @param ... Ignored.
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
#' names(as.list(snap))
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
