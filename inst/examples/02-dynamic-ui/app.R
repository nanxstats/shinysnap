# The cascade: a select decides which branch of dynamic UI is shown; the
# branch contains a nested level of dynamic UI; one input keeps the same id
# across re-renders. This is the situation that needs delays with
# session$sendInputMessage() and needs none with shinysnap.
library(shiny)
library(shinysnap)

ui <- fluidPage(
  titlePanel("shinysnap: dynamic UI"),
  selectInput("method", "Method", c("a", "b"), "a"),
  uiOutput("branch"),
  uiOutput("common"),
  textInput("filename", "File name", "dynamic-state"),
  # A plain downloadButton(): the client script is injected by the server.
  downloadButton("save", "Save state"),
  verbatimTextOutput("summary")
)

server <- function(input, output, session) {
  snap_enable(app = "shinysnap-dynamic-ui", version = "1.0.0", exclude = "^filename$")
  counters <- reactiveValues(shared = 0L, a_n = 0L, b_k = 0L)

  output$branch <- renderUI({
    if (identical(input$method, "a")) {
      tagList(
        numericInput("a_n", "a: n", 10),
        sliderInput("a_rate", "a: rate", 0, 1, 0.5),
        selectInput("a_sub", "a: sub-branch", c("x", "y"), "x"),
        uiOutput("sub")
      )
    } else {
      tagList(
        numericInput("b_k", "b: k", 3),
        textInput("b_text", "b: text", "beta")
      )
    }
  })

  output$sub <- renderUI({
    req(identical(input$method, "a"))
    if (identical(input$a_sub, "x")) {
      numericInput("a_sub_x", "a/x: value", 1)
    } else {
      numericInput("a_sub_y", "a/x: other value", 2)
    }
  })

  # Same id, re-rendered whenever the method changes.
  output$common <- renderUI({
    numericInput("shared", paste("shared (default for", input$method, ")"), if (identical(input$method, "a")) 100 else 200)
  })

  observeEvent(input$shared, counters$shared <- counters$shared + 1L)
  observeEvent(input$a_n, counters$a_n <- counters$a_n + 1L)
  observeEvent(input$b_k, counters$b_k <- counters$b_k + 1L)

  snap_download_handler("save", filename = reactive(input$filename))
  output$summary <- renderPrint(str(reactiveValuesToList(input)))

  exportTestValues(
    snapshot = snap_serialize(snap_take(session = session)),
    counters = reactiveValuesToList(counters)
  )
}

shinyApp(ui, server)
