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

#' Error unless a Shiny session is available
#'
#' @noRd
require_session <- function(session, what) {
  if (is.null(session)) {
    snap_abort(
      sprintf(
        "`%s()` must be called from a Shiny server function or module: no session was found.",
        what
      ),
      class = "shinysnap_no_session"
    )
  }
  session
}

#' Is the session a module scope?
#'
#' Only session proxies created by `moduleServer()` count. The root session
#' never does, even though `MockShinySession` reports a namespace prefix.
#'
#' @noRd
is_module_session <- function(session) {
  inherits(session, "session_proxy")
}

#' The namespace prefix of a session (`"mod-"`), or `""` at the root
#'
#' @noRd
session_prefix <- function(session) {
  if (is_module_session(session)) session$ns("") else ""
}

#' Is the value an action button's value?
#'
#' @noRd
is_action_button_value <- function(x) {
  inherits(x, "shinyActionButtonValue")
}

#' Is the value a `fileInput()` value?
#'
#' @noRd
is_file_input_value <- function(x) {
  is.data.frame(x) && identical(sort(names(x)), c("datapath", "name", "size", "type"))
}

#' Reduce a user-supplied name to `[A-Za-z0-9._-]`
#'
#' @noRd
sanitize_filename <- function(x, fallback = "state") {
  x <- as.character(x)[1L]
  if (is.na(x)) x <- ""
  x <- gsub("[^A-Za-z0-9._-]+", "_", x)
  x <- gsub("^[._]+|[._]+$", "", x)
  if (!nzchar(x)) fallback else x
}

#' Validate a character vector of regular expressions
#'
#' @noRd
check_patterns <- function(x, what) {
  if (is.null(x)) {
    return(character())
  }
  if (!is.character(x) || anyNA(x)) {
    snap_abort(sprintf("`%s` must be a character vector of regular expressions.", what))
  }
  x
}
