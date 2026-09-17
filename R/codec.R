# Codec: R values <-> JSON-ready trees ----------------------------------------
#
# `encode_value()` turns an R value into an intermediate representation (IR)
# that `json_render()` serializes; `decode_value()` inverts the walk on the
# tree returned by `jsonlite::parse_json(simplifyVector = FALSE)`.
#
# The IR is deliberately tiny:
#
#   NULL                        -> null
#   unnamed atomic of length 1  -> scalar
#   json_arr(atomic)            -> array of scalars, whatever the length
#   unnamed list                -> array, elements encoded recursively
#   named list                  -> object, elements encoded recursively
#
# Everything JSON cannot say (the type of an empty vector, NA, non-finite
# doubles, names, dates, matrices, ...) is written as a typed wrapper: an
# object with a "$type" key.

codec_storage <- c("logical", "integer", "double", "character")

difftime_units <- c("secs", "mins", "hours", "days", "weeks")

#' Create a codec context
#'
#' A small mutable environment threaded through the encode/decode walk. It
#' carries the options and collects notes (shown under `verbose` after
#' encoding) and the paths of embedded R objects skipped because `trust` was
#' `FALSE` (reported once after decoding).
#'
#' @noRd
codec_ctx <- function(unsupported = "error", verbose = FALSE, trust = FALSE,
                      unknown_types = "error", keep_attachments = FALSE,
                      bundle_dir = NULL) {
  ctx <- new.env(parent = emptyenv())
  ctx$unsupported <- unsupported
  ctx$verbose <- verbose
  ctx$trust <- trust
  ctx$unknown_types <- unknown_types
  ctx$keep_attachments <- keep_attachments
  ctx$bundle_dir <- bundle_dir
  ctx$n_objects <- 0L
  ctx$notes <- character()
  ctx$untrusted <- character()
  ctx
}

#' Record a note for `verbose` output
#'
#' @noRd
codec_note <- function(ctx, ...) {
  if (isTRUE(ctx$verbose)) ctx$notes <- c(ctx$notes, paste0(...))
  invisible(NULL)
}

#' Emit the collected notes as one message
#'
#' @noRd
emit_notes <- function(ctx) {
  if (length(ctx$notes)) message(paste(ctx$notes, collapse = "\n"))
  invisible(NULL)
}

#' Emit one warning for all embedded objects skipped under `trust = FALSE`
#'
#' @noRd
emit_untrusted <- function(ctx) {
  if (length(ctx$untrusted)) {
    snap_warn(
      sprintf(
        paste0(
          "Skipped %d embedded R object(s) because `trust = FALSE`: %s. ",
          "Pass `trust = TRUE` only if you trust the source of this file."
        ),
        length(ctx$untrusted), quote_ids(ctx$untrusted)
      ),
      class = "shinysnap_untrusted", ids = ctx$untrusted
    )
  }
  invisible(NULL)
}

#' Raise a malformed-file error naming the offending path
#'
#' @noRd
format_abort <- function(path, what, ...) {
  snap_abort(
    sprintf("`%s` %s.", path, what),
    class = "shinysnap_format_error", path = path, ...
  )
}

#' Mark an atomic vector as "always an array" in the IR
#'
#' @noRd
json_arr <- function(x) {
  attributes(x) <- NULL
  class(x) <- "shinysnap_json_array"
  x
}

#' Build a typed wrapper (`NULL` fields are omitted)
#'
#' @noRd
typed <- function(type, ...) {
  fields <- list(...)
  fields <- fields[!vapply(fields, is.null, logical(1))]
  c(list("$type" = type), fields)
}

#' A named list that renders as a JSON object even when empty
#'
#' @noRd
as_object <- function(x) {
  if (length(x) == 0L) {
    return(structure(list(), names = character(0)))
  }
  x
}

#' `NA` without counting `NaN` as missing
#'
#' @noRd
is_na_strict <- function(x) {
  if (is.double(x)) is.na(x) & !is.nan(x) else is.na(x)
}

#' Are the names usable as JSON object keys?
#'
#' Keys must be present, non-empty, unique, and must not start with `$`,
#' which is reserved for typed wrappers.
#'
#' @noRd
check_names <- function(nms, what) {
  if (is.null(nms) || anyNA(nms) || !all(nzchar(nms))) {
    snap_abort(
      sprintf("All %s must have non-empty names.", what),
      class = "shinysnap_unsupported_value"
    )
  }
  if (anyDuplicated(nms)) {
    snap_abort(
      sprintf(
        "The %s have duplicated names: %s.",
        what, quote_ids(unique(nms[duplicated(nms)]))
      ),
      class = "shinysnap_unsupported_value"
    )
  }
  if (any(startsWith(nms, "$"))) {
    snap_abort(
      sprintf(
        "Names starting with \"$\" are reserved; found %s among the %s.",
        quote_ids(nms[startsWith(nms, "$")]), what
      ),
      class = "shinysnap_unsupported_value"
    )
  }
  invisible(nms)
}

