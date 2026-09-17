# Snapshot and restore from inside moduleServer(): ids are namespaced,
# tracked values and hooks are namespaced automatically.
library(shiny)
library(shinysnap)

params_ui <- function(id, label) {
  ns <- NS(id)
  tagList(
    h4(label),
    numericInput(ns("n"), "n", 10),
    selectInput(ns("kind"), "kind", c("linear", "quadratic"), "linear"),
    actionButton(ns("bump"), "Bump"),
    snap_download_button(ns("save"), "Save from module"),
    snap_file_input(ns("restore"), "Restore from module")
  )
}

params_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    rv <- reactiveValues(bumps = 0L)
    snap_track(rv)
    observeEvent(input$bump, rv$bumps <- rv$bumps + 1L)
    snap_on_save(function(state) {
      state$values$summary <- paste(state$inputs$kind, state$inputs$n)
    })
    snap_download_handler("save", filename = paste0(id, "-state"))
    snap_file_restore("restore")
    seen <- reactiveValues(inputs = list(), values = list(), report_ids = list())
    snap_on_restore(function(state) {
      seen$inputs <- c(seen$inputs, list(names(state$inputs)))
      seen$values <- c(seen$values, list(names(state$values)))
    })
    snap_on_restored(function(state, report) {
      seen$report_ids <- c(seen$report_ids, list(report$id))
    })
    exportTestValues(
      module_snapshot = snap_serialize(snap_take(session = session, scope = "module")),
      root_snapshot = snap_serialize(snap_take(session = session)),
      seen = reactiveValuesToList(seen)
    )
    NULL
  })
}

ui <- fluidPage(
  titlePanel("shinysnap: modules"),
  fluidRow(
    column(6, params_ui("left", "Left")),
    column(6, params_ui("right", "Right"))
  ),
  textInput("title", "Title", "two modules"),
  snap_download_button("save", "Save everything")
)

server <- function(input, output, session) {
  snap_enable(app = "shinysnap-modules", version = "1.0.0")
  params_server("left")
  params_server("right")
  snap_download_handler("save")
  reports <- reactiveVal(list())
  snap_on_restored(function(state, report) {
    reports(c(reports(), list(list(
      timed_out = attr(report, "timed_out"),
      status = stats::setNames(as.list(report$status), report$id)
    ))))
  })
  exportTestValues(
    snapshot = snap_serialize(snap_take(session = session)),
    reports = reports()
  )
}

shinyApp(ui, server)
