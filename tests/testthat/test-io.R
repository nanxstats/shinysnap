example_json <- '{
  "format": 1,
  "app": {"name": "myapp", "version": "2.4.1"},
  "created": "2026-09-16T18:22:03Z",
  "producer": {"shinysnap": "0.1.0", "shiny": "1.14.0", "r": "4.5.1"},
  "inputs": {
    "dates": {"$type": "Date", "value": ["2024-01-01", "2024-03-01"]},
    "M": {"$type": "array", "storage": "integer", "dim": [2, 3],
          "dimnames": [["a", "b"], null], "value": [1, 2, 3, 4, 5, 6]},
    "method": "b",
    "n": 100,
    "rate": 0.025,
    "threshold": {"$type": "double", "value": [0.5, "inf"]},
    "weights": [0.5, 0.75]
  },
  "values": {
    "rv_display": {"digits": 3, "scientific": false}
  },
  "bindings": {
    "dates": "shiny.dateRangeInput", "M": "shinyMatrix.matrixInput",
    "method": "shiny.selectInput", "n": "shiny.sliderInput", "rate": "shiny.numberInput",
    "threshold": "shiny.numberInput", "weights": "shiny.sliderInput"
  },
  "meta": {}
}'

full_snapshot <- function() {
  new_snapshot(
    inputs = list(
      M = matrix(1:6, 2, dimnames = list(c("a", "b"), NULL)),
      dates = as.Date(c("2024-01-01", "2024-03-01")),
      method = "b",
      n = 100L,
      rate = 0.025,
      selected = NULL,
      threshold = c(0.5, Inf),
      weights = c(0.5, 0.75)
    ),
    values = list(rv_display = list(digits = 3L, scientific = FALSE)),
    bindings = c(
      M = "shinyMatrix.matrixInput", dates = "shiny.dateRangeInput",
      method = "shiny.selectInput", n = "shiny.sliderInput",
      rate = "shiny.numberInput", threshold = "shiny.numberInput",
      weights = "shiny.sliderInput"
    ),
    meta = list(note = "baseline", tags = c("a", "b")),
    app = list(name = "myapp", version = "2.4.1"),
    created = "2026-09-16T18:22:03Z",
    producer = snap_producer()
  )
}

test_that("the example file from the format description decodes as expected", {
  snap <- snap_unserialize(example_json)
  expect_s3_class(snap, "shinysnap")
  expect_identical(snap$format, 1L)
  expect_identical(snap$app, list(name = "myapp", version = "2.4.1"))
  expect_identical(snap$created, "2026-09-16T18:22:03Z")
  expect_identical(snap$producer, list(shinysnap = "0.1.0", shiny = "1.14.0", r = "4.5.1"))
  inputs <- snap_inputs(snap)
  expect_identical(names(inputs), c("dates", "M", "method", "n", "rate", "threshold", "weights"))
  expect_identical(inputs$dates, as.Date(c("2024-01-01", "2024-03-01")))
  expect_identical(inputs$M, matrix(1:6, 2, dimnames = list(c("a", "b"), NULL)))
  expect_identical(inputs$method, "b")
  expect_identical(inputs$n, 100L)
  expect_identical(inputs$rate, 0.025)
  expect_identical(inputs$threshold, c(0.5, Inf))
  expect_identical(inputs$weights, c(0.5, 0.75))
  expect_identical(snap_values(snap), list(rv_display = list(digits = 3L, scientific = FALSE)))
  expect_identical(snap$bindings[["M"]], "shinyMatrix.matrixInput")
  expect_length(snap$bindings, 7)
  expect_identical(snap_meta(snap), list())
  expect_identical(snap$attachments, list())
})

test_that("serialize/unserialize round-trips a snapshot exactly", {
  snap <- full_snapshot()
  txt <- snap_serialize(snap)
  back <- snap_unserialize(txt)
  expect_identical(back, snap)
  expect_true(identical(back, snap))
  expect_identical(snap_unserialize(snap_serialize(snap, pretty = FALSE)), snap)
})

