#' Track server-side values
#'
#' Registers a `reactiveValues` object so that [snap_take()] captures its
#' fields (all of them, or the ones named in `fields`) under `name` in the
#' snapshot's `values` section, and so that a restore can write them back.
#'
#' Inside a module, `name` is namespaced automatically.
#'
#' @param values A `reactiveValues` object.
#' @param fields Names of the fields to capture, or `NULL` for all fields.
#' @param name The name to store the values under. Defaults to the name of
#'   the variable passed as `values`.
#' @param session The Shiny session. Defaults to the current session.
#'
#' @returns The (namespaced) name the values are stored under, invisibly.
#'
#' @examples
#' if (interactive()) {
#'   library(shiny)
#'
#'   server <- function(input, output, session) {
#'     prefs <- reactiveValues(digits = 3L, scientific = FALSE)
#'     snap_track(prefs)
#'   }
#' }
#' @export
snap_track <- function(values, fields = NULL, name = NULL,
                       session = shiny::getDefaultReactiveDomain()) {
  session <- require_session(session, "snap_track")
  if (!shiny::is.reactivevalues(values)) {
    snap_abort("`values` must be a `reactiveValues()` object.")
  }
  if (!is.null(fields) && (!is.character(fields) || anyNA(fields))) {
    snap_abort("`fields` must be a character vector or NULL.")
  }
  if (is.null(name)) {
    name <- deparse(substitute(values))
    if (length(name) != 1L || !grepl("^[A-Za-z.][A-Za-z0-9._]*$", name)) {
      snap_abort("Cannot derive a name from `values`; pass `name` explicitly.")
    }
  }
  if (!is_string(name) || !nzchar(name)) {
    snap_abort("`name` must be a single non-empty string.")
  }
  if (is_module_session(session)) name <- session$ns(name)
  ctrl <- snap_controller(session)
  ctrl$track(name, values, fields)
  invisible(name)
}
