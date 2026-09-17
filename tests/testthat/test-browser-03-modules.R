test_that("03-modules: snapshots use full ids and namespace tracked values and hooks", {
  app <- start_app("03-modules")
  on.exit(app$stop())

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