test_that("the writer stamps producer and fills created when missing", {
  snap <- new_snapshot(inputs = list(n = 1L))
  txt <- snap_serialize(snap)
  back <- snap_unserialize(txt)
  expect_identical(back$producer, snap_producer())
  expect_match(back$created, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
  back["producer"] <- list(NULL)
  back["created"] <- list(NULL)
  expect_identical(back, snap)

  stale <- full_snapshot()
  stale$producer <- list(shinysnap = "0.0.1")
  expect_identical(snap_unserialize(snap_serialize(stale))$producer, snap_producer())
})

test_that("the JSON layout is canonical", {
  txt <- snap_serialize(full_snapshot())
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  expect_identical(lines[1], "{")
  expect_identical(lines[2], "  \"format\": 1,")
  expect_identical(lines[3], "  \"app\": {\"name\": \"myapp\", \"version\": \"2.4.1\"},")
  expect_identical(lines[4], "  \"created\": \"2026-09-16T18:22:03Z\",")
  expect_match(lines[5], "^  \"producer\": \\{\"shinysnap\": ")
  expect_identical(lines[6], "  \"inputs\": {")
  keys <- sub("^  \"([a-z]+)\":.*$", "\\1", grep("^  \"", lines, value = TRUE))
  expect_identical(keys, c("format", "app", "created", "producer", "inputs", "values", "bindings", "meta"))
  expect_identical(lines[length(lines)], "}")
  expect_match(txt, "\n$")
  expect_match(txt, "    \"n\": 100,", fixed = TRUE)
  expect_match(txt, "    \"rate\": 0.025,", fixed = TRUE)
  expect_match(txt, "    \"selected\": null,", fixed = TRUE)
  expect_match(txt, "    \"threshold\": {\"$type\": \"double\", \"value\": [0.5, \"inf\"]},", fixed = TRUE)
  expect_match(txt, "    \"weights\": [0.5, 0.75]", fixed = TRUE)
  expect_false(grepl("attachments", txt, fixed = TRUE))
  expect_identical(snap_serialize(full_snapshot()), txt)
})

test_that("compact output is a single line without spaces", {
  txt <- snap_serialize(full_snapshot(), pretty = FALSE)
  expect_false(grepl("\n", txt, fixed = TRUE))
  expect_false(grepl(": ", txt, fixed = TRUE))
  expect_true(startsWith(txt, "{\"format\":1,\"app\":{\"name\":\"myapp\""))
})

test_that("acceptance: doubles and integers are distinguishable and exact", {
  snap <- new_snapshot(inputs = list(sum = 0.1 + 0.2, i = 1L, d = 1))
  txt <- snap_serialize(snap)
  expect_match(txt, "\"sum\": 0.30000000000000004", fixed = TRUE)
  expect_match(txt, "\"i\": 1,", fixed = TRUE)
  expect_match(txt, "\"d\": 1.0", fixed = TRUE)
  back <- snap_inputs(snap_unserialize(txt))
  expect_identical(back$sum, 0.1 + 0.2)
  expect_identical(back$i, 1L)
  expect_identical(back$d, 1)
})

test_that("acceptance: hand-edited values read back", {
  txt <- snap_serialize(full_snapshot())
  edited <- sub("\"n\": 100,", "\"n\": 250,", txt, fixed = TRUE)
  edited <- sub("\"method\": \"b\",", "\"method\": \"c\",", edited, fixed = TRUE)
  edited <- sub("\"weights\": [0.5, 0.75]", "\"weights\": [0.25, 0.5, 0.25]", edited, fixed = TRUE)
  back <- snap_inputs(snap_unserialize(edited))
  expect_identical(back$n, 250L)
  expect_identical(back$method, "c")
  expect_identical(back$weights, c(0.25, 0.5, 0.25))
})

test_that("empty and minimal files decode to empty sections", {
  snap <- snap_unserialize("{\"format\": 1}")
  expect_identical(snap$format, 1L)
  expect_identical(snap$app, list(name = NULL, version = NULL))
  expect_null(snap$created)
  expect_null(snap$producer)
  expect_identical(snap$inputs, list())
  expect_identical(snap$values, list())
  expect_identical(snap$bindings, character())
  expect_identical(snap$attachments, list())
  expect_identical(snap$meta, list())
  expect_identical(snap_unserialize("{\"format\": 1, \"inputs\": {}, \"bindings\": {}, \"app\": {}}"), snap)
  expect_identical(snap_unserialize(snap_serialize(snap))$inputs, list())
  expect_identical(snap_unserialize("{\"format\": 1.0}")$format, 1L)
})

test_that("multi-line input is accepted", {
  lines <- strsplit(example_json, "\n", fixed = TRUE)[[1]]
  expect_identical(snap_unserialize(lines), snap_unserialize(example_json))
})

test_that("top-level problems produce clear errors", {
  expect_error(snap_unserialize("[]"), "JSON object", class = "shinysnap_format_error")
  expect_error(snap_unserialize("\"x\""), "JSON object", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"inputs\": {}}"), "\"format\" field is missing", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": \"1\"}"), "integer", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1.5}"), "integer", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 2}"), "upgrade shinysnap", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 0}"), "Unsupported format", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1"), "Invalid JSON", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1, \"inputs\": [1]}"), "\"inputs\" field must be an object", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1, \"inputs\": {\"a\": 1, \"a\": 2}}"), "duplicated keys", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1, \"app\": {\"name\": 1}}"), "app\\$name", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1, \"created\": 1}"), "\"created\"", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1, \"bindings\": {\"n\": 1}}"), "\"bindings\"", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1, \"bindings\": [\"a\"]}"), "\"bindings\"", class = "shinysnap_format_error")
  expect_error(snap_unserialize("{\"format\": 1, \"producer\": {\"r\": null}}"), "\"producer\"", class = "shinysnap_format_error")
  expect_error(snap_unserialize(42), class = "shinysnap_format_error")
})

