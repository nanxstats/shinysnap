example_json <- '{
  "format": 1,
  "app": {"name": "myapp", "version": "2.4.1"},
  "created": "2026-09-16T18:22:03Z",
  "producer": {"shinysnap": "0.1.0", "shiny": "1.14.0", "r": "4.5.1"},
  "inputs": {
    "dates": {"$type": "Date", "value": ["2024-01-01", "2024-03-01"]},
    "M": {"$type": "array", "storage": "integer", "dim": [2, 3],
          "dimnames": [["a", "b"], null], "value": [1, 2, 3, 4, 5, 6]},
    "method": "b",
    "n": 100,
    "rate": 0.025,
    "threshold": {"$type": "double", "value": [0.5, "inf"]},
    "weights": [0.5, 0.75]
  },
  "values": {
    "rv_display": {"digits": 3, "scientific": false}
  },
  "bindings": {
    "dates": "shiny.dateRangeInput", "M": "shinyMatrix.matrixInput",
    "method": "shiny.selectInput", "n": "shiny.sliderInput", "rate": "shiny.numberInput",
    "threshold": "shiny.numberInput", "weights": "shiny.sliderInput"
  },
  "meta": {}
}'

full_snapshot <- function() {
  new_snapshot(
    inputs = list(
      M = matrix(1:6, 2, dimnames = list(c("a", "b"), NULL)),
      dates = as.Date(c("2024-01-01", "2024-03-01")),
      method = "b",
      n = 100L,
      rate = 0.025,
      selected = NULL,
      threshold = c(0.5, Inf),
      weights = c(0.5, 0.75)
    ),
    values = list(rv_display = list(digits = 3L, scientific = FALSE)),
    bindings = c(
      M = "shinyMatrix.matrixInput", dates = "shiny.dateRangeInput",
      method = "shiny.selectInput", n = "shiny.sliderInput",
      rate = "shiny.numberInput", threshold = "shiny.numberInput",
      weights = "shiny.sliderInput"
    ),
    meta = list(note = "baseline", tags = c("a", "b")),
    app = list(name = "myapp", version = "2.4.1"),
    created = "2026-09-16T18:22:03Z",
    producer = snap_producer()
  )
}

test_that("the example file from the format description decodes as expected", {
  snap <- snap_unserialize(example_json)
  expect_s3_class(snap, "shinysnap")
  expect_identical(snap$format, 1L)
  expect_identical(snap$app, list(name = "myapp", version = "2.4.1"))
  expect_identical(snap$created, "2026-09-16T18:22:03Z")
  expect_identical(snap$producer, list(shinysnap = "0.1.0", shiny = "1.14.0", r = "4.5.1"))
  inputs <- snap_inputs(snap)
  expect_identical(names(inputs), c("dates", "M", "method", "n", "rate", "threshold", "weights"))
  expect_identical(inputs$dates, as.Date(c("2024-01-01", "2024-03-01")))
  expect_identical(inputs$M, matrix(1:6, 2, dimnames = list(c("a", "b"), NULL)))
  expect_identical(inputs$method, "b")
  expect_identical(inputs$n, 100L)
  expect_identical(inputs$rate, 0.025)
  expect_identical(inputs$threshold, c(0.5, Inf))
  expect_identical(inputs$weights, c(0.5, 0.75))
  expect_identical(snap_values(snap), list(rv_display = list(digits = 3L, scientific = FALSE)))
  expect_identical(snap$bindings[["M"]], "shinyMatrix.matrixInput")
  expect_length(snap$bindings, 7)
  expect_identical(snap_meta(snap), list())
  expect_identical(snap$attachments, list())
})

test_that("serialize/unserialize round-trips a snapshot exactly", {
  snap <- full_snapshot()
  txt <- snap_serialize(snap)
  back <- snap_unserialize(txt)
  expect_identical(back, snap)
  expect_true(identical(back, snap))
  expect_identical(snap_unserialize(snap_serialize(snap, pretty = FALSE)), snap)
})

