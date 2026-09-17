# The whole transaction, with the client simulated: the controller's `send`
# field records outgoing messages and `session$setInputs()` plays the
# client's replies.

sim_server <- function(input, output, session) {
  ctrl <- snap_enable(app = "sim", version = "1")
  session$userData$sent <- list()
  ctrl$send <- function(type, message) {
    session$userData$sent[[length(session$userData$sent) + 1L]] <- list(type = type, message = message)
  }
  rv <- reactiveValues(a = 1L, b = "x", c = TRUE)
  snap_track(rv)
  NULL
}

sent_messages <- function(session) session$userData$sent

client_ready <- function(session, inventory = list(n = "shiny.numberInput", txt = "shiny.textInput", pw = "shiny.passwordInput")) {
  session$setInputs(.shinysnap_ready = TRUE, .shinysnap_inventory = inventory)
}

client_result <- function(session, txn, results, timed_out = FALSE, elapsed = 42) {
  session$setInputs(.shinysnap_result = list(
    txn = txn, elapsed = elapsed, timedOut = timed_out, results = results
  ))
}

row <- function(id, status, binding = "", detail = "") {
  list(id = id, status = status, binding = binding, detail = detail)
}

sim_snapshot <- function(...) {
  new_snapshot(
    inputs = list(n = 5L, txt = "hi", pw = "s3cret", go = action_value(2L), ghost = "boo"),
    values = list(rv = list(a = 9L, b = "y", extra = "new")),
    bindings = c(n = "shiny.numberInput", ghost = "shiny.textInput"),
    app = list(name = "sim", version = "0.9"),
    ...
  )
}

test_that("a restore writes values, runs hooks, sends records, and resolves to a report", {
  shiny::testServer(sim_server, {
    client_ready(session)
    seen <- new.env()
    snap_on_restore(function(state) seen$state <- state, session = session)
    snap_on_restored(function(state, report) seen$report <- report, session = session)

    p <- snap_restore(sim_snapshot(), session = session, on_done = function(r) seen$done <- r)
    expect_s3_class(p, "shinysnap_restore")
    expect_false(promises::is.promising(p))
    expect_true(promises::is.promise(p$promise))
    expect_output(print(p), "shinysnap_restore")
    expect_true(snap_is_restoring(session))
    expect_identical(isolate(rv$a), 9L)
    expect_identical(isolate(rv$b), "y")
    expect_identical(isolate(rv$extra), "new")
    expect_identical(isolate(rv$c), TRUE)
    expect_identical(names(seen$state$inputs), c("n", "txt", "ghost"))
    expect_identical(seen$state$values$rv$a, 9L)
    expect_s3_class(seen$state$snapshot, "shinysnap")

    sent <- sent_messages(session)
    expect_length(sent, 1L)
    expect_identical(sent[[1]]$type, "shinysnap:restore")
    msg <- sent[[1]]$message
    expect_identical(msg$timeout, 10000)
    expect_identical(msg$settle, 300)
    expect_false(msg$debug)
    expect_identical(vapply(msg$inputs, `[[`, "", "id"), c("n", "txt", "ghost"))
    expect_identical(msg$inputs[[1]], list(id = "n", binding = "shiny.numberInput", message = list(value = 5L), expect = 5L))
    expect_identical(msg$inputs[[3]]$binding, "shiny.textInput")
    expect_identical(seen$state$txn, msg$txn)
    expect_identical(p$txn, msg$txn)

    expect_warning(
      client_result(session, msg$txn, list(
        row("n", "applied", "shiny.numberInput"),
        row("txt", "constructed", "shiny.textInput"),
        row("ghost", "missing", "shiny.textInput")
      )),
      "never appeared on the page: `ghost`",
      class = "shinysnap_restore_warning"
    )
    report <- settle_promise(p)
    expect_s3_class(report, c("shinysnap_report", "data.frame"))
    expect_identical(report$id, c("n", "txt", "ghost", "pw", "go"))
    expect_identical(report$status, c("applied", "constructed", "missing", "skipped", "skipped"))
    expect_identical(report$detail[4:5], c("no payload from restorer", "action button"))
    expect_identical(report$binding[4], "shiny.passwordInput")
    expect_identical(attr(report, "txn"), msg$txn)
    expect_identical(attr(report, "elapsed"), 0.042)
    expect_true(attr(report, "settled"))
    expect_false(attr(report, "timed_out"))
    expect_false(snap_is_restoring(session))
    expect_identical(seen$done, report)
    expect_identical(seen$report, report)
    expect_output(print(report), "3 input\\(s\\)|5 input\\(s\\)")
    expect_output(print(report), "missing: 1")
  })
})

