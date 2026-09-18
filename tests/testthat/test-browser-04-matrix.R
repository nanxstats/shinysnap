test_that("04-matrix: matrices, dates, selections, tabs, and bslib components restore", {
  skip_if_not_installed("bslib")
  skip_if_not_installed("shinyMatrix")
  app <- start_app("04-matrix")
  on.exit(app$stop())
  s0 <- export_snapshot(app)
  expect_identical(s0$bindings[["m"]], "shinyMatrix.matrixNumeric")
  expect_identical(s0$bindings[["labels"]], "shinyMatrix.matrixCharacter")
  expect_identical(s0$bindings[["acc"]], "bslib.accordion")
  expect_identical(s0$bindings[["sb"]], "bslib.sidebar")
  expect_identical(s0$bindings[["period"]], "shiny.dateRangeInput")
  expect_identical(s0$bindings[["when"]], "shiny.sliderInput")
  expect_false("flags" %in% names(s0$inputs) && !is.null(s0$inputs$flags))
  expect_true(is.matrix(s0$inputs$m))
  expect_identical(s0$inputs$acc, "Matrix")
  expect_true(s0$inputs$sb)

  target <- s0
  target$inputs$period <- as.Date(c("2023-06-01", "2023-06-30"))
  target$inputs$day <- as.Date("2023-12-25")
  target$inputs$range <- c(10L, 40L)
  target$inputs$when <- as.Date("2024-03-15")
  target$inputs$flags <- c("x", "z")
  target$inputs$mode <- "slow"
  target$inputs$multi <- c("two", "three")
  target$inputs$m[] <- c(5, 6, 7, 8)
  target$inputs$labels[] <- c("p", "q")
  target$inputs$tabs <- "Second"
  target$inputs$acc <- "Tabs"
  target$inputs$sb <- FALSE

  report <- restore_json(app, snap_serialize(target, pretty = FALSE))
  expect_false(isTRUE(report$timed_out))
  expect_all_restored(report)
  after <- export_snapshot(app)
  for (id in names(target$inputs)) {
    expect_identical(after$inputs[[id]], target$inputs[[id]], label = id)
  }

  # And back to the initial state: the empty checkbox group, the open
  # sidebar, and the first accordion panel.
  report <- restore_json(app, snap_serialize(s0, pretty = FALSE))
  expect_false(isTRUE(report$timed_out))
  expect_all_restored(report)
  after <- export_snapshot(app)
  expect_null(after$inputs$flags)
  expect_identical(after$inputs$acc, "Matrix")
  expect_true(after$inputs$sb)
  expect_identical(after$inputs, s0$inputs)

  # The same through the upload control.
  report <- restore_upload(app, "restore", target)
  expect_all_restored(report)
  expect_identical(export_snapshot(app)$inputs$m, target$inputs$m)
})
