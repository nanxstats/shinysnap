# The zip bundle: manifest.json plus attachments/<id>/<file> and
# objects/<n>-<path>.rds. Reading validates every archive entry before
# extracting, because zip::unzip() itself follows ".." entries.

#' @noRd
require_zip <- function() {
  if (!requireNamespace("zip", quietly = TRUE)) {
    snap_abort(
      "The zip bundle format needs the zip package; install it with `install.packages(\"zip\")`."
    )
  }
  invisible(TRUE)
}

#' Write a snapshot as a zip bundle
#'
#' @noRd
write_bundle <- function(x, path, pretty = TRUE, unsupported = c("error", "rds"),
                         verbose = FALSE) {
  require_zip()
  unsupported <- match.arg(unsupported)
  staging <- tempfile("shinysnap-bundle-")
  dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  x$attachments <- stage_attachments(x$attachments, staging)
  ctx <- codec_ctx(
    unsupported = unsupported, verbose = isTRUE(verbose),
    keep_attachments = TRUE, bundle_dir = staging
  )
  ir <- encode_snapshot(x, ctx)
  emit_notes(ctx)
  write_utf8(json_render(ir, pretty = isTRUE(pretty)), file.path(staging, "manifest.json"))
  entries <- list.files(staging, recursive = TRUE, all.files = TRUE, include.dirs = FALSE)
  entries <- c("manifest.json", sort(setdiff(entries, "manifest.json"), method = "radix"))
  if (file.exists(path)) unlink(path)
  # "mirror" keeps the relative paths as listed; "cherry-pick" would store
  # nested files under their base names.
  zip::zip(path, files = entries, root = staging, mode = "mirror", include_directories = FALSE)
  invisible(path)
}

#' Copy uploaded files into the staging directory
#'
#' Returns the attachment records with an added `path` field (the
#' archive-relative location) for the manifest.
#'
#' @noRd
stage_attachments <- function(attachments, staging) {
  if (length(attachments) == 0L) {
    return(attachments)
  }
  for (id in names(attachments)) {
    rec <- attachments[[id]]
    n <- length(rec$datapath)
    if (n == 0L) next
    if (any(!file.exists(rec$datapath))) {
      snap_abort(
        sprintf(
          "The uploaded file(s) of `%s` no longer exist on disk: %s.",
          id, quote_ids(rec$datapath[!file.exists(rec$datapath)])
        )
      )
    }
    dir_id <- gsub("[^A-Za-z0-9._-]+", "_", id)
    dest_dir <- file.path(staging, "attachments", dir_id)
    dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
    names <- as.character(rec$name)
    names <- vapply(seq_len(n), function(i) {
      nm <- gsub("[^A-Za-z0-9._-]+", "_", basename(names[i]))
      nm <- sub("^\\.+", "", nm)
      if (!nzchar(nm)) nm <- paste0("file-", i)
      nm
    }, character(1))
    if (anyDuplicated(names)) names <- paste0(seq_len(n), "-", names)
    for (i in seq_len(n)) {
      file.copy(rec$datapath[i], file.path(dest_dir, names[i]), overwrite = TRUE)
    }
    rec$path <- file.path("attachments", dir_id, names)
    attachments[[id]] <- rec
  }
  attachments
}

#' Read a zip bundle
#'
#' @noRd
read_bundle <- function(path, trust = FALSE, unknown_types = "error") {
  require_zip()
  entries <- tryCatch(
    zip::zip_list(path),
    error = function(e) {
      snap_abort(
        sprintf("`%s` is not a readable zip archive: %s", path, conditionMessage(e)),
        class = "shinysnap_format_error"
      )
    }
  )
  check_bundle_entries(entries$filename, entries$uncompressed_size, path)
  if (!"manifest.json" %in% entries$filename) {
    snap_abort(
      sprintf("`%s` is not a shinysnap bundle: it has no manifest.json.", path),
      class = "shinysnap_format_error"
    )
  }
  dir <- tempfile("shinysnap-bundle-")
  dir.create(dir)
  zip::unzip(path, exdir = dir)
  manifest <- bundle_file(dir, "manifest.json", "manifest.json", prefix = "manifest.json")
  ctx <- codec_ctx(trust = isTRUE(trust), unknown_types = unknown_types, bundle_dir = dir)
  x <- decode_snapshot(json_parse(read_utf8(manifest)), ctx)
  emit_untrusted(ctx)
  attr(x, "bundle_dir") <- dir
  x
}

#' Refuse archives that could write outside the extraction directory or
#' that are too large to extract
#'
#' @noRd
check_bundle_entries <- function(names, sizes, path) {
  parts <- strsplit(names, "/", fixed = TRUE)
  bad <- vapply(seq_along(names), function(i) {
    nm <- names[i]
    !nzchar(nm) || grepl("^([A-Za-z]:)?[/\\\\]", nm) || grepl("\\", nm, fixed = TRUE) ||
      any(parts[[i]] %in% c("..", "."))
  }, logical(1))
  if (any(bad)) {
    snap_abort(
      sprintf(
        "Refusing to extract `%s`: it contains unsafe entries (%s).",
        path, quote_ids(names[bad])
      ),
      class = "shinysnap_unsafe_bundle"
    )
  }
  limit <- getOption("shinysnap.max_bundle_bytes", 100 * 1024^2)
  total <- sum(as.numeric(sizes), na.rm = TRUE)
  if (is.numeric(limit) && length(limit) == 1L && !is.na(limit) && total > limit) {
    snap_abort(
      sprintf(
        "Refusing to extract `%s`: %.0f bytes uncompressed exceed the limit of %.0f (option shinysnap.max_bundle_bytes).",
        path, total, limit
      ),
      class = "shinysnap_unsafe_bundle"
    )
  }
  invisible(TRUE)
}
