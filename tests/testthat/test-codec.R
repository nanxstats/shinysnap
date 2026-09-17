# Helpers ---------------------------------------------------------------------

encode_text <- function(x, pretty = TRUE, ...) {
  json_render(encode_value(x, "inputs$x", codec_ctx(...)), pretty = pretty)
}

decode_text <- function(text, ...) {
  decode_value(
    jsonlite::parse_json(text, simplifyVector = FALSE),
    "inputs$x", codec_ctx(...)
  )
}

roundtrip <- function(x, pretty = TRUE, ...) {
  decode_text(encode_text(x, pretty = pretty, ...), ...)
}

expect_roundtrip <- function(x, label = NULL) {
  y <- roundtrip(x)
  expect_identical(y, x, label = label)
  expect_true(identical(y, x), label = paste("identical():", label))
  z <- roundtrip(x, pretty = FALSE)
  expect_true(identical(z, x), label = paste("compact identical():", label))
}

# Round-trip corpus -----------------------------------------------------------

corpus <- list(
  null = NULL,
  true = TRUE,
  false = FALSE,
  na_lgl = NA,
  lgl_vec = c(TRUE, NA, FALSE),
  lgl_named = c(a = TRUE, b = FALSE),
  lgl0 = logical(0),
  int = 1L,
  int_neg = -5L,
  int_na = NA_integer_,
  int_vec = c(1L, NA, 3L),
  int_all_na = c(NA_integer_, NA_integer_),
  int_named = c(a = 1L, b = 2L),
  int_max = .Machine$integer.max,
  int0 = integer(0),
  dbl = 1,
  dbl_sum = 0.1 + 0.2,
  dbl_na = NA_real_,
  dbl_nan = NaN,
  dbl_inf = Inf,
  dbl_neg_inf = -Inf,
  dbl_mixed = c(1.5, Inf, NA, NaN, -Inf, 2),
  dbl_all_na = c(NA_real_, NA_real_),
  dbl_named = c(a = 1.5, b = NA),
  dbl_named_inf = c(a = Inf, b = 1),
  dbl_xmax = .Machine$double.xmax,
  dbl_xmin = .Machine$double.xmin,
  dbl_denorm = 5e-324,
  dbl_tiny = 1e-300,
  dbl_big = 1e21,
  dbl_vec = c(0.5, 0.75, 100, 1e16, 1e-6),
  dbl0 = numeric(0),
  chr = "a",
  chr_empty = "",
  chr_na = NA_character_,
  chr_vec = c("a", NA, "c"),
  chr_all_na = c(NA_character_, NA_character_),
  chr_named = c(a = "x", b = "y"),
  chr_escapes = "quote\" backslash\\ newline\n tab\t cr\r ctrl\001 bs\b ff\f del\177",
  chr_unicode = c("caf\u00e9", "\u4e2d\u6587", "\u2028", "emoji \U0001F600"),
  chr_html = "</script><b>&amp;</b>",
  chr_looks_like_number = c("1", "1.0", "inf", "NaN", "null", "true"),
  chr0 = character(0),
  date = as.Date("2024-01-01"),
  date_vec = as.Date(c("2024-01-01", NA, "1999-12-31")),
  date_named = as.Date(c(start = "2024-01-01", end = "2024-03-01")),
  date0 = as.Date(character(0)),
  posixct_utc = as.POSIXct("2024-01-01 10:00:00", tz = "UTC"),
  posixct_frac = as.POSIXct("2024-01-01 10:00:00.5", tz = "UTC"),
  posixct_ms = as.POSIXct("2024-01-01 10:00:00.123", tz = "UTC"),
  posixct_ny = as.POSIXct("2024-07-01 10:00:00.123", tz = "America/New_York"),
  posixct_local = as.POSIXct("2024-01-01 10:00:00"),
  posixct_no_tzone = structure(1704103200.5, class = c("POSIXct", "POSIXt")),
  posixct_na = as.POSIXct(c("2024-01-01 10:00:00", NA), tz = "UTC"),
  posixct_pre_1970 = as.POSIXct("1969-12-31 23:59:59.25", tz = "UTC"),
  difftime_mins = as.difftime(c(1.5, NA), units = "mins"),
  difftime_secs = as.difftime(90, units = "secs"),
  difftime_inf = as.difftime(c(1, Inf), units = "days"),
  factor = factor(c("a", "b", NA), levels = c("a", "b", "c")),
  factor_ordered = factor(c("lo", "hi"), levels = c("lo", "hi"), ordered = TRUE),
  factor_named = factor(c(x = "a", y = "b")),
  factor_empty = factor(character(0)),
  matrix_int = matrix(1:6, 2),
  matrix_dimnames = matrix(1:6, 2, dimnames = list(c("a", "b"), NULL)),
  matrix_full_dimnames = matrix(c(1.5, 2, 3, 4), 2, dimnames = list(c("a", "b"), c("x", "y"))),
  matrix_null_dimnames = structure(1:4, dim = c(2L, 2L), dimnames = list(NULL, NULL)),
  matrix_chr = matrix(c("a", NA, "c", "d"), 2),
  matrix_lgl_na = matrix(NA, 2, 2),
  matrix_dbl_inf = matrix(c(1.5, Inf, NA, 2), 2),
  matrix_empty = matrix(numeric(0), 0, 3),
  matrix_1x1 = matrix(7L, 1, 1),
  array_3d = array(1:24, c(2, 3, 4)),
  df = data.frame(x = 1:3, y = c("a", "b", "c"), z = c(TRUE, NA, FALSE)),
  df_factor = data.frame(f = factor(c("a", "b")), n = c(0.5, 1)),
  df_date = data.frame(d = as.Date(c("2024-01-01", "2024-01-02"))),
  df_rownames = data.frame(x = 1:2, row.names = c("r1", "r2")),
  df_subset = data.frame(x = 1:3, y = 4:6)[2:3, , drop = FALSE],
  df_int_rownames = data.frame(x = 1:3, row.names = c(10L, 20L, 30L)),
  df_empty = data.frame(),
  df_zero_rows = data.frame(x = integer(0), y = character(0)),
  df_one_col_na = data.frame(x = c(NA_character_, NA_character_)),
  df_matrix_col = {
    d <- data.frame(id = 1:2)
    d$m <- matrix(1:4, 2)
    d
  },
  list_named = list(a = 1, b = "x", c = NULL),
  list_nested = list(a = list(b = list(c = 1:3, d = list(e = "deep")))),
  list_unnamed_scalars = list(1, "a", TRUE, NULL),
  list_unnamed_vectors = list(c(1, 2), c("a", "b")),
  list_unnamed_mixed = list(1, c(2, 3), NULL),
  list_of_lists = list(list(1, 2), list(a = 3)),
  list_of_named = list(list(a = 1), list(a = 2)),
  list_partial_names = list(a = 1, 2),
  list_dup_names = list(a = 1, a = 2),
  list_empty_name = structure(list(1, 2), names = c("", "x")),
  list_empty = list(),
  list_empty_named = structure(list(), names = character(0)),
  list_of_nulls = list(NULL, NULL),
  list_with_null_and_list = list(NULL, list(a = 1)),
  list_with_matrix = list(M = matrix(1:4, 2), v = c(a = 1)),
  list_with_df = list(d = data.frame(x = 1:2), n = 1L),
  list_with_empty = list(a = character(0), b = list(), c = structure(list(), names = character(0)))
)