test_that("files from another app are refused unless check_app = FALSE", {
  shiny::testServer(sim_server, {
    client_ready(session)
    other <- sim_snapshot()
    other$app$name <- "someone-else"
    err <- expect_error(snap_restore(other, session = session), class = "shinysnap_app_mismatch")
    expect_match(conditionMessage(err), "someone-else")
    expect_length(sent_messages(session), 0L)
    expect_false(snap_is_restoring(session))
    p <- snap_restore(other, session = session, check_app = FALSE)
    expect_length(sent_messages(session), 1L)
    anonymous <- sim_snapshot()
    anonymous$app$name <- NULL
    p2 <- snap_restore(anonymous, session = session)
    expect_length(sent_messages(session), 3L)
    expect_s3_class(promise_error(p), "shinysnap_cancelled")
  })
})

test_that("validate runs first, then migrate, then the built-in checks", {
  shiny::testServer(sim_server, {
    client_ready(session)
    calls <- character()
    err <- expect_error(
      snap_restore(sim_snapshot(),
        session = session,
        validate = function(snap) {
          calls <<- c(calls, "validate")
          stop("nope: not my file")
        },
        migrate = function(snap, from) {
          calls <<- c(calls, "migrate")
          snap
        }
      ),
      "nope: not my file"
    )
    expect_identical(calls, "validate")
    expect_length(sent_messages(session), 0L)
    expect_identical(isolate(rv$a), 1L)

    calls <- character()
    p <- snap_restore(sim_snapshot(),
      session = session,
      validate = function(snap) calls <<- c(calls, paste0("validate:", snap$app$version)),
      migrate = function(snap, from) {
        calls <<- c(calls, paste0("migrate:", from))
        snap$values$rv$a <- 100L
        snap$inputs$n <- 50L
        snap
      }
    )
    expect_identical(calls, c("validate:0.9", "migrate:0.9"))
    expect_identical(isolate(rv$a), 100L)
    expect_identical(sent_messages(session)[[1]]$message$inputs[[1]]$message$value, 50L)

    expect_error(
      snap_restore(sim_snapshot(), session = session, migrate = function(snap, from) 42),
      class = "shinysnap_invalid"
    )
    bad <- new_snapshot(inputs = list("bad id" = 1))
    expect_error(snap_restore(bad, session = session), "invalid input ids", class = "shinysnap_invalid")
    expect_error(snap_restore(sim_snapshot(), session = session, validate = "x"), "`validate`")
    expect_error(snap_restore(sim_snapshot(), session = session, timeout = 0), "`timeout`")
    expect_error(snap_restore(sim_snapshot(), session = session, settle = -1), "`settle`")
    expect_error(snap_restore(sim_snapshot(), session, TRUE), "must be named")
    expect_error(snap_restore(sim_snapshot(), session = NULL), class = "shinysnap_no_session")
  })
})

test_that("a restore waits for the client script and starts when it reports ready", {
  shiny::testServer(sim_server, {
    p <- snap_restore(sim_snapshot(), session = session)
    expect_length(sent_messages(session), 0L)
    expect_true(snap_is_restoring(session))
    expect_identical(isolate(rv$a), 1L)
    session$setInputs(.shinysnap_ready = TRUE)
    expect_length(sent_messages(session), 1L)
    expect_identical(isolate(rv$a), 9L)
    txn <- sent_messages(session)[[1]]$message$txn
    client_result(session, txn, list(row("n", "applied"), row("txt", "applied"), row("ghost", "applied")))
    report <- settle_promise(p)
    expect_identical(unique(report$status[1:3]), "applied")
  })
})