test_that("errors inside sections name the path", {
  err <- expect_error(
    snap_unserialize("{\"format\": 1, \"inputs\": {\"x\": {\"$type\": \"wat\"}}}"),
    class = "shinysnap_unknown_type"
  )
  expect_identical(err$path, "inputs$x")
  err <- expect_error(
    snap_unserialize("{\"format\": 1, \"values\": {\"rv\": {\"k\": [1, \"a\"]}}}"),
    class = "shinysnap_format_error"
  )
  expect_identical(err$path, "values$rv$k")
  err <- expect_error(
    snap_serialize(new_snapshot(values = list(rv = list(f = mean)))),
    class = "shinysnap_unsupported_value"
  )
  expect_identical(err$path, "values$rv$f")
})

test_that("embedded R objects are gated behind trust = TRUE", {
  snap <- new_snapshot(
    inputs = list(n = 1L),
    values = list(fit = structure(list(coef = 1), class = "myfit"), other = new.env())
  )
  expect_error(snap_serialize(snap), class = "shinysnap_unsupported_value")
  txt <- snap_serialize(snap, unsupported = "rds")
  expect_message(snap_serialize(snap, unsupported = "rds", verbose = TRUE), "opaque")

  w <- expect_warning(back <- snap_unserialize(txt), class = "shinysnap_untrusted")
  expect_match(conditionMessage(w), "values$fit", fixed = TRUE)
  expect_match(conditionMessage(w), "values$other", fixed = TRUE)
  expect_identical(w$ids, c("values$fit", "values$other"))
  expect_identical(back$values, list(fit = NULL, other = NULL))
  expect_identical(back$inputs$n, 1L)

  trusted <- snap_unserialize(txt, trust = TRUE)
  expect_identical(trusted$values$fit, structure(list(coef = 1), class = "myfit"))
  expect_true(is.environment(trusted$values$other))
})

test_that("verbose serialization reports notes", {
  tb <- structure(list(x = 1:2), class = c("tbl_df", "tbl", "data.frame"), row.names = c(NA_integer_, -2L))
  snap <- new_snapshot(values = list(tb = tb))
  expect_message(snap_serialize(snap, verbose = TRUE), "tibble")
  expect_silent(snap_serialize(snap))
})

test_that("unknown types can be kept for inspection", {
  txt <- "{\"format\": 1, \"inputs\": {\"x\": {\"$type\": \"wat\", \"value\": 1}}}"
  snap <- snap_unserialize(txt, unknown_types = "keep")
  expect_identical(snap$inputs$x[["$type"]], "wat")
})

