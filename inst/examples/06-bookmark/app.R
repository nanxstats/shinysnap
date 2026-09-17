# Coexistence with shiny's URL bookmarking: the URL that
# snap_as_bookmark_url() builds from a snapshot carries the same state as the
# one session$doBookmark() produces.
library(shiny)
library(shinysnap)

enableBookmarking("url")

ui <- function(request) {
  fluidPage(
    titlePanel("shinysnap: bookmark URLs"),
    textInput("text", "Text", "hello world & more"),
    numericInput("number", "Number", 5),
    checkboxGroupInput("flags", "Flags", c("a", "b"), "a"),
    dateInput("day", "Day", "2024-01-15"),
    selectInput("pick", "Pick", c("x", "y"), "y", multiple = TRUE),
    actionButton("bookmark", "Bookmark"),
    verbatimTextOutput("url")
  )
}

server <- function(input, output, session) {
  snap_enable(app = "shinysnap-bookmark", version = "1.0.0")
  setBookmarkExclude("bookmark")
  bookmark_url <- reactiveVal(NULL)
  onBookmarked(function(url) bookmark_url(url))
  observeEvent(input$bookmark, session$doBookmark())
  output$url <- renderText(bookmark_url() %||% "")
  exportTestValues(
    bookmark_url = bookmark_url(),
    snapshot_url = snap_as_bookmark_url(snap_take(session = session), session = session)
  )
}

shinyApp(ui, server)
