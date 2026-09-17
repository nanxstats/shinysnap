#' Interoperate with bookmarks, tests, and bundles
#'
#' @description
#' * `snap_as_bookmark_url()` encodes a snapshot the way shiny's URL
#'   bookmarking (`enableBookmarking("url")`) does, so that the state can be
#'   opened by reloading the app at that URL. The app must have URL
#'   bookmarking enabled and a UI *function* for the URL to restore; the
#'   query string carries the same `_inputs_` and `_values_` keys that
#'   `session$doBookmark()` writes, with input ids in the order stored in
#'   the snapshot.
#' * `snap_as_test_inputs()` returns the input values as a named list for
#'   `shiny::testServer()`: `session$setInputs(!!!snap_as_test_inputs(x))`.
#' * `snap_attachment()` returns the local path(s) of the file(s) a
#'   `fileInput()` held when the snapshot was taken, if the snapshot came
#'   from a bundle (see [snap_write()]) or from the same session.
#'
#' @param x A snapshot object, a file path, or JSON text.
#' @param session A Shiny session whose `clientData` provides the base URL
#'   (protocol, host, port, and path), or `NULL`.
#' @param base_url The base URL to prepend, for example
#'   `"https://example.org/app/"`. When neither `session` nor `base_url` is
#'   given, only the query string (starting with `?`) is returned.
#' @param id An input id.
#'
#' @returns `snap_as_bookmark_url()` returns a string. `snap_as_test_inputs()`
#'   returns a named list. `snap_attachment()` returns a character vector of
#'   file paths (one per uploaded file), or `NULL` when the snapshot has no
#'   attachment for `id`.
#'
#' @examples
#' snap <- snap_unserialize('{
#'   "format": 1,
#'   "inputs": {"n": 100, "method": "b", "weights": [0.5, 0.75]},
#'   "values": {"note": "baseline"}
#' }')
#' snap_as_bookmark_url(snap, base_url = "https://example.org/app/")
#' str(snap_as_test_inputs(snap))
#' snap_attachment(snap, "upload")
#' @export
snap_as_bookmark_url <- function(x, session = NULL, base_url = NULL) {
  x <- as_snapshot(x)
  query <- encode_bookmark_query(x$inputs, x$values)
  if (is.null(base_url) && !is.null(session)) {
    base_url <- session_base_url(session)
  }
  if (!is.null(base_url) && !is_string(base_url)) {
    snap_abort("`base_url` must be NULL or a single string.")
  }
  paste0(base_url %||% "", "?", query)
}

#' @rdname snap_as_bookmark_url
#' @export
snap_as_test_inputs <- function(x) {
  as_snapshot(x)$inputs
}

#' @rdname snap_as_bookmark_url
#' @export
snap_attachment <- function(x, id) {
  if (!is_string(id)) {
    snap_abort("`id` must be a single input id.")
  }
  rec <- as_snapshot(x)$attachments[[id]]
  if (is.null(rec)) {
    return(NULL)
  }
  as.character(rec$datapath)
}

#' The `_inputs_&...&_values_&...` query string of a URL bookmark
#'
#' Mirrors shiny's `encodeShinySaveState()`: every value is serialized with
#' shiny's JSON settings and both keys and values are percent-encoded like
#' JavaScript's `encodeURIComponent()`.
#'
#' @noRd
encode_bookmark_query <- function(inputs, values) {
  pairs <- function(x) {
    json <- vapply(x, shiny_to_json, character(1), USE.NAMES = FALSE)
    paste0(encode_uri_component(names(x)), "=", encode_uri_component(json), collapse = "&")
  }
  parts <- character()
  if (length(inputs)) parts <- c(parts, "_inputs_", pairs(inputs))
  if (length(values)) parts <- c(parts, "_values_", pairs(values))
  paste(parts, collapse = "&")
}

#' Serialize a value with the settings shiny uses for URL bookmarks
#'
#' The same as shiny's internal `toJSON(x, strict_atomic = FALSE)`.
#'
#' @noRd
shiny_to_json <- function(x) {
  digits <- getOption("shiny.json.digits", I(16))
  as.character(jsonlite::toJSON(
    x,
    dataframe = "columns", null = "null", na = "null", auto_unbox = TRUE,
    digits = digits, use_signif = inherits(digits, "AsIs"), force = TRUE,
    POSIXt = "ISO8601", UTC = TRUE, rownames = FALSE, keep_vec_names = TRUE,
    json_verbatim = TRUE
  ))
}

#' Percent-encode like JavaScript's `encodeURIComponent()`
#'
#' Leaves `A-Z a-z 0-9 - _ . ! ~ * ' ( )` as they are and encodes every other
#' UTF-8 byte as `%XX`.
#'
#' @noRd
encode_uri_component <- function(x) {
  keep <- as.raw(c(
    0x30:0x39, 0x41:0x5A, 0x61:0x7A,
    0x2D, 0x5F, 0x2E, 0x21, 0x7E, 0x2A, 0x27, 0x28, 0x29
  ))
  vapply(as.character(x), function(s) {
    if (is.na(s)) s <- "NA"
    bytes <- charToRaw(enc2utf8(s))
    if (length(bytes) == 0L) {
      return("")
    }
    out <- sprintf("%%%02X", as.integer(bytes))
    ok <- bytes %in% keep
    out[ok] <- vapply(bytes[ok], rawToChar, character(1))
    paste(out, collapse = "")
  }, character(1), USE.NAMES = FALSE)
}

#' The protocol, host, port, and path the browser used to open the app
#'
#' @noRd
session_base_url <- function(session) {
  cd <- session$clientData
  if (is.null(cd)) {
    snap_abort("The session has no client data; pass `base_url`.")
  }
  get <- function(key) shiny::isolate(cd[[key]])
  protocol <- get("url_protocol")
  host <- get("url_hostname")
  port <- get("url_port")
  path <- get("url_pathname")
  if (!is_string(protocol) || !is_string(host) || !is_string(path)) {
    snap_abort("The session's client data has no URL yet; pass `base_url`.")
  }
  port <- if (length(port) == 1L && !is.na(port)) as.character(port) else ""
  paste0(protocol, "//", host, if (nzchar(port)) paste0(":", port), path)
}