for (nm in names(corpus)) {
  test_that(paste("round trip:", nm), {
    expect_roundtrip(corpus[[nm]], label = nm)
  })
}

test_that("negative zero keeps its sign", {
  expect_identical(1 / roundtrip(-0), -Inf)
  expect_identical(1 / roundtrip(c(-0, 0)), c(-Inf, Inf))
})

test_that("NA and NaN stay distinct inside doubles", {
  y <- roundtrip(c(NA, NaN, 1))
  expect_true(is.na(y[1]) && !is.nan(y[1]))
  expect_true(is.nan(y[2]))
})

test_that("names with NA survive", {
  v <- c(a = 1, b = 2)
  names(v)[2] <- NA
  expect_roundtrip(v)
})

test_that("POSIXct keeps the tz attribute as written", {
  expect_null(attr(roundtrip(corpus$posixct_no_tzone), "tzone"))
  expect_identical(attr(roundtrip(corpus$posixct_local), "tzone"), "")
  expect_identical(attr(roundtrip(corpus$posixct_ny), "tzone"), "America/New_York")
})

test_that("POSIXct is rounded, not truncated, to the millisecond", {
  x <- as.POSIXct("2024-01-01 10:00:00.123", tz = "UTC")
  expect_match(encode_text(x), "10:00:00.123Z", fixed = TRUE)
  y <- structure(1704103200.9996, class = c("POSIXct", "POSIXt"), tzone = "UTC")
  expect_match(encode_text(y), "10:00:01.000Z", fixed = TRUE)
})

