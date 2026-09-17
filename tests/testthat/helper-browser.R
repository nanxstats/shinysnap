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

# Wait until the exported list of restore reports differs from `before`.
wait_for_reports <- function(app, before, timeout = 20000) {
  app$wait_for_value(export = "reports", ignore = list(before, NULL), timeout = timeout)
}

last_report <- function(reports) reports[[length(reports)]]

# Restore from the JSON text area of the example apps and return the report.
restore_json <- function(app, json, timeout = 20000) {
  before <- app$get_value(export = "reports")
  app$set_inputs(json = json)
  app$click("restore_text")
  last_report(wait_for_reports(app, before, timeout = timeout))
}

# Restore through an upload control and return the report.
restore_upload <- function(app, id, snap, timeout = 20000) {
  path <- tempfile(fileext = ".json")
  snap_write(snap, path)
  before <- app$get_value(export = "reports")
  args <- list(path)
  names(args) <- id
  do.call(app$upload_file, args)
  last_report(wait_for_reports(app, before, timeout = timeout))
}

expect_all_restored <- function(report, ok = c("applied", "constructed", "reapplied")) {
  statuses <- unlist(report$status)
  bad <- statuses[!statuses %in% ok]
  testthat::expect_true(
    length(bad) == 0,
    label = paste0(
      "statuses: ", paste(names(statuses), statuses, sep = "=", collapse = ", "),
      "; details: ", paste(names(report$detail), unlist(report$detail), sep = "=", collapse = ", ")
    )
  )
}
