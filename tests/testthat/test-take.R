action_value <- function(n = 0L) {
  structure(as.integer(n), class = c("shinyActionButtonValue", "integer"))
}

unserializable <- function(value, stateDir) {
  structure(list(), serializable = FALSE)
}

test_that("snap_take() captures inputs, applies the drop rules, and sorts ids", {
  server <- function(input, output, session) {
    snap_enable(app = "t", version = "1.2.3")
    shiny::setSerializer("pw", unserializable)
    shiny::setSerializer("upper", function(value, stateDir) toupper(value))
    shiny::setBookmarkExclude("secret_bm")
    snap_exclude("^btn_")
  }
  shiny::testServer(server, {
    session$setInputs(
      zeta = 1L, alpha = "a", pw = "hunter2", upper = "abc", secret_bm = 5,
      btn_one = 1, go = action_value(), .shinysnap_hidden = "x"
    )
    snap <- snap_take(session)
    expect_s3_class(snap, "shinysnap")
    expect_identical(names(snap_inputs(snap)), c("alpha", "upper", "zeta"))
    expect_identical(snap_inputs(snap)$upper, "ABC")
    expect_identical(snap_inputs(snap)$zeta, 1L)
    expect_identical(snap$app, list(name = "t", version = "1.2.3"))
    expect_match(snap$created, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")
    expect_identical(snap$producer, snap_producer())
    expect_identical(snap$bindings, character())
    expect_identical(snap$values, list())
    expect_identical(snap$attachments, list())
    expect_identical(snap_take(session, meta = list(note = "x"))$meta, list(note = "x"))
  })
})

test_that("live_only keeps only inputs the client reports as bound", {
  server <- function(input, output, session) NULL
  shiny::testServer(server, {
    session$setInputs(a = 1L, b = 2L, stale = 3L)
    expect_identical(names(snap_take(session)$inputs), c("a", "b", "stale"))

    session$setInputs(.shinysnap_inventory = list(
      b = "shiny.sliderInput", a = "shiny.numberInput", extra = "x", odd = 1
    ))
    snap <- snap_take(session)
    expect_identical(names(snap$inputs), c("a", "b"))
    expect_identical(snap$bindings, c(a = "shiny.numberInput", b = "shiny.sliderInput"))

    full <- snap_take(session, live_only = FALSE)
    expect_identical(names(full$inputs), c("a", "b", "stale"))
    expect_identical(full$bindings, c(a = "shiny.numberInput", b = "shiny.sliderInput"))

    session$setInputs(.shinysnap_inventory = structure(list(), names = character(0)))
    expect_identical(snap_take(session)$inputs, list())
    expect_identical(snap_take(session)$bindings, character())
  })
})

test_that("snap_enable(live_only = FALSE) changes the default", {
  server <- function(input, output, session) snap_enable(live_only = FALSE)
  shiny::testServer(server, {
    session$setInputs(a = 1L, stale = 3L, .shinysnap_inventory = list(a = "shiny.numberInput"))
    expect_identical(names(snap_take(session)$inputs), c("a", "stale"))
    expect_identical(names(snap_take(session, live_only = TRUE)$inputs), "a")
  })
})

test_that("verbose mode explains what is dropped", {
  server <- function(input, output, session) snap_enable(verbose = TRUE, exclude = "^skip")
  shiny::testServer(server, {
    session$setInputs(a = 1L, skip_me = 2L)
    msgs <- testthat::capture_messages(snap_take(session))
    expect_match(msgs, "has not reported", all = FALSE)
    expect_match(msgs, "not capturing: `skip_me`", fixed = TRUE, all = FALSE)
    session$setInputs(stale = 3L, .shinysnap_inventory = list(a = "shiny.numberInput", skip_me = "x"))
    msgs <- testthat::capture_messages(snap_take(session))
    expect_match(msgs, "not on the page: `stale`", fixed = TRUE, all = FALSE)
    expect_length(msgs, 2L)
  })
})

test_that("include and exclude patterns combine across enable, calls, and helpers", {
  server <- function(input, output, session) snap_enable(exclude = "^x_")
  shiny::testServer(server, {
    session$setInputs(x_1 = 1, y_1 = 2, y_2 = 3, z = 4)
    expect_identical(names(snap_take(session)$inputs), c("y_1", "y_2", "z"))
    expect_identical(names(snap_take(session, include = "^y_")$inputs), c("y_1", "y_2"))
    expect_identical(names(snap_take(session, exclude = "^y_")$inputs), "z")
    expect_identical(snap_exclude("^y_1$", session), c("^x_", "^y_1$"))
    expect_identical(names(snap_take(session)$inputs), c("y_2", "z"))
    expect_identical(snap_include(c("^y", "^z"), session), c("^y", "^z"))
    expect_identical(names(snap_take(session)$inputs), c("y_2", "z"))
    expect_identical(names(snap_take(session, include = "^z")$inputs), c("y_2", "z"))
  })
})

test_that("file inputs become attachments", {
  server <- function(input, output, session) NULL
  shiny::testServer(server, {
    upload <- data.frame(
      name = c("a.csv", "b.csv"), size = c(12L, 34L), type = "text/csv",
      datapath = c("/tmp/a.csv", "/tmp/b.csv"), stringsAsFactors = FALSE
    )
    session$setInputs(upload = upload, n = 1L)
    snap <- snap_take(session)
    expect_identical(names(snap$inputs), "n")
    expect_identical(snap$attachments, list(upload = list(
      name = c("a.csv", "b.csv"), size = c(12L, 34L), type = c("text/csv", "text/csv"),
      datapath = c("/tmp/a.csv", "/tmp/b.csv")
    )))
  })
})

test_that("empty file inputs are skipped when the inventory identifies them", {
  server <- function(input, output, session) NULL
  shiny::testServer(server, {
    upload <- data.frame(name = "a.csv", size = 1L, type = "text/csv", datapath = "/tmp/a.csv")
    session$setInputs(
      empty = NULL, full = upload, n = 1L,
      .shinysnap_inventory = list(
        empty = "shiny.fileInputBinding", full = "shiny.fileInputBinding", n = "shiny.numberInput"
      )
    )
    snap <- snap_take(session)
    expect_identical(names(snap$inputs), "n")
    expect_identical(names(snap$attachments), "full")
    expect_identical(names(snap$bindings), "n")
  })
})

test_that("tracked values and save hooks fill the values section", {
  server <- function(input, output, session) {
    rv_display <- reactiveValues(digits = 3L, scientific = FALSE, hidden = "h")
    other <- reactiveValues(a = 1)
    snap_track(rv_display, fields = c("digits", "scientific", "missing"))
    snap_track(other, name = "renamed")
    off <- snap_on_save(function(state) state$values$n_inputs <- length(state$inputs))
    snap_on_save(function(state) state$values$note <- paste(names(state$inputs), collapse = "+"))
  }
  shiny::testServer(server, {
    session$setInputs(b = 2, a = 1)
    snap <- snap_take(session)
    expect_identical(snap$values, list(
      n_inputs = 2L, note = "a+b", renamed = list(a = 1),
      rv_display = list(digits = 3L, scientific = FALSE)
    ))
    off()
    expect_false("n_inputs" %in% names(snap_take(session)$values))
    expect_identical(snap_take(session, values = FALSE)$values, list())
    rv_display$digits <- 5L
    expect_identical(snap_take(session)$values$rv_display$digits, 5L)
  })
})

test_that("snap_track() derives the name from the variable", {
  server <- function(input, output, session) {
    rv_one <- reactiveValues(x = 1)
    expect_identical(snap_track(rv_one), "rv_one")
    expect_identical(snap_track(rv_one, name = "again"), "again")
    expect_error(snap_track(1), "reactiveValues", class = "shinysnap_error")
    expect_error(snap_track(rv_one, fields = 1), "fields", class = "shinysnap_error")
    expect_error(snap_track(rv_one, name = ""), "name", class = "shinysnap_error")
    expect_error(snap_track(reactiveValues(a = 1)), "Cannot derive", class = "shinysnap_error")
  }
  shiny::testServer(server, {
    expect_identical(names(snap_take(session)$values), c("again", "rv_one"))
  })
})

mod_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    rv <- shiny::reactiveValues(count = 1L)
    snap_track(rv)
    snap_on_save(function(state) state$values$seen <- names(state$inputs))
    NULL
  })
}