# Wire format -----------------------------------------------------------------

test_that("scalars, arrays, and typed wrappers look as specified", {
  expect_identical(encode_text(NULL, pretty = FALSE), "null")
  expect_identical(encode_text(TRUE, pretty = FALSE), "true")
  expect_identical(encode_text(1L, pretty = FALSE), "1")
  expect_identical(encode_text(1, pretty = FALSE), "1.0")
  expect_identical(encode_text(0.1 + 0.2, pretty = FALSE), "0.30000000000000004")
  expect_identical(encode_text(1e16, pretty = FALSE), "1e+16")
  expect_identical(encode_text(-0, pretty = FALSE), "-0.0")
  expect_identical(encode_text("a", pretty = FALSE), "\"a\"")
  expect_identical(encode_text(c(1L, NA), pretty = FALSE), "[1,null]")
  expect_identical(encode_text(c(0.5, 0.75), pretty = FALSE), "[0.5,0.75]")
  expect_identical(encode_text(c("a", "b"), pretty = FALSE), "[\"a\",\"b\"]")
  expect_identical(encode_text(NA, pretty = FALSE), "{\"$type\":\"logical\",\"value\":[null]}")
  expect_identical(encode_text(NA_character_, pretty = FALSE), "{\"$type\":\"character\",\"value\":[null]}")
  expect_identical(encode_text(character(0), pretty = FALSE), "{\"$type\":\"character\",\"value\":[]}")
  expect_identical(
    encode_text(c(0.5, Inf, -Inf, NaN, NA), pretty = FALSE),
    "{\"$type\":\"double\",\"value\":[0.5,\"inf\",\"-inf\",\"NaN\",null]}"
  )
  expect_identical(
    encode_text(c(a = 1L), pretty = FALSE),
    "{\"$type\":\"integer\",\"names\":[\"a\"],\"value\":[1]}"
  )
  expect_identical(
    encode_text(as.Date(c("2024-01-01", NA)), pretty = FALSE),
    "{\"$type\":\"Date\",\"value\":[\"2024-01-01\",null]}"
  )
  expect_identical(
    encode_text(as.POSIXct("2024-01-01 10:00:00", tz = "UTC"), pretty = FALSE),
    "{\"$type\":\"POSIXct\",\"tz\":\"UTC\",\"value\":[\"2024-01-01T10:00:00.000Z\"]}"
  )
  expect_identical(
    encode_text(as.POSIXct("2024-07-01 10:00:00", tz = "America/New_York"), pretty = FALSE),
    "{\"$type\":\"POSIXct\",\"tz\":\"America/New_York\",\"value\":[\"2024-07-01T10:00:00.000-04:00\"]}"
  )
  expect_identical(
    encode_text(as.difftime(90, units = "secs"), pretty = FALSE),
    "{\"$type\":\"difftime\",\"units\":\"secs\",\"value\":[90.0]}"
  )
  expect_identical(
    encode_text(factor(c("a", NA), levels = c("a", "b")), pretty = FALSE),
    "{\"$type\":\"factor\",\"levels\":[\"a\",\"b\"],\"value\":[\"a\",null]}"
  )
  expect_identical(
    encode_text(factor("a", levels = "a", ordered = TRUE), pretty = FALSE),
    "{\"$type\":\"factor\",\"levels\":[\"a\"],\"ordered\":true,\"value\":[\"a\"]}"
  )
  expect_identical(
    encode_text(matrix(1:6, 2, dimnames = list(c("a", "b"), NULL)), pretty = FALSE),
    "{\"$type\":\"array\",\"storage\":\"integer\",\"dim\":[2,3],\"dimnames\":[[\"a\",\"b\"],null],\"value\":[1,2,3,4,5,6]}"
  )
  expect_identical(
    encode_text(matrix(c(1.5, 2, 3, 4), 2), pretty = FALSE),
    "{\"$type\":\"array\",\"storage\":\"double\",\"dim\":[2,2],\"value\":[1.5,2.0,3.0,4.0]}"
  )
  expect_identical(
    encode_text(data.frame(x = 1:2, y = c("a", "b")), pretty = FALSE),
    "{\"$type\":\"data.frame\",\"nrow\":2,\"columns\":{\"x\":[1,2],\"y\":[\"a\",\"b\"]}}"
  )
  expect_identical(
    encode_text(data.frame(x = 1:2, row.names = c("r1", "r2")), pretty = FALSE),
    "{\"$type\":\"data.frame\",\"nrow\":2,\"row.names\":[\"r1\",\"r2\"],\"columns\":{\"x\":[1,2]}}"
  )
  expect_identical(encode_text(list(a = 1, b = NULL), pretty = FALSE), "{\"a\":1.0,\"b\":null}")
  expect_identical(encode_text(list(), pretty = FALSE), "{\"$type\":\"list\",\"value\":[]}")
  expect_identical(encode_text(structure(list(), names = character(0)), pretty = FALSE), "{}")
  expect_identical(encode_text(list(1, "a"), pretty = FALSE), "{\"$type\":\"list\",\"value\":[1.0,\"a\"]}")
  expect_identical(
    encode_text(list(a = 1, 2), pretty = FALSE),
    "{\"$type\":\"list\",\"names\":[\"a\",\"\"],\"value\":[1.0,2.0]}"
  )
  expect_identical(encode_text(list(c(1, 2), "a"), pretty = FALSE), "[[1.0,2.0],\"a\"]")
})

