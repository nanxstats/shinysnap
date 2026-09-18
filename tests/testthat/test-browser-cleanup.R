test_that("browser teardown removes child-process files, including after an error", {
  skip_if_no_browser()
  previous <- start_test_browser()
  expect_identical(start_test_browser(), previous)
  vars <- c("TMPDIR", "TMP", "TEMP")
  # Exercise restoration of both unset and empty environment variables.
  withr::local_envvar(c(TMP = NA_character_, TEMP = ""))
  before <- Sys.getenv(vars, unset = NA_character_)
  r_temp <- tempdir()
  browser <- NULL
  chrome_tmp <- NULL
  script <- withr::local_tempfile(
    fileext = ".R",
    lines = c(
      'paths <- Sys.getenv(c("TMPDIR", "TMP", "TEMP"))',
      "stopifnot(length(unique(paths)) == 1L, dir.exists(paths[[1]]))",
      'for (name in c("com.google.Chrome.test", ".org.chromium.Chromium.test")) {',
      "  dir <- file.path(paths[[1]], name)",
      "  dir.create(dir)",
      '  writeLines("child process detritus", file.path(dir, "lock"))',
      "}"
    )
  )

  run_browser <- function(fail) {
    browser <<- local_test_browser()
    chrome_tmp <<- Sys.getenv("TMPDIR")
    expect_identical(tempdir(), r_temp)
    expect_identical(dirname(chrome_tmp), r_temp)
    expect_identical(unname(Sys.getenv(vars)), rep(chrome_tmp, 3))
    expect_identical(chromote::default_chromote_object(), browser)
    status <- system2(
      file.path(R.home("bin"), "Rscript"),
      c("--vanilla", shQuote(script))
    )
    expect_identical(status, 0L)
    expect_true(file.exists(file.path(chrome_tmp, "com.google.Chrome.test", "lock")))
    expect_true(file.exists(file.path(chrome_tmp, ".org.chromium.Chromium.test", "lock")))
    if (fail) stop("simulated test failure")
  }

  for (fail in c(FALSE, TRUE)) {
    if (fail) {
      expect_error(run_browser(fail), "simulated test failure")
    } else {
      run_browser(fail)
    }
    expect_false(browser$is_alive())
    expect_false(dir.exists(chrome_tmp))
    expect_identical(Sys.getenv(vars, unset = NA_character_), before)
    expect_identical(chromote::default_chromote_object(), previous)
    expect_true(previous$is_alive())
  }
})
