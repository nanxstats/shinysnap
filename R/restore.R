report_statuses <- c(
  "applied", "constructed", "reapplied", "missing", "failed", "mismatched",
  "skipped"
)

#' Restore a snapshot into the running app
#'
#' Writes the snapshot's tracked values back into the registered
#' `reactiveValues`, runs the restore hooks, and sends the input values to the
#' browser, where the client script applies each one as soon as its input is
#' on the page. Inputs inside dynamic UI that appears (or re-renders) during
#' the restore receive their values without any timing configuration; while
#' the restore is in flight, shiny's `restoreInput()` mechanism is primed so
#' that dynamic UI is built with the restored values directly.
#'
#' @details
#' The function never blocks. It returns a promise that resolves to a
#' *restore report* once the browser reports that the page has settled (no
#' activity for `settle` seconds) or `timeout` seconds have passed. The report
#' is a data frame with one row per input and the columns `id`, `status`,
#' `binding`, and `detail`, plus the attributes `txn`, `elapsed` (seconds),
#' `settled`, and `timed_out`. Statuses:
#'
#' * `applied`: sent to an input that was on the page.
#' * `constructed`: the input appeared during the restore already carrying
#'   the value, thanks to `restoreInput()`.
#' * `reapplied`: the input re-rendered during the restore and received the
#'   value again.
#' * `missing`: the input never appeared before the restore settled.
#' * `failed`: the input's binding raised an error.
#' * `mismatched`: applied, but the input reports a different value
#'   afterwards (for example a select whose choices do not contain it).
#' * `skipped`: excluded, or its restorer chose not to restore it.
#'
#' Preparation errors (an unreadable file, a failing `validate` or `migrate`
#' hook, a file from a different app) are raised immediately. Problems during
#' the transaction reject the promise: a second `snap_restore()` cancels the
#' first (condition class `shinysnap_cancelled`), a failing hook, and, with
#' `unknown = "error"`, inputs that never appeared or failed.
#'
#' @param x A snapshot object, a file path, or JSON text.
#' @param session The Shiny session. Defaults to the current session.
#' @param ... Not used; arguments after `session` must be named.
#' @param inputs,values Restore the inputs / the tracked values? Set one to
#'   `FALSE` to restore only the other.
#' @param include,exclude Regular expressions matched against fully
#'   namespaced ids, in addition to those configured with [snap_enable()].
#' @param validate A function of the snapshot that should `stop()` with a
#'   user-facing message when the file is not acceptable. Runs first.
#' @param migrate A function `function(snapshot, from_version)` returning a
#'   modified snapshot, for example filling in defaults for values introduced
#'   after `from_version` (the app version recorded in the file, or `NULL`).
#'   Runs after `validate`, before anything is touched.
#' @param check_app Refuse files whose app name differs from the one
#'   configured with [snap_enable()] (only when both are known).
#' @param unknown What to do when inputs never appeared or failed: `"warn"`
#'   (one consolidated warning, the default), `"skip"` (nothing), or
#'   `"error"` (reject the promise).
#' @param timeout Seconds after which the browser stops waiting for inputs
#'   that have not appeared.
#' @param settle Seconds of quiet (no busy state, no new UI) after which the
#'   browser considers the restore complete.
#' @param use_restore_context Prime shiny's `restoreInput()` mechanism during
#'   the restore. Defaults to the value configured with [snap_enable()].
#' @param on_done A function of the report, called when the restore settles;
#'   a convenience for code that does not want to work with promises.
#'
#' @returns A handle of class `shinysnap_restore`, invisibly: a list with the
#'   transaction id in `txn` and a [promises::promise()] that resolves to the
#'   restore report in `promise`. The handle is deliberately not a promise
#'   itself: shiny waits for a promise returned from an observer before it
#'   flushes, and the report can only arrive after the browser has finished
#'   applying the restore, so returning the promise from an observer would
#'   stall the restore. Use `on_done`, [snap_on_restored()], or
#'   `promises::then(handle$promise, ...)` to work with the report.
#'
#' @examples
#' if (interactive()) {
#'   library(shiny)
#'
#'   server <- function(input, output, session) {
#'     observeEvent(input$restore_from_text, {
#'       snap_restore(input$json, on_done = function(report) print(report))
#'     })
#'   }
#' }
#' @export
snap_restore <- function(x, session = shiny::getDefaultReactiveDomain(), ...,
                         inputs = TRUE, values = TRUE, include = NULL,
                         exclude = NULL, validate = NULL, migrate = NULL,
                         check_app = TRUE, unknown = c("warn", "skip", "error"),
                         timeout = 10, settle = 0.3, use_restore_context = NULL,
                         on_done = NULL) {
  if (...length() > 0L) {
    snap_abort("Arguments of `snap_restore()` after `session` must be named.")
  }
  session <- require_session(session, "snap_restore")
  unknown <- match.arg(unknown)
  include <- check_patterns(include, "include")
  exclude <- check_patterns(exclude, "exclude")
  for (arg in c("validate", "migrate", "on_done")) {
    fn <- get(arg)
    if (!is.null(fn) && !is.function(fn)) {
      snap_abort(sprintf("`%s` must be a function or NULL.", arg))
    }
  }
  if (!is.numeric(timeout) || length(timeout) != 1L || is.na(timeout) || timeout <= 0) {
    snap_abort("`timeout` must be a single positive number of seconds.")
  }
  if (!is.numeric(settle) || length(settle) != 1L || is.na(settle) || settle < 0) {
    snap_abort("`settle` must be a single non-negative number of seconds.")
  }
  ctrl <- snap_controller(session)
  root <- session$rootScope()
  use_ctx <- if (is.null(use_restore_context)) {
    ctrl$use_restore_context
  } else {
    isTRUE(use_restore_context)
  }

  # 1. Coerce, validate, migrate, and check: all before anything is touched.
  snap <- as_snapshot(x)
  if (!is.null(validate)) validate(snap)
  if (!is.null(migrate)) snap <- as_snapshot(migrate(snap, snap$app$version))
  check_snapshot_for_restore(snap, ctrl, check_app)

  # 2. Decide what to apply and build the client records.
  plan <- plan_inputs(snap, ctrl, session, inputs, include, exclude)
  state <- list(
    inputs = plan$inputs,
    values = if (isTRUE(values)) snap$values else list(),
    snapshot = snap,
    txn = new_txn_id()
  )
  txn <- new.env(parent = emptyenv())
  txn$id <- state$txn
  txn$state <- state
  txn$records <- plan$records
  txn$skipped <- plan$skipped
  txn$opts <- list(
    unknown = unknown, timeout = timeout, settle = settle, use_ctx = use_ctx
  )
  txn$started <- NULL
  txn$prev_ctx <- NULL
  txn$observer <- NULL

  # 3. Replace any transaction in flight.
  cancel_transaction(ctrl, "superseded by a new restore")
  ctrl$txn <- txn
  ctrl$flags$restoring <- TRUE

  p <- promises::promise(function(resolve, reject) {
    txn$resolve <- resolve
    txn$reject <- reject
    begin <- function() {
      if (!identical(ctrl$txn, txn)) {
        return(invisible(NULL))
      }
      tryCatch(
        start_transaction(ctrl, txn),
        error = function(e) {
          abort_transaction(ctrl, txn)
          reject(e)
        }
      )
      invisible(NULL)
    }
    if (ctrl$is_ready()) {
      begin()
    } else {
      ctrl$note("the client script is not ready yet; the restore starts when it is")
      txn$observer <- shiny::observeEvent(
        root$input[[".shinysnap_ready"]],
        {
          txn$observer <- NULL
          begin()
        },
        once = TRUE,
        domain = root
      )
    }
  })
  if (!is.null(on_done)) {
    promises::then(p, onFulfilled = on_done, onRejected = function(e) NULL)
  }
  # Register a no-op handler so that ignoring the restore (for example when
  # only `on_done` is used) never raises an unhandled promise rejection, for
  # a cancellation or any other error. Callers that want to handle the error
  # attach their own handler to `handle$promise`.
  promises::catch(p, function(e) NULL)
  invisible(new_restore_handle(state$txn, p))
}

