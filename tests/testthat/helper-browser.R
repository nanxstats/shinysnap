# Helpers for the shinytest2-based browser tests.

skip_if_no_browser <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("shinytest2")
  testthat::skip_if_not_installed("chromote")
  chrome <- tryCatch(chromote::find_chrome(), error = function(e) NULL)
  testthat::skip_if(is.null(chrome) || !nzchar(chrome), "Chrome is not available")
}

example_app <- function(name) {
  path <- system.file("examples", name, package = "shinysnap")
  testthat::skip_if(!nzchar(path), paste("example app", name, "not found"))
  path
}

# Start an example app and wait until the client script has reported.
start_app <- function(name, ...) {
  skip_if_no_browser()
  app <- shinytest2::AppDriver$new(
    example_app(name),
    variant = NULL, name = name, load_timeout = 30000, ...
  )
  app$wait_for_value(input = ".shinysnap_ready", timeout = 15000)
  app
}

# Wait until the inventory differs from `before`, then let things settle.
wait_for_inventory <- function(app, before) {
  app$wait_for_value(
    input = ".shinysnap_inventory", ignore = list(before, NULL), timeout = 10000
  )
  app$wait_for_idle(duration = 300, timeout = 10000)
  app$get_value(input = ".shinysnap_inventory")
}

export_snapshot <- function(app, name = "snapshot") {
  snap_unserialize(app$get_value(export = name))
}
