#' Convert a snapshot to and from JSON text
#'
#' `snap_serialize()` writes a snapshot as JSON text in the canonical
#' shinysnap format; `snap_unserialize()` reads it back. These are the
#' in-memory counterparts of `snap_write()` and `snap_read()`.
#'
#' @details
#' The JSON format is designed to be read and edited by people: doubles are
#' written with the fewest digits that read back to the same value, integers
#' as plain digit runs, and everything JSON cannot express directly (the
#' type of an empty vector, `NA`, `Inf`, names, dates, matrices, factors,
#' data frames) as a small object with a `"$type"` key.
#'
#' Values that the format cannot describe (environments, functions, S4 and
#' R6 objects, unknown classes) are an error by default. With
#' `unsupported = "rds"` they are embedded as base64 serialized R objects
#' instead; because unserializing arbitrary data is unsafe, reading them back
#' requires `trust = TRUE`, otherwise they decode to `NULL` with a warning.
#'
#' @param x A snapshot object, as returned by `snap_take()` or
#'   [snap_unserialize()].
#' @param format The text format. Only `"json"` is available.
#' @param pretty Pretty-print with two-space indentation (the default) or
#'   emit compact JSON on one line.
#' @param unsupported What to do with values the JSON format cannot describe:
#'   `"error"` (the default) or `"rds"` to embed them as serialized R objects.
#' @param verbose Print a message about what was converted or dropped.
#' @param text JSON text: a single string or a character vector of lines.
#' @param trust Decode embedded serialized R objects (`"$type": "rds"`)? Only
#'   set this to `TRUE` for files from a source you trust.
#' @param unknown_types What to do with a `"$type"` the reader does not know:
#'   `"error"` (the default) or `"keep"` to keep the raw parsed value.
#'
#' @returns `snap_serialize()` returns a single string. `snap_unserialize()`
#'   returns a snapshot object of class `shinysnap`.
#'
#' @examples
#' text <- '{
#'   "format": 1,
#'   "app": {"name": "myapp", "version": "2.4.1"},
#'   "inputs": {
#'     "dates": {"$type": "Date", "value": ["2024-01-01", "2024-03-01"]},
#'     "method": "b",
#'     "n": 100,
#'     "rate": 0.025,
#'     "weights": [0.5, 0.75]
#'   }
#' }'
#' snap <- snap_unserialize(text)
#' snap
#' str(snap_inputs(snap))
#' cat(snap_serialize(snap))
#' @export
snap_serialize <- function(x, format = "json", pretty = TRUE,
                           unsupported = c("error", "rds"), verbose = FALSE) {
  format <- match.arg(format, "json")
  unsupported <- match.arg(unsupported)
  x <- as_snapshot(x)
  ctx <- codec_ctx(unsupported = unsupported, verbose = isTRUE(verbose))
  ir <- encode_snapshot(x, ctx)
  emit_notes(ctx)
  json_render(ir, pretty = isTRUE(pretty))
}

#' @rdname snap_serialize
#' @export
snap_unserialize <- function(text, format = "json", trust = FALSE,
                             unknown_types = c("error", "keep")) {
  format <- match.arg(format, "json")
  unknown_types <- match.arg(unknown_types)
  ctx <- codec_ctx(trust = isTRUE(trust), unknown_types = unknown_types)
  x <- decode_snapshot(json_parse(text), ctx)
  emit_untrusted(ctx)
  x
}

#' Encode a snapshot as an IR tree
#'
#' `producer` is always stamped with the versions of the software writing
#' the file; `created` is filled in only when missing.
#'
#' @noRd
encode_snapshot <- function(x, ctx) {
  root <- list(
    format = as.integer(x$format),
    app = list(name = x$app$name, version = x$app$version),
    created = x$created %||% iso_now(),
    producer = as_object(snap_producer()),
    inputs = encode_section(x$inputs, "inputs", ctx),
    values = encode_section(x$values, "values", ctx),
    bindings = as_object(as.list(x$bindings))
  )
  if (length(x$attachments)) {
    root$attachments <- encode_section(x$attachments, "attachments", ctx)
  }
  root$meta <- encode_section(x$meta, "meta", ctx)
  root
}

