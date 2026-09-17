test_that("new_snapshot() normalizes its fields", {
  snap <- new_snapshot()
  expect_s3_class(snap, "shinysnap")
  expect_identical(
    names(snap),
    c("format", "app", "created", "producer", "inputs", "values", "bindings", "attachments", "meta")
  )
  expect_identical(snap$format, 1L)
  expect_identical(snap$app, list(name = NULL, version = NULL))
  expect_null(snap$created)
  expect_null(snap$producer)
  expect_identical(snap$inputs, list())
  expect_identical(snap$values, list())
  expect_identical(snap$bindings, character())
  expect_identical(snap$attachments, list())
  expect_identical(snap$meta, list())

  expect_identical(new_snapshot(inputs = NULL), snap)
  expect_identical(new_snapshot(inputs = structure(list(), names = character(0))), snap)
  expect_identical(new_snapshot(bindings = structure(character(0), names = character(0))), snap)
  expect_identical(new_snapshot(app = list(name = "x"))$app, list(name = "x", version = NULL))
  expect_identical(new_snapshot(format = 1)$format, 1L)
})

test_that("validate_snapshot() rejects malformed objects", {
  expect_error(validate_snapshot(list()), class = "shinysnap_invalid")
  expect_error(validate_snapshot(structure(list(format = 1L), class = "shinysnap")), "missing field", class = "shinysnap_invalid")
  expect_error(new_snapshot(inputs = list(1, 2)), "unique, non-empty names", class = "shinysnap_invalid")
  expect_error(new_snapshot(inputs = list(a = 1, a = 2)), "unique, non-empty names", class = "shinysnap_invalid")
  expect_error(new_snapshot(inputs = 1:3), "must be a list", class = "shinysnap_invalid")
  expect_error(new_snapshot(values = list(a = 1, 2)), class = "shinysnap_invalid")
  expect_error(new_snapshot(meta = list("x")), class = "shinysnap_invalid")
  expect_error(new_snapshot(bindings = "shiny.textInput"), "named character", class = "shinysnap_invalid")
  expect_error(new_snapshot(bindings = c(a = NA_character_)), class = "shinysnap_invalid")
  expect_error(new_snapshot(bindings = list(a = "x")), "character vector", class = "shinysnap_invalid")
  expect_error(new_snapshot(app = list(name = 1)), "app\\$name", class = "shinysnap_invalid")
  expect_error(new_snapshot(app = list(version = c("1", "2"))), "app\\$version", class = "shinysnap_invalid")
  expect_error(new_snapshot(created = 1), "created", class = "shinysnap_invalid")
  expect_error(new_snapshot(producer = "x"), "producer", class = "shinysnap_invalid")
  expect_identical(new_snapshot(format = "1")$format, 1L)
  bad <- new_snapshot()
  bad$format <- "1"
  expect_error(validate_snapshot(bad), "format", class = "shinysnap_invalid")
  expect_error(new_snapshot(format = NA), "format", class = "shinysnap_invalid")
})

test_that("as_snapshot() coerces lists and JSON text", {
  snap <- as_snapshot(list(inputs = list(n = 1L)))
  expect_identical(snap, new_snapshot(inputs = list(n = 1L)))
  expect_identical(as_snapshot(snap), snap)
  expect_identical(as_snapshot(list()), new_snapshot())
  expect_identical(as_snapshot("{\"format\": 1, \"inputs\": {\"n\": 1}}"), snap)
  expect_identical(as_snapshot("  \n{\"format\": 1, \"inputs\": {\"n\": 1}}"), snap)
  expect_error(as_snapshot(list(inputs = list(), bogus = 1)), "bogus", class = "shinysnap_invalid")
  expect_error(as_snapshot(42), class = "shinysnap_invalid")
  expect_error(as_snapshot("state.json"), class = "shinysnap_invalid")
  expect_error(as_snapshot(list(1, 2)), class = "shinysnap_invalid")
})

