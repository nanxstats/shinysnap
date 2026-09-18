#' Exclude or include inputs by pattern
#'
#' `snap_exclude()` adds regular expressions; inputs whose fully namespaced
#' id matches any of them are left out of snapshots and ignored on restore.
#' `snap_include()` adds patterns that an id must match to be captured at
#' all. Both accumulate over calls within a session and complement the
#' `exclude`/`include` arguments of [snap_enable()] and [snap_take()].
#'
#' Ids excluded with shiny's `setBookmarkExclude()` are always honoured too,
#' and action buttons, password inputs, and file inputs are never captured
#' as input values.
#'
#' @param patterns A character vector of regular expressions, matched
#'   against fully namespaced input ids (for example `"^mod-btn_"`).
#' @param session The Shiny session. Defaults to the current session.
#'
#' @returns The complete vector of patterns registered so far, invisibly.
#'
#' @examples
#' if (interactive()) {
#'   library(shiny)
#'
#'   server <- function(input, output, session) {
#'     snap_exclude(c("^btn_", "^nav_"))
#'     snap_include(c("^model_", "^prefs_"))
#'   }
#' }
#' @export
snap_exclude <- function(patterns, session = shiny::getDefaultReactiveDomain()) {
  session <- require_session(session, "snap_exclude")
  patterns <- check_patterns(patterns, "patterns")
  ctrl <- snap_controller(session)
  ctrl$exclude <- unique(c(ctrl$exclude, patterns))
  invisible(ctrl$exclude)
}

#' @rdname snap_exclude
#' @export
snap_include <- function(patterns, session = shiny::getDefaultReactiveDomain()) {
  session <- require_session(session, "snap_include")
  patterns <- check_patterns(patterns, "patterns")
  ctrl <- snap_controller(session)
  ctrl$include <- unique(c(ctrl$include, patterns))
  invisible(ctrl$include)
}

#' Does an id match any of the patterns?
#'
#' @noRd
matches_any <- function(ids, patterns) {
  hit <- rep(FALSE, length(ids))
  for (p in patterns) hit <- hit | grepl(p, ids)
  hit
}

#' Apply the exclusion rules to a vector of input ids
#'
#' Rules, in order: shiny's bookmark exclude list, the controller's and the
#' call's `exclude` patterns, and, when any `include` pattern is registered,
#' the requirement to match at least one of them.
#'
#' @returns A logical vector: `TRUE` for ids to keep.
#'
#' @noRd
select_ids <- function(ids, ctrl, include = NULL, exclude = NULL) {
  keep <- !(ids %in% ctrl$root$getBookmarkExclude())
  keep <- keep & !matches_any(ids, c(ctrl$exclude, exclude))
  incl <- c(ctrl$include, include)
  if (length(incl)) {
    keep <- keep & matches_any(ids, incl)
  }
  keep
}
