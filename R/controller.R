#' Per-session controller
#'
#' One instance per Shiny session, created lazily by the first `snap_*()`
#' server function and stored in the root session's `userData`. It holds
#' the configuration, the tracked `reactiveValues`, the hook managers, and
#' (from the restore side) the state of the current transaction.
#'
#' @noRd
SnapController <- R6Class(
  "SnapController",
  public = list(
    root = NULL,
    app = NULL,
    version = NULL,
    exclude = character(),
    include = character(),
    live_only = TRUE,
    use_restore_context = TRUE,
    verbose = FALSE,
    tracked = list(),
    on_save = NULL,
    on_restore = NULL,
    on_restored = NULL,
    dependency_injected = FALSE,
    restorers = list(),
    flags = NULL,
    txn = NULL,
    send = NULL,
    result_observer = NULL,
    cleanup_registered = FALSE,
    initialize = function(root) {
      self$root <- root
      self$app <- getOption("shinysnap.app")
      self$version <- getOption("shinysnap.version")
      self$on_save <- new_callbacks()
      self$on_restore <- new_callbacks()
      self$on_restored <- new_callbacks()
      self$flags <- shiny::reactiveValues(restoring = FALSE)
      # Messages to the client go through a replaceable field so that tests
      # can observe them; real sessions send custom messages from the root.
      self$send <- function(type, message) {
        root$sendCustomMessage(type, message)
      }
    },
    configure = function(app = NULL, version = NULL, exclude = NULL,
                         include = NULL, live_only = TRUE,
                         use_restore_context = TRUE, verbose = FALSE) {
      self$app <- app %||% getOption("shinysnap.app")
      self$version <- version %||% getOption("shinysnap.version")
      if (!is.null(self$app) && !is_string(self$app)) {
        snap_abort("`app` must be NULL or a single string.")
      }
      if (!is.null(self$version)) {
        self$version <- as.character(self$version)
        if (!is_string(self$version)) {
          snap_abort("`version` must be NULL or a single string.")
        }
      }
      self$exclude <- check_patterns(exclude, "exclude")
      self$include <- check_patterns(include, "include")
      self$live_only <- isTRUE(live_only)
      self$use_restore_context <- isTRUE(use_restore_context)
      self$verbose <- isTRUE(verbose)
      invisible(self)
    },
    track = function(name, values, fields = NULL) {
      self$tracked[[name]] <- list(values = values, fields = fields)
      invisible(name)
    },
    # The client's map of bound input id -> binding name, or NULL when the
    # client script has not reported yet. Read in isolation so that callers
    # never take a reactive dependency on it.
    inventory = function() {
      inv <- shiny::isolate(self$root$input[[".shinysnap_inventory"]])
      if (is.null(inv)) {
        return(NULL)
      }
      if (!is.list(inv)) inv <- as.list(inv)
      out <- vapply(inv, function(x) {
        if (is.character(x) && length(x) == 1L && !is.na(x)) x else ""
      }, character(1))
      if (length(out) == 0L) {
        return(character())
      }
      out
    },
    is_ready = function() {
      isTRUE(shiny::isolate(self$root$input[[".shinysnap_ready"]]))
    },
    # Inject the client script into the page. Only real sessions can do this;
    # the injection is idempotent on the client, so it is safe even when the
    # UI already includes snap_dependency().
    ensure_dependency = function() {
      if (self$dependency_injected || !inherits(self$root, "ShinySession")) {
        return(invisible(FALSE))
      }
      shiny::insertUI(
        selector = "head", where = "beforeEnd",
        ui = htmltools::tagList(snap_dependency()),
        immediate = TRUE, session = self$root
      )
      self$dependency_injected <- TRUE
      invisible(TRUE)
    },
    note = function(...) {
      if (self$verbose) message("shinysnap: ", ...)
      invisible(NULL)
    }
  )
)