# Encoding -------------------------------------------------------------------

#' Encode an R value as a JSON-ready tree
#'
#' @param x The value.
#' @param path Where the value sits, for messages (for example `inputs$n`).
#' @param ctx A codec context, see `codec_ctx()`.
#'
#' @noRd
encode_value <- function(x, path = "value", ctx = codec_ctx()) {
  if (is.null(x)) {
    return(NULL)
  }
  if (isS4(x)) {
    return(encode_unsupported(x, path, ctx))
  }
  if (is.null(oldClass(x))) {
    if (is.atomic(x)) {
      if (!is.null(dim(x))) {
        return(encode_array(x, path, ctx))
      }
      return(encode_atomic(x, path, ctx))
    }
    if (is.list(x)) {
      return(encode_list(x, path, ctx))
    }
    return(encode_unsupported(x, path, ctx))
  }
  if (inherits(x, "data.frame")) {
    return(encode_data_frame(x, path, ctx))
  }
  if (inherits(x, "factor")) {
    return(encode_factor(x, path, ctx))
  }
  if (inherits(x, "Date")) {
    return(encode_date(x, path, ctx))
  }
  if (inherits(x, "POSIXct")) {
    return(encode_posixct(x, path, ctx))
  }
  if (inherits(x, "difftime")) {
    return(encode_difftime(x, path, ctx))
  }
  encode_unsupported(x, path, ctx)
}

#' Note attributes the format does not describe
#'
#' @noRd
note_dropped <- function(x, keep, path, ctx) {
  extra <- setdiff(names(attributes(x)), keep)
  if (length(extra)) {
    codec_note(
      ctx, "Dropped attribute(s) ", quote_ids(extra), " of `", path, "`."
    )
  }
  invisible(NULL)
}

#' Note classes beyond the one the wrapper describes
#'
#' @noRd
note_dropped_classes <- function(x, keep, path, ctx) {
  extra <- setdiff(oldClass(x), keep)
  if (length(extra)) {
    codec_note(ctx, "Dropped class(es) ", quote_ids(extra), " of `", path, "`.")
  }
  invisible(NULL)
}

#' Names as an IR array, or `NULL`
#'
#' @noRd
encode_names <- function(nms) {
  if (is.null(nms)) NULL else json_arr(nms)
}

#' Elements of a double vector that may contain non-finite values
#'
#' Finite values stay numbers; `Inf`, `-Inf`, and `NaN` become zmij's
#' spellings as strings; `NA` becomes `null`.
#'
#' @noRd
encode_double_elements <- function(x) {
  x <- as.double(x)
  attributes(x) <- NULL
  out <- as.list(x)
  na <- is_na_strict(x)
  nonfinite <- !is.finite(x) & !na
  out[nonfinite] <- as.list(zmij::format_double(x[nonfinite]))
  out[na] <- list(NULL)
  out
}

#' Elements of a plain atomic vector as an IR array
#'
#' @noRd
encode_elements <- function(x) {
  attributes(x) <- NULL
  if (is.double(x) && any(!is.finite(x) & !is_na_strict(x))) {
    return(encode_double_elements(x))
  }
  json_arr(x)
}

#' Encode a plain (possibly named) atomic vector
#'
#' @noRd
encode_atomic <- function(x, path, ctx) {
  storage <- typeof(x)
  if (!storage %in% codec_storage) {
    return(encode_unsupported(x, path, ctx))
  }
  note_dropped(x, "names", path, ctx)
  nms <- names(x)
  if (length(x) == 0L) {
    return(typed(storage, value = json_arr(x)))
  }
  na <- is_na_strict(x)
  if (all(na)) {
    return(typed(storage, names = encode_names(nms), value = json_arr(x)))
  }
  if (storage == "double" && any(!is.finite(x) & !na)) {
    return(typed(
      "double",
      names = encode_names(nms), value = encode_double_elements(x)
    ))
  }
  if (!is.null(nms)) {
    return(typed(storage, names = encode_names(nms), value = json_arr(x)))
  }
  if (length(x) == 1L) {
    attributes(x) <- NULL
    return(x)
  }
  json_arr(x)
}

#' Encode a matrix or array (column-major)
#'
#' @noRd
encode_array <- function(x, path, ctx) {
  storage <- typeof(x)
  if (!storage %in% codec_storage) {
    return(encode_unsupported(x, path, ctx))
  }
  note_dropped(x, c("dim", "dimnames"), path, ctx)
  dn <- dimnames(x)
  if (!is.null(names(dn))) {
    codec_note(ctx, "Dropped the names of `dimnames(", path, ")`.")
  }
  typed(
    "array",
    storage = storage,
    dim = json_arr(as.integer(dim(x))),
    dimnames = if (is.null(dn)) {
      NULL
    } else {
      lapply(unname(dn), function(d) {
        if (is.null(d)) NULL else json_arr(as.character(d))
      })
    },
    value = encode_elements(x)
  )
}