test_that("strings are escaped per RFC 8259 and non-ASCII is kept as UTF-8", {
  expect_identical(
    encode_text("q\" b\\ n\n t\t r\r x\001 bs\b ff\f", pretty = FALSE),
    "\"q\\\" b\\\\ n\\n t\\t r\\r x\\u0001 bs\\b ff\\f\""
  )
  expect_identical(encode_text("caf\u00e9", pretty = FALSE), "\"caf\u00e9\"")
  bad <- "\xff"
  expect_error(encode_text(bad), class = "shinysnap_unsupported_value")
})

test_that("pretty printing keeps short containers inline and expands long ones", {
  txt <- encode_text(list(dim = c(2L, 3L), value = 1:6))
  expect_identical(txt, "{\"dim\": [2, 3], \"value\": [1, 2, 3, 4, 5, 6]}\n")
  long <- encode_text(list(a = seq_len(40), b = "x"))
  lines <- strsplit(long, "\n", fixed = TRUE)[[1]]
  expect_identical(lines[1], "{")
  expect_identical(lines[2], "  \"a\": [")
  expect_identical(lines[3], "    1,")
  expect_identical(lines[length(lines) - 1], "  \"b\": \"x\"")
  expect_identical(lines[length(lines)], "}")
  expect_match(long, "\n$")
  expect_identical(decode_text(long), list(a = seq_len(40), b = "x"))
})

test_that("output is deterministic", {
  x <- corpus[names(corpus) != "null"]
  expect_identical(encode_text(x), encode_text(x))
})

# Reading hand-written JSON --------------------------------------------------

test_that("plain JSON reads back as the natural R value", {
  expect_identical(decode_text("1"), 1L)
  expect_identical(decode_text("1.0"), 1)
  expect_identical(decode_text("1e2"), 100)
  expect_identical(decode_text("[1, 2]"), c(1L, 2L))
  expect_identical(decode_text("[1, 2.5]"), c(1, 2.5))
  expect_identical(decode_text("[1, null]"), c(1L, NA))
  expect_identical(decode_text("[\"a\", null]"), c("a", NA))
  expect_identical(decode_text("[true, false]"), c(TRUE, FALSE))
  expect_identical(decode_text("[null, null]"), c(NA, NA))
  expect_identical(decode_text("[]"), list())
  expect_identical(decode_text("{}"), structure(list(), names = character(0)))
  expect_identical(decode_text("{\"a\": null}"), list(a = NULL))
  expect_identical(decode_text("[[1, 2], [3]]"), list(c(1L, 2L), 3L))
  expect_identical(decode_text("[{\"a\": 1}, 2]"), list(list(a = 1L), 2L))
  expect_identical(decode_text("{\"$type\": \"integer\", \"value\": 1}"), 1L)
  expect_identical(decode_text("{\"$type\": \"double\", \"value\": [\"1.5\", 2]}"), c(1.5, 2))
  expect_identical(decode_text("{\"$type\": \"matrix\", \"storage\": \"double\", \"dim\": [1, 2], \"value\": [1, 2]}"), matrix(c(1, 2), 1))
  expect_identical(
    decode_text("{\"$type\": \"POSIXct\", \"tz\": \"UTC\", \"value\": [\"2024-01-01T10:00:00Z\", \"2024-01-01T10:00:00+0100\"]}"),
    as.POSIXct(c("2024-01-01 10:00:00", "2024-01-01 09:00:00"), tz = "UTC")
  )
  expect_identical(
    decode_text("{\"$type\": \"POSIXct\", \"value\": [\"2024-01-01T10:00:00\"]}"),
    structure(1704103200, class = c("POSIXct", "POSIXt"))
  )
})

