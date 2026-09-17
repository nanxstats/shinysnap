test_that("02-dynamic-ui: a snapshot contains only the live branch's inputs", {
  app <- start_app("02-dynamic-ui")
  on.exit(app$stop())

  inv <- app$get_value(input = ".shinysnap_inventory")
  expect_true(all(c("method", "a_n", "a_rate", "a_sub", "a_sub_x", "shared") %in% names(inv)))
  expect_false(any(c("b_k", "b_text", "a_sub_y") %in% names(inv)))
  expect_identical(inv$method, "shiny.selectInput")
  expect_identical(inv$a_n, "shiny.numberInput")
  expect_identical(inv$a_rate, "shiny.sliderInput")

  snap <- export_snapshot(app)
  expect_setequal(names(snap$inputs), c("a_n", "a_rate", "a_sub", "a_sub_x", "method", "shared"))
  expect_identical(snap$inputs$a_n, 10L)
  expect_identical(snap$inputs$a_rate, 0.5)
  expect_identical(snap$inputs$shared, 100L)

  # Second-level dynamic UI: switch the sub-branch.
  app$set_inputs(a_sub = "y")
  inv <- wait_for_inventory(app, inv)
  expect_true("a_sub_y" %in% names(inv))
  expect_false("a_sub_x" %in% names(inv))
  snap <- export_snapshot(app)
  expect_true("a_sub_y" %in% names(snap$inputs))
  expect_false("a_sub_x" %in% names(snap$inputs))

  # First-level: switch the branch.
  app$set_inputs(method = "b")
  inv2 <- wait_for_inventory(app, inv)
  expect_false(any(c("a_n", "a_rate", "a_sub", "a_sub_x", "a_sub_y") %in% names(inv2)))
  expect_true(all(c("b_k", "b_text", "shared", "method") %in% names(inv2)))

  snap2 <- export_snapshot(app)
  expect_setequal(names(snap2$inputs), c("b_k", "b_text", "method", "shared"))
  expect_identical(snap2$inputs$b_k, 3L)
  expect_identical(snap2$inputs$b_text, "beta")
  expect_identical(snap2$inputs$shared, 200L)
  expect_identical(unname(snap2$bindings[c("b_k", "b_text")]), c("shiny.numberInput", "shiny.textInput"))

  # Shiny itself still remembers the stale values; the inventory is what filters them.
  stale <- app$get_values(input = TRUE)$input
  expect_true(all(c("a_n", "a_rate", "a_sub_x") %in% names(stale)))

  path <- app$get_download("save")
  from_file <- snap_read(path)
  expect_identical(from_file$inputs, snap2$inputs)
  expect_identical(from_file$bindings, snap2$bindings)
})

dynamic_snapshot <- function(inputs) {
  new_snapshot(
    inputs = inputs,
    app = list(name = "shinysnap-dynamic-ui", version = "1.0.0"),
    created = "2026-01-01T00:00:00Z"
  )
}

test_that("02-dynamic-ui: with the accelerator, dynamic UI is constructed with the restored values", {
  app <- start_app("02-dynamic-ui")
  on.exit(app$stop())
  json <- snap_serialize(
    dynamic_snapshot(list(method = "b", b_k = 7L, b_text = "zeta", shared = 55L)),
    pretty = FALSE
  )
  report <- restore_json(app, json)
  expect_false(isTRUE(report$timed_out))
  expect_identical(report$status$method, "applied")
  expect_identical(report$status$b_k, "constructed")
  expect_identical(report$status$b_text, "constructed")
  expect_identical(report$status$shared, "constructed")

  vals <- app$get_values(input = TRUE)$input
  expect_identical(vals$method, "b")
  expect_identical(vals$b_k, 7L)
  expect_identical(vals$b_text, "zeta")
  expect_identical(vals$shared, 55L)

  counters <- app$get_value(export = "counters")
  expect_identical(counters$b_k, 1L)
  seen <- app$get_value(export = "restoring_seen")
  expect_true(isTRUE(seen$b_k[[1]]))
  expect_false(isTRUE(app$get_value(export = "is_restoring")))
  expect_length(app$get_value(export = "errors"), 0)
})