#' Encode a `Date` vector (day precision)
#'
#' @noRd
encode_date <- function(x, path, ctx) {
  note_dropped(x, c("class", "names"), path, ctx)
  note_dropped_classes(x, "Date", path, ctx)
  s <- rep(NA_character_, length(x))
  ok <- !is.na(x)
  s[ok] <- format(x[ok], "%Y-%m-%d")
  typed("Date", names = encode_names(names(x)), value = json_arr(s))
}

#' Format instants as ISO 8601 strings in a time zone, at millisecond precision
#'
#' The instant is rounded (not truncated) to the millisecond. The offset is
#' written as `Z` for UTC and for the session time zone (`tz = ""`, which is
#' formatted in UTC because the local zone is machine-dependent), and as
#' `+hh:mm` otherwise.
#'
#' @noRd
format_iso_datetime <- function(secs, tz) {
  out <- rep(NA_character_, length(secs))
  ok <- !is.na(secs)
  if (!any(ok)) {
    return(out)
  }
  ms <- round(secs[ok] * 1000)
  whole <- floor(ms / 1000)
  frac <- as.integer(ms - whole * 1000)
  use_tz <- if (identical(tz, "")) "UTC" else tz
  base <- .POSIXct(whole, tz = use_tz)
  head <- format(base, "%Y-%m-%dT%H:%M:%S", tz = use_tz)
  if (tz %in% c("", "UTC")) {
    offset <- "Z"
  } else {
    z <- format(base, "%z", tz = use_tz)
    offset <- paste0(substr(z, 1L, 3L), ":", substr(z, 4L, 5L))
  }
  out[ok] <- sprintf("%s.%03d%s", head, frac, offset)
  out
}

#' Encode a `POSIXct` vector
#'
#' @noRd
encode_posixct <- function(x, path, ctx) {
  note_dropped(x, c("class", "names", "tzone"), path, ctx)
  note_dropped_classes(x, c("POSIXct", "POSIXt"), path, ctx)
  tz <- attr(x, "tzone")
  tz1 <- if (is.null(tz) || !length(tz)) "" else as.character(tz)[[1L]]
  secs <- as.double(unclass(x))
  attributes(secs) <- NULL
  typed(
    "POSIXct",
    names = encode_names(names(x)),
    tz = if (is.null(tz)) NULL else tz1,
    value = json_arr(format_iso_datetime(secs, tz1))
  )
}

#' Encode a `difftime` vector
#'
#' @noRd
encode_difftime <- function(x, path, ctx) {
  note_dropped(x, c("class", "names", "units"), path, ctx)
  note_dropped_classes(x, "difftime", path, ctx)
  units <- as.character(attr(x, "units") %||% "secs")[[1L]]
  typed(
    "difftime",
    names = encode_names(names(x)),
    units = units,
    value = encode_elements(as.double(unclass(x)))
  )
}

#' Encode a factor
#'
#' @noRd
encode_factor <- function(x, path, ctx) {
  note_dropped(x, c("class", "names", "levels"), path, ctx)
  note_dropped_classes(x, c("factor", "ordered"), path, ctx)
  typed(
    "factor",
    names = encode_names(names(x)),
    levels = json_arr(as.character(levels(x))),
    ordered = if (is.ordered(x)) TRUE else NULL,
    value = json_arr(as.character(unname(x)))
  )
}

#' Encode a data frame (column-wise)
#'
#' @noRd
encode_data_frame <- function(x, path, ctx) {
  if (inherits(x, "tbl_df")) {
    codec_note(ctx, "Converted tibble `", path, "` to a data frame.")
  }
  note_dropped(x, c("names", "row.names", "class"), path, ctx)
  note_dropped_classes(x, c("data.frame", "tbl_df", "tbl"), path, ctx)
  cols <- names(x)
  check_names(cols, paste0("columns of `", path, "`"))
  n <- .row_names_info(x, 2L)
  rn <- if (.row_names_info(x, 1L) <= 0L) {
    NULL
  } else {
    json_arr(attr(x, "row.names"))
  }
  columns <- lapply(seq_along(cols), function(i) {
    encode_value(x[[i]], paste0(path, "$", cols[i]), ctx)
  })
  names(columns) <- cols
  typed(
    "data.frame",
    nrow = as.integer(n), row.names = rn, columns = as_object(columns)
  )
}

#' Would the element decode as a JSON scalar or null?
#'
#' @noRd
is_scalar_like <- function(e) {
  is.null(e) || (is.atomic(e) && length(e) == 1L && is.null(attributes(e)))
}