test_that("snap_serialize accepts a list or JSON text", {
  expect_identical(
    snap_unserialize(snap_serialize(list(inputs = list(n = 1L), created = "2026-01-01T00:00:00Z"))),
    new_snapshot(inputs = list(n = 1L), created = "2026-01-01T00:00:00Z", producer = snap_producer())
  )
  expect_identical(
    snap_inputs(snap_serialize("{\"format\": 1, \"inputs\": {\"n\": 5}}")),
    list(n = 5L)
  )
})

test_that("attachments are dropped from JSON with a message", {
  snap <- new_snapshot(
    inputs = list(n = 1L),
    attachments = list(upload = list(name = "data.csv", size = 1234L, type = "text/csv")),
    created = "2026-09-16T18:22:03Z",
    producer = snap_producer()
  )
  expect_message(txt <- snap_serialize(snap), "`upload`", fixed = TRUE)
  expect_false(grepl("attachments", txt, fixed = TRUE))
  back <- snap_unserialize(txt)
  expect_identical(back$attachments, list())
  back$attachments <- snap$attachments
  expect_identical(back, snap)
  ctx <- codec_ctx(keep_attachments = TRUE)
  ir <- encode_snapshot(snap, ctx)
  expect_identical(names(ir$attachments), "upload")
})

test_that("a malformed app field is rejected", {
  expect_error(snap_unserialize("{\"format\": 1, \"app\": [1]}"), "\"app\"", class = "shinysnap_format_error")
})

test_that("snap_write() and snap_read() round-trip JSON files exactly", {
  snap <- full_snapshot()
  path <- withr::local_tempfile(fileext = ".json")
  expect_identical(snap_write(snap, path), path)
  expect_identical(snap_read(path), snap)
  expect_identical(snap_read(path, format = "json"), snap)
  bytes <- readBin(path, "raw", file.size(path))
  expect_identical(bytes, charToRaw(snap_serialize(snap)))
  path2 <- withr::local_tempfile(fileext = ".json")
  snap_write(snap, path2)
  expect_identical(readBin(path2, "raw", file.size(path2)), bytes)

  compact <- withr::local_tempfile(fileext = ".json")
  snap_write(snap, compact, pretty = FALSE)
  expect_identical(length(readLines(compact, warn = FALSE)), 1L)
  expect_identical(snap_read(compact), snap)

  noext <- withr::local_tempfile()
  snap_write(snap, noext, format = "json")
  expect_identical(snap_read(noext, format = "json"), snap)
  expect_error(snap_write(snap, noext), "extension", class = "shinysnap_error")
  expect_error(snap_read(noext), "extension", class = "shinysnap_error")
})

test_that("snap_read() copes with byte-order marks, CRLF, and non-ASCII", {
  snap <- new_snapshot(inputs = list(name = "café", text = "a\nb"), created = "2026-01-01T00:00:00Z")
  path <- withr::local_tempfile(fileext = ".json")
  txt <- snap_serialize(snap)
  raw <- c(as.raw(c(0xEF, 0xBB, 0xBF)), charToRaw(gsub("\n", "\r\n", enc2utf8(txt), fixed = TRUE)))
  writeBin(raw, path)
  back <- snap_read(path)
  expect_identical(back$inputs, snap$inputs)
  writeBin(as.raw(c(0x7B, 0xFF, 0x7D)), path)
  expect_error(snap_read(path), "UTF-8", class = "shinysnap_format_error")
  expect_error(snap_read(file.path(tempdir(), "missing-file.json")), "not found", class = "shinysnap_format_error")
  expect_error(snap_read(1), "`path`", class = "shinysnap_error")
  expect_error(snap_write(snap, c("a", "b")), "`path`", class = "shinysnap_error")
})