test_that("unknown $type errors with the id, or is kept on request", {
  txt <- "{\"$type\": \"quaternion\", \"value\": [1, 2, 3, 4]}"
  err <- expect_error(decode_text(txt), class = "shinysnap_unknown_type")
  expect_match(conditionMessage(err), "inputs$x", fixed = TRUE)
  expect_match(conditionMessage(err), "quaternion", fixed = TRUE)
  expect_identical(err$path, "inputs$x")
  kept <- decode_text(txt, unknown_types = "keep")
  expect_identical(kept[["$type"]], "quaternion")
  expect_identical(kept$value, list(1L, 2L, 3L, 4L))
})

test_that("malformed typed values error with the id", {
  bad <- c(
    "{\"$type\": 1}",
    "{\"$type\": \"double\"}",
    "{\"$type\": \"double\", \"value\": [\"abc\"]}",
    "{\"$type\": \"double\", \"value\": [true]}",
    "{\"$type\": \"integer\", \"value\": [1.5]}",
    "{\"$type\": \"integer\", \"value\": [1e10]}",
    "{\"$type\": \"integer\", \"value\": [\"1\"]}",
    "{\"$type\": \"logical\", \"value\": [1]}",
    "{\"$type\": \"character\", \"value\": [1]}",
    "{\"$type\": \"character\", \"value\": {\"a\": 1}}",
    "{\"$type\": \"character\", \"value\": [[1]]}",
    "{\"$type\": \"character\", \"names\": [\"a\"], \"value\": [\"x\", \"y\"]}",
    "{\"$type\": \"Date\", \"value\": [\"2024-13-01\"]}",
    "{\"$type\": \"Date\", \"value\": [\"2024-01-01T00:00\"]}",
    "{\"$type\": \"POSIXct\", \"value\": [\"nope\"]}",
    "{\"$type\": \"POSIXct\", \"value\": [\"2024-13-01T00:00:00Z\"]}",
    "{\"$type\": \"POSIXct\", \"tz\": 1, \"value\": []}",
    "{\"$type\": \"difftime\", \"units\": \"fortnights\", \"value\": [1]}",
    "{\"$type\": \"difftime\", \"value\": [1]}",
    "{\"$type\": \"factor\", \"levels\": [\"a\"], \"value\": [\"b\"]}",
    "{\"$type\": \"factor\", \"levels\": [\"a\"], \"ordered\": \"yes\", \"value\": [\"a\"]}",
    "{\"$type\": \"array\", \"storage\": \"integer\", \"dim\": [2, 2], \"value\": [1, 2, 3]}",
    "{\"$type\": \"array\", \"storage\": \"complex\", \"dim\": [1], \"value\": [1]}",
    "{\"$type\": \"array\", \"storage\": \"integer\", \"value\": [1]}",
    "{\"$type\": \"array\", \"storage\": \"integer\", \"dim\": [-1], \"value\": []}",
    "{\"$type\": \"array\", \"storage\": \"integer\", \"dim\": [1, 2], \"dimnames\": [null], \"value\": [1, 2]}",
    "{\"$type\": \"array\", \"storage\": \"integer\", \"dim\": [1, 2], \"dimnames\": [null, [\"a\"]], \"value\": [1, 2]}",
    "{\"$type\": \"data.frame\", \"nrow\": -1, \"columns\": {}}",
    "{\"$type\": \"data.frame\", \"nrow\": 2, \"columns\": {\"x\": [1]}}",
    "{\"$type\": \"data.frame\", \"nrow\": 1, \"columns\": [1]}",
    "{\"$type\": \"data.frame\", \"nrow\": 1, \"row.names\": [\"a\", \"b\"], \"columns\": {\"x\": [1]}}",
    "{\"$type\": \"data.frame\", \"nrow\": 2, \"row.names\": [\"a\", \"a\"], \"columns\": {\"x\": [1, 2]}}",
    "{\"$type\": \"list\"}",
    "{\"$type\": \"list\", \"value\": {\"a\": 1}}",
    "{\"$type\": \"list\", \"names\": [\"a\"], \"value\": [1, 2]}",
    "{\"$type\": \"rds\"}",
    "{\"$type\": \"rds\", \"base64\": \"not base64!!\"}",
    "{\"$type\": \"rds\", \"path\": \"objects/x.rds\"}",
    "[1, \"a\"]",
    "[true, 1]",
    "{\"a\": 1, \"a\": 2}",
    "{\"\": 1}",
    "{\"$other\": 1}"
  )
  for (txt in bad) {
    err <- expect_error(decode_text(txt, trust = TRUE), class = "shinysnap_format_error")
    expect_match(conditionMessage(err), "inputs$x", fixed = TRUE, label = txt)
  }
})

