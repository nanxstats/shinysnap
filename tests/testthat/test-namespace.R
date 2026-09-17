test_that("no export collides with shiny or shinytest2", {
  ours <- getNamespaceExports("shinysnap")
  expect_true(all(startsWith(ours, "snap_")))
  expect_length(intersect(ours, getNamespaceExports("shiny")), 0L)
  expect_false(any(grepl("snapshot", ours, ignore.case = TRUE)))
  skip_if_not_installed("shinytest2")
  expect_length(intersect(ours, getNamespaceExports("shinytest2")), 0L)
})