test_that("the rds format works but requires trust to read", {
  snap <- full_snapshot()
  path <- withr::local_tempfile(fileext = ".rds")
  snap_write(snap, path)
  expect_error(snap_read(path), "trust = TRUE", class = "shinysnap_trust_error")
  expect_identical(snap_read(path, trust = TRUE), snap)
  expect_identical(snap_read(path, format = "rds", trust = TRUE), snap)
  bare <- new_snapshot(inputs = list(n = 1L))
  snap_write(bare, path)
  back <- snap_read(path, trust = TRUE)
  expect_identical(back$producer, snap_producer())
  expect_true(is_string(back$created))
  saveRDS(list(not = "a snapshot"), path)
  expect_error(snap_read(path, trust = TRUE), class = "shinysnap_invalid")
  expect_error(snap_write(snap, withr::local_tempfile(fileext = ".tar")), "extension")
})

# Bundles ---------------------------------------------------------------------

bundle_fixture <- function() {
  up <- tempfile(fileext = ".csv")
  writeLines(c("a,b", "1,2"), up)
  up2 <- tempfile(fileext = ".txt")
  writeLines("hello", up2)
  new_snapshot(
    inputs = list(n = 1L, when = as.Date("2024-01-01"), M = matrix(1:4, 2)),
    values = list(fit = structure(list(coef = 1), class = "myfit"), plain = list(a = 1)),
    attachments = list(
      upload = list(name = "data.csv", size = file.size(up), type = "text/csv", datapath = up),
      multi = list(
        name = c("x.txt", "x.txt"), size = c(6, 6), type = c("text/plain", "text/plain"),
        datapath = c(up2, up2)
      )
    ),
    meta = list(note = "bundle"),
    app = list(name = "b", version = "1"),
    created = "2026-01-01T00:00:00Z"
  )
}

strip_bundle <- function(s) {
  attr(s, "bundle_dir") <- NULL
  s$producer <- NULL
  for (id in names(s$attachments)) s$attachments[[id]]$datapath <- NULL
  s
}

test_that("a bundle round-trips inputs, values, attachments, and opaque objects", {
  skip_if_not_installed("zip")
  snap <- bundle_fixture()
  path <- withr::local_tempfile(fileext = ".zip")
  expect_error(snap_write(snap, path), class = "shinysnap_unsupported_value")
  snap_write(snap, path, unsupported = "rds")
  entries <- zip::zip_list(path)$filename
  expect_identical(entries[1], "manifest.json")
  expect_true("attachments/upload/data.csv" %in% entries)
  expect_true(all(c("attachments/multi/1-x.txt", "attachments/multi/2-x.txt") %in% entries))
  expect_true(any(grepl("^objects/1-values_fit\\.rds$", entries)))

  expect_warning(back <- snap_read(path), class = "shinysnap_untrusted")
  expect_s3_class(back, "shinysnap")
  expect_null(back$values$fit)
  expect_identical(back$values$plain, list(a = 1))
  expect_identical(back$inputs, snap$inputs)
  expect_identical(back$meta, snap$meta)
  expect_identical(names(back$attachments), c("upload", "multi"))
  expect_identical(back$attachments$upload$name, "data.csv")
  expect_identical(back$attachments$upload$size, file.size(snap$attachments$upload$datapath))
  expect_identical(back$attachments$upload$type, "text/csv")
  p <- snap_attachment(back, "upload")
  expect_true(file.exists(p))
  expect_identical(readLines(p), c("a,b", "1,2"))
  expect_identical(basename(snap_attachment(back, "multi")), c("1-x.txt", "2-x.txt"))
  expect_identical(readLines(snap_attachment(back, "multi")[2]), "hello")
  expect_null(snap_attachment(back, "nope"))
  expect_error(snap_attachment(back, 1), "`id`")
  dir <- attr(back, "bundle_dir")
  expect_true(dir.exists(dir))
  expect_true(startsWith(normalizePath(p), normalizePath(dir)))

  trusted <- snap_read(path, trust = TRUE)
  expect_identical(trusted$values$fit, snap$values$fit)
  expect_identical(strip_bundle(trusted), strip_bundle(snap))

  # The manifest is the JSON format with file records.
  txt <- read_utf8(file.path(dir, "manifest.json"))
  expect_match(txt, "\"$type\": \"file\"", fixed = TRUE)
  expect_match(txt, "\"path\": \"attachments/upload/data.csv\"", fixed = TRUE)
  expect_match(txt, "\"path\": [\"attachments/multi/1-x.txt\", \"attachments/multi/2-x.txt\"]", fixed = TRUE)
  expect_match(txt, "\"path\": \"objects/1-values_fit.rds\"", fixed = TRUE)

  # Re-bundling a read bundle copies the extracted files.
  path2 <- withr::local_tempfile(fileext = ".zip")
  snap_write(trusted, path2, unsupported = "rds")
  again <- snap_read(path2, trust = TRUE)
  expect_identical(strip_bundle(again), strip_bundle(snap))
  expect_identical(readLines(snap_attachment(again, "upload")), c("a,b", "1,2"))

  # Without attachments or opaque values a bundle needs no trust.
  plain <- new_snapshot(inputs = list(n = 2L), created = "2026-01-01T00:00:00Z")
  path3 <- withr::local_tempfile(fileext = ".zip")
  snap_write(plain, path3)
  expect_silent(read <- snap_read(path3))
  expect_identical(strip_bundle(read), strip_bundle(plain))
  expect_identical(zip::zip_list(path3)$filename, "manifest.json")
  expect_identical(snap_read(path3, format = "zip")$inputs, list(n = 2L))
})

