test_that("03-modules: snapshots use full ids and namespace tracked values and hooks", {
  app <- start_app("03-modules")

  app$set_inputs(`left-n` = 7, `right-kind` = "quadratic")
  app$click("right-bump")
  app$click("right-bump")

  snap <- export_snapshot(app)
  expect_identical(
    names(snap$inputs),
    c("left-kind", "left-n", "right-kind", "right-n", "title")
  )
  expect_identical(snap$inputs[["left-n"]], 7L)
  expect_identical(snap$inputs[["right-kind"]], "quadratic")
  expect_identical(snap$values, list(
    `left-rv` = list(bumps = 0L), `left-summary` = "linear 7",
    `right-rv` = list(bumps = 2L), `right-summary` = "quadratic 10"
  ))
  expect_identical(snap$bindings[["left-kind"]], "shiny.selectInput")

  left <- snap_unserialize(app$get_value(export = "left-module_snapshot"))
  expect_identical(names(left$inputs), c("left-kind", "left-n"))
  right_root <- snap_unserialize(app$get_value(export = "right-root_snapshot"))
  expect_identical(names(right_root$inputs), names(snap$inputs))

  path <- app$get_download("left-save")
  from_module <- snap_read(path)
  expect_identical(from_module$inputs, snap$inputs)
  expect_identical(snap_read(app$get_download("save"))$values, snap$values)
})

test_that("03-modules: a restore started inside a module restores the whole app", {
  app <- start_app("03-modules")
  snap <- export_snapshot(app)
  snap$inputs[["left-n"]] <- 3L
  snap$inputs[["right-n"]] <- 4L
  snap$inputs[["right-kind"]] <- "quadratic"
  snap$inputs$title <- "restored title"
  snap$values[["left-rv"]]$bumps <- 11L
  report <- restore_upload(app, "left-restore", snap)
  expect_false(isTRUE(report$timed_out))
  expect_all_restored(report)
  vals <- app$get_values(input = TRUE)$input
  expect_identical(vals[["left-n"]], 3L)
  expect_identical(vals[["right-n"]], 4L)
  expect_identical(vals[["right-kind"]], "quadratic")
  expect_identical(vals$title, "restored title")
  after <- export_snapshot(app)
  expect_identical(after$values[["left-rv"]]$bumps, 11L)
  seen <- app$get_value(export = "left-seen")
  expect_identical(unlist(seen$inputs), c("kind", "n"))
  expect_identical(unlist(seen$values), c("rv", "summary"))
  expect_identical(unlist(seen$report_ids), c("left-kind", "left-n"))
})
