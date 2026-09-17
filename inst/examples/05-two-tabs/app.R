# A parameter-heavy app with two tabs that each offer a save button and an
# upload control, a select whose value decides which dynamic UI is shown,
# matrix inputs, and several reactiveValues for display preferences. The
# hand-rolled version of this needs staggered delays, a special case for
# matrix inputs, and per-field fallbacks for old files; this one does not.
library(shiny)
library(shinyMatrix)
library(shinysnap)

main_tab <- tagList(
  selectInput("model", "Model", c("simple", "complex"), "simple"),
  uiOutput("model_inputs"),
  matrixInput(
    "weights", "Weights",
    value = matrix(c(0.5, 1, 1.5, 2), 2), class = "numeric"
  ),
  actionButton("btn_more_digits", "More digits"),
  textInput("filename_main", "File name", "main"),
  snap_download_button("btn_save_main", "Save state"),
  snap_file_input("btn_restore_main", "Restore state")
)

details_tab <- tagList(
  uiOutput("detail_inputs"),
  matrixInput(
    "adjustments", "Adjustments",
    value = matrix(c(10, 20), 1), class = "numeric"
  ),
  textInput("filename_details", "File name", "details"),
  snap_download_button("btn_save_details", "Save state"),
  snap_file_input("btn_restore_details", "Restore state")
)

ui <- navbarPage(
  "shinysnap: two tabs",
  id = "nav",
  tabPanel("Main", value = "main", main_tab),
  tabPanel("Details", value = "details", details_tab)
)

server <- function(input, output, session) {
  snap_enable(
    app = "shinysnap-two-tabs", version = "2.4.0",
    exclude = c("^btn_", "^nav$", "^filename_")
  )

  prefs <- reactiveValues(digits = 3L, scientific = FALSE)
  main_options <- reactiveValues(threshold = 0.025, count = 1L)
  detail_options <- reactiveValues(threshold = 0.05, count = 2L)
  snap_track(prefs)
  snap_track(main_options)
  snap_track(detail_options)
  observeEvent(input$btn_more_digits, prefs$digits <- prefs$digits + 1L)

  output$model_inputs <- renderUI({
    if (identical(input$model, "simple")) {
      tagList(
        numericInput("simple_n", "simple: sample size", 100),
        sliderInput("simple_rate", "simple: rate", 0, 0.1, 0.025)
      )
    } else {
      numericInput("complex_k", "complex: k", 3)
    }
  })
  output$detail_inputs <- renderUI({
    req(input$model)
    tagList(
      numericInput("detail_k", "k (details)", if (identical(input$model, "simple")) 3 else 5),
      textInput("detail_note", "Note", "")
    )
  })
  # Both dynamic outputs live on tabs; keep them rendering while hidden so
  # that a restore can reach their inputs whichever tab is active.
  outputOptions(output, "model_inputs", suspendWhenHidden = FALSE)
  outputOptions(output, "detail_inputs", suspendWhenHidden = FALSE)

  # A derived result kept for downstream tools; not needed to restore.
  snap_on_save(function(state) {
    state$values$summary <- list(model = input$model, total_weight = sum(input$weights))
  })

  snap_download_handler(
    c("btn_save_main", "btn_save_details"),
    filename = reactive(if (identical(input$nav, "main")) input$filename_main else input$filename_details)
  )

  snap_file_restore(
    c("btn_restore_main", "btn_restore_details"),
    validate = function(snap) {
      if (is.null(snap$inputs$model)) stop("This file does not look like it was saved by this app.")
    },
    migrate = function(snap, from) {
      # Defaults for fields introduced after `from`; nothing else changes.
      if (is.null(snap$values$prefs$scientific)) snap$values$prefs$scientific <- FALSE
      snap
    }
  )

  reports <- reactiveVal(list())
  snap_on_restored(function(state, report) {
    reports(c(reports(), list(list(
      timed_out = attr(report, "timed_out"),
      status = stats::setNames(as.list(report$status), report$id),
      detail = stats::setNames(as.list(report$detail), report$id)
    ))))
  })

  exportTestValues(
    snapshot = snap_serialize(snap_take(session = session)),
    reports = reports(),
    values = list(
      prefs = reactiveValuesToList(prefs),
      main_options = reactiveValuesToList(main_options),
      detail_options = reactiveValuesToList(detail_options)
    )
  )
}

shinyApp(ui, server)
