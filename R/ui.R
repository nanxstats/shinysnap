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

#' Restore-state upload and its handler
#'
#' `snap_file_input()` is a `fileInput()` with the client script attached.
#' `snap_file_restore()` observes it: when a file is uploaded it reads the
#' snapshot with [snap_read()], runs `validate` and `migrate`, and calls
#' [snap_restore()], reporting problems to the user.
#'
#' @param id The input id. `snap_file_restore()` accepts a vector of ids, so
#'   that several upload controls share one definition.
#' @param label,accept,... Passed on to `shiny::fileInput()`. In
#'   `snap_file_restore()`, `...` is passed on to [snap_restore()].
#' @inheritParams snap_restore
#' @param on_error How to report a file that cannot be restored: a
#'   `showNotification()` (the default), a `showModal()` dialog, or `stop()`.
#' @param session The Shiny session. Defaults to the current session.
#'
#' @returns `snap_file_input()` returns a tag. `snap_file_restore()` returns
#'   the ids invisibly.
#'
#' @examples
#' if (interactive()) {
#'   library(shiny)
#'
#'   ui <- fluidPage(
#'     sliderInput("n", "n", 1, 100, 50),
#'     snap_download_button("save"),
#'     snap_file_input("restore")
#'   )
#'
#'   server <- function(input, output, session) {
#'     snap_enable(app = "demo", version = "1.0.0")
#'     snap_download_handler("save")
#'     snap_file_restore("restore", validate = function(snap) {
#'       if (is.null(snap$inputs$n)) stop("This file does not contain `n`.")
#'     })
#'   }
#'
#'   shinyApp(ui, server)
#' }
#' @export
snap_file_input <- function(id, label = "Restore state", accept = ".json", ...) {
  tag <- shiny::fileInput(id, label, accept = accept, ...)
  htmltools::attachDependencies(tag, snap_dependency(), append = TRUE)
}

#' @rdname snap_file_input
#' @export
snap_file_restore <- function(id, ..., validate = NULL, migrate = NULL,
                              on_error = c("notify", "modal", "stop"),
                              session = shiny::getDefaultReactiveDomain()) {
  session <- require_session(session, "snap_file_restore")
  if (!is.character(id) || length(id) == 0L || anyNA(id) || !all(nzchar(id))) {
    snap_abort("`id` must be a character vector of input ids.")
  }
  on_error <- match.arg(on_error)
  dots <- list(...)
  snap_controller(session)
  input <- session$input
  report_error <- function(e) {
    if (inherits(e, "shinysnap_cancelled")) {
      return(invisible(NULL))
    }
    msg <- conditionMessage(e)
    switch(on_error,
      notify = shiny::showNotification(
        msg,
        type = "error", duration = 10, session = session
      ),
      modal = shiny::showModal(
        shiny::modalDialog(
          title = "Could not restore this file", msg,
          easyClose = TRUE, footer = shiny::modalButton("Close")
        ),
        session = session
      ),
      stop = stop(e)
    )
    invisible(NULL)
  }
  for (one in id) {
    local({
      one <- one
      shiny::observeEvent(
        input[[one]],
        {
          upload <- input[[one]]
          if (!is_file_input_value(upload) || nrow(upload) < 1L) {
            return(invisible(NULL))
          }
          p <- tryCatch(
            {
              snap <- snap_read(
                upload$datapath[[1L]],
                format = format_from_path(upload$name[[1L]])
              )
              do.call(snap_restore, c(
                list(snap, session = session, validate = validate, migrate = migrate),
                dots
              ))
            },
            error = function(e) {
              report_error(e)
              NULL
            }
          )
          if (!is.null(p)) promises::catch(p$promise, report_error)
          invisible(NULL)
        },
        domain = session
      )
    })
  }
  invisible(id)
}
