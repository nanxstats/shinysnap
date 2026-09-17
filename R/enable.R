#' Configure shinysnap for a session
#'
#' Sets the app identity and the defaults used by [snap_take()] and
#' `snap_restore()` for the current session. Calling it is optional: every
#' `snap_*()` server function creates the per-session state on first use with
#' the defaults below. Call it again to change the settings.
#'
#' @param app,version The name and version of the app, written into every
#'   snapshot file. They default to the options `shinysnap.app` and
#'   `shinysnap.version`, which packaged apps can set once in `.onLoad()`.
#' @param exclude,include Character vectors of regular expressions matched
#'   against fully namespaced input ids. Matching `exclude` patterns are
#'   never captured; when `include` is given, only matching ids are. Ids
#'   excluded with shiny's `setBookmarkExclude()` are always honoured too.
#' @param live_only Capture only inputs that are currently on the page (as
#'   reported by the client script), dropping values of inputs whose UI has
#'   been removed. Set to `FALSE` to capture every value shiny remembers.
#' @param use_restore_context Prime shiny's `restoreInput()` mechanism during
#'   a restore, so that dynamic UI re-rendered during the restore is built
#'   with the restored values. Turn off only to debug.
#' @param verbose Print messages about what is captured, dropped, and
#'   restored.
#' @param session The Shiny session. Defaults to the current session.
#'
#' @returns The per-session controller, invisibly.
#'
#' @examples
#' if (interactive()) {
#'   library(shiny)
#'
#'   server <- function(input, output, session) {
#'     snap_enable(app = "myapp", version = "2.4.0", exclude = c("^btn_", "^nav_"))
#'   }
#' }
#' @export
snap_enable <- function(app = NULL, version = NULL, exclude = NULL, include = NULL,
                        live_only = TRUE, use_restore_context = TRUE,
                        verbose = FALSE,
                        session = shiny::getDefaultReactiveDomain()) {
  session <- require_session(session, "snap_enable")
  ctrl <- snap_controller(session)
  ctrl$configure(
    app = app, version = version, exclude = exclude, include = include,
    live_only = live_only, use_restore_context = use_restore_context,
    verbose = verbose
  )
  invisible(ctrl)
}

#' The client-side script as an HTML dependency
#'
#' The `snap_*()` server functions inject this script into the page on first
#' use, so including it in the UI is optional. Include it explicitly when you
#' want the script to load with the page, before the server function runs.
#'
#' @returns An [htmltools::htmlDependency()].
#'
#' @examples
#' snap_dependency()
#' @export
snap_dependency <- function() {
  htmltools::htmlDependency(
    name = "shinysnap",
    version = as.character(utils::packageVersion("shinysnap")),
    src = c(file = system.file("www", package = "shinysnap")),
    script = "shinysnap.js"
  )
}

#' Get (or create) the controller of a session
#'
#' @noRd
snap_controller <- function(session, create = TRUE) {
  root <- session$rootScope()
  ctrl <- root$userData$.shinysnap
  if (is.null(ctrl)) {
    if (!create) {
      return(NULL)
    }
    ctrl <- SnapController$new(root)
    root$userData$.shinysnap <- ctrl
    ctrl$ensure_dependency()
  }
  ctrl
}