test_that("print() gives a compact summary", {
  snap <- new_snapshot(
    inputs = list(n = 1L, rate = 0.5),
    values = list(rv_display = list(digits = 3L)),
    app = list(name = "myapp", version = "2.4.1"),
    created = "2026-09-16T18:22:03Z"
  )
  lines <- format(snap)
  expect_identical(lines[1], "<shinysnap>")
  expect_match(lines[2], "myapp (version 2.4.1)", fixed = TRUE)
  expect_match(lines[3], "2026-09-16T18:22:03Z", fixed = TRUE)
  expect_match(lines[4], "inputs:      2 (n, rate)", fixed = TRUE)
  expect_match(lines[5], "values:      1 (rv_display)", fixed = TRUE)
  expect_match(lines[6], "attachments: 0", fixed = TRUE)
  expect_length(lines, 6)
  expect_output(out <- print(snap), "<shinysnap>")
  expect_identical(out, snap)

  bare <- new_snapshot()
  lines <- format(bare)
  expect_match(lines[2], "<none>", fixed = TRUE)
  expect_match(lines[3], "<unset>", fixed = TRUE)
  expect_match(lines[4], "inputs:      0", fixed = TRUE)

  many <- new_snapshot(
    inputs = setNames(as.list(seq_len(12)), paste0("x", seq_len(12))),
    meta = list(note = "n"),
    app = list(name = "app")
  )
  lines <- format(many)
  expect_match(lines[2], "app:         app$")
  expect_match(lines[4], "12 (x1, x2, x3, x4, x5, x6, x7, x8, ...)", fixed = TRUE)
  expect_match(lines[7], "meta:        1 (note)", fixed = TRUE)
})

test_that("accessors and as.list() return the underlying parts", {
  snap <- new_snapshot(
    inputs = list(n = 1L),
    values = list(rv = list(a = 1)),
    meta = list(note = "x")
  )
  expect_identical(snap_inputs(snap), list(n = 1L))
  expect_identical(snap_values(snap), list(rv = list(a = 1)))
  expect_identical(snap_meta(snap), list(note = "x"))
  expect_identical(snap_inputs(list(inputs = list(n = 2L))), list(n = 2L))
  lst <- as.list(snap)
  expect_false(inherits(lst, "shinysnap"))
  expect_identical(lst$inputs, list(n = 1L))
  expect_identical(names(lst), names(snap))
})

test_that("snap_producer() reports versions as strings", {
  p <- snap_producer()
  expect_type(p, "list")
  expect_true(all(c("shinysnap", "r") %in% names(p)))
  expect_true(all(vapply(p, is_string, logical(1))))
  expect_identical(p$shinysnap, as.character(utils::packageVersion("shinysnap")))
})

test_that("validate_snapshot() checks the app field", {
  bad <- new_snapshot()
  bad$app <- "x"
  expect_error(validate_snapshot(bad), "`app` must be a list", class = "shinysnap_invalid")
})

test_that("snap_diff() lists added, removed, and changed entries", {
  a <- new_snapshot(
    inputs = list(n = 1L, x = "old", same = TRUE, gone = 1),
    values = list(prefs = list(digits = 3L, sci = FALSE), scalar = 1, other = list(k = 1)),
    meta = list(note = "a")
  )
  b <- new_snapshot(
    inputs = list(n = 1L, x = "new", same = TRUE, fresh = 2),
    values = list(prefs = list(digits = 4L, sci = FALSE, extra = "e"), scalar = 2, other = list(k = 1)),
    meta = list(note = "a", tag = "t")
  )
  d <- snap_diff(a, b)
  expect_s3_class(d, c("shinysnap_diff", "data.frame"))
  expect_identical(names(d), c("id", "section", "status", "old", "new"))
  expect_identical(d$id, c("x", "gone", "fresh", "prefs$digits", "scalar", "prefs$extra", "tag"))
  expect_identical(d$section, c("inputs", "inputs", "inputs", "values", "values", "values", "meta"))
  expect_identical(d$status, c("changed", "removed", "added", "changed", "changed", "added", "added"))
  expect_identical(d$old, list("old", 1, NULL, 3L, 1, NULL, NULL))
  expect_identical(d$new, list("new", NULL, 2, 4L, 2, "e", "t"))
  expect_output(print(d), "7 difference\\(s\\)")
  expect_output(print(d), "prefs\\$digits")

  none <- snap_diff(a, a)
  expect_identical(nrow(none), 0L)
  expect_identical(names(none), c("id", "section", "status", "old", "new"))
  expect_output(print(none), "no differences")

  # NULL-valued inputs are compared too, and text or files are accepted.
  c1 <- "{\"format\": 1, \"inputs\": {\"sel\": null}}"
  c2 <- "{\"format\": 1, \"inputs\": {\"sel\": \"a\"}}"
  d2 <- snap_diff(c1, c2)
  expect_identical(d2$status, "changed")
  expect_identical(d2$old, list(NULL))
  expect_identical(snap_diff(c1, c1)$status, character())
})
