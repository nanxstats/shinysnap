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
    if (isTRUE(ctx$keep_attachments)) {
      root$attachments <- encode_attachments(x$attachments)
    } else {
      message(sprintf(
        paste0(
          "shinysnap: %d uploaded file(s) (%s) are not included in the JSON ",
          "file; write a zip bundle to keep uploaded files."
        ),
        length(x$attachments), quote_ids(names(x$attachments))
      ))
    }
  }
  root$meta <- encode_section(x$meta, "meta", ctx)
  root
}

#' Encode attachment records for a bundle manifest
#'
#' Each record must already carry `path`, the archive-relative location the
#' bundle writer copied the upload to.
#'
#' @noRd
encode_attachments <- function(attachments) {
  scalar_or_array <- function(v) {
    v <- unname(v)
    if (length(v) == 1L) v else json_arr(v)
  }
  out <- lapply(attachments, function(rec) {
    # Built by hand: typed() takes a `type` argument, and the record has a
    # `type` field (the MIME type) that must not be confused with "$type".
    list(
      "$type" = "file",
      name = scalar_or_array(as.character(rec$name)),
      size = scalar_or_array(as.double(rec$size)),
      type = scalar_or_array(as.character(rec$type)),
      path = scalar_or_array(as.character(rec$path))
    )
  })
  names(out) <- names(attachments)
  out
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

#' Write a snapshot to a file and read it back
#'
#' `snap_write()` saves a snapshot; `snap_read()` loads one. The canonical
#' format is JSON (see [snap_serialize()]): plain text, readable, diffable,
#' and safe to open. The `"zip"` format is a *bundle*: a zip archive holding
#' the same JSON as `manifest.json` plus the files of any `fileInput()`
#' uploads (under `attachments/`) and, with `unsupported = "rds"`, opaque R
#' objects (under `objects/`); it needs the zip package. The `"rds"` format
#' stores the R object with `saveRDS()`; it is neither readable nor safe
#' across versions, and reading it requires `trust = TRUE` because
#' unserializing a file runs arbitrary code paths.
#'
#' Reading a bundle checks the archive for path traversal and caps its
#' uncompressed size at `getOption("shinysnap.max_bundle_bytes", 100 * 1024^2)`
#' bytes, then extracts it into a fresh temporary directory;
#' [snap_attachment()] returns the local paths of the extracted uploads and
#' bundled objects are decoded only with `trust = TRUE`.
#'
#' @param x A snapshot object.
#' @param path The file path.
#' @param format `"auto"` picks the format from the extension (`.json`,
#'   `.zip`, or `.rds`); otherwise the format to use regardless of the
#'   extension.
#' @param pretty Pretty-print JSON (the default) or write one compact line.
#' @param ... Passed on to [snap_serialize()] (`unsupported`, `verbose`).
#' @param trust Decode embedded serialized R objects and allow the `"rds"`
#'   format? Only set this to `TRUE` for files from a source you trust.
#' @param unknown_types What to do with a `"$type"` the reader does not know:
#'   `"error"` (the default) or `"keep"` to keep the raw parsed value.
#'
#' @returns `snap_write()` returns `path` invisibly; `snap_read()` returns a
#'   snapshot object.
#'
#' @examples
#' snap <- snap_unserialize('{"format": 1, "inputs": {"n": 100, "rate": 0.025}}')
#' path <- tempfile(fileext = ".json")
#' snap_write(snap, path)
#' cat(readLines(path), sep = "\n")
#' identical(snap_inputs(snap_read(path)), snap_inputs(snap))
#' @export
snap_write <- function(x, path, format = c("auto", "json", "zip", "rds"), pretty = TRUE, ...) {
  if (!is_string(path)) {
    snap_abort("`path` must be a single file path.")
  }
  format <- match.arg(format)
  if (format == "auto") format <- format_from_path(path)
  x <- as_snapshot(x)
  switch(format,
    json = write_utf8(snap_serialize(x, pretty = pretty, ...), path),
    zip = write_bundle(x, path, pretty = pretty, ...),
    rds = {
      x$producer <- snap_producer()
      x$created <- x$created %||% iso_now()
      saveRDS(x, path)
    }
  )
  invisible(path)
}

#' @rdname snap_write
#' @export
snap_read <- function(path, format = c("auto", "json", "zip", "rds"), trust = FALSE,
                      unknown_types = c("error", "keep"), ...) {
  if (!is_string(path)) {
    snap_abort("`path` must be a single file path.")
  }
  if (!file.exists(path)) {
    snap_abort(sprintf("File not found: `%s`.", path), class = "shinysnap_format_error")
  }
  format <- match.arg(format)
  unknown_types <- match.arg(unknown_types)
  if (format == "auto") format <- format_from_path(path)
  switch(format,
    json = snap_unserialize(
      read_utf8(path),
      trust = trust, unknown_types = unknown_types
    ),
    zip = read_bundle(path, trust = trust, unknown_types = unknown_types),
    rds = {
      if (!isTRUE(trust)) {
        snap_abort(
          paste0(
            "Reading an .rds snapshot unserializes arbitrary R objects; pass ",
            "`trust = TRUE` if you trust the source of this file."
          ),
          class = "shinysnap_trust_error"
        )
      }
      as_snapshot(readRDS(path))
    }
  )
}

#' Pick the format from a file extension
#'
#' @noRd
format_from_path <- function(path) {
  ext <- tolower(sub("^.*\\.([A-Za-z0-9]+)$", "\\1", basename(path)))
  if (identical(ext, tolower(basename(path)))) ext <- ""
  switch(ext,
    json = "json",
    zip = "zip",
    rds = "rds",
    snap_abort(
      sprintf(
        "Cannot infer the format of `%s` from its extension; pass `format`.",
        path
      )
    )
  )
}

#' Write a string as UTF-8 bytes, without newline conversion
#'
#' @noRd
write_utf8 <- function(text, path) {
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeBin(charToRaw(enc2utf8(text)), con)
  invisible(path)
}

#' Read a whole file as one UTF-8 string, dropping a byte-order mark
#'
#' @noRd
read_utf8 <- function(path) {
  size <- file.info(path)$size
  raw <- readBin(path, what = "raw", n = size)
  bom <- as.raw(c(0xEF, 0xBB, 0xBF))
  if (length(raw) >= 3L && identical(raw[1:3], bom)) raw <- raw[-(1:3)]
  txt <- rawToChar(raw)
  Encoding(txt) <- "UTF-8"
  if (!validUTF8(txt)) {
    snap_abort(
      sprintf("`%s` is not valid UTF-8.", path),
      class = "shinysnap_format_error"
    )
  }
  txt
}
