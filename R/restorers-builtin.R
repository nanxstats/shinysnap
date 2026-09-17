# Built-in restorers: what the corresponding update*() function sends, minus
# everything that is not the value. Verified against the bindings' source.

#' @noRd
strip_attrs <- function(value) {
  if (is.atomic(value)) {
    attributes(value) <- attributes(value)[intersect(names(attributes(value)), c("class", "tzone", "levels"))]
  }
  value
}

#' @noRd
restorer_default <- function(id, value, binding, session) {
  list(value = strip_attrs(value))
}

#' @noRd
restorer_skip <- function(id, value, binding, session) {
  NULL
}

# checkboxGroupInput and selectInput accept an array of values; `[]` clears
# the selection.
#' @noRd
restorer_selection <- function(id, value, binding, session) {
  if (is.null(value) || length(value) == 0L) {
    return(list(value = list()))
  }
  list(value = as.list(as.character(value)))
}

# radioButtons: setValue() escapes the value as a string, so it must be a
# scalar; `[]` clears the selection.
#' @noRd
restorer_radio <- function(id, value, binding, session) {
  if (is.null(value) || length(value) == 0L) {
    return(list(value = list()))
  }
  list(value = as.character(value)[[1L]])
}

#' @noRd
format_ymd <- function(x) {
  x <- tryCatch(as.Date(x), error = function(e) as.Date(NA))
  out <- rep(NA_character_, length(x))
  ok <- !is.na(x)
  out[ok] <- format(x[ok], "%Y-%m-%d")
  out
}

# dateRangeInput: receiveMessage() wants {start, end}; a missing key leaves
# that end untouched, so NA ends are dropped. getValue() returns
# [start, end] as strings.
#' @noRd
restorer_date_range <- function(id, value, binding, session) {
  if (is.null(value)) {
    return(NULL)
  }
  d <- format_ymd(value)
  d <- c(d, NA_character_, NA_character_)[1:2]
  msg <- list()
  if (!is.na(d[1])) msg$start <- d[1]
  if (!is.na(d[2])) msg$end <- d[2]
  with_expect(list(value = as_object(msg)), as.list(d))
}

# dateInput: an ISO string; NULL/NA clears. getValue() returns the string.
#' @noRd
restorer_date <- function(id, value, binding, session) {
  if (is.null(value)) {
    return(list(value = NULL))
  }
  d <- format_ymd(value)[1]
  if (is.na(d)) {
    return(list(value = NULL))
  }
  list(value = d)
}

# sliderInput: numbers as they are; dates and date-times as milliseconds
# since the epoch (what updateSliderInput() sends). getValue() returns
# "YYYY-MM-DD" strings for date sliders and seconds for date-time sliders.
#' @noRd
restorer_slider <- function(id, value, binding, session) {
  if (is.null(value)) {
    return(NULL)
  }
  if (inherits(value, "Date")) {
    ms <- 1000 * as.numeric(as.POSIXct(value, tz = "UTC"))
    return(with_expect(list(value = unname(ms)), as.list(format_ymd(value))))
  }
  if (inherits(value, "POSIXct")) {
    secs <- as.numeric(value)
    return(with_expect(list(value = unname(secs * 1000)), as.list(secs)))
  }
  list(value = strip_attrs(value))
}

# bslib::accordion(): {method: "set", values: [...]} opens exactly those panels.
#' @noRd
restorer_accordion <- function(id, value, binding, session) {
  list(method = "set", values = if (is.null(value)) list() else as.list(as.character(value)))
}

# bslib::sidebar(): the input value is TRUE when open.
#' @noRd
restorer_sidebar <- function(id, value, binding, session) {
  list(method = if (isTRUE(value)) "open" else "close")
}

# shinyMatrix::matrixInput(): what updateMatrixInput() sends. The widget
# stores rows of cells plus row and column names (empty arrays when absent).
#' @noRd
restorer_matrix <- function(id, value, binding, session) {
  if (is.null(value)) {
    return(NULL)
  }
  if (!is.matrix(value)) {
    value <- as.matrix(value)
  }
  rn <- rownames(value)
  cn <- colnames(value)
  data <- value
  dimnames(data) <- NULL
  payload <- list(value = list(data = data, rownames = rn, colnames = cn))
  with_expect(payload, list(
    data = data,
    rownames = as.list(rn %||% character()),
    colnames = as.list(cn %||% character())
  ))
}

builtin_restorers <- list(
  shiny.checkboxGroupInput = restorer_selection,
  shiny.radioInput = restorer_radio,
  shiny.selectInput = restorer_selection,
  shiny.dateInput = restorer_date,
  shiny.dateRangeInput = restorer_date_range,
  shiny.sliderInput = restorer_slider,
  shiny.passwordInput = restorer_skip,
  shiny.actionButtonInput = restorer_skip,
  shiny.fileInputBinding = restorer_skip,
  bslib.accordion = restorer_accordion,
  bslib.sidebar = restorer_sidebar,
  `bslib.task-button` = restorer_skip,
  bslib.card = restorer_skip,
  shinyMatrix.matrixNumeric = restorer_matrix,
  shinyMatrix.matrixCharacter = restorer_matrix
)