#' @noRd
new_restore_handle <- function(txn, promise) {
  structure(list(txn = txn, promise = promise), class = "shinysnap_restore")
}

#' @export
print.shinysnap_restore <- function(x, ...) {
  cat(sprintf("<shinysnap_restore> transaction %s\n", x$txn))
  cat("  $promise resolves to the restore report; see ?snap_restore.\n")
  invisible(x)
}

#' Built-in checks that always run before a restore
#'
#' @noRd
check_snapshot_for_restore <- function(snap, ctrl, check_app) {
  if (isTRUE(check_app) && !is.null(ctrl$app) && !is.null(snap$app$name) &&
    !identical(ctrl$app, snap$app$name)) {
    snap_abort(
      sprintf(
        "This file was saved by a different app (\"%s\"; this app is \"%s\").",
        snap$app$name, ctrl$app
      ),
      class = "shinysnap_app_mismatch"
    )
  }
  ids <- names(snap$inputs)
  bad <- ids[!grepl("^[^[:space:][:cntrl:]]+$", ids)]
  if (length(bad)) {
    snap_abort(
      sprintf("The file contains invalid input ids: %s.", quote_ids(bad)),
      class = "shinysnap_invalid"
    )
  }
  invisible(snap)
}

#' Filter the inputs to restore and build one client record per input
#'
#' @noRd
plan_inputs <- function(snap, ctrl, session, inputs, include, exclude) {
  all <- if (isTRUE(inputs)) snap$inputs else list()
  ids <- names(all)
  if (is.null(ids)) ids <- character()
  inv <- ctrl$inventory()
  binding_of <- function(id) {
    b <- inv[id]
    if (length(b) == 1L && !is.na(b) && nzchar(b)) {
      return(unname(b))
    }
    b <- snap$bindings[id]
    if (length(b) == 1L && !is.na(b) && nzchar(b)) {
      return(unname(b))
    }
    ""
  }
  skipped <- list()
  skip <- function(id, binding, why) {
    skipped[[length(skipped) + 1L]] <<- list(
      id = id, status = "skipped", binding = binding, detail = why
    )
  }
  keep <- select_ids(ids, ctrl, include, exclude)
  records <- list()
  kept <- list()
  for (i in seq_along(ids)) {
    id <- ids[i]
    value <- all[[i]]
    binding <- binding_of(id)
    if (!keep[i]) {
      skip(id, binding, "excluded")
      next
    }
    if (is_action_button_value(value)) {
      skip(id, binding, "action button")
      next
    }
    fn <- resolve_restorer(id, binding, ctrl)
    payload <- fn(id, value, binding, session)
    if (is.null(payload)) {
      skip(id, binding, "no payload from restorer")
      next
    }
    if (!is.list(payload)) {
      snap_abort(
        sprintf("The restorer for `%s` must return a list or NULL.", id),
        class = "shinysnap_error"
      )
    }
    records[[length(records) + 1L]] <- build_record(id, binding, payload)
    kept[id] <- list(value)
  }
  list(inputs = kept, records = records, skipped = skipped)
}

