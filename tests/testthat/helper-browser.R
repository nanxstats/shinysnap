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

# Chrome inherits these variables, whereas R's tempdir() is fixed at startup.
# Keep Chrome's own files (including com.google.Chrome.* on Linux) inside a
# directory we own, and stop the browser before withr removes that directory.
local_test_browser <- function(.local_envir = parent.frame()) {
  # R CMD check nests tempdir() under working_dir. Keep the prefix short so
  # Chrome's appended com.google.Chrome.XXXXXX/SingletonSocket still fits in
  # Linux's 108-byte Unix-domain socket address (including its terminator).
  chrome_tmp <- withr::local_tempdir(
    pattern = "snap-", .local_envir = .local_envir
  )
  withr::local_envvar(
    c(TMPDIR = chrome_tmp, TMP = chrome_tmp, TEMP = chrome_tmp),
    .local_envir = .local_envir
  )

  # Leave an existing interactive browser alive and restore it after testing.
  previous <- if (chromote::has_default_chromote_object()) {
    chromote::default_chromote_object()
  } else {
    NULL
  }
  withr::defer(
    if (!is.null(previous)) chromote::set_default_chromote_object(previous),
    envir = .local_envir
  )

  chrome <- chromote::Chrome$new()
  withr::defer(chrome$close(wait = TRUE), envir = .local_envir)
  browser <- chromote::Chromote$new(browser = chrome)
  withr::defer(browser$close(), envir = .local_envir)
  chromote::set_default_chromote_object(browser)
  browser
}

# AppDriver$stop() closes a tab, not the shared browser. Own one browser for
# the suite, created only when a browser test actually runs (after skip checks).
start_test_browser <- local({
  browser <- NULL
  function() {
    if (is.null(browser) || !browser$is_alive()) {
      browser <<- local_test_browser(.local_envir = testthat::teardown_env())
    }
    invisible(browser)
  }
})

# Start an example app and wait until the client script has reported.
start_app <- function(name, ...) {
  skip_if_no_browser()
  start_test_browser()
  app <- shinytest2::AppDriver$new(
    example_app(name),
    variant = NULL, name = name, load_timeout = 30000, ...
  )
  withr::defer(app$stop(), envir = parent.frame())
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
restore_upload <- function(app, id, snap, timeout = 20000, format = "json") {
  path <- withr::local_tempfile(fileext = paste0(".", format))
  snap_write(snap, path, format = format)
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