test_that("the writer stamps producer and fills created when missing", {
  snap <- new_snapshot(inputs = list(n = 1L))
  txt <- snap_serialize(snap)
  back <- snap_unserialize(txt)
  expect_identical(back$producer, snap_producer())
  expect_match(back$created, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
  back["producer"] <- list(NULL)
  back["created"] <- list(NULL)
  expect_identical(back, snap)

  stale <- full_snapshot()
  stale$producer <- list(shinysnap = "0.0.1")
  expect_identical(snap_unserialize(snap_serialize(stale))$producer, snap_producer())
})

test_that("the JSON layout is canonical", {
  txt <- snap_serialize(full_snapshot())
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  expect_identical(lines[1], "{")
  expect_identical(lines[2], "  \"format\": 1,")
  expect_identical(lines[3], "  \"app\": {\"name\": \"myapp\", \"version\": \"2.4.1\"},")
  expect_identical(lines[4], "  \"created\": \"2026-09-16T18:22:03Z\",")
  expect_match(lines[5], "^  \"producer\": \\{\"shinysnap\": ")
  expect_identical(lines[6], "  \"inputs\": {")
  keys <- sub("^  \"([a-z]+)\":.*$", "\\1", grep("^  \"", lines, value = TRUE))
  expect_identical(keys, c("format", "app", "created", "producer", "inputs", "values", "bindings", "meta"))
  expect_identical(lines[length(lines)], "}")
  expect_match(txt, "\n$")
  expect_match(txt, "    \"n\": 100,", fixed = TRUE)
  expect_match(txt, "    \"rate\": 0.025,", fixed = TRUE)
  expect_match(txt, "    \"selected\": null,", fixed = TRUE)
  expect_match(txt, "    \"threshold\": {\"$type\": \"double\", \"value\": [0.5, \"inf\"]},", fixed = TRUE)
  expect_match(txt, "    \"weights\": [0.5, 0.75]", fixed = TRUE)
  expect_false(grepl("attachments", txt, fixed = TRUE))
  expect_identical(snap_serialize(full_snapshot()), txt)
})

test_that("compact output is a single line without spaces", {
  txt <- snap_serialize(full_snapshot(), pretty = FALSE)
  expect_false(grepl("\n", txt, fixed = TRUE))
  expect_false(grepl(": ", txt, fixed = TRUE))
  expect_true(startsWith(txt, "{\"format\":1,\"app\":{\"name\":\"myapp\""))
})

test_that("acceptance: doubles and integers are distinguishable and exact", {
  snap <- new_snapshot(inputs = list(sum = 0.1 + 0.2, i = 1L, d = 1))
  txt <- snap_serialize(snap)
  expect_match(txt, "\"sum\": 0.30000000000000004", fixed = TRUE)
  expect_match(txt, "\"i\": 1,", fixed = TRUE)
  expect_match(txt, "\"d\": 1.0", fixed = TRUE)
  back <- snap_inputs(snap_unserialize(txt))
  expect_identical(back$sum, 0.1 + 0.2)
  expect_identical(back$i, 1L)
  expect_identical(back$d, 1)
})

test_that("acceptance: hand-edited values read back", {
  txt <- snap_serialize(full_snapshot())
  edited <- sub("\"n\": 100,", "\"n\": 250,", txt, fixed = TRUE)
  edited <- sub("\"method\": \"b\",", "\"method\": \"c\",", edited, fixed = TRUE)
  edited <- sub("\"weights\": [0.5, 0.75]", "\"weights\": [0.25, 0.5, 0.25]", edited, fixed = TRUE)
  back <- snap_inputs(snap_unserialize(edited))
  expect_identical(back$n, 250L)
  expect_identical(back$method, "c")
  expect_identical(back$weights, c(0.25, 0.5, 0.25))
})

test_that("empty and minimal files decode to empty sections", {
  snap <- snap_unserialize("{\"format\": 1}")
  expect_identical(snap$format, 1L)
  expect_identical(snap$app, list(name = NULL, version = NULL))
  expect_null(snap$created)
  expect_null(snap$producer)
  expect_identical(snap$inputs, list())
  expect_identical(snap$values, list())
  expect_identical(snap$bindings, character())
  expect_identical(snap$attachments, list())
  expect_identical(snap$meta, list())
  expect_identical(snap_unserialize("{\"format\": 1, \"inputs\": {}, \"bindings\": {}, \"app\": {}}"), snap)
  expect_identical(snap_unserialize(snap_serialize(snap))$inputs, list())
  expect_identical(snap_unserialize("{\"format\": 1.0}")$format, 1L)
})

test_that("multi-line input is accepted", {
  lines <- strsplit(example_json, "\n", fixed = TRUE)[[1]]
  expect_identical(snap_unserialize(lines), snap_unserialize(example_json))
})

test_that("top-level problems produce clear errors", {
  expect_error(snap_unserialize("[]"), "JSON object", class = "shinysnap_format_error")
  expect_error(snap_unserialize("\"x\""), "JSON object", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"inputs\": {}}"), "\"format\" field is missing", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": \"1\"}"), "integer", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1.5}"), "integer", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 2}"), "upgrade shinysnap", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 0}"), "Unsupported format", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1"), "Invalid JSON", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1, \"inputs\": [1]}"), "\"inputs\" field must be an object", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1, \"inputs\": {\"a\": 1, \"a\": 2}}"), "duplicated keys", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1, \"app\": {\"name\": 1}}"), "app\\$name", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1, \"created\": 1}"), "\"created\"", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1, \"bindings\": {\"n\": 1}}"), "\"bindings\"", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1, \"bindings\": [\"a\"]}"), "\"bindings\"", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1, \"producer\": {\"r\": null}}"), "\"producer\"", class = "shinysnap_format_error")
  expect_error(snap_unserialize(42), class = "shinysnap_format_error")
})

