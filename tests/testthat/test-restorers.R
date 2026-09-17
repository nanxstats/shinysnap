fake_ctrl <- function(restorers = list()) list(restorers = restorers)

payload <- function(binding, value, id = "x") {
  fn <- resolve_restorer(id, binding, fake_ctrl())
  fn(id, value, binding, NULL)
}

# Identify a builtin restorer by what it does with a length-2 character
# value: a list-valued payload is a selection restorer, a scalar is radio,
# and a length-2 atomic is the default. This avoids comparing function
# objects, which covr instrumentation would break.
restorer_kind <- function(fn) {
  v <- fn("id", c("a", "b"), "b", NULL)$value
  if (is.list(v)) "selection" else if (length(v) == 1L) "radio" else "default"
}

expect_payload <- function(binding, value, message, expect = "value") {
  p <- payload(binding, value)
  out <- p
  attr(out, "expect") <- NULL
  expect_identical(out, message, label = binding)
  rec <- build_record("x", binding, p)
  if (identical(expect, "value")) {
    expect_identical(rec$expect, message$value, label = paste(binding, "expect"))
  } else {
    expect_identical(rec$expect, expect, label = paste(binding, "expect"))
  }
  invisible(rec)
}

test_that("the default restorer sends {value} with attributes stripped", {
  expect_payload("", 5L, list(value = 5L))
  expect_payload("shiny.textInput", "hi", list(value = "hi"))
  expect_payload("shiny.numberInput", c(a = 1.5), list(value = 1.5))
  expect_payload("shiny.checkboxInput", TRUE, list(value = TRUE))
  expect_payload("shiny.bootstrapTabInput", "Second", list(value = "Second"))
  expect_payload("unknown.binding", list(a = 1), list(value = list(a = 1)))
  expect_identical(payload("shiny.textInput", NULL), list(value = NULL))
})

test_that("selection inputs clear with [] and send arrays otherwise", {
  for (b in c("shiny.checkboxGroupInput", "shiny.selectInput")) {
    expect_payload(b, NULL, list(value = list()))
    expect_payload(b, character(0), list(value = list()))
    expect_payload(b, "a", list(value = list("a")))
    expect_payload(b, c("a", "c"), list(value = list("a", "c")))
    expect_payload(b, factor("f"), list(value = list("f")))
  }
})

test_that("radio buttons receive a scalar, or [] to clear", {
  expect_payload("shiny.radioInput", NULL, list(value = list()))
  expect_payload("shiny.radioInput", character(0), list(value = list()))
  expect_payload("shiny.radioInput", "z", list(value = "z"))
  expect_payload("shiny.radioInput", c("z", "y"), list(value = "z"))
  expect_payload("shiny.radioInput", factor("f"), list(value = "f"))
})

test_that("date inputs send ISO strings and NA clears", {
  expect_payload("shiny.dateInput", as.Date("2024-01-15"), list(value = "2024-01-15"))
  expect_payload("shiny.dateInput", "2024-01-15", list(value = "2024-01-15"))
  expect_payload("shiny.dateInput", as.Date(NA), list(value = NULL))
  expect_payload("shiny.dateInput", NULL, list(value = NULL))
  expect_payload("shiny.dateInput", "not a date", list(value = NULL))
})

test_that("date range inputs send {start, end} and expect the string pair", {
  expect_payload(
    "shiny.dateRangeInput", as.Date(c("2024-01-01", "2024-03-01")),
    list(value = list(start = "2024-01-01", end = "2024-03-01")),
    expect = list("2024-01-01", "2024-03-01")
  )
  expect_payload(
    "shiny.dateRangeInput", as.Date(c("2024-01-01", NA)),
    list(value = list(start = "2024-01-01")),
    expect = list("2024-01-01", NA_character_)
  )
  expect_payload(
    "shiny.dateRangeInput", as.Date(c(NA, NA)),
    list(value = structure(list(), names = character(0))),
    expect = list(NA_character_, NA_character_)
  )
  expect_null(payload("shiny.dateRangeInput", NULL))
})

test_that("sliders send numbers, or milliseconds for dates and date-times", {
  expect_payload("shiny.sliderInput", 25L, list(value = 25L))
  expect_payload("shiny.sliderInput", c(20, 80), list(value = c(20, 80)))
  d <- as.Date(c("2024-01-01", "2024-01-02"))
  expect_payload(
    "shiny.sliderInput", d,
    list(value = c(1704067200000, 1704153600000)),
    expect = list("2024-01-01", "2024-01-02")
  )
  t <- as.POSIXct("2024-01-01 10:00:00", tz = "UTC")
  expect_payload(
    "shiny.sliderInput", t,
    list(value = 1704103200000),
    expect = list(1704103200)
  )
  expect_null(payload("shiny.sliderInput", NULL))
})

test_that("bslib components use method messages", {
  expect_payload("bslib.accordion", c("A", "B"), list(method = "set", values = list("A", "B")), expect = NULL)
  expect_payload("bslib.accordion", NULL, list(method = "set", values = list()), expect = NULL)
  expect_payload("bslib.sidebar", TRUE, list(method = "open"), expect = NULL)
  expect_payload("bslib.sidebar", FALSE, list(method = "close"), expect = NULL)
  expect_payload("bslib.sidebar", NULL, list(method = "close"), expect = NULL)
  rec <- build_record("x", "bslib.sidebar", payload("bslib.sidebar", TRUE))
  expect_false("expect" %in% names(rec))
})