#' Encode a list
#'
#' Fully named lists become objects. Unnamed lists become bare arrays only
#' when at least one element is not scalar-like, because an array of scalars
#' reads back as an atomic vector; all other cases use the typed wrapper.
#'
#' @noRd
encode_list <- function(x, path, ctx) {
  note_dropped(x, "names", path, ctx)
  nms <- names(x)
  n <- length(x)
  if (n == 0L) {
    if (is.null(nms)) {
      return(typed("list", value = list()))
    }
    return(as_object(list()))
  }
  if (has_full_names(x) && !anyDuplicated(nms)) {
    check_names(nms, paste0("elements of `", path, "`"))
    out <- lapply(seq_len(n), function(i) {
      encode_value(x[[i]], paste0(path, "$", nms[i]), ctx)
    })
    names(out) <- nms
    return(out)
  }
  elems <- lapply(seq_len(n), function(i) {
    encode_value(x[[i]], sprintf("%s[[%d]]", path, i), ctx)
  })
  if (!is.null(nms)) {
    return(typed("list", names = json_arr(nms), value = elems))
  }
  if (all(vapply(x, is_scalar_like, logical(1)))) {
    return(typed("list", value = elems))
  }
  elems
}

#' Error, or embed as an opaque serialized object
#'
#' @noRd
encode_unsupported <- function(x, path, ctx) {
  cls <- paste(class(x), collapse = "/")
  if (identical(ctx$unsupported, "rds")) {
    codec_note(
      ctx, "Embedded `", path, "` (class ", cls,
      ") as an opaque R object; reading it requires `trust = TRUE`."
    )
    if (!is.null(ctx$bundle_dir)) {
      # In a bundle, opaque objects go to objects/<n>-<path>.rds.
      ctx$n_objects <- ctx$n_objects + 1L
      rel <- file.path("objects", sprintf(
        "%d-%s.rds", ctx$n_objects, gsub("[^A-Za-z0-9._-]+", "_", path)
      ))
      dir.create(file.path(ctx$bundle_dir, "objects"), showWarnings = FALSE)
      saveRDS(x, file.path(ctx$bundle_dir, rel))
      return(typed("rds", class = json_arr(class(x)), path = rel))
    }
    b64 <- jsonlite::base64_enc(serialize(x, NULL))
    b64 <- gsub("\n", "", b64, fixed = TRUE)
    return(typed("rds", class = json_arr(class(x)), base64 = b64))
  }
  snap_abort(
    sprintf(
      paste0(
        "Cannot encode `%s` (class %s) in the JSON format. Convert it to a ",
        "supported type (atomic vector, list, matrix, data frame, factor, ",
        "Date, POSIXct, difftime), or use `unsupported = \"rds\"` to embed ",
        "it as an opaque R object that requires `trust = TRUE` to read."
      ),
      path, cls
    ),
    class = "shinysnap_unsupported_value", path = path
  )
}

# Decoding -------------------------------------------------------------------

#' Decode a parsed JSON tree into an R value
#'
#' @param x A node from `jsonlite::parse_json(simplifyVector = FALSE)`.
#' @inheritParams encode_value
#'
#' @noRd
decode_value <- function(x, path = "value", ctx = codec_ctx()) {
  if (is.null(x)) {
    return(NULL)
  }
  if (is.list(x)) {
    if (is.null(names(x))) {
      return(decode_array(x, path, ctx))
    }
    return(decode_object(x, path, ctx))
  }
  if (is.atomic(x) && length(x) == 1L) {
    return(x)
  }
  format_abort(path, "is not a valid JSON node")
}

#' Is the node a JSON scalar or null?
#'
#' @noRd
is_json_scalar <- function(e) {
  is.null(e) || (is.atomic(e) && length(e) == 1L)
}

#' Is the node a single JSON string?
#'
#' @noRd
is_string_scalar <- function(e) {
  is.character(e) && length(e) == 1L && !is.na(e)
}

#' Validate object keys
#'
#' @noRd
check_keys <- function(nms, path) {
  if (anyNA(nms) || !all(nzchar(nms))) {
    format_abort(path, "has an empty key")
  }
  if (anyDuplicated(nms)) {
    format_abort(
      path,
      sprintf("has duplicated keys: %s", quote_ids(unique(nms[duplicated(nms)])))
    )
  }
  if (any(startsWith(nms, "$"))) {
    format_abort(
      path,
      sprintf(
        "has reserved keys: %s (only \"$type\" is allowed, as the first key)",
        quote_ids(nms[startsWith(nms, "$")])
      )
    )
  }
  invisible(nms)
}

#' Decode a JSON object: typed wrapper or named list
#'
#' @noRd
decode_object <- function(x, path, ctx) {
  nms <- names(x)
  if ("$type" %in% nms) {
    return(decode_typed(x, path, ctx))
  }
  if (length(x) == 0L) {
    return(as_object(list()))
  }
  check_keys(nms, path)
  out <- lapply(seq_along(x), function(i) {
    decode_value(x[[i]], paste0(path, "$", nms[i]), ctx)
  })
  names(out) <- nms
  out
}

#' Decode a JSON array: atomic vector or unnamed list
#'
#' @noRd
decode_array <- function(x, path, ctx) {
  if (length(x) == 0L) {
    return(list())
  }
  if (all(vapply(x, is_json_scalar, logical(1)))) {
    return(decode_scalar_array(x, path))
  }
  lapply(seq_along(x), function(i) {
    decode_value(x[[i]], sprintf("%s[[%d]]", path, i), ctx)
  })
}