test_that("inside a module, ids are full and values are namespaced", {
  shiny::testServer(mod_server, args = list(id = "m"), {
    session$setInputs(n = 5L, txt = "x")
    snap <- snap_take(session)
    expect_identical(names(snap$inputs), c("m-n", "m-txt"))
    expect_identical(snap$values, list(`m-rv` = list(count = 1L), `m-seen` = c("n", "txt")))
    expect_identical(names(snap_take(session, scope = "module")$inputs), c("m-n", "m-txt"))
  })
})

test_that("a root snapshot sees module inputs and values; module scope filters ids", {
  server <- function(input, output, session) {
    snap_enable(app = "root")
    mod_server("m")
    rv_root <- reactiveValues(x = 1)
    snap_track(rv_root)
  }
  shiny::testServer(server, {
    session$setInputs(top = 1L, `m-n` = 2L)
    snap <- snap_take(session)
    expect_identical(names(snap$inputs), c("m-n", "top"))
    expect_named(snap$values, c("m-rv", "m-seen", "rv_root"))
    expect_identical(snap$values[["m-seen"]], "n")
    expect_identical(names(snap_take(session, scope = "module")$inputs), c("m-n", "top"))
    scoped <- snap_take(session$makeScope("m"), scope = "module")
    expect_identical(names(scoped$inputs), "m-n")
    expect_identical(scoped$app$name, "root")
  })
})