test_that("a second restore cancels the first, whether deferred or in flight", {
  shiny::testServer(sim_server, {
    p1 <- snap_restore(sim_snapshot(), session = session)
    p2 <- snap_restore(sim_snapshot(), session = session)
    e1 <- promise_error(p1)
    expect_s3_class(e1, "shinysnap_cancelled")
    expect_match(conditionMessage(e1), "superseded")
    session$setInputs(.shinysnap_ready = TRUE)
    expect_length(sent_messages(session), 1L)
    txn2 <- sent_messages(session)[[1]]$message$txn

    p3 <- snap_restore(sim_snapshot(), session = session)
    e2 <- promise_error(p2)
    expect_s3_class(e2, "shinysnap_cancelled")
    expect_identical(e2$txn, txn2)
    sent <- sent_messages(session)
    expect_identical(vapply(sent, `[[`, "", "type"), c("shinysnap:restore", "shinysnap:cancel", "shinysnap:restore"))
    expect_identical(sent[[2]]$message$txn, txn2)
    txn3 <- sent[[3]]$message$txn
    expect_true(snap_is_restoring(session))

    # A late result for the cancelled transaction is ignored.
    client_result(session, txn2, list(row("n", "applied"), row("txt", "applied"), row("ghost", "applied")))
    expect_true(snap_is_restoring(session))
    client_result(session, txn3, list(row("n", "applied"), row("txt", "applied"), row("ghost", "applied")))
    report <- settle_promise(p3)
    expect_identical(attr(report, "txn"), txn3)
    expect_false(snap_is_restoring(session))
  })
})

test_that("the unknown policy controls what missing and failed inputs do", {
  shiny::testServer(sim_server, {
    client_ready(session)
    results <- list(row("n", "failed", "shiny.numberInput", "boom"), row("txt", "applied"), row("ghost", "missing"))

    p <- snap_restore(sim_snapshot(), session = session, unknown = "skip")
    expect_silent(client_result(session, sent_messages(session)[[1]]$message$txn, results))
    report <- settle_promise(p)
    expect_identical(report$status[1:3], c("failed", "applied", "missing"))

    p <- snap_restore(sim_snapshot(), session = session, unknown = "error")
    txn <- sent_messages(session)[[2]]$message$txn
    expect_silent(client_result(session, txn, results, timed_out = TRUE))
    err <- promise_error(p)
    expect_s3_class(err, "shinysnap_restore_error")
    expect_match(conditionMessage(err), "`ghost`")
    expect_match(conditionMessage(err), "`n` \\(boom\\)")
    expect_s3_class(err$report, "shinysnap_report")
    expect_true(attr(err$report, "timed_out"))
    expect_false(attr(err$report, "settled"))
    expect_false(snap_is_restoring(session))

    p <- snap_restore(sim_snapshot(), session = session)
    txn <- sent_messages(session)[[3]]$message$txn
    w <- expect_warning(client_result(session, txn, results), class = "shinysnap_restore_warning")
    expect_match(conditionMessage(w), "1 input\\(s\\) failed")
    expect_s3_class(w$report, "shinysnap_report")
    expect_s3_class(settle_promise(p), "shinysnap_report")
  })
})

test_that("inputs = FALSE restores values only and resolves at once", {
  shiny::testServer(sim_server, {
    client_ready(session)
    p <- snap_restore(sim_snapshot(), session = session, inputs = FALSE)
    expect_length(sent_messages(session), 0L)
    expect_identical(isolate(rv$a), 9L)
    report <- settle_promise(p)
    expect_identical(nrow(report), 0L)
    expect_false(snap_is_restoring(session))
    expect_output(print(report), "0 input")

    rv$a <- 1L
    p <- snap_restore(sim_snapshot(), session = session, values = FALSE)
    expect_identical(isolate(rv$a), 1L)
    expect_length(sent_messages(session), 1L)
  })
})

