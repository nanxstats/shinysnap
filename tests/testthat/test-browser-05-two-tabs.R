test_that("05-two-tabs: a file saved on one tab restores on the other with no delays in app code", {
  app <- start_app("05-two-tabs")
  on.exit(app$stop())

  inv0 <- app$get_value(input = ".shinysnap_inventory")
  app$set_inputs(model = "complex")
  inv <- wait_for_inventory(app, inv0)
  expect_true(all(c("complex_k", "detail_k", "detail_note", "weights", "adjustments") %in% names(inv)))
  app$set_inputs(complex_k = 9)
  app$click("btn_more_digits")
  app$click("btn_more_digits")

  saved <- app$get_download("btn_save_main")
  s1 <- snap_read(saved)
  expect_identical(s1$app, list(name = "shinysnap-two-tabs", version = "2.4.0"))
  expect_identical(s1$inputs$model, "complex")
  expect_identical(s1$inputs$complex_k, 9L)
  expect_false(any(grepl("^btn_|^nav$|^filename_", names(s1$inputs))))
  expect_identical(s1$values$prefs$digits, 5L)
  expect_identical(s1$values$summary$model, "complex")
  expect_true(is.matrix(s1$inputs$weights))

  # Change everything and move to the other tab.
  app$set_inputs(model = "simple")
  inv <- wait_for_inventory(app, inv)
  app$set_inputs(simple_n = 12)
  app$set_inputs(nav = "details")
  app$set_inputs(detail_k = 77, detail_note = "changed")
  app$click("btn_more_digits")
  expect_identical(app$get_value(export = "values")$prefs$digits, 6L)

  # Hand-edit the file: a matrix, a text, and a values section missing a
  # field that migrate() fills in.
  edited <- s1
  edited$inputs$weights[] <- c(9, 8, 7, 6)
  edited$inputs$detail_note <- "from file"
  edited$values$prefs$scientific <- NULL
  report <- restore_upload(app, "btn_restore_details", edited)
  expect_false(isTRUE(report$timed_out))
  expect_all_restored(report)
  expect_false("simple_n" %in% names(report$status))

  vals <- app$get_values(input = TRUE)$input
  expect_identical(vals$nav, "details")
  expect_identical(vals$model, "complex")
  expect_identical(vals$complex_k, 9L)
  expect_identical(vals$detail_k, edited$inputs$detail_k)
  expect_identical(vals$detail_note, "from file")
  after <- export_snapshot(app)
  expect_identical(after$inputs$weights, edited$inputs$weights)
  values <- app$get_value(export = "values")
  expect_identical(values$prefs$digits, 5L)
  expect_false(values$prefs$scientific)
  expect_identical(values$main_options$threshold, 0.025)

  # A file that fails validation leaves the state alone.
  bad <- new_snapshot(inputs = list(unrelated = 1L), app = list(name = "shinysnap-two-tabs"))
  path <- tempfile(fileext = ".json")
  snap_write(bad, path)
  app$upload_file(btn_restore_main = path)
  app$wait_for_idle(duration = 500, timeout = 10000)
  expect_identical(app$get_values(input = TRUE)$input$complex_k, 9L)
  expect_length(app$get_value(export = "reports"), 1L)
})