#' Decode an array of scalars/nulls into an atomic vector
#'
#' The type comes from the non-null elements: integer when every number
#' parsed as an integer, double otherwise; mixing kinds is an error.
#'
#' @noRd
decode_scalar_array <- function(x, path) {
  types <- vapply(x, function(e) {
    if (is.null(e)) NA_character_ else typeof(e)
  }, character(1))
  present <- unique(types[!is.na(types)])
  if (length(present) == 0L) {
    return(rep(NA, length(x)))
  }
  if (all(present %in% c("integer", "double"))) {
    storage <- if (all(present == "integer")) "integer" else "double"
  } else if (identical(present, "logical") || identical(present, "character")) {
    storage <- present
  } else {
    format_abort(
      path,
      sprintf("is an array that mixes %s values", paste(present, collapse = " and "))
    )
  }
  out <- vector(storage, length(x))
  is_null <- is.na(types)
  out[is_null] <- NA
  out[!is_null] <- unlist(x[!is_null], use.names = FALSE)
  out
}

#' Dispatch on `$type`
#'
#' @noRd
decode_typed <- function(x, path, ctx) {
  type <- x[["$type"]]
  if (!is_string_scalar(type)) {
    format_abort(path, "has a \"$type\" that is not a string")
  }
  switch(type,
    logical = ,
    integer = ,
    double = ,
    character = decode_atomic_wrapper(x, type, path),
    Date = decode_date(x, path),
    POSIXct = decode_posixct(x, path),
    difftime = decode_difftime(x, path),
    factor = decode_factor(x, path),
    array = ,
    matrix = decode_array_wrapper(x, path),
    data.frame = decode_data_frame(x, path, ctx),
    list = decode_list_wrapper(x, path, ctx),
    rds = decode_rds(x, path, ctx),
    file = decode_file(x, path, ctx),
    decode_unknown_type(x, type, path, ctx)
  )
}

#' The `value` field of a wrapper as a list of scalars
#'
#' @noRd
wrapper_value <- function(x, path) {
  if (!"value" %in% names(x)) {
    format_abort(path, "is a typed value without a \"value\" field")
  }
  v <- x[["value"]]
  if (!is.list(v)) v <- list(v)
  if (!is.null(names(v)) || !all(vapply(v, is_json_scalar, logical(1)))) {
    format_abort(path, "must have an array of scalars as its \"value\"")
  }
  v
}

#' Error for elements of the wrong kind
#'
#' @noRd
bad_elements <- function(path, what) {
  format_abort(path, sprintf("must contain only %s or null in its \"value\"", what))
}

#' Decode a list of scalars/nulls into a vector of the given storage type
#'
#' @noRd
decode_elements <- function(v, storage, path) {
  n <- length(v)
  is_null <- vapply(v, is.null, logical(1))
  out <- vector(storage, n)
  out[is_null] <- NA
  if (all(is_null)) {
    return(out)
  }
  present <- v[!is_null]
  vals <- switch(storage,
    logical = {
      if (!all(vapply(present, is.logical, logical(1)))) {
        bad_elements(path, "true/false")
      }
      unlist(present, use.names = FALSE)
    },
    integer = {
      if (!all(vapply(present, is.numeric, logical(1)))) {
        bad_elements(path, "integers")
      }
      nums <- as.double(unlist(present, use.names = FALSE))
      if (any(nums != trunc(nums)) || any(abs(nums) > .Machine$integer.max)) {
        bad_elements(path, "integers")
      }
      as.integer(nums)
    },
    double = decode_double_elements(present, path),
    character = {
      if (!all(vapply(present, is.character, logical(1)))) {
        bad_elements(path, "strings")
      }
      unlist(present, use.names = FALSE)
    }
  )
  out[!is_null] <- vals
  out
}

#' Doubles: numbers as parsed, strings through zmij (for `inf`, `NaN`, ...)
#'
#' @noRd
decode_double_elements <- function(present, path) {
  is_num <- vapply(present, is.numeric, logical(1))
  is_chr <- vapply(present, is.character, logical(1))
  if (!all(is_num | is_chr)) {
    bad_elements(path, "numbers")
  }
  out <- numeric(length(present))
  out[is_num] <- as.double(unlist(present[is_num], use.names = FALSE))
  if (any(is_chr)) {
    out[is_chr] <- tryCatch(
      zmij::parse_double(unlist(present[is_chr], use.names = FALSE)),
      error = function(e) bad_elements(path, "numbers")
    )
  }
  out
}

#' Names of a wrapper as a character vector, or `NULL`
#'
#' @noRd
decode_names <- function(x, path, n) {
  nms <- x[["names"]]
  if (is.null(nms)) {
    return(NULL)
  }
  if (!is.list(nms)) nms <- list(nms)
  ok <- vapply(nms, function(e) is.null(e) || is.character(e), logical(1))
  if (length(nms) != n || !all(ok)) {
    format_abort(path, sprintf("must have %d names, as strings or null", n))
  }
  vapply(nms, function(e) if (is.null(e)) NA_character_ else e, character(1))
}