#' Start the transaction: values, hooks, restore context, client message
#'
#' @noRd
start_transaction <- function(ctrl, txn) {
  state <- txn$state
  restore_values(ctrl, state$values)
  ctrl$on_restore$invoke(state)
  if (isTRUE(txn$opts$use_ctx)) prime_restore_context(ctrl, txn)
  txn$started <- Sys.time()
  if (length(txn$records) == 0L) {
    finish_transaction(ctrl, txn, NULL)
    return(invisible(NULL))
  }
  ensure_result_observer(ctrl)
  ctrl$send("shinysnap:restore", list(
    txn = txn$id,
    timeout = txn$opts$timeout * 1000,
    settle = txn$opts$settle * 1000,
    debug = isTRUE(ctrl$verbose),
    inputs = txn$records
  ))
  ctrl$note("restore ", txn$id, ": sent ", length(txn$records), " input(s) to the client")
  invisible(NULL)
}

#' Write the file's values into the tracked reactiveValues
#'
#' Only the fields present in the file are assigned; the `migrate` hook is
#' where defaults for new fields belong.
#'
#' @noRd
restore_values <- function(ctrl, values) {
  if (length(values) == 0L) {
    return(invisible(NULL))
  }
  shiny::isolate({
    for (nm in intersect(names(ctrl$tracked), names(values))) {
      tracked <- ctrl$tracked[[nm]]
      fields <- values[[nm]]
      if (!is.list(fields) || length(fields) == 0L || !has_full_names(fields)) {
        next
      }
      if (!is.null(tracked$fields)) {
        fields <- fields[intersect(names(fields), tracked$fields)]
      }
      for (f in names(fields)) {
        tracked$values[[f]] <- fields[[f]]
      }
    }
  })
  invisible(NULL)
}

#' The session's restore context, if it supports what we need
#'
#' @noRd
restore_context_of <- function(root) {
  ctx <- root$restoreContext
  if (inherits(ctx, "RestoreContext") && is.function(ctx$set) &&
    is.function(ctx$asList)) {
    ctx
  } else {
    NULL
  }
}

#' Make `restoreInput()` return the snapshot's values during the transaction
#'
#' @noRd
prime_restore_context <- function(ctrl, txn) {
  ctx <- restore_context_of(ctrl$root)
  if (is.null(ctx)) {
    return(invisible(FALSE))
  }
  prev <- ctx$asList()
  txn$prev_ctx <- list(
    active = isTRUE(ctx$active),
    initErrorMessage = ctx$initErrorMessage,
    input = prev$input,
    values = if (is.environment(prev$values)) {
      as.list.environment(prev$values, all.names = TRUE)
    } else {
      as.list(prev$values)
    },
    dir = prev$dir
  )
  ctx$set(active = TRUE, input = txn$state$inputs, values = list(), dir = NULL)
  invisible(TRUE)
}

