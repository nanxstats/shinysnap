#' Save-state button and its download handler
#'
#' `snap_download_button()` is a `downloadButton()` with the client script
#' attached. `snap_download_handler()` defines the matching download: it
#' takes a snapshot with [snap_take()] when the button is clicked and writes
#' it with [snap_write()]. Together they replace the usual
#' `downloadHandler()` boilerplate.
#'
#' @param id The output id of the button. `snap_download_handler()` accepts
#'   a vector of ids, so that several buttons (for example one per tab)
#'   share one definition.
#' @param label,icon,class,... Passed on to `shiny::downloadButton()`. In
#'   `snap_download_handler()`, `...` is passed on to [snap_take()].
#' @param filename The file name without extension: a string, a function, or
#'   a reactive (for example a text input where the user names the file). It
#'   is reduced to the characters `A-Z a-z 0-9 . _ -`, falls back to
#'   `"state"` when empty, and gets the format's extension appended.
#' @param format The file format. Only `"json"` is available.
#' @param snapshot `NULL` to take a snapshot when the button is clicked (the
#'   default), a snapshot object, or a function or reactive returning one.
#' @param session The Shiny session. Defaults to the current session.
#'
#' @returns `snap_download_button()` returns a tag. `snap_download_handler()`
#'   returns the ids invisibly.
#'
#' @examples
#' if (interactive()) {
#'   library(shiny)
#'
#'   ui <- fluidPage(
#'     sliderInput("n", "n", 1, 100, 50),
#'     textInput("filename", "File name", "state"),
#'     snap_download_button("save")
#'   )
#'
#'   server <- function(input, output, session) {
#'     snap_enable(app = "demo", version = "1.0.0", exclude = "^filename$")
#'     snap_download_handler("save", filename = reactive(input$filename))
#'   }
#'
#'   shinyApp(ui, server)
#' }
#' @export
snap_download_button <- function(id, label = "Save state",
                                 icon = shiny::icon("download"),
                                 class = NULL, ...) {
  btn <- shiny::downloadButton(id, label = label, class = class, icon = icon, ...)
  htmltools::attachDependencies(btn, snap_dependency(), append = TRUE)
}

#' @rdname snap_download_button
#' @export
snap_download_handler <- function(id, filename = "state", format = "json", ...,
                                  snapshot = NULL,
                                  session = shiny::getDefaultReactiveDomain()) {
  session <- require_session(session, "snap_download_handler")
  if (!is.character(id) || length(id) == 0L || anyNA(id) || !all(nzchar(id))) {
    snap_abort("`id` must be a character vector of output ids.")
  }
  format <- match.arg(format, "json")
  dots <- list(...)
  snap_controller(session)
  ext <- paste0(".", format)
  handler <- shiny::downloadHandler(
    filename = function() {
      name <- shiny::isolate(resolve_filename(filename))
      name <- sub(paste0("\\", ext, "$"), "", name, ignore.case = TRUE)
      paste0(sanitize_filename(name), ext)
    },
    content = function(file) {
      snap <- shiny::isolate(resolve_snapshot(snapshot, session, dots))
      snap_write(snap, file, format = format)
    },
    contentType = "application/json"
  )
  out <- session$output
  for (one in id) out[[one]] <- handler
  invisible(id)
}

#' Evaluate the `filename` argument of the download handler
#'
#' @noRd
resolve_filename <- function(filename) {
  if (is.function(filename)) filename <- filename()
  filename <- as.character(filename)
  if (length(filename) == 0L || is.na(filename[1L])) "" else filename[1L]
}

#' Evaluate the `snapshot` argument of the download handler
#'
#' @noRd
resolve_snapshot <- function(snapshot, session, dots) {
  if (is.null(snapshot)) {
    return(do.call(snap_take, c(list(session = session), dots)))
  }
  if (is.function(snapshot)) snapshot <- snapshot()
  as_snapshot(snapshot)
}
