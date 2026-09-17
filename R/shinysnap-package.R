#' shinysnap: Save and Restore the State of 'shiny' Applications
#'
#' @description
#' shinysnap takes a *snapshot* of a running app, that is, the current input
#' values plus any server-side values you register, writes it to a plain JSON
#' file, and restores it later into a different session without a page reload
#' and without bookmarking.
#'
#' The word "snapshot" is used here in the sense of a virtual machine or file
#' system snapshot: a saved state that can be written to a file, shared, and
#' restored later. It has nothing to do with snapshot *testing* (the
#' `expect_snapshot` functions of testthat and shinytest2, or testthat's
#' `_snaps/` directories) and nothing to do with screenshots.
#'
#' @section The snapshot object:
#' A snapshot is a plain list of class `shinysnap` with these fields:
#'
#' * `format`: the file format version (an integer).
#' * `app`: a list with `name` and `version` of the app (each may be `NULL`).
#' * `created`: an ISO 8601 UTC timestamp of when the state was captured.
#' * `producer`: versions of shinysnap, shiny, and R that wrote the file.
#' * `inputs`: a named list of input values, keyed by fully namespaced ids.
#' * `values`: a named list of server-side values.
#' * `bindings`: a named character vector mapping input ids to the name of
#'   the client-side input binding that produced them.
#' * `attachments`: file records, used by the bundle format.
#' * `meta`: free-form, user-supplied metadata.
#'
#' Use [snap_serialize()] and [snap_unserialize()] to convert between the
#' object and its JSON text.
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom R6 R6Class
## usethis namespace: end
NULL