#' Put the previous restore context back
#'
#' @noRd
unprime_restore_context <- function(ctrl, txn) {
  prev <- txn$prev_ctx
  if (is.null(prev)) {
    return(invisible(FALSE))
  }
  txn$prev_ctx <- NULL
  ctx <- restore_context_of(ctrl$root)
  if (is.null(ctx)) {
    return(invisible(FALSE))
  }
  ctx$set(
    active = prev$active, initErrorMessage = prev$initErrorMessage,
    input = prev$input, values = prev$values, dir = prev$dir
  )
  invisible(TRUE)
}

#' Watch for the client's result once per session
#'
#' @noRd
ensure_result_observer <- function(ctrl) {
  root <- ctrl$root
  if (is.null(ctrl$result_observer)) {
    ctrl$result_observer <- shiny::observeEvent(
      root$input[[".shinysnap_result"]],
      {
        res <- root$input[[".shinysnap_result"]]
        txn <- ctrl$txn
        if (!is.null(txn) && !is.null(txn$started) && identical(res$txn, txn$id)) {
          finish_transaction(ctrl, txn, res)
        }
      },
      domain = root
    )
  }
  if (!ctrl$cleanup_registered) {
    ctrl$cleanup_registered <- TRUE
    root$onSessionEnded(function() {
      cancel_transaction(ctrl, "the session ended")
    })
  }
  invisible(NULL)
}

#' Reject and drop the transaction in flight, if any
#'
#' @noRd
cancel_transaction <- function(ctrl, why) {
  old <- ctrl$txn
  if (is.null(old)) {
    return(invisible(FALSE))
  }
  ctrl$txn <- NULL
  if (!is.null(old$observer)) {
    old$observer$destroy()
    old$observer <- NULL
  }
  if (!is.null(old$started) && length(old$records)) {
    ctrl$send("shinysnap:cancel", list(txn = old$id))
  }
  unprime_restore_context(ctrl, old)
  ctrl$flags$restoring <- FALSE
  ctrl$note("restore ", old$id, " cancelled: ", why)
  if (is.function(old$reject)) {
    old$reject(cancelled_condition(old$id, why))
  }
  invisible(TRUE)
}

#' Drop a transaction whose start failed
#'
#' @noRd
abort_transaction <- function(ctrl, txn) {
  if (identical(ctrl$txn, txn)) ctrl$txn <- NULL
  unprime_restore_context(ctrl, txn)
  ctrl$flags$restoring <- FALSE
  invisible(NULL)
}

#' Build the report, run the restored hooks, and settle the promise
#'
#' @noRd
finish_transaction <- function(ctrl, txn, res) {
  ctrl$txn <- NULL
  unprime_restore_context(ctrl, txn)
  ctrl$flags$restoring <- FALSE
  report <- build_report(txn, res)
  ctrl$note(
    "restore ", txn$id, " ", if (isTRUE(attr(report, "timed_out"))) "timed out" else "settled",
    ": ", paste(sprintf("%s=%d", names(table(report$status)), table(report$status)), collapse = ", ")
  )
  err <- tryCatch(
    {
      ctrl$on_restored$invoke(txn$state, report)
      NULL
    },
    error = identity
  )
  if (!is.null(err)) {
    txn$reject(err)
    return(invisible(NULL))
  }
  problems <- report[report$status %in% c("missing", "failed"), , drop = FALSE]
  if (nrow(problems) && txn$opts$unknown != "skip") {
    msg <- describe_problems(problems)
    if (txn$opts$unknown == "error") {
      txn$reject(structure(
        list(message = msg, call = NULL, report = report),
        class = c("shinysnap_restore_error", "shinysnap_error", "error", "condition")
      ))
      return(invisible(NULL))
    }
    snap_warn(msg, class = "shinysnap_restore_warning", report = report)
  }
  txn$resolve(report)
  invisible(NULL)
}

#' One sentence about the inputs that could not be restored
#'
#' @noRd
describe_problems <- function(problems) {
  parts <- character()
  missing <- problems$id[problems$status == "missing"]
  failed <- problems[problems$status == "failed", , drop = FALSE]
  if (length(missing)) {
    parts <- c(parts, sprintf(
      "%d input(s) never appeared on the page: %s",
      length(missing), quote_ids(missing)
    ))
  }
  if (nrow(failed)) {
    parts <- c(parts, sprintf(
      "%d input(s) failed: %s",
      nrow(failed),
      paste0("`", failed$id, "` (", failed$detail, ")", collapse = ", ")
    ))
  }
  paste0("Restore incomplete: ", paste(parts, collapse = "; "), ".")
}