#' Apply wrapper names to a decoded vector
#'
#' @noRd
set_names_from <- function(vals, x, path) {
  nms <- decode_names(x, path, length(vals))
  if (!is.null(nms)) names(vals) <- nms
  vals
}

#' Decode `logical`, `integer`, `double`, and `character` wrappers
#'
#' @noRd
decode_atomic_wrapper <- function(x, storage, path) {
  vals <- decode_elements(wrapper_value(x, path), storage, path)
  set_names_from(vals, x, path)
}

#' Decode a `Date` wrapper
#'
#' @noRd
decode_date <- function(x, path) {
  s <- decode_elements(wrapper_value(x, path), "character", path)
  ok <- is.na(s) | grepl("^-?[0-9]{4,}-[0-9]{2}-[0-9]{2}$", s)
  out <- rep(as.Date(NA), length(s))
  out[ok] <- as.Date(s[ok], format = "%Y-%m-%d")
  bad <- !ok | (is.na(out) & !is.na(s))
  if (any(bad)) {
    format_abort(
      path,
      sprintf("has invalid dates: %s (use \"YYYY-MM-DD\")", quote_ids(s[bad]))
    )
  }
  set_names_from(out, x, path)
}

#' Parse ISO 8601 instants written by `format_iso_datetime()`
#'
#' Accepts `YYYY-MM-DDThh:mm:ss[.fff][Z|+hh:mm|+hhmm]`; a missing offset means
#' UTC. The result is computed as whole seconds plus the decimal fraction,
#' which is how R itself builds `POSIXct` values, so millisecond instants
#' round-trip exactly.
#'
#' @noRd
parse_iso_datetime <- function(s, path) {
  re <- paste0(
    "^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})",
    "(\\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?$"
  )
  out <- rep(NA_real_, length(s))
  ok <- !is.na(s)
  if (!any(ok)) {
    return(out)
  }
  m <- regmatches(s[ok], regexec(re, s[ok]))
  matched <- lengths(m) > 0L
  if (!all(matched)) {
    format_abort(
      path,
      sprintf(
        "has invalid date-times: %s (use \"YYYY-MM-DDThh:mm:ss.fffZ\")",
        quote_ids(s[ok][!matched])
      )
    )
  }
  part <- function(i) vapply(m, `[[`, character(1), i)
  num <- function(i) as.numeric(part(i))
  whole <- unclass(ISOdatetime(
    num(2), num(3), num(4), num(5), num(6), 0,
    tz = "UTC"
  ))
  if (anyNA(whole)) {
    format_abort(
      path,
      sprintf("has impossible date-times: %s", quote_ids(s[ok][is.na(whole)]))
    )
  }
  whole <- whole + num(7)
  offset <- part(9)
  has_offset <- nzchar(offset) & offset != "Z"
  if (any(has_offset)) {
    o <- gsub(":", "", offset[has_offset], fixed = TRUE)
    sign <- ifelse(substr(o, 1L, 1L) == "-", -1, 1)
    hh <- as.numeric(substr(o, 2L, 3L))
    mm <- as.numeric(substr(o, 4L, 5L))
    whole[has_offset] <- whole[has_offset] - sign * (hh * 3600 + mm * 60)
  }
  frac <- part(8)
  fracv <- rep(0, length(frac))
  fracv[nzchar(frac)] <- as.numeric(paste0("0", frac[nzchar(frac)]))
  out[ok] <- whole + fracv
  out
}

#' Decode a `POSIXct` wrapper
#'
#' @noRd
decode_posixct <- function(x, path) {
  tz <- x[["tz"]]
  if (!is.null(tz) && !is_string_scalar(tz)) {
    format_abort(path, "has a \"tz\" that is not a string")
  }
  s <- decode_elements(wrapper_value(x, path), "character", path)
  out <- .POSIXct(parse_iso_datetime(s, path), tz = tz)
  set_names_from(out, x, path)
}

#' Decode a `difftime` wrapper
#'
#' @noRd
decode_difftime <- function(x, path) {
  units <- x[["units"]]
  if (!is_string_scalar(units) || !units %in% difftime_units) {
    format_abort(
      path,
      sprintf("must have \"units\" in %s", quote_ids(difftime_units))
    )
  }
  vals <- decode_elements(wrapper_value(x, path), "double", path)
  out <- structure(vals, units = units, class = "difftime")
  set_names_from(out, x, path)
}

