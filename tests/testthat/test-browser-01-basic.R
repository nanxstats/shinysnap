test_that("01-basic: the inventory names every core binding and the snapshot is typed", {
  app <- start_app("01-basic")
  on.exit(app$stop())

  inv <- app$get_value(input = ".shinysnap_inventory")
  expected <- c(
    text = "shiny.textInput", textarea = "shiny.textareaInput",
    password = "shiny.passwordInput", number = "shiny.numberInput",
    checkbox = "shiny.checkboxInput", checkgroup = "shiny.checkboxGroupInput",
    radio = "shiny.radioInput", slider = "shiny.sliderInput", range = "shiny.sliderInput",
    date = "shiny.dateInput", daterange = "shiny.dateRangeInput",
    select = "shiny.selectInput", multi = "shiny.selectInput",
    upload = "shiny.fileInputBinding", go = "shiny.actionButtonInput",
    tabs = "shiny.bootstrapTabInput", filename = "shiny.textInput"
  )
  for (id in names(expected)) {
    expect_identical(inv[[id]], expected[[id]], label = id)
  }

  snap <- export_snapshot(app)
  expect_identical(snap$app, list(name = "shinysnap-basic", version = "1.0.0"))
  inputs <- snap$inputs
  expect_false(any(c("password", "go", "upload", "filename") %in% names(inputs)))
  expect_identical(names(inputs), sort(names(inputs), method = "radix"))
  expect_identical(inputs$text, "hello")
  expect_identical(inputs$textarea, "line 1\nline 2")
  expect_identical(inputs$number, 42L)
  expect_identical(inputs$checkbox, TRUE)
  expect_identical(inputs$checkgroup, c("a", "c"))
  expect_identical(inputs$radio, "y")
  expect_identical(inputs$slider, 25L)
  expect_identical(inputs$range, c(20L, 80L))
  expect_identical(inputs$date, as.Date("2024-01-15"))
  expect_identical(inputs$daterange, as.Date(c("2024-01-01", "2024-03-01")))
  expect_identical(inputs$select, "two")
  expect_identical(inputs$multi, c("one", "three"))
  expect_identical(inputs$tabs, "First")
  expect_identical(snap$values, list(rv = list(clicks = 0L, note = "none")))
  expect_identical(snap$bindings[["daterange"]], "shiny.dateRangeInput")
  expect_identical(names(snap$bindings), names(inputs))

  app$click("go")
  app$set_inputs(text = "changed", tabs = "Second")
  snap2 <- export_snapshot(app)
  expect_identical(snap2$inputs$text, "changed")
  expect_identical(snap2$inputs$tabs, "Second")
  expect_identical(snap2$values$rv$clicks, 1L)

  path <- app$get_download("save")
  from_file <- snap_read(path)
  expect_identical(from_file$inputs, snap2$inputs)
  expect_identical(from_file$values, snap2$values)
  expect_identical(from_file$bindings, snap2$bindings)
})

test_that("01-basic: a saved file restores every core input through the upload control", {
  app <- start_app("01-basic")
  on.exit(app$stop())
  snap <- export_snapshot(app)
  snap$inputs$text <- "restored"
  snap$inputs$textarea <- "one\ntwo"
  snap$inputs$number <- 7L
  snap$inputs$checkbox <- FALSE
  snap$inputs$checkgroup <- "b"
  snap$inputs$radio <- "z"
  snap$inputs$slider <- 60L
  snap$inputs$range <- c(5L, 95L)
  snap$inputs$date <- as.Date("2025-05-05")
  snap$inputs$daterange <- as.Date(c("2025-01-01", "2025-12-31"))
  snap$inputs$select <- "three"
  snap$inputs$multi <- "two"
  snap$inputs$tabs <- "Second"
  snap$values$rv$note <- "from file"
  report <- restore_upload(app, "restore", snap)
  expect_false(isTRUE(report$timed_out))
  expect_all_restored(report)
  after <- export_snapshot(app)
  for (id in names(snap$inputs)) {
    expect_identical(after$inputs[[id]], snap$inputs[[id]], label = id)
  }
  expect_identical(after$values$rv$note, "from file")
})

test_that("01-basic: a bundle keeps an uploaded file and restores through the upload control", {
  skip_if_not_installed("zip")
  app <- start_app("01-basic")
  on.exit(app$stop())
  csv <- tempfile("data-", fileext = ".csv")
  writeLines(c("x,y", "1,2", "3,4"), csv)
  app$upload_file(upload = csv)
  app$set_inputs(text = "with upload", filename = "bundled")
  path <- app$get_download("save_bundle")
  expect_identical(basename(path), "bundled.zip")
  bundle <- snap_read(path)
  expect_identical(bundle$inputs$text, "with upload")
  expect_false("upload" %in% names(bundle$inputs))
  expect_identical(bundle$attachments$upload$name, basename(csv))
  expect_identical(readLines(snap_attachment(bundle, "upload")), c("x,y", "1,2", "3,4"))

  bundle$inputs$text <- "from bundle"
  bundle$inputs$number <- 9L
  report <- restore_upload(app, "restore", bundle, format = "zip")
  expect_false(isTRUE(report$timed_out))
  expect_all_restored(report)
  expect_false("upload" %in% names(report$status))
  vals <- app$get_values(input = TRUE)$input
  expect_identical(vals$text, "from bundle")
  expect_identical(vals$number, 9L)
})