test_that("matrix inputs send data plus row and column names", {
  m <- matrix(c(1, NA, 3, 4), 2, dimnames = list(c("r1", "r2"), NULL))
  data <- m
  dimnames(data) <- NULL
  rec <- expect_payload(
    "shinyMatrix.matrixNumeric", m,
    list(value = list(data = data, rownames = c("r1", "r2"), colnames = NULL)),
    expect = list(data = data, rownames = list("r1", "r2"), colnames = list())
  )
  expect_identical(rec$message$value$data, data)
  ch <- matrix(c("a", "b"), 1)
  expect_payload(
    "shinyMatrix.matrixCharacter", ch,
    list(value = list(data = ch, rownames = NULL, colnames = NULL)),
    expect = list(data = ch, rownames = list(), colnames = list())
  )
  expect_payload(
    "shinyMatrix.matrixNumeric", 1:2,
    list(value = list(data = matrix(1:2, 2), rownames = NULL, colnames = NULL)),
    expect = list(data = matrix(1:2, 2), rownames = list(), colnames = list())
  )
  expect_null(payload("shinyMatrix.matrixNumeric", NULL))
})

test_that("passwords, buttons, and file inputs are skipped", {
  for (b in c(
    "shiny.passwordInput", "shiny.actionButtonInput", "shiny.fileInputBinding",
    "bslib.task-button", "bslib.card"
  )) {
    expect_null(payload(b, "anything"), label = b)
  }
})

test_that("build_record() carries expect only when known", {
  rec <- build_record("n", "shiny.numberInput", list(value = 5))
  expect_identical(rec, list(id = "n", binding = "shiny.numberInput", message = list(value = 5), expect = 5))
  rec <- build_record("n", "b", list(value = NULL))
  expect_true("expect" %in% names(rec))
  expect_null(rec$expect)
  rec <- build_record("n", "b", list(method = "open"))
  expect_false("expect" %in% names(rec))
  rec <- build_record("n", "b", with_expect(list(value = 1), "one"))
  expect_identical(rec$expect, "one")
  expect_null(attr(rec$message, "expect"))
})

test_that("restorers resolve by session id, session binding, global, built-in, default", {
  on.exit(snap_restorer("test.binding", NULL), add = TRUE)
  on.exit(snap_restorer("myid", NULL), add = TRUE)
  ctrl <- fake_ctrl()
  expect_identical(restorer_kind(resolve_restorer("myid", "test.binding", ctrl)), "default")
  expect_identical(restorer_kind(resolve_restorer("myid", "shiny.radioInput", ctrl)), "radio")

  g_binding <- function(id, value, binding, session) list(g = "binding")
  g_id <- function(id, value, binding, session) list(g = "id")
  snap_restorer("test.binding", g_binding)
  expect_identical(resolve_restorer("myid", "test.binding", ctrl), g_binding)
  snap_restorer("myid", g_id)
  expect_identical(resolve_restorer("myid", "test.binding", ctrl), g_id)
  expect_true(all(c("test.binding", "myid") %in% snap_restorers(session = NULL)$name))
  expect_identical(unique(snap_restorers(session = NULL)$scope[snap_restorers(session = NULL)$name == "myid"]), "global")

  s_binding <- function(id, value, binding, session) list(s = "binding")
  s_id <- function(id, value, binding, session) list(s = "id")
  ctrl <- fake_ctrl(list(test.binding = s_binding))
  expect_identical(resolve_restorer("myid", "test.binding", ctrl), s_binding)
  ctrl <- fake_ctrl(list(test.binding = s_binding, myid = s_id))
  expect_identical(resolve_restorer("myid", "test.binding", ctrl), s_id)

  # A global restorer for a binding overrides the built-in one.
  snap_restorer("shiny.radioInput", g_binding)
  on.exit(snap_restorer("shiny.radioInput", NULL), add = TRUE)
  expect_identical(resolve_restorer("r", "shiny.radioInput", fake_ctrl()), g_binding)
  snap_restorer("shiny.radioInput", NULL)
  expect_identical(restorer_kind(resolve_restorer("r", "shiny.radioInput", fake_ctrl())), "radio")

  expect_error(snap_restorer("", g_id), "`x`", class = "shinysnap_error")
  expect_error(snap_restorer("x", "not a function"), "`fn`", class = "shinysnap_error")
  expect_silent(snap_restorer("never-registered", NULL))
})

test_that("snap_restorers() lists built-ins and session restorers", {
  tbl <- snap_restorers(session = NULL)
  expect_true(all(c("name", "scope") %in% names(tbl)))
  expect_true(all(names(builtin_restorers) %in% tbl$name[tbl$scope == "builtin"]))
  server <- function(input, output, session) {
    snap_restorer("special_id", function(id, value, binding, session) list(value = "!"), session = session)
  }
  shiny::testServer(server, {
    tbl <- snap_restorers(session)
    expect_true("special_id" %in% tbl$name[tbl$scope == "session"])
    ctrl <- snap_controller(session)
    expect_identical(resolve_restorer("special_id", "", ctrl)("special_id", 1, "", session), list(value = "!"))
  })
})