# Unsupported values and trust gating ----------------------------------------

test_that("unsupported values error naming the id and the class", {
  cases <- list(
    env = new.env(),
    fun = mean,
    complex = 1i,
    raw = as.raw(1),
    foo = structure(1, class = "foo"),
    action = structure(0L, class = c("shinyActionButtonValue", "integer")),
    posixlt = as.POSIXlt("2024-01-01", tz = "UTC"),
    asis = I(1:3),
    nested = list(a = list(b = new.env()))
  )
  for (nm in names(cases)) {
    err <- expect_error(encode_text(cases[[nm]]), class = "shinysnap_unsupported_value")
    expect_match(conditionMessage(err), "inputs$x", fixed = TRUE, label = nm)
  }
  err <- expect_error(encode_text(structure(1, class = "foo")))
  expect_match(conditionMessage(err), "class foo", fixed = TRUE)
  err <- expect_error(encode_text(list(a = list(b = new.env()))))
  expect_identical(err$path, "inputs$x$a$b")
  expect_match(conditionMessage(err), "environment", fixed = TRUE)
})

test_that("names starting with $ are reserved", {
  expect_error(encode_text(list("$type" = 1)), class = "shinysnap_unsupported_value")
  expect_error(encode_text(list("$other" = 1)), class = "shinysnap_unsupported_value")
  expect_error(encode_text(data.frame(check.names = FALSE, "$x" = 1)), class = "shinysnap_unsupported_value")
})

test_that("unsupported = 'rds' embeds objects that need trust = TRUE to read", {
  x <- list(keep = 1L, opaque = structure(list(1), class = "foo"))
  txt <- encode_text(x, unsupported = "rds")
  expect_match(txt, "\"$type\": \"rds\"", fixed = TRUE)
  expect_match(txt, "\"class\": [\"foo\"]", fixed = TRUE)
  expect_false(grepl("\n\"", txt, fixed = TRUE))

  ctx <- codec_ctx()
  y <- decode_value(jsonlite::parse_json(txt, simplifyVector = FALSE), "inputs$x", ctx)
  expect_identical(y, list(keep = 1L, opaque = NULL))
  expect_identical(ctx$untrusted, "inputs$x$opaque")

  z <- decode_text(txt, trust = TRUE)
  expect_identical(z, x)
})

test_that("verbose notes report conversions and dropped attributes", {
  tb <- structure(list(x = 1:2), class = c("tbl_df", "tbl", "data.frame"), row.names = c(NA_integer_, -2L))
  ctx <- codec_ctx(verbose = TRUE)
  ir <- encode_value(tb, "values$tb", ctx)
  expect_match(ctx$notes, "tibble", all = FALSE)
  expect_identical(decode_text(json_render(ir)), data.frame(x = 1:2))

  ctx <- codec_ctx(verbose = TRUE)
  encode_value(structure(1:3, foo = "bar"), "inputs$v", ctx)
  expect_match(ctx$notes, "foo", all = FALSE)

  ctx <- codec_ctx(verbose = TRUE)
  encode_value(structure(as.Date("2024-01-01"), class = c("special", "Date")), "inputs$d", ctx)
  expect_match(ctx$notes, "special", all = FALSE)

  ctx <- codec_ctx(verbose = TRUE)
  encode_value(matrix(1:4, 2, dimnames = list(r = c("a", "b"), c = c("x", "y"))), "inputs$m", ctx)
  expect_match(ctx$notes, "dimnames", all = FALSE)

  ctx <- codec_ctx(verbose = FALSE)
  encode_value(tb, "values$tb", ctx)
  expect_length(ctx$notes, 0)
})