test_that("errors inside sections name the path", {
  err <- expect_error(
    snap_unserialize("{\"format\": 1, \"inputs\": {\"x\": {\"$type\": \"wat\"}}}"),
    class = "shinysnap_unknown_type"
  )
  expect_identical(err$path, "inputs$x")
  err <- expect_error(
    snap_unserialize("{\"format\": 1, \"values\": {\"rv\": {\"k\": [1, \"a\"]}}}"),
    class = "shinysnap_format_error"
  )
  expect_identical(err$path, "values$rv$k")
  err <- expect_error(
    snap_serialize(new_snapshot(values = list(rv = list(f = mean)))),
    class = "shinysnap_unsupported_value"
  )
  expect_identical(err$path, "values$rv$f")
})

test_that("embedded R objects are gated behind trust = TRUE", {
  snap <- new_snapshot(
    inputs = list(n = 1L),
    values = list(fit = structure(list(coef = 1), class = "myfit"), other = new.env())
  )
  expect_error(snap_serialize(snap), class = "shinysnap_unsupported_value")
  txt <- snap_serialize(snap, unsupported = "rds")
  expect_message(snap_serialize(snap, unsupported = "rds", verbose = TRUE), "opaque")

  w <- expect_warning(back <- snap_unserialize(txt), class = "shinysnap_untrusted")
  expect_match(conditionMessage(w), "values$fit", fixed = TRUE)
  expect_match(conditionMessage(w), "values$other", fixed = TRUE)
  expect_identical(w$ids, c("values$fit", "values$other"))
  expect_identical(back$values, list(fit = NULL, other = NULL))
  expect_identical(back$inputs$n, 1L)

  trusted <- snap_unserialize(txt, trust = TRUE)
  expect_identical(trusted$values$fit, structure(list(coef = 1), class = "myfit"))
  expect_true(is.environment(trusted$values$other))
})

test_that("verbose serialization reports notes", {
  tb <- structure(list(x = 1:2), class = c("tbl_df", "tbl", "data.frame"), row.names = c(NA_integer_, -2L))
  snap <- new_snapshot(values = list(tb = tb))
  expect_message(snap_serialize(snap, verbose = TRUE), "tibble")
  expect_silent(snap_serialize(snap))
})

test_that("unknown types can be kept for inspection", {
  txt <- "{\"format\": 1, \"inputs\": {\"x\": {\"$type\": \"wat\", \"value\": 1}}}"
  snap <- snap_unserialize(txt, unknown_types = "keep")
  expect_identical(snap$inputs$x[["$type"]], "wat")
})

test_that("snap_serialize accepts a list or JSON text", {
  expect_identical(
    snap_unserialize(snap_serialize(list(inputs = list(n = 1L), created = "2026-01-01T00:00:00Z"))),
    new_snapshot(inputs = list(n = 1L), created = "2026-01-01T00:00:00Z", producer = snap_producer())
  )
  expect_identical(
    snap_inputs(snap_serialize("{\"format\": 1, \"inputs\": {\"n\": 5}}")),
    list(n = 5L)
  )
})

test_that("attachments are written only when present", {
  snap <- new_snapshot(
    inputs = list(n = 1L),
    attachments = list(upload = list(name = "data.csv", size = 1234L, type = "text/csv")),
    created = "2026-09-16T18:22:03Z",
    producer = snap_producer()
  )
  txt <- snap_serialize(snap)
  expect_match(txt, "\"attachments\": {", fixed = TRUE)
  expect_identical(snap_unserialize(txt), snap)
})

test_that("a malformed app field is rejected", {
  expect_error(snap_unserialize("{\"format\": 1, \"app\": [1]}"), "\"app\"", class = "shinysnap_format_error")
})