test_that("02-dynamic-ui: without the accelerator the restored value still beats the default", {
  app <- start_app("02-dynamic-ui")
  on.exit(app$stop())
  app$set_inputs(use_ctx = FALSE)
  json <- snap_serialize(
    dynamic_snapshot(list(method = "b", b_k = 7L, b_text = "zeta", shared = 55L)),
    pretty = FALSE
  )
  report <- restore_json(app, json)
  expect_false(isTRUE(report$timed_out))
  expect_identical(report$status$method, "applied")
  expect_identical(report$status$b_k, "applied")
  expect_identical(report$status$b_text, "applied")
  expect_identical(report$status$shared, "reapplied")

  vals <- app$get_values(input = TRUE)$input
  expect_identical(vals$b_k, 7L)
  expect_identical(vals$b_text, "zeta")
  expect_identical(vals$shared, 55L)
  counters <- app$get_value(export = "counters")
  expect_identical(counters$b_k, 2L)
  expect_false(isTRUE(app$get_value(export = "is_restoring")))
})

test_that("02-dynamic-ui: an input that never appears is reported missing and the promise resolves", {
  app <- start_app("02-dynamic-ui")
  on.exit(app$stop())
  app$set_inputs(timeout = 3)
  json <- snap_serialize(
    dynamic_snapshot(list(method = "a", a_n = 42L, ghost = "boo")),
    pretty = FALSE
  )
  # `ghost` never appears; the transaction still settles (on the quiet
  # period, ahead of the timeout) and reports it missing.
  report <- restore_json(app, json)
  expect_identical(report$status$ghost, "missing")
  expect_identical(report$status$a_n, "applied")
  expect_identical(app$get_values(input = TRUE)$input$a_n, 42L)
  expect_length(app$get_value(export = "errors"), 0)
  expect_false(isTRUE(app$get_value(export = "is_restoring")))
})

test_that("02-dynamic-ui: a second restore cancels the first", {
  app <- start_app("02-dynamic-ui")
  on.exit(app$stop())
  app$set_inputs(timeout = 8)
  stuck <- snap_serialize(dynamic_snapshot(list(method = "a", ghost = "boo")), pretty = FALSE)
  good <- snap_serialize(dynamic_snapshot(list(method = "b", b_k = 9L)), pretty = FALSE)
  before <- app$get_value(export = "reports")
  app$set_inputs(json = stuck)
  app$click("restore_text")
  app$set_inputs(json = good)
  app$click("restore_text")
  reports <- wait_for_reports(app, before)
  expect_length(reports, length(before) + 1L)
  report <- last_report(reports)
  expect_false(isTRUE(report$timed_out))
  expect_identical(report$status$b_k, "constructed")
  expect_null(report$status$ghost)
  expect_identical(app$get_value(export = "cancelled"), 1L)
  expect_identical(app$get_values(input = TRUE)$input$b_k, 9L)
})

test_that("02-dynamic-ui: a saved file restores through the upload control, two levels deep", {
  app <- start_app("02-dynamic-ui")
  on.exit(app$stop())
  snap <- export_snapshot(app)
  snap$inputs$a_n <- 77L
  snap$inputs$a_rate <- 0.25
  snap$inputs$a_sub <- "y"
  snap$inputs$a_sub_x <- NULL
  snap$inputs$a_sub_y <- 5L
  snap$inputs$shared <- 123L
  report <- restore_upload(app, "restore", snap)
  expect_false(isTRUE(report$timed_out))
  expect_all_restored(report)
  expect_identical(report$status$a_sub, "applied")
  expect_identical(report$status$a_sub_y, "constructed")
  expect_null(report$status$a_sub_x)
  vals <- app$get_values(input = TRUE)$input
  expect_identical(vals$a_n, 77L)
  expect_identical(vals$a_rate, 0.25)
  expect_identical(vals$a_sub, "y")
  expect_identical(vals$a_sub_y, 5L)
  expect_identical(vals$shared, 123L)
  after <- export_snapshot(app)
  expect_false("a_sub_x" %in% names(after$inputs))
})