#' Decode a `factor` wrapper
#'
#' @noRd
decode_factor <- function(x, path) {
  lv <- x[["levels"]]
  if (is.null(lv)) {
    lv <- character()
  } else {
    if (!is.list(lv)) lv <- list(lv)
    if (!all(vapply(lv, is_json_scalar, logical(1)))) {
      format_abort(path, "must have an array of strings as its \"levels\"")
    }
    lv <- decode_elements(lv, "character", path)
  }
  vals <- decode_elements(wrapper_value(x, path), "character", path)
  ordered <- x[["ordered"]]
  if (!is.null(ordered) && !(is.logical(ordered) && length(ordered) == 1L)) {
    format_abort(path, "has an \"ordered\" flag that is not true/false")
  }
  unknown <- !is.na(vals) & !(vals %in% lv)
  if (any(unknown)) {
    format_abort(
      path,
      sprintf("has values outside its levels: %s", quote_ids(unique(vals[unknown])))
    )
  }
  cls <- if (isTRUE(ordered)) c("ordered", "factor") else "factor"
  out <- structure(match(vals, lv), levels = lv, class = cls)
  set_names_from(out, x, path)
}

#' Decode an `array` (or `matrix`) wrapper
#'
#' @noRd
decode_array_wrapper <- function(x, path) {
  storage <- x[["storage"]]
  if (!is_string_scalar(storage) || !storage %in% codec_storage) {
    format_abort(
      path,
      sprintf("must have \"storage\" in %s", quote_ids(codec_storage))
    )
  }
  dim <- x[["dim"]]
  if (is.null(dim)) {
    format_abort(path, "is an array without \"dim\"")
  }
  if (!is.list(dim)) dim <- list(dim)
  if (!all(vapply(dim, is_json_scalar, logical(1)))) {
    format_abort(path, "must have an array of integers as its \"dim\"")
  }
  dimv <- decode_elements(dim, "integer", path)
  if (length(dimv) == 0L || anyNA(dimv) || any(dimv < 0L)) {
    format_abort(path, "has an invalid \"dim\"")
  }
  vals <- decode_elements(wrapper_value(x, path), storage, path)
  if (length(vals) != prod(dimv)) {
    format_abort(
      path,
      sprintf(
        "has %d values but dim [%s] needs %d",
        length(vals), paste(dimv, collapse = ", "), prod(dimv)
      )
    )
  }
  dn <- x[["dimnames"]]
  if (!is.null(dn)) {
    if (!is.list(dn) || !is.null(names(dn)) || length(dn) != length(dimv)) {
      format_abort(
        path,
        sprintf("must have %d entries (arrays or null) in \"dimnames\"", length(dimv))
      )
    }
    dn <- lapply(seq_along(dn), function(i) {
      d <- dn[[i]]
      if (is.null(d)) {
        return(NULL)
      }
      if (!is.list(d)) d <- list(d)
      if (!all(vapply(d, is_json_scalar, logical(1)))) {
        format_abort(path, "must have arrays of strings in \"dimnames\"")
      }
      d <- decode_elements(d, "character", path)
      if (length(d) != dimv[i]) {
        format_abort(
          path,
          sprintf("has %d dimnames for dimension %d of extent %d", length(d), i, dimv[i])
        )
      }
      d
    })
  }
  dim(vals) <- dimv
  if (!is.null(dn)) dimnames(vals) <- dn
  vals
}

#' Decode a `data.frame` wrapper
#'
#' @noRd
decode_data_frame <- function(x, path, ctx) {
  n <- x[["nrow"]]
  if (!is.numeric(n) || length(n) != 1L || is.na(n) || n < 0 || n != trunc(n)) {
    format_abort(path, "must have a non-negative integer \"nrow\"")
  }
  n <- as.integer(n)
  cols <- x[["columns"]]
  if (is.null(cols)) cols <- as_object(list())
  if (!is.list(cols) || (length(cols) > 0L && is.null(names(cols)))) {
    format_abort(path, "must have an object as its \"columns\"")
  }
  if (length(cols) > 0L) check_keys(names(cols), paste0(path, "$columns"))
  out <- lapply(seq_along(cols), function(i) {
    decode_value(cols[[i]], paste0(path, "$", names(cols)[i]), ctx)
  })
  lens <- vapply(out, NROW, integer(1))
  if (any(lens != n)) {
    format_abort(
      path,
      sprintf(
        "has column(s) %s whose length is not nrow = %d",
        quote_ids(names(cols)[lens != n]), n
      )
    )
  }
  if (length(out) == 0L) {
    out <- as_object(list())
  } else {
    names(out) <- names(cols)
  }
  rn <- x[["row.names"]]
  if (is.null(rn)) {
    rn <- .set_row_names(n)
  } else {
    if (!is.list(rn)) rn <- list(rn)
    if (!all(vapply(rn, is_json_scalar, logical(1)))) {
      format_abort(path, "must have an array of strings or integers as \"row.names\"")
    }
    kind <- if (all(vapply(rn, is.character, logical(1)))) "character" else "integer"
    rn <- decode_elements(rn, kind, path)
    if (length(rn) != n || anyNA(rn) || anyDuplicated(rn)) {
      format_abort(path, sprintf("must have %d unique, non-missing row names", n))
    }
  }
  structure(out, class = "data.frame", row.names = rn)
}

