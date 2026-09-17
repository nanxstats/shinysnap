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