#' Encode one named section (`inputs`, `values`, ...) as an object
#'
#' @noRd
encode_section <- function(x, name, ctx) {
  if (length(x) == 0L) {
    return(as_object(list()))
  }
  nms <- names(x)
  check_names(nms, paste0("entries of `", name, "`"))
  out <- lapply(seq_along(x), function(i) {
    encode_value(x[[i]], paste0(name, "$", nms[i]), ctx)
  })
  names(out) <- nms
  out
}

#' Decode a parsed JSON tree into a snapshot
#'
#' @noRd
decode_snapshot <- function(tree, ctx) {
  if (!is.list(tree) || is.null(names(tree))) {
    snap_abort(
      "A snapshot file must contain a JSON object.",
      class = "shinysnap_format_error"
    )
  }
  check_keys(names(tree), "the snapshot")
  fmt <- tree[["format"]]
  if (is.null(fmt)) {
    snap_abort(
      "This does not look like a shinysnap file: the \"format\" field is missing.",
      class = "shinysnap_format_error"
    )
  }
  if (!is.numeric(fmt) || length(fmt) != 1L || is.na(fmt) || fmt != trunc(fmt)) {
    snap_abort(
      "The \"format\" field must be an integer.",
      class = "shinysnap_format_error"
    )
  }
  if (fmt > snap_format_version) {
    snap_abort(
      sprintf(
        paste0(
          "This file uses format version %d, but this version of shinysnap ",
          "reads up to format %d. Please upgrade shinysnap."
        ),
        as.integer(fmt), snap_format_version
      ),
      class = "shinysnap_format_error"
    )
  }
  if (fmt < 1L) {
    snap_abort(
      sprintf("Unsupported format version %d.", as.integer(fmt)),
      class = "shinysnap_format_error"
    )
  }
  new_snapshot(
    format = as.integer(fmt),
    app = decode_app(tree[["app"]]),
    created = decode_optional_string(tree[["created"]], "created"),
    producer = decode_string_map(tree[["producer"]], "producer"),
    inputs = decode_section(tree[["inputs"]], "inputs", ctx),
    values = decode_section(tree[["values"]], "values", ctx),
    bindings = unlist(decode_string_map(tree[["bindings"]], "bindings")),
    attachments = decode_section(tree[["attachments"]], "attachments", ctx),
    meta = decode_section(tree[["meta"]], "meta", ctx)
  )
}

#' Decode the `app` object
#'
#' @noRd
decode_app <- function(app) {
  if (is.null(app)) {
    return(list(name = NULL, version = NULL))
  }
  if (!is.list(app) || (length(app) > 0L && is.null(names(app)))) {
    snap_abort("The \"app\" field must be an object.", class = "shinysnap_format_error")
  }
  list(
    name = decode_optional_string(app[["name"]], "app$name"),
    version = decode_optional_string(app[["version"]], "app$version")
  )
}

#' A string or `NULL`
#'
#' @noRd
decode_optional_string <- function(x, what) {
  if (!is.null(x) && !is_string_scalar(x)) {
    snap_abort(
      sprintf("The \"%s\" field must be a string.", what),
      class = "shinysnap_format_error"
    )
  }
  x
}

#' An object of strings as a named list (or `NULL` when absent/empty)
#'
#' @noRd
decode_string_map <- function(x, what) {
  if (is.null(x) || length(x) == 0L) {
    return(NULL)
  }
  ok <- is.list(x) && !is.null(names(x)) &&
    all(vapply(x, is_string_scalar, logical(1)))
  if (!ok) {
    snap_abort(
      sprintf("The \"%s\" field must be an object of strings.", what),
      class = "shinysnap_format_error"
    )
  }
  check_keys(names(x), what)
  x
}

#' Decode one named section into a named list
#'
#' @noRd
decode_section <- function(x, name, ctx) {
  if (is.null(x) || length(x) == 0L) {
    return(list())
  }
  if (!is.list(x) || is.null(names(x))) {
    snap_abort(
      sprintf("The \"%s\" field must be an object.", name),
      class = "shinysnap_format_error"
    )
  }
  nms <- names(x)
  check_keys(nms, name)
  out <- lapply(seq_along(x), function(i) {
    decode_value(x[[i]], paste0(name, "$", nms[i]), ctx)
  })
  names(out) <- nms
  out
}