test_that("values respect the tracked fields and ignore unknown names", {
  server <- function(input, output, session) {
    ctrl <- snap_enable()
    session$userData$sent <- list()
    ctrl$send <- function(type, message) NULL
    rv <- reactiveValues(a = 1L, b = "x")
    snap_track(rv, fields = "a")
    NULL
  }
  shiny::testServer(server, {
    client_ready(session)
    snap <- new_snapshot(values = list(rv = list(a = 2L, b = "changed"), other = list(z = 1), bad = "not a list"))
    p <- snap_restore(snap, session = session)
    expect_identical(isolate(rv$a), 2L)
    expect_identical(isolate(rv$b), "x")
    expect_identical(nrow(settle_promise(p)), 0L)
  })
})

test_that("errors in hooks reject the promise and clean up", {
  shiny::testServer(sim_server, {
    client_ready(session)
    off <- snap_on_restore(function(state) stop("hook failed"), session = session)
    p <- snap_restore(sim_snapshot(), session = session)
    err <- promise_error(p)
    expect_match(conditionMessage(err), "hook failed")
    expect_false(snap_is_restoring(session))
    expect_length(sent_messages(session), 0L)
    off()

    off <- snap_on_restored(function(state, report) stop("after failed"), session = session)
    p <- snap_restore(sim_snapshot(), session = session)
    txn <- sent_messages(session)[[1]]$message$txn
    client_result(session, txn, list(row("n", "applied"), row("txt", "applied"), row("ghost", "applied")))
    err <- promise_error(p)
    expect_match(conditionMessage(err), "after failed")
    expect_false(snap_is_restoring(session))
    off()
    expect_error(snap_on_restore("x", session = session), "`fn`")
    expect_error(snap_on_restored("x", session = session), "`fn`")
  })
})

test_that("exclusions and restorers decide what is sent", {
  server <- function(input, output, session) {
    ctrl <- snap_enable(exclude = "^txt$")
    session$userData$sent <- list()
    ctrl$send <- function(type, message) {
      session$userData$sent[[length(session$userData$sent) + 1L]] <- list(type = type, message = message)
    }
    shiny::setBookmarkExclude("ghost")
    snap_restorer("n", function(id, value, binding, session) list(value = value * 10L), session = session)
    NULL
  }
  shiny::testServer(server, {
    client_ready(session)
    p <- snap_restore(sim_snapshot(), session = session, exclude = "^pw$")
    msg <- sent_messages(session)[[1]]$message
    expect_identical(vapply(msg$inputs, `[[`, "", "id"), "n")
    expect_identical(msg$inputs[[1]]$message$value, 50L)
    client_result(session, msg$txn, list(row("n", "applied")))
    report <- settle_promise(p)
    expect_identical(report$status, c("applied", "skipped", "skipped", "skipped", "skipped"))
    expect_identical(report$detail, c("", "excluded", "excluded", "action button", "excluded"))

    # Nothing left to send: the promise resolves without a client round trip.
    p <- snap_restore(sim_snapshot(), session = session, include = "^ghost$")
    expect_length(sent_messages(session), 1L)
    report <- settle_promise(p)
    expect_identical(unique(report$status), "skipped")
    expect_identical(nrow(report), 5L)

    snap_restorer("n", function(id, value, binding, session) "not a list", session = session)
    expect_error(snap_restore(sim_snapshot(), session = session), "must return a list")
  })
})

mod_restore <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    rv <- shiny::reactiveValues(count = 1L)
    snap_track(rv)
    seen <- session$userData$seen
    snap_on_restore(function(state) {
      seen$inputs <- names(state$inputs)
      seen$values <- state$values
    })
    snap_on_restored(function(state, report) {
      seen$report <- report
    })
    NULL
  })
}

