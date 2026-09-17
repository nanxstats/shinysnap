# JSON writer and reader ------------------------------------------------------
#
# The writer serializes the IR produced by `encode_value()` (see codec.R). It
# is hand-written so that doubles go through `zmij::format_double()`, which
# yields the shortest string that reads back to the same double, and so that
# the layout is deterministic: identical snapshots give identical bytes.
#
# The reader is `jsonlite::parse_json(simplifyVector = FALSE)`, whose number
# parsing is correctly rounded and which returns integers for plain digit
# runs and doubles for anything with a "." or an exponent.

#' Escape strings for JSON (RFC 8259), keeping non-ASCII as UTF-8
#'
#' `NA` stays `NA` so callers can turn it into `null`.
#'
#' @noRd
json_quote <- function(x) {
  if (length(x) == 0L) {
    return(character(0))
  }
  x <- enc2utf8(as.character(x))
  if (!all(validUTF8(x[!is.na(x)]))) {
    snap_abort(
      "Cannot write a string that is not valid UTF-8.",
      class = "shinysnap_unsupported_value"
    )
  }
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("\"", "\\\"", x, fixed = TRUE)
  x <- gsub("\n", "\\n", x, fixed = TRUE)
  x <- gsub("\r", "\\r", x, fixed = TRUE)
  x <- gsub("\t", "\\t", x, fixed = TRUE)
  x <- gsub("\b", "\\b", x, fixed = TRUE)
  x <- gsub("\f", "\\f", x, fixed = TRUE)
  ctrl <- grepl("[\\x01-\\x1f]", x, perl = TRUE)
  ctrl[is.na(ctrl)] <- FALSE
  if (any(ctrl)) {
    for (code in 1:31) {
      x[ctrl] <- gsub(
        intToUtf8(code), sprintf("\\u%04x", code), x[ctrl],
        fixed = TRUE
      )
    }
  }
  out <- paste0("\"", x, "\"")
  out[is.na(x)] <- NA_character_
  out
}

#' Render the elements of an atomic vector as JSON scalar literals
#'
#' @noRd
json_scalars <- function(x) {
  attributes(x) <- NULL
  out <- switch(typeof(x),
    logical = ifelse(x, "true", "false"),
    integer = as.character(x),
    double = {
      if (any(is.nan(x) | is.infinite(x))) {
        stop("Internal error: non-finite double reached the JSON writer.")
      }
      zmij::format_double(x)
    },
    character = json_quote(x),
    stop("Internal error: cannot render ", typeof(x), " as JSON scalars.")
  )
  out[is.na(x)] <- "null"
  out
}

#' Render a node on one line
#'
#' @noRd
render_inline <- function(x, compact = FALSE) {
  comma <- if (compact) "," else ", "
  colon <- if (compact) ":" else ": "
  if (is.null(x)) {
    return("null")
  }
  if (inherits(x, "shinysnap_json_array")) {
    return(paste0("[", paste(json_scalars(x), collapse = comma), "]"))
  }
  if (is.list(x)) {
    nms <- names(x)
    if (length(x) == 0L) {
      return(if (is.null(nms)) "[]" else "{}")
    }
    items <- vapply(x, render_inline, character(1), compact = compact)
    if (is.null(nms)) {
      return(paste0("[", paste(items, collapse = comma), "]"))
    }
    if (anyNA(nms)) stop("Internal error: NA object key.")
    return(paste0(
      "{", paste0(json_quote(nms), colon, items, collapse = comma), "}"
    ))
  }
  if (is.atomic(x) && length(x) == 1L) {
    return(json_scalars(x))
  }
  stop("Internal error: cannot render a ", typeof(x), " of length ", length(x), ".")
}

#' Render a node, expanding containers that do not fit on one line
#'
#' A container is written inline when the line (`indent` plus the key prefix
#' plus the inline form) fits within `width`; otherwise one element per line,
#' indented by two spaces. This keeps short vectors readable and makes diffs
#' of long ones line-based.
#'
#' @noRd
render_node <- function(x, indent, prefix, width) {
  inline <- render_inline(x)
  if (indent + prefix + nchar(inline) <= width) {
    return(inline)
  }
  if (is.null(x) || length(x) == 0L) {
    return(inline)
  }
  pad <- strrep(" ", indent + 2L)
  pad0 <- strrep(" ", indent)
  if (inherits(x, "shinysnap_json_array")) {
    items <- json_scalars(x)
    return(paste0("[\n", paste0(pad, items, collapse = ",\n"), "\n", pad0, "]"))
  }
  if (is.list(x)) {
    nms <- names(x)
    if (is.null(nms)) {
      items <- vapply(x, function(e) {
        render_node(e, indent + 2L, 0L, width)
      }, character(1))
      return(paste0("[\n", paste0(pad, items, collapse = ",\n"), "\n", pad0, "]"))
    }
    keys <- paste0(json_quote(nms), ": ")
    items <- vapply(seq_along(x), function(i) {
      render_node(x[[i]], indent + 2L, nchar(keys[i]), width)
    }, character(1))
    return(paste0("{\n", paste0(pad, keys, items, collapse = ",\n"), "\n", pad0, "}"))
  }
  inline
}

#' Serialize an IR tree to JSON text
#'
#' @param x The IR tree.
#' @param pretty Pretty-print (two-space indentation, trailing newline) or
#'   emit compact JSON on a single line.
#' @param width Line width used to decide whether a container stays inline.
#'
#' @noRd
json_render <- function(x, pretty = TRUE, width = 80L) {
  if (!pretty) {
    return(render_inline(x, compact = TRUE))
  }
  paste0(render_node(x, 0L, 0L, width), "\n")
}

#' Parse JSON text into a tree of lists and scalars
#'
#' @noRd
json_parse <- function(text) {
  if (!is.character(text)) {
    snap_abort("`text` must be a character vector.", class = "shinysnap_format_error")
  }
  text <- paste(text, collapse = "\n")
  tryCatch(
    jsonlite::parse_json(text, simplifyVector = FALSE),
    error = function(e) {
      snap_abort(
        paste0("Invalid JSON: ", conditionMessage(e)),
        class = "shinysnap_format_error"
      )
    }
  )
}