test_that("subclasses of known types decode as the base type", {
  x <- structure(as.Date("2024-01-01"), class = c("special", "Date"))
  expect_identical(roundtrip(x), as.Date("2024-01-01"))
  d <- structure(c(1, 2), units = "secs", class = c("hms", "difftime"))
  expect_identical(roundtrip(d), as.difftime(c(1, 2), units = "secs"))
})

# Additional edge cases -------------------------------------------------------

test_that("all-NA POSIXct round-trips", {
  x <- as.POSIXct(c(NA_character_, NA_character_), tz = "UTC")
  expect_roundtrip(x)
})

test_that("S4 objects and unsupported storage types are unsupported", {
  methods::setClass("SnapS4Test", representation(x = "numeric"), where = environment())
  obj <- methods::new("SnapS4Test", x = 1)
  expect_error(encode_text(obj), class = "shinysnap_unsupported_value")
  expect_error(encode_text(matrix(1i, 1, 1)), class = "shinysnap_unsupported_value")
})

test_that("data frames need unique, non-empty column names", {
  dup <- data.frame(a = 1, a = 2, check.names = FALSE)
  err <- expect_error(encode_text(dup), class = "shinysnap_unsupported_value")
  expect_match(conditionMessage(err), "duplicated", fixed = TRUE)
  unnamed <- structure(list(1), names = "", class = "data.frame", row.names = 1L)
  expect_error(encode_text(unnamed), "non-empty names", class = "shinysnap_unsupported_value")
})

test_that("wrapper fields accept scalar shorthands", {
  expect_identical(
    decode_text("{\"$type\": \"integer\", \"names\": \"a\", \"value\": 1}"),
    c(a = 1L)
  )
  expect_identical(
    decode_text("{\"$type\": \"factor\", \"levels\": \"a\", \"value\": \"a\"}"),
    factor("a")
  )
  expect_identical(
    decode_text("{\"$type\": \"array\", \"storage\": \"integer\", \"dim\": 2, \"value\": [1, 2]}"),
    array(1:2, 2L)
  )
  expect_identical(
    decode_text("{\"$type\": \"array\", \"storage\": \"integer\", \"dim\": [1, 2], \"dimnames\": [\"r\", null], \"value\": [1, 2]}"),
    matrix(1:2, 1, dimnames = list("r", NULL))
  )
  expect_identical(
    decode_text("{\"$type\": \"data.frame\", \"nrow\": 1, \"row.names\": \"a\", \"columns\": {\"x\": 1}}"),
    data.frame(x = 1L, row.names = "a")
  )
  expect_identical(decode_text("{\"$type\": \"data.frame\", \"nrow\": 0}"), data.frame())
  expect_identical(decode_text("{\"$type\": \"list\", \"value\": null}"), list())
  expect_identical(decode_text("{\"$type\": \"list\", \"value\": 1}"), list(1L))
})

test_that("non-scalar entries in wrapper fields are rejected", {
  bad <- c(
    "{\"$type\": \"factor\", \"levels\": [[1]], \"value\": []}",
    "{\"$type\": \"array\", \"storage\": \"integer\", \"dim\": [[1]], \"value\": [1]}",
    "{\"$type\": \"array\", \"storage\": \"integer\", \"dim\": [1], \"dimnames\": [[[1]]], \"value\": [1]}",
    "{\"$type\": \"data.frame\", \"nrow\": 1, \"row.names\": [[1]], \"columns\": {\"x\": [1]}}"
  )
  for (txt in bad) {
    expect_error(decode_text(txt), class = "shinysnap_format_error", label = txt)
  }
})

test_that("bare arrays of long vectors expand one element per line", {
  x <- list(seq_len(30), seq_len(30) + 0.5)
  txt <- encode_text(x)
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  expect_identical(lines[1], "[")
  expect_identical(lines[2], "  [")
  expect_identical(lines[3], "    1,")
  expect_identical(lines[length(lines)], "]")
  expect_identical(decode_text(txt), x)
})