test_that("hooks registered inside a module see only the module's scope", {
  server <- function(input, output, session) {
    ctrl <- snap_enable()
    session$userData$sent <- list()
    ctrl$send <- function(type, message) {
      session$userData$sent[[length(session$userData$sent) + 1L]] <- list(type = type, message = message)
    }
    session$userData$seen <- new.env()
    mod_restore("m")
    NULL
  }
  shiny::testServer(server, {
    client_ready(session)
    snap <- new_snapshot(
      inputs = list(top = 1L, `m-n` = 2L, `m-txt` = "x"),
      values = list(`m-rv` = list(count = 7L), root_only = list(z = 1))
    )
    p <- snap_restore(snap, session = session)
    seen <- session$userData$seen
    expect_identical(seen$inputs, c("n", "txt"))
    expect_identical(seen$values, list(rv = list(count = 7L)))
    txn <- sent_messages(session)[[1]]$message$txn
    expect_warning(
      client_result(session, txn, list(row("top", "applied"), row("m-n", "applied"), row("m-txt", "missing"))),
      class = "shinysnap_restore_warning"
    )
    report <- settle_promise(p)
    expect_identical(seen$report$id, c("m-n", "m-txt"))
    expect_s3_class(seen$report, "shinysnap_report")
    expect_identical(attr(seen$report, "txn"), txn)
    expect_identical(nrow(report), 3L)
  })
})

test_that("snap_file_restore() reads the upload and restores it", {
  server <- function(input, output, session) {
    ctrl <- snap_enable(app = "sim")
    session$userData$sent <- list()
    ctrl$send <- function(type, message) {
      session$userData$sent[[length(session$userData$sent) + 1L]] <- list(type = type, message = message)
    }
    snap_file_restore(c("up_a", "up_b"), validate = function(snap) {
      if (is.null(snap$inputs$n)) stop("no n in this file")
    })
    snap_file_restore("modal", on_error = "modal")
    expect_error(snap_file_restore(""), "`id`")
    NULL
  }
  shiny::testServer(server, {
    client_ready(session)
    good <- withr::local_tempfile(fileext = ".json")
    file_snapshot <- sim_snapshot()
    file_snapshot$inputs$go <- NULL
    snap_write(file_snapshot, good)
    upload <- function(path, name = basename(path)) {
      data.frame(name = name, size = file.size(path), type = "application/json", datapath = path)
    }
    session$setInputs(up_a = upload(good))
    expect_length(sent_messages(session), 1L)
    session$setInputs(up_b = upload(good, name = "renamed.JSON"))
    expect_length(sent_messages(session), 3L)

    # A file that fails validation: reported, nothing sent.
    bad <- withr::local_tempfile(fileext = ".json")
    writeLines("{\"format\": 1, \"inputs\": {\"other\": 1}}", bad)
    expect_silent(session$setInputs(up_a = upload(bad)))
    expect_length(sent_messages(session), 3L)
    # The modal handler has no validate hook: it restores (cancelling the
    # previous transaction first).
    expect_silent(session$setInputs(modal = upload(bad)))
    expect_length(sent_messages(session), 5L)
    expect_identical(sent_messages(session)[[4]]$type, "shinysnap:cancel")
    # Unreadable files and unknown extensions: reported, nothing sent.
    broken <- withr::local_tempfile(fileext = ".json")
    writeLines("{\"format\": 1", broken)
    expect_silent(session$setInputs(up_a = upload(broken)))
    expect_silent(session$setInputs(up_a = upload(good, name = "state.txt")))
    expect_length(sent_messages(session), 5L)
  })
})

test_that("snap_restore() accepts paths and JSON text", {
  shiny::testServer(sim_server, {
    client_ready(session)
    path <- withr::local_tempfile(fileext = ".json")
    file_snapshot <- sim_snapshot()
    file_snapshot$inputs$go <- NULL
    snap_write(file_snapshot, path)
    p <- snap_restore(path, session = session)
    expect_length(sent_messages(session), 1L)
    p <- snap_restore("{\"format\": 1, \"inputs\": {\"n\": 7}}", session = session)
    expect_identical(sent_messages(session)[[3]]$message$inputs[[1]]$message$value, 7L)
    expect_error(snap_restore("/no/such/file.json", session = session), class = "shinysnap_invalid")
  })
})

