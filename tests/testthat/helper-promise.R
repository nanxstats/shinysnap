# Drive the event loop until a promise settles; return its value or re-raise.
settle_promise <- function(p, timeout = 5) {
  if (inherits(p, "shinysnap_restore")) p <- p$promise
  state <- new.env(parent = emptyenv())
  state$done <- FALSE
  promises::then(
    p,
    onFulfilled = function(v) {
      state$value <- v
      state$done <- TRUE
    },
    onRejected = function(e) {
      state$error <- e
      state$done <- TRUE
    }
  )
  deadline <- Sys.time() + timeout
  while (!state$done && Sys.time() < deadline) later::run_now(0.02)
  if (!state$done) stop("the promise did not settle in time")
  if (!is.null(state$error)) stop(state$error)
  state$value
}

promise_error <- function(p, timeout = 5) {
  tryCatch(
    {
      settle_promise(p, timeout)
      NULL
    },
    error = identity
  )
}

action_value <- function(n = 0L) {
  structure(as.integer(n), class = c("shinyActionButtonValue", "integer"))
}
