test_that("snap_as_bookmark_url() encodes like shiny's URL bookmarking", {
  snap <- new_snapshot(
    inputs = list(
      n = 5L, txt = "a b&c=d/\u00e9", flag = TRUE, rate = 0.1 + 0.2,
      dates = as.Date(c("2024-01-01", "2024-02-01")), m = matrix(1:4, 2),
      none = NULL, sel = c("x", "y"), one = "x"
    ),
    values = list(note = "hi", nested = list(a = 1L, b = c(TRUE, FALSE)))
  )
  enc <- encode_uri_component
  expected <- paste0(
    "_inputs_&",
    "n=5&txt=", enc("\"a b&c=d/\u00e9\""), "&flag=true&rate=0.3",
    "&dates=", enc("[\"2024-01-01\",\"2024-02-01\"]"),
    "&m=", enc("[[1,3],[2,4]]"), "&none=null&sel=", enc("[\"x\",\"y\"]"),
    "&one=", enc("\"x\""),
    "&_values_&note=", enc("\"hi\""), "&nested=", enc("{\"a\":1,\"b\":[true,false]}")
  )
  expect_identical(snap_as_bookmark_url(snap), paste0("?", expected))
  expect_identical(
    snap_as_bookmark_url(snap, base_url = "https://example.org/app/"),
    paste0("https://example.org/app/?", expected)
  )
  expect_identical(snap_as_bookmark_url(new_snapshot(values = list(a = 1L))), "?_values_&a=1")
  expect_identical(snap_as_bookmark_url(new_snapshot(inputs = list(a = 1L))), "?_inputs_&a=1")
  expect_identical(snap_as_bookmark_url(new_snapshot()), "?")
  expect_error(snap_as_bookmark_url(snap, base_url = 1), "`base_url`")

  fake <- list(clientData = list(
    url_protocol = "http:", url_hostname = "localhost", url_port = "3838", url_pathname = "/app/"
  ))
  expect_identical(
    snap_as_bookmark_url(new_snapshot(inputs = list(a = 1L)), session = fake),
    "http://localhost:3838/app/?_inputs_&a=1"
  )
  fake$clientData$url_port <- ""
  expect_identical(
    snap_as_bookmark_url(new_snapshot(inputs = list(a = 1L)), session = fake),
    "http://localhost/app/?_inputs_&a=1"
  )
  expect_error(snap_as_bookmark_url(snap, session = list(clientData = NULL)), "client data")
  expect_error(snap_as_bookmark_url(snap, session = list(clientData = list())), "no URL yet")
  # MockShinySession reports a fixed URL (with a numeric port).
  server <- function(input, output, session) NULL
  shiny::testServer(server, {
    expect_identical(
      snap_as_bookmark_url(new_snapshot(inputs = list(a = 1L)), session = session),
      "http://mocksession:1234/mockpath?_inputs_&a=1"
    )
  })
})

test_that("encode_uri_component() follows JavaScript's rules", {
  corpus <- c(
    "abc", "a b", "a&b=c", "\u00e9", "\u65e5\u672c", "%25", "-_.!~*'()", "\"quoted\"",
    "[1,2]", "{\"a\":1}", "", "a+b", "100%", "#hash?q", "line\nbreak", "tab\t"
  )
  expect_identical(
    encode_uri_component(corpus),
    c(
      "abc", "a%20b", "a%26b%3Dc", "%C3%A9", "%E6%97%A5%E6%9C%AC", "%2525",
      "-_.!~*'()", "%22quoted%22", "%5B1%2C2%5D", "%7B%22a%22%3A1%7D", "",
      "a%2Bb", "100%25", "%23hash%3Fq", "line%0Abreak", "tab%09"
    )
  )
  expect_identical(encode_uri_component(NA_character_), "NA")
  skip_if_not_installed("httpuv")
  expect_identical(encode_uri_component(corpus), httpuv::encodeURIComponent(corpus))
})

test_that("shiny_to_json() matches shiny's serialization settings", {
  expect_identical(shiny_to_json("b"), "\"b\"")
  expect_identical(shiny_to_json(c("a", "b")), "[\"a\",\"b\"]")
  expect_identical(shiny_to_json(0.1 + 0.2), "0.3")
  expect_identical(shiny_to_json(NULL), "null")
  expect_identical(shiny_to_json(NA), "null")
  expect_identical(shiny_to_json(as.Date("2024-01-15")), "\"2024-01-15\"")
  expect_identical(shiny_to_json(matrix(1:4, 2)), "[[1,3],[2,4]]")
  expect_identical(shiny_to_json(list(a = 1L, b = NULL)), "{\"a\":1,\"b\":null}")
  withr::with_options(list(shiny.json.digits = 3), {
    expect_identical(shiny_to_json(pi), "3.142")
  })
})

test_that("snap_as_test_inputs() feeds testServer()", {
  snap <- new_snapshot(inputs = list(n = 5L, txt = "x", none = NULL, d = as.Date("2024-01-01")))
  inputs <- snap_as_test_inputs(snap)
  expect_identical(inputs, snap$inputs)
  expect_identical(snap_as_test_inputs("{\"format\": 1, \"inputs\": {\"k\": 2}}"), list(k = 2L))
  server <- function(input, output, session) NULL
  shiny::testServer(server, {
    session$setInputs(!!!inputs)
    expect_identical(input$n, 5L)
    expect_identical(input$txt, "x")
    expect_identical(input$d, as.Date("2024-01-01"))
    expect_null(input$none)
  })
})

test_that("snap_attachment() returns the upload paths recorded in the session", {
  server <- function(input, output, session) NULL
  shiny::testServer(server, {
    session$setInputs(upload = data.frame(name = "a.csv", size = 1L, type = "t", datapath = "/tmp/a.csv"))
    snap <- snap_take(session)
    expect_identical(snap_attachment(snap, "upload"), "/tmp/a.csv")
    expect_null(snap_attachment(snap, "other"))
  })
})