test_that("the pending promise is rejected when the session ends", {
  shiny::testServer(sim_server, {
    client_ready(session)
    p <- snap_restore(sim_snapshot(), session = session)
    session$close()
    err <- promise_error(p)
    expect_s3_class(err, "shinysnap_cancelled")
    expect_match(conditionMessage(err), "session ended")
  })
})

test_that("snap_is_restoring() is safe everywhere", {
  expect_false(snap_is_restoring(NULL))
  server <- function(input, output, session) NULL
  shiny::testServer(server, {
    expect_false(snap_is_restoring(session))
    snap_enable(session = session)
    expect_false(snap_is_restoring(session))
    r <- reactive(snap_is_restoring(session))
    expect_false(isolate(r()))
  })
})

test_that("the report class prints, subsets, and normalizes statuses", {
  report <- new_report(
    list(row("a", "applied", "b1"), row("b", "bogus"), list(id = "c")),
    "t1", 1.5, FALSE
  )
  expect_identical(report$status, c("applied", "failed", "failed"))
  expect_identical(report$binding, c("b1", "", ""))
  sub <- subset_report(report, c(TRUE, FALSE, TRUE))
  expect_identical(sub$id, c("a", "c"))
  expect_identical(attr(sub, "txn"), "t1")
  expect_identical(attr(sub, "elapsed"), 1.5)
  expect_s3_class(sub, "shinysnap_report")
  expect_output(print(report), "settled after 1.50 s")
  expect_output(print(report), "applied: 1, failed: 2")
  timed <- new_report(list(), "t2", 2, TRUE)
  expect_output(print(timed), "timed out")
  expect_false(attr(timed, "settled"))
})

test_that("the restore context is primed and put back around a transaction", {
  make_ctx <- getFromNamespace("RestoreContext", "shiny")
  restore_input <- getFromNamespace("restoreInput", "shiny")
  ctx <- make_ctx$new()
  ctx$set(active = TRUE, input = list(prev = "old"), values = list(kept = 1L))
  ctrl <- list(root = list(restoreContext = ctx), note = function(...) NULL)
  txn <- new.env(parent = emptyenv())
  txn$state <- list(inputs = list(n = 5L, method = "b"))

  expect_true(prime_restore_context(ctrl, txn))
  expect_true(ctx$active)
  # restoreInput() now returns the snapshot's values (this is the accelerator).
  got <- shiny::withReactiveDomain(
    structure(list(restoreContext = ctx), class = "ShinySession"),
    restore_input("n", default = -1)
  )
  expect_identical(got, 5L)
  expect_identical(txn$prev_ctx$input, list(prev = "old"))

  expect_true(unprime_restore_context(ctrl, txn))
  expect_null(txn$prev_ctx)
  expect_identical(ctx$input$asList(), list(prev = "old"))
  expect_identical(as.list(ctx$values), list(kept = 1L))

  # No-op when there is no usable restore context (MockShinySession).
  bare <- list(root = list(restoreContext = NULL))
  expect_false(prime_restore_context(bare, new.env(parent = emptyenv())))
  expect_null(restore_context_of(list(restoreContext = NULL)))
  expect_false(unprime_restore_context(ctrl, txn))
})

test_that("the accelerator runs end to end in a testServer with a real restore context", {
  make_ctx <- getFromNamespace("RestoreContext", "shiny")
  shiny::testServer(sim_server, {
    session$restoreContext <- make_ctx$new()
    client_ready(session)
    p <- snap_restore(sim_snapshot(), session = session)
    expect_true(session$restoreContext$active)
    expect_true(session$restoreContext$input$available("n"))
    txn <- sent_messages(session)[[1]]$message$txn
    client_result(session, txn, list(row("n", "constructed"), row("txt", "applied"), row("ghost", "applied")))
    settle_promise(p)
    # After the transaction, the (empty) previous context is restored.
    expect_false(session$restoreContext$active)
  })
})
