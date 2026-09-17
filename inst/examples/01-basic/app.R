# Every core input type, plus a save button.
library(shiny)
library(shinysnap)

ui <- fluidPage(
  titlePanel("shinysnap: basic inputs"),
  sidebarLayout(
    sidebarPanel(
      textInput("text", "Text", "hello"),
      textAreaInput("textarea", "Text area", "line 1\nline 2"),
      passwordInput("password", "Password", "secret"),
      numericInput("number", "Number", 42),
      checkboxInput("checkbox", "Checkbox", TRUE),
      checkboxGroupInput("checkgroup", "Checkbox group", c("a", "b", "c"), selected = c("a", "c")),
      radioButtons("radio", "Radio", c("x", "y", "z"), selected = "y"),
      sliderInput("slider", "Slider", 0, 100, 25),
      sliderInput("range", "Range", 0, 100, c(20, 80)),
      dateInput("date", "Date", "2024-01-15"),
      dateRangeInput("daterange", "Date range", "2024-01-01", "2024-03-01"),
      selectInput("select", "Select", c("one", "two", "three"), "two"),
      selectInput("multi", "Multi select", c("one", "two", "three"), c("one", "three"), multiple = TRUE),
      fileInput("upload", "Upload"),
      actionButton("go", "Go"),
      textInput("filename", "File name", "basic-state"),
      snap_download_button("save"),
      snap_download_button("save_bundle", "Save bundle (zip)"),
      snap_file_input("restore")
    ),
    mainPanel(
      tabsetPanel(
        id = "tabs",
        tabPanel("First", verbatimTextOutput("summary")),
        tabPanel("Second", "Second tab")
      )
    )
  )
)

server <- function(input, output, session) {
  snap_enable(app = "shinysnap-basic", version = "1.0.0", exclude = c("^filename$", "^restore$"))
  rv <- reactiveValues(clicks = 0L, note = "none")
  snap_track(rv)
  observeEvent(input$go, rv$clicks <- rv$clicks + 1L)
  snap_download_handler("save", filename = reactive(input$filename))
  snap_download_handler("save_bundle", filename = reactive(input$filename), format = "zip")
  snap_file_restore("restore")

  reports <- reactiveVal(list())
  snap_on_restored(function(state, report) {
    reports(c(reports(), list(list(
      timed_out = attr(report, "timed_out"),
      status = stats::setNames(as.list(report$status), report$id),
      detail = stats::setNames(as.list(report$detail), report$id)
    ))))
  })

  output$summary <- renderPrint(str(reactiveValuesToList(input)))

  exportTestValues(
    snapshot = snap_serialize(snap_take(session = session)),
    reports = reports()
  )
}

shinyApp(ui, server)