test_that("app and version fall back to options and coerce versions", {
  withr::local_options(shinysnap.app = "opt-app", shinysnap.version = "9")
  server <- function(input, output, session) NULL
  shiny::testServer(server, {
    expect_identical(snap_take(session)$app, list(name = "opt-app", version = "9"))
    snap_enable(app = "explicit", version = 2, session = session)
    expect_identical(snap_take(session)$app, list(name = "explicit", version = "2"))
    snap_enable(session = session)
    expect_identical(snap_take(session)$app, list(name = "opt-app", version = "9"))
  })
})

test_that("the controller is created once per session and shared with modules", {
  server <- function(input, output, session) {
    ctrl <- snap_enable(app = "x")
    expect_identical(session$userData$.shinysnap, ctrl)
    expect_identical(snap_controller(session$makeScope("m")), ctrl)
    expect_identical(snap_controller(session), ctrl)
    expect_false(ctrl$dependency_injected)
    expect_false(ctrl$ensure_dependency())
    expect_null(ctrl$inventory())
    expect_false(ctrl$is_ready())
  }
  shiny::testServer(server, {
    session$setInputs(.shinysnap_ready = TRUE, .shinysnap_inventory = list(a = "shiny.textInput"))
    ctrl <- snap_controller(session, create = FALSE)
    expect_true(ctrl$is_ready())
    expect_identical(ctrl$inventory(), c(a = "shiny.textInput"))
  })
})

test_that("server functions error clearly without a session or with bad arguments", {
  expect_error(snap_take(NULL), "server function", class = "shinysnap_no_session")
  expect_error(snap_enable(session = NULL), class = "shinysnap_no_session")
  expect_error(snap_track(1, session = NULL), class = "shinysnap_no_session")
  expect_error(snap_on_save(identity, session = NULL), class = "shinysnap_no_session")
  expect_error(snap_exclude("x", session = NULL), class = "shinysnap_no_session")
  expect_error(snap_include("x", session = NULL), class = "shinysnap_no_session")
  server <- function(input, output, session) {
    expect_error(snap_enable(app = 1), "`app`", class = "shinysnap_error")
    expect_error(snap_enable(exclude = 1), "`exclude`", class = "shinysnap_error")
    expect_error(snap_exclude(NA_character_), "patterns", class = "shinysnap_error")
    expect_error(snap_on_save("not a function"), "`fn`", class = "shinysnap_error")
  }
  shiny::testServer(server, {
    expect_error(snap_take(session, 1), "must be named", class = "shinysnap_error")
    expect_error(snap_take(session, meta = list(1)), "`meta`", class = "shinysnap_error")
    expect_error(snap_take(session, include = 1), "`include`", class = "shinysnap_error")
  })
})

test_that("the callback manager invokes in order and deregisters", {
  cb <- new_callbacks()
  seen <- character()
  off1 <- cb$add(function(x) seen <<- c(seen, paste0("one:", x)))
  off2 <- cb$add(function(x) seen <<- c(seen, paste0("two:", x)))
  cb$invoke("a")
  expect_identical(seen, c("one:a", "two:a"))
  expect_identical(cb$count(), 2L)
  off1()
  cb$invoke("b")
  expect_identical(seen, c("one:a", "two:a", "two:b"))
  off1()
  off2()
  expect_identical(cb$count(), 0L)
})

test_that("helpers classify values and sanitize names", {
  expect_true(is_action_button_value(action_value()))
  expect_false(is_action_button_value(1L))
  expect_true(is_file_input_value(data.frame(name = "a", size = 1, type = "t", datapath = "p")))
  expect_false(is_file_input_value(data.frame(name = "a", size = 1)))
  expect_identical(sanitize_filename("My File.json"), "My_File.json")
  expect_identical(sanitize_filename(" .hidden "), "hidden")
  expect_identical(sanitize_filename("a/b\\c:d*e?"), "a_b_c_d_e")
  expect_identical(sanitize_filename(""), "state")
  expect_identical(sanitize_filename(NA), "state")
  expect_identical(sanitize_filename("___"), "state")
  expect_identical(sanitize_filename(c("first", "second"), fallback = "x"), "first")
})