test_that("bundle writing refuses missing uploads and odd names are sanitized", {
  skip_if_not_installed("zip")
  snap <- new_snapshot(attachments = list(
    up = list(name = "a.csv", size = 1, type = "t", datapath = file.path(tempdir(), "does-not-exist.csv"))
  ))
  expect_error(snap_write(snap, withr::local_tempfile(fileext = ".zip")), "no longer exist")
  f <- withr::local_tempfile(fileext = ".bin")
  writeLines("x", f)
  odd <- new_snapshot(attachments = list(
    `my id` = list(name = "../we ird/na me.csv", size = 1, type = "t", datapath = f),
    dots = list(name = "...", size = 1, type = "t", datapath = f)
  ))
  path <- withr::local_tempfile(fileext = ".zip")
  snap_write(odd, path)
  entries <- zip::zip_list(path)$filename
  expect_true("attachments/my_id/na_me.csv" %in% entries)
  expect_true("attachments/dots/file-1" %in% entries)
  back <- snap_read(path)
  expect_identical(back$attachments[["my id"]]$name, "../we ird/na me.csv")
  expect_true(file.exists(snap_attachment(back, "dots")))
})

test_that("unsafe or oversized bundles are refused before extraction", {
  skip_if_not_installed("zip")
  root <- withr::local_tempdir()
  dir.create(file.path(root, "inner"))
  writeLines("evil", file.path(root, "evil.txt"))
  writeLines("{\"format\": 1}", file.path(root, "inner", "manifest.json"))
  bad <- withr::local_tempfile(fileext = ".zip")
  suppressWarnings(zip::zip(
    bad,
    files = c("manifest.json", "../evil.txt"),
    root = file.path(root, "inner"), mode = "mirror"
  ))
  expect_true("../evil.txt" %in% zip::zip_list(bad)$filename)
  before <- list.files(tempdir(), pattern = "^shinysnap-bundle-")
  err <- expect_error(snap_read(bad), class = "shinysnap_unsafe_bundle")
  expect_match(conditionMessage(err), "../evil.txt", fixed = TRUE)
  expect_identical(list.files(tempdir(), pattern = "^shinysnap-bundle-"), before)

  expect_error(check_bundle_entries(c("manifest.json", "/abs/path"), c(1, 1), "x"), "unsafe", class = "shinysnap_unsafe_bundle")
  expect_error(check_bundle_entries(c("manifest.json", "C:\\win\\path"), c(1, 1), "x"), class = "shinysnap_unsafe_bundle")
  expect_error(check_bundle_entries(c("manifest.json", "a/./b"), c(1, 1), "x"), class = "shinysnap_unsafe_bundle")
  expect_error(check_bundle_entries(c("manifest.json", ""), c(1, 1), "x"), class = "shinysnap_unsafe_bundle")
  expect_true(check_bundle_entries(c("manifest.json", "attachments/", "attachments/u/a.csv"), c(1, 0, 1), "x"))

  good <- withr::local_tempfile(fileext = ".zip")
  snap_write(new_snapshot(inputs = list(n = 1L)), good)
  withr::with_options(list(shinysnap.max_bundle_bytes = 10), {
    expect_error(snap_read(good), "exceed", class = "shinysnap_unsafe_bundle")
  })
  expect_s3_class(snap_read(good), "shinysnap")

  notzip <- withr::local_tempfile(fileext = ".zip")
  writeLines("nope", notzip)
  expect_error(snap_read(notzip), "not a readable zip", class = "shinysnap_format_error")
  nomanifest <- withr::local_tempfile(fileext = ".zip")
  writeLines("x", file.path(root, "other.txt"))
  zip::zip(nomanifest, files = "other.txt", root = root, mode = "cherry-pick")
  expect_error(snap_read(nomanifest), "no manifest.json", class = "shinysnap_format_error")
})

