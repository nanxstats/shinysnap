# shinyMatrix, date inputs, and bslib components: every binding whose
# receiveMessage() wants something other than {value: x}.
library(shiny)
library(bslib)
library(shinyMatrix)
library(shinysnap)

ui <- page_sidebar(
  title = "shinysnap: matrix, dates, bslib",
  sidebar = sidebar(
    id = "sb", open = TRUE,
    dateRangeInput("period", "Period", "2024-01-01", "2024-03-01"),
    dateInput("day", "Day", "2024-02-15"),
    sliderInput("range", "Range", 0, 100, c(20, 80)),
    sliderInput("when", "Date slider", as.Date("2024-01-01"), as.Date("2024-12-31"), as.Date("2024-06-01")),
    checkboxGroupInput("flags", "Flags", c("x", "y", "z"), selected = character(0)),
    radioButtons("mode", "Mode", c("fast", "slow"), "fast"),
    selectInput("multi", "Multi", c("one", "two", "three"), "one", multiple = TRUE),
    snap_download_button("save"),
    snap_file_input("restore")
  ),
  accordion(
    id = "acc", open = "Matrix", multiple = TRUE,
    accordion_panel(
      "Matrix",
      value = "Matrix",
      matrixInput(
        "m", "Numeric matrix",
        value = matrix(c(1, 2, 3, 4), 2, dimnames = list(c("r1", "r2"), c("c1", "c2"))),
        class = "numeric", rows = list(names = TRUE), cols = list(names = TRUE)
      ),
      matrixInput("labels", "Character matrix", value = matrix(c("a", "b"), 1), class = "character")
    ),
    accordion_panel(
      "Tabs",
      value = "Tabs",
      tabsetPanel(id = "tabs", tabPanel("First", "first"), tabPanel("Second", "second"))
    ),
    accordion_panel(
      "Restore",
      value = "Restore",
      textAreaInput("json", "Snapshot JSON", rows = 6),
      actionButton("restore_text", "Restore from text"),
      verbatimTextOutput("report")
    )
  )
)

server <- function(input, output, session) {
  snap_enable(app = "shinysnap-matrix", version = "1.0.0", exclude = c("^json$", "^restore"))
  reports <- reactiveVal(list())
  snap_on_restored(function(state, report) {
    reports(c(reports(), list(list(
      timed_out = attr(report, "timed_out"),
      status = stats::setNames(as.list(report$status), report$id),
      detail = stats::setNames(as.list(report$detail), report$id)
    ))))
  })
  snap_download_handler("save")
  snap_file_restore("restore")
  observeEvent(input$restore_text, {
    req(nzchar(input$json))
    snap_restore(input$json)
    NULL
  })
  output$report <- renderPrint({
    if (length(reports())) str(reports()[[length(reports())]])
  })
  exportTestValues(
    snapshot = snap_serialize(snap_take(session = session)),
    reports = reports()
  )
}

shinyApp(ui, server)
