# The cascade: a select decides which branch of dynamic UI is shown; the
# branch contains a nested level of dynamic UI; one input keeps the same id
# across re-renders. This is the situation that needs delays with
# session$sendInputMessage() and needs none with shinysnap.
library(shiny)
library(shinysnap)

ui <- fluidPage(
  titlePanel("shinysnap: dynamic UI"),
  fluidRow(
    column(
      6,
      selectInput("method", "Method", c("a", "b"), "a"),
      uiOutput("branch"),
      uiOutput("common")
    ),
    column(
      6,
      textInput("filename", "File name", "dynamic-state"),
      # A plain downloadButton(): the client script is injected by the server.
      downloadButton("save", "Save state"),
      snap_file_input("restore"),
      textAreaInput("json", "Snapshot JSON", rows = 8),
      checkboxInput("use_ctx", "Use the restore context (accelerator)", TRUE),
      numericInput("timeout", "Timeout (seconds)", 5, min = 1),
      actionButton("restore_text", "Restore from text"),
      verbatimTextOutput("report")
    )
  ),
  verbatimTextOutput("summary")
)

report_as_list <- function(report) {
  list(
    txn = attr(report, "txn"),
    timed_out = attr(report, "timed_out"),
    elapsed = attr(report, "elapsed"),
    status = stats::setNames(as.list(report$status), report$id),
    detail = stats::setNames(as.list(report$detail), report$id)
  )
}

server <- function(input, output, session) {
  snap_enable(
    app = "shinysnap-dynamic-ui", version = "1.0.0",
    exclude = c("^filename$", "^json$", "^use_ctx$", "^timeout$", "^restore")
  )
  counters <- reactiveValues(shared = 0L, a_n = 0L, b_k = 0L)
  log <- reactiveValues(
    reports = list(), restoring_seen = list(), cancelled = 0L, errors = character()
  )

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
      numericInput("a_sub_y", "a/y: other value", 2)
    }
  })

  # Same id, re-rendered whenever the method changes.
  output$common <- renderUI({
    numericInput(
      "shared", paste("shared (default for", input$method, ")"),
      if (identical(input$method, "a")) 100 else 200
    )
  })

  observeEvent(input$shared, {
    counters$shared <- counters$shared + 1L
    log$restoring_seen$shared <- c(log$restoring_seen$shared, snap_is_restoring())
  })
  observeEvent(input$a_n, counters$a_n <- counters$a_n + 1L)
  observeEvent(input$b_k, {
    counters$b_k <- counters$b_k + 1L
    log$restoring_seen$b_k <- c(log$restoring_seen$b_k, snap_is_restoring())
  })

  snap_on_restored(function(state, report) {
    log$reports <- c(log$reports, list(report_as_list(report)))
  })

  observeEvent(input$restore_text, {
    req(nzchar(input$json))
    handle <- snap_restore(
      input$json,
      use_restore_context = isTRUE(input$use_ctx), timeout = input$timeout
    )
    promises::catch(handle$promise, function(e) {
      if (inherits(e, "shinysnap_cancelled")) {
        log$cancelled <- log$cancelled + 1L
      } else {
        log$errors <- c(log$errors, conditionMessage(e))
      }
    })
    NULL
  })
  snap_file_restore("restore")
  snap_download_handler("save", filename = reactive(input$filename))

  output$summary <- renderPrint(str(reactiveValuesToList(input)))
  output$report <- renderPrint({
    if (length(log$reports)) str(log$reports[[length(log$reports)]])
  })

  exportTestValues(
    snapshot = snap_serialize(snap_take(session = session)),
    counters = reactiveValuesToList(counters),
    reports = log$reports,
    restoring_seen = log$restoring_seen,
    cancelled = log$cancelled,
    errors = log$errors,
    is_restoring = snap_is_restoring(session = session)
  )
}

shinyApp(ui, server)
