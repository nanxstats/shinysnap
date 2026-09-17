#' Null-coalescing operator
#'
#' @noRd
`%||%` <- function(x, y) if (is.null(x)) y else x

#' Signal a classed error
#'
#' All errors raised by shinysnap inherit from `shinysnap_error`, so callers
#' can catch them selectively. `class` adds more specific classes in front.
#'
#' @noRd
snap_abort <- function(message, class = NULL, ...) {
  stop(structure(
    list(message = message, call = NULL, ...),
    class = c(class, "shinysnap_error", "error", "condition")
  ))
}

#' Signal a classed warning
#'
#' @noRd
snap_warn <- function(message, class = NULL, ...) {
  warning(structure(
    list(message = message, call = NULL, ...),
    class = c(class, "shinysnap_warning", "warning", "condition")
  ))
}

#' Is `x` a single, non-missing string?
#'
#' @noRd
is_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x)
}

#' Does `x` carry complete names (no `NA`, no empty string)?
#'
#' @noRd
has_full_names <- function(x) {
  nms <- names(x)
  !is.null(nms) && !anyNA(nms) && all(nzchar(nms))
}

#' Format ids for a message
#'
#' @noRd
quote_ids <- function(x) {
  paste0("`", x, "`", collapse = ", ")
}

#' The current time as an ISO 8601 UTC timestamp
#'
#' @noRd
iso_now <- function() {
  format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

#' Version of an installed package as a string, or `NULL`
#'
#' @noRd
pkg_version_string <- function(pkg) {
  tryCatch(as.character(utils::packageVersion(pkg)), error = function(e) NULL)
}

#' Versions of the software writing a snapshot file
#'
#' @noRd
snap_producer <- function() {
  out <- list(
    shinysnap = pkg_version_string("shinysnap"),
    shiny = pkg_version_string("shiny"),
    r = paste(R.version$major, R.version$minor, sep = ".")
  )
  out[!vapply(out, is.null, logical(1))]
}