#' Decode a `list` wrapper
#'
#' @noRd
decode_list_wrapper <- function(x, path, ctx) {
  if (!"value" %in% names(x)) {
    format_abort(path, "is a typed list without a \"value\" field")
  }
  v <- x[["value"]]
  if (is.null(v)) v <- list()
  if (!is.list(v)) v <- list(v)
  if (!is.null(names(v))) {
    format_abort(path, "must have an array as its \"value\"")
  }
  out <- lapply(seq_along(v), function(i) {
    decode_value(v[[i]], sprintf("%s[[%d]]", path, i), ctx)
  })
  nms <- decode_names(x, path, length(out))
  if (!is.null(nms)) names(out) <- nms
  out
}

#' Decode an embedded serialized R object (requires `trust = TRUE`)
#'
#' @noRd
decode_rds <- function(x, path, ctx) {
  if (!isTRUE(ctx$trust)) {
    ctx$untrusted <- c(ctx$untrusted, path)
    return(NULL)
  }
  b64 <- x[["base64"]]
  if (is_string_scalar(b64)) {
    return(tryCatch(
      unserialize(jsonlite::base64_dec(b64)),
      error = function(e) {
        format_abort(path, "holds an embedded R object that cannot be unserialized")
      }
    ))
  }
  rel <- x[["path"]]
  if (is_string_scalar(rel)) {
    if (is.null(ctx$bundle_dir)) {
      format_abort(path, "refers to a bundled object, which requires reading a bundle")
    }
    file <- bundle_file(ctx$bundle_dir, rel, path, prefix = "objects/")
    return(tryCatch(
      readRDS(file),
      error = function(e) {
        format_abort(path, "holds a bundled R object that cannot be read")
      }
    ))
  }
  format_abort(path, "is an \"rds\" wrapper without \"base64\" or \"path\"")
}

#' Decode a `file` record (an attachment in a bundle manifest)
#'
#' The record decodes to the same shape `snap_take()` produces:
#' `list(name, size, type, datapath)`, with `datapath` pointing into the
#' extracted bundle, or `NA` when the record is read outside a bundle.
#'
#' @noRd
decode_file <- function(x, path, ctx) {
  field <- function(key, storage) {
    v <- x[[key]]
    if (is.null(v)) {
      return(vector(storage, 0L))
    }
    if (!is.list(v)) v <- list(v)
    if (!all(vapply(v, is_json_scalar, logical(1)))) {
      format_abort(path, sprintf("must have scalars or an array in \"%s\"", key))
    }
    decode_elements(v, storage, path)
  }
  name <- field("name", "character")
  size <- field("size", "double")
  type <- field("type", "character")
  rel <- field("path", "character")
  n <- length(name)
  if (n == 0L || length(rel) != n || length(size) != n || length(type) != n) {
    format_abort(path, "must have \"name\", \"size\", \"type\", and \"path\" of equal length")
  }
  datapath <- rep(NA_character_, n)
  if (!is.null(ctx$bundle_dir)) {
    datapath <- vapply(rel, function(r) {
      bundle_file(ctx$bundle_dir, r, path, prefix = "attachments/")
    }, character(1), USE.NAMES = FALSE)
  }
  list(name = name, size = size, type = type, datapath = datapath)
}

#' Resolve a manifest path inside an extracted bundle, safely
#'
#' The path must be relative, must not climb out of the bundle, must live
#' under `prefix`, and must exist as a regular file.
#'
#' @noRd
bundle_file <- function(dir, rel, path, prefix) {
  bad <- !is_string(rel) || !nzchar(rel) || grepl("^([A-Za-z]:)?[/\\]", rel) ||
    grepl("\\", rel, fixed = TRUE) || !startsWith(rel, prefix) ||
    any(strsplit(rel, "/", fixed = TRUE)[[1]] %in% c("..", "", "."))
  if (bad) {
    format_abort(path, sprintf("refers to an invalid bundle path \"%s\"", rel))
  }
  file <- file.path(dir, rel)
  info <- file.info(file, extra_cols = FALSE)
  if (is.na(info$isdir) || isTRUE(info$isdir) || nzchar(Sys.readlink(file))) {
    format_abort(path, sprintf("refers to \"%s\", which is not a file in the bundle", rel))
  }
  root <- normalizePath(dir, winslash = "/", mustWork = TRUE)
  real <- normalizePath(file, winslash = "/", mustWork = TRUE)
  if (!startsWith(real, paste0(root, "/"))) {
    format_abort(path, sprintf("refers to \"%s\", which lies outside the bundle", rel))
  }
  real
}

#' Unknown `$type`: error, or keep the raw node
#'
#' @noRd
decode_unknown_type <- function(x, type, path, ctx) {
  if (identical(ctx$unknown_types, "keep")) {
    return(x)
  }
  snap_abort(
    sprintf(
      paste0(
        "`%s` has the unknown type \"%s\". The file may have been written by ",
        "a newer version of shinysnap: upgrade the package, or pass ",
        "`unknown_types = \"keep\"` to keep the raw value."
      ),
      path, type
    ),
    class = "shinysnap_unknown_type", path = path, type = type
  )
}
