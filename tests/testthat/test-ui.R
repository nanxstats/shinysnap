test_that("snap_download_button() attaches the client script", {
  btn <- snap_download_button("save", "Save it")
  expect_s3_class(btn, "shiny.tag")
  deps <- htmltools::findDependencies(btn)
  expect_true("shinysnap" %in% vapply(deps, function(d) d$name, character(1)))
  html <- as.character(btn)
  expect_match(html, "Save it", fixed = TRUE)
  expect_match(html, "id=\"save\"", fixed = TRUE)
})

test_that("snap_dependency() points at the shipped script", {
  dep <- snap_dependency()
  expect_s3_class(dep, "html_dependency")
  expect_identical(dep$name, "shinysnap")
  expect_identical(dep$script, "shinysnap.js")
  expect_true(file.exists(file.path(dep$src$file, "shinysnap.js")))
})

test_that("snap_download_handler() writes snapshot files with sanitized names", {
  server <- function(input, output, session) {
    snap_enable(app = "dl", version = "1")
    rv <- reactiveValues(k = 2L)
    snap_track(rv)
    snap_download_handler(c("save_a", "save_b"), filename = reactive(input$fname))
    snap_download_handler("fixed", filename = "My File.JSON")
    snap_download_handler("fun", filename = function() "from fun")
    snap_download_handler("given", snapshot = function() {
      snap_unserialize("{\"format\": 1, \"inputs\": {\"z\": 1}}")
    })
    snap_download_handler("obj", snapshot = snap_unserialize("{\"format\": 1, \"inputs\": {\"q\": 2}}"))
    snap_download_handler("subset", include = "^n$", values = FALSE)
    expect_error(snap_download_handler(character()), "`id`", class = "shinysnap_error")
    expect_error(snap_download_handler("x", format = "xml"))
  }
  shiny::testServer(server, {
    session$setInputs(n = 1L, fname = "run 01", other = "x")
    path <- output$save_a
    expect_identical(basename(path), "run_01.json")
    snap <- snap_read(path)
    expect_identical(names(snap$inputs), c("fname", "n", "other"))
    expect_identical(snap$values, list(rv = list(k = 2L)))
    expect_identical(snap$app, list(name = "dl", version = "1"))
    expect_identical(basename(output$save_b), "run_01.json")
    expect_identical(basename(output$fixed), "My_File.json")
    expect_identical(basename(output$fun), "from_fun.json")
    expect_identical(snap_read(output$given)$inputs, list(z = 1L))
    expect_identical(snap_read(output$obj)$inputs, list(q = 2L))
    subset <- snap_read(output$subset)
    expect_identical(names(subset$inputs), "n")
    expect_identical(subset$values, list())
    session$setInputs(fname = "")
    expect_identical(basename(output$save_a), "state.json")
  })
})

test_that("snap_download_handler() namespaces ids inside modules", {
  mod <- function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      snap_download_handler("save", filename = "mod")
      NULL
    })
  }
  shiny::testServer(mod, args = list(id = "m"), {
    session$setInputs(n = 3L)
    path <- output$save
    expect_identical(basename(path), "mod.json")
    expect_identical(snap_read(path)$inputs, list(`m-n` = 3L))
  })
})
