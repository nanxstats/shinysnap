query_pairs <- function(url) {
  q <- sub("^[^?]*\\?", "", url)
  sort(strsplit(q, "&", fixed = TRUE)[[1]])
}

test_that("06-bookmark: snap_as_bookmark_url() carries the same state as session$doBookmark()", {
  app <- start_app("06-bookmark")
  on.exit(app$stop())
  app$set_inputs(text = "changed & \u00e9", number = 42, flags = c("a", "b"))
  app$click("bookmark")
  native <- app$wait_for_value(export = "bookmark_url", ignore = list(NULL, ""), timeout = 10000)
  ours <- app$get_value(export = "snapshot_url")
  expect_match(native, "^http://.*\\?_inputs_&")
  expect_identical(sub("\\?.*$", "", ours), sub("\\?.*$", "", native))
  expect_identical(query_pairs(ours), query_pairs(native))
  expect_false(any(grepl("shinysnap", query_pairs(native))))
})