test_that("manifests that point outside the bundle or at missing files are refused", {
  skip_if_not_installed("zip")
  make_bundle <- function(manifest, extra = list()) {
    staging <- withr::local_tempdir(.local_envir = parent.frame())
    writeLines(manifest, file.path(staging, "manifest.json"))
    for (rel in names(extra)) {
      dir.create(dirname(file.path(staging, rel)), recursive = TRUE, showWarnings = FALSE)
      writeLines(extra[[rel]], file.path(staging, rel))
    }
    path <- tempfile(fileext = ".zip")
    zip::zip(path, files = list.files(staging, recursive = TRUE), root = staging, mode = "mirror")
    path
  }
  record <- function(path) sprintf('{"format": 1, "attachments": {"u": {"$type": "file", "name": "a", "size": 1, "type": "t", "path": "%s"}}}', path)
  expect_error(snap_read(make_bundle(record("attachments/u/../../x"))), "invalid bundle path", class = "shinysnap_format_error")
  expect_error(snap_read(make_bundle(record("/etc/passwd"))), "invalid bundle path", class = "shinysnap_format_error")
  expect_error(snap_read(make_bundle(record("objects/a"))), "invalid bundle path", class = "shinysnap_format_error")
  expect_error(snap_read(make_bundle(record("attachments/u/missing"))), "not a file in the bundle", class = "shinysnap_format_error")
  expect_error(snap_read(make_bundle(record("attachments/u"), list("attachments/u/a" = "x"))), "not a file", class = "shinysnap_format_error")
  ok <- snap_read(make_bundle(record("attachments/u/a"), list("attachments/u/a" = "content")))
  expect_identical(readLines(snap_attachment(ok, "u")), "content")

  rds <- function(path) sprintf('{"format": 1, "values": {"v": {"$type": "rds", "class": ["x"], "path": "%s"}}}', path)
  expect_warning(untrusted <- snap_read(make_bundle(rds("objects/1-v.rds"))), class = "shinysnap_untrusted")
  expect_null(untrusted$values$v)
  expect_error(snap_read(make_bundle(rds("attachments/1-v.rds")), trust = TRUE), "invalid bundle path", class = "shinysnap_format_error")
  expect_error(snap_read(make_bundle(rds("objects/1-v.rds")), trust = TRUE), "not a file", class = "shinysnap_format_error")
  broken <- make_bundle(rds("objects/1-v.rds"), list("objects/1-v.rds" = "not an rds"))
  expect_error(snap_read(broken, trust = TRUE), "cannot be read", class = "shinysnap_format_error")
  # An rds wrapper with a path in plain JSON (no bundle) is rejected.
  expect_error(snap_unserialize(rds("objects/1-v.rds"), trust = TRUE), "requires reading a bundle", class = "shinysnap_format_error")
  # File records outside a bundle decode with an unknown local path.
  plain <- snap_unserialize(record("attachments/u/a"))
  expect_identical(plain$attachments$u$name, "a")
  expect_identical(plain$attachments$u$datapath, NA_character_)
  expect_error(snap_unserialize('{"format": 1, "attachments": {"u": {"$type": "file", "name": "a"}}}'), "equal length", class = "shinysnap_format_error")
})