#' Turn the client's result (or none) into a report data frame
#'
#' @noRd
build_report <- function(txn, res) {
  rows <- list()
  if (!is.null(res)) {
    for (r in res$results) {
      rows[[length(rows) + 1L]] <- list(
        id = as.character(r$id %||% ""),
        status = as.character(r$status %||% "missing"),
        binding = as.character(r$binding %||% ""),
        detail = as.character(r$detail %||% "")
      )
    }
  }
  rows <- c(rows, txn$skipped)
  elapsed <- if (!is.null(res$elapsed)) {
    as.numeric(res$elapsed) / 1000
  } else if (!is.null(txn$started)) {
    as.numeric(difftime(Sys.time(), txn$started, units = "secs"))
  } else {
    0
  }
  new_report(rows, txn$id, elapsed, isTRUE(res$timedOut))
}

#' @noRd
new_report <- function(rows, txn, elapsed, timed_out) {
  col <- function(field) {
    vapply(rows, function(r) as.character(r[[field]] %||% ""), character(1))
  }
  status <- col("status")
  status[!status %in% report_statuses] <- "failed"
  df <- data.frame(
    id = col("id"), status = status, binding = col("binding"),
    detail = col("detail"), stringsAsFactors = FALSE
  )
  structure(
    df,
    class = c("shinysnap_report", "data.frame"),
    txn = txn, elapsed = elapsed, settled = !timed_out, timed_out = timed_out
  )
}

#' Subset a report's rows, keeping its attributes
#'
#' @noRd
subset_report <- function(report, keep) {
  out <- report
  class(out) <- "data.frame"
  out <- out[keep, , drop = FALSE]
  rownames(out) <- NULL
  structure(
    out,
    class = c("shinysnap_report", "data.frame"),
    txn = attr(report, "txn"), elapsed = attr(report, "elapsed"),
    settled = attr(report, "settled"), timed_out = attr(report, "timed_out")
  )
}

#' @export
print.shinysnap_report <- function(x, ...) {
  counts <- table(factor(x$status, levels = report_statuses))
  counts <- counts[counts > 0]
  cat(sprintf(
    "<shinysnap_report> %d input(s), %s after %.2f s\n",
    nrow(x),
    if (isTRUE(attr(x, "timed_out"))) "timed out" else "settled",
    attr(x, "elapsed") %||% NA_real_
  ))
  if (length(counts)) {
    cat("  ", paste(sprintf("%s: %d", names(counts), counts), collapse = ", "), "\n", sep = "")
  }
  if (nrow(x)) {
    df <- x
    class(df) <- "data.frame"
    print(df, row.names = FALSE, ...)
  }
  invisible(x)
}

#' @noRd
cancelled_condition <- function(id, why) {
  structure(
    list(
      message = sprintf("Restore %s was cancelled: %s.", id, why),
      call = NULL, txn = id
    ),
    class = c("shinysnap_cancelled", "shinysnap_error", "error", "condition")
  )
}

#' @noRd
new_txn_id <- function() {
  paste(sample(c(letters, 0:9), 8, replace = TRUE), collapse = "")
}

#' Is a restore in flight?
#'
#' `TRUE` from the moment [snap_restore()] is called until the browser reports
#' that the restore has settled (or timed out), `FALSE` otherwise. Inside a
#' reactive context the result is reactive, so observers and outputs can
#' react to the end of a restore; outside one it is a plain value.
#'
#' Use it to keep expensive observers from running on every intermediate
#' value during a restore, and to run something once the state is complete.
#'
#' @param session The Shiny session. Defaults to the current session.
#'
#' @returns A logical scalar.
#'
#' @examples
#' if (interactive()) {
#'   library(shiny)
#'
#'   server <- function(input, output, session) {
#'     observeEvent(input$n, {
#'       if (snap_is_restoring()) {
#'         return()
#'       }
#'       message("user changed n to ", input$n)
#'     })
#'   }
#' }
#' @export
snap_is_restoring <- function(session = shiny::getDefaultReactiveDomain()) {
  if (is.null(session)) {
    return(FALSE)
  }
  ctrl <- snap_controller(session, create = FALSE)
  if (is.null(ctrl)) {
    return(FALSE)
  }
  read <- function() isTRUE(ctrl$flags$restoring)
  tryCatch(read(), error = function(e) shiny::isolate(read()))
}
