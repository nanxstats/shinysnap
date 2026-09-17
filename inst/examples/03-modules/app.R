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
    snap_download_button(ns("save"), "Save from module")
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
    exportTestValues(
      module_snapshot = snap_serialize(snap_take(session = session, scope = "module")),
      root_snapshot = snap_serialize(snap_take(session = session))
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
  exportTestValues(
    snapshot = snap_serialize(snap_take(session = session))
  )
}

shinyApp(ui, server)
