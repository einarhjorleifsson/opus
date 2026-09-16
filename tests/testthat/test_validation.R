# The validation family, asserted on VALUE and not merely on shape.
#
# Until 2026-09-09 every check below read `expect_type(result$valid,
# "logical")`, which passes whether the dictionary validates or not -- a
# dictionary that started failing would have left this suite green. The three
# flags do NOT share an expected state, so they are now asserted separately.
# Measured 2026-09-09 against the staged HH parquet (150,217 rows) with
# data-dict 0.0.3:
#
#   spec_valid  TRUE   the dictionary conforms to data-dict.yaml 0.1.0
#   meta_valid  TRUE   the archive's column names and types match it
#   data_valid  FALSE  -- and correctly so. 9 value-level errors, each an
#                      ICES-side defect already carried in
#                      DATRAS-known-issues.yaml or TODO.md: 8 x D01 (nulls in
#                      a `required` field -- StationName 6,899, HaulDuration
#                      51, HaulLatitude 31,017, HaulLongitude 31,038,
#                      Distance 25,874, BottomDepth 1,732, ShootLatitude 288,
#                      ShootLongitude 317) and 1 x D04 (ThermoCline carries 3
#                      values outside its allowed set). Plus 11 S31 `todo`
#                      warnings, which are notes to ourselves, not defects.
#
# So `data_valid` is deliberately NOT expect_true: asserting it would encode a
# claim this package's own registry contradicts. It keeps the shape check.
# Pinning its error count would be the real ratchet, but the count belongs to
# the whole archive and these tests run against a small bundled fixture, so
# the two numbers are not comparable -- see TODO.md.

hh_path <- system.file("HH.parquet", package = "opus")

test_that("op_validate_spec validates YAML dictionary", {
  dict_path <- system.file("DATRAS-imbus.yaml", package = "opus")
  result <- op_validate_spec(dict_path = dict_path)
  expect_type(result, "list")
  expect_true("valid" %in% names(result))
  expect_true("exit_status" %in% names(result))
  expect_true(result$valid)                    # the dictionary must validate
  expect_identical(result$exit_status, 0L)
})

test_that("op_validate_spec fails with missing CLI", {
  expect_error(
    op_validate_spec(cli_bin = "/nonexistent/data-dict"),
    "data-dict CLI not found"
  )
})

test_that("op_validate_spec fails with missing dictionary", {
  expect_error(
    op_validate_spec(dict_path = "/nonexistent/dict.yaml"),
    "Dictionary not found"
  )
})

test_that("op_inspect_parquet returns the schema it documents", {
  # This asserted `result$output` until 2026-09-09. There is no such field and
  # never was one under `describe --json`; the assertion predates data-dict
  # v0.0.3 (2026-08-04), when `types parquet` was removed and this function
  # was switched over -- see the note on its own @return. The function and its
  # roxygen were both correct; only the test was stale, and it could not say so
  # because it skips on a fixture deleted in 57b34c0.
  skip_if_not(file.exists(hh_path), "HH.parquet not found")

  result <- op_inspect_parquet(hh_path)
  expect_type(result, "list")
  expect_identical(names(result), c("valid", "columns", "raw_output", "command"))
  expect_true(result$valid)

  # `columns` carries the analysis-level `type` AND the physical
  # `parquet_type` side by side, which is the point of it: `Quarter` reads
  # `number` against `INT32 / Integer(i32)`. The coarseness is by design, and
  # the pairing is what lets a caller see both without casting from either.
  expect_s3_class(result$columns, "data.frame")
  expect_identical(names(result$columns), c("name", "type", "parquet_type"))
  expect_gt(nrow(result$columns), 0L)

  expect_type(result$raw_output, "character")
  expect_type(result$command, "character")
})

test_that("op_inspect_parquet fails with missing file", {
  expect_error(
    op_inspect_parquet("/nonexistent/file.parquet"),
    "Parquet file not found"
  )
})

test_that("op_validate_meta validates metadata against dictionary", {
  skip_if_not(file.exists(hh_path), "HH.parquet not found")

  result <- op_validate_meta(hh_path, "HH")
  expect_type(result, "list")
  expect_true("valid" %in% names(result))
  expect_true("exit_status" %in% names(result))
  expect_true("result" %in% names(result))
  # Names and types are a property of the schema, not of the row subset, so
  # this holds for the bundled fixture exactly as for the full archive.
  expect_true(result$valid)
})

test_that("op_validate_meta fails with missing table", {
  skip_if_not(file.exists(hh_path), "HH.parquet not found")

  expect_error(
    op_validate_meta(hh_path, "NONEXISTENT"),
    "Table .* not found in dictionary"
  )
})

test_that("op_validate_data validates data values against constraints", {
  skip_if_not(file.exists(hh_path), "HH.parquet not found")

  result <- op_validate_data(hh_path, "HH")
  expect_type(result, "list")
  expect_true("valid" %in% names(result))
  expect_true("exit_status" %in% names(result))
  expect_true("result" %in% names(result))
  # NOT expect_true -- see the note at the top of this file. Value-level
  # violations in HH are real, documented, and ICES-side.
  expect_type(result$valid, "logical")
  expect_true("problems" %in% names(result$result))
})

test_that("op_validate_data fails with missing table", {
  skip_if_not(file.exists(hh_path), "HH.parquet not found")

  expect_error(
    op_validate_data(hh_path, "NONEXISTENT"),
    "Table .* not found in dictionary"
  )
})

test_that("op_validate_full runs all validation checks", {
  skip_if_not(file.exists(hh_path), "HH.parquet not found")

  result <- op_validate_full(hh_path, "HH")
  expect_type(result, "list")
  expect_true("spec_valid" %in% names(result))
  expect_true("meta_valid" %in% names(result))
  expect_true("data_valid" %in% names(result))
  expect_true(result$spec_valid)
  expect_true(result$meta_valid)
  expect_type(result$data_valid, "logical")   # deliberately not expect_true
})

# --- op_validation_problems(): the accessor contract ------------------------
# These need no CLI and no fixture -- a report is just a parsed list -- so
# unlike everything above they actually run. Both bugs they pin were found
# 2026-09-09 while asserting the flags above, and neither was reachable by any
# existing test.

.fake_report <- function(n = 2) {
  list(
    `$version` = "0.1.0",
    status = if (n > 0) "error" else "ok",
    steps = list(),
    problems = lapply(seq_len(n), function(i) {
      list(code = paste0("D0", i), severity = "error", kind = "data",
           table = "HH", columns = list("StationName"),
           message = paste("problem", i), count = i,
           rows = list(1L, 2L), redacted = FALSE)
    })
  )
}

test_that("op_validation_problems() flattens one row per problem", {
  out <- op_validation_problems(.fake_report(3))
  expect_identical(nrow(out), 3L)
  expect_identical(names(out),
                   c("code", "severity", "kind", "table", "columns",
                     "message", "count", "rows", "redacted"))
  expect_identical(out$code, c("D01", "D02", "D03"))
  expect_identical(out$columns[1], "StationName")
  expect_identical(out$rows[1], "1, 2")
})

test_that("op_validation_problems() unwraps whichever slot the report is in", {
  # The regression. op_validate_spec() puts its report under `$report`,
  # op_validate_meta()/op_validate_data() under `$result`; the accessor read
  # only the top level, so passing what a validate function returned yielded
  # 0 rows against a report holding 20 -- silently, which reads as a clean
  # bill of health.
  rep <- .fake_report(2)
  expect_identical(nrow(op_validation_problems(rep)), 2L)                    # bare
  expect_identical(nrow(op_validation_problems(list(valid = FALSE,
                                                    result = rep))), 2L)     # meta/data
  expect_identical(nrow(op_validation_problems(list(valid = FALSE,
                                                    report = rep))), 2L)     # spec
})

test_that("op_validation_problems() refuses to call a non-report clean", {
  expect_error(op_validation_problems(list(a = 1)), "not a validation report")
  expect_error(op_validation_problems("nope"), "must be a parsed")
  # op_validate_full() carries two reports, so unwrapping one would be a guess
  expect_error(
    op_validation_problems(list(spec_valid = TRUE, meta_result = .fake_report(),
                                data_result = .fake_report())),
    "carries two reports")
})

test_that("op_validation_problems() returns an empty frame for NULL or none", {
  for (x in list(NULL, .fake_report(0))) {
    out <- op_validation_problems(x)
    expect_identical(nrow(out), 0L)
    expect_identical(names(out),
                     c("code", "severity", "kind", "table", "columns",
                       "message", "count", "rows", "redacted"))
  }
})

test_that("op_validate_full() passes cli_bin by name, so it runs at all", {
  # It called op_validate_spec(dict_path, cli_bin) positionally, binding a
  # path to that function's `json` parameter and dying in `if (json)`. The
  # function could never run; its only test skips on the deleted fixture.
  expect_true("cli_bin" %in% names(formals(op_validate_full)))
  expect_identical(names(formals(op_validate_spec))[2], "json")
  expect_error(op_validate_full("/nonexistent.parquet", "HH",
                                cli_bin = "/nonexistent/data-dict"),
               "data-dict CLI not found")
})

# --- .op_dict_for(): the source injection both render/validate paths share ---
# Pure YAML surgery, so these need no CLI and no fixture and actually run.
# Extracted 2026-09-09 when op_render_report() became its second caller; these
# pin the three corners its comment names, none of which had a test.

.dict_fixture <- function() {
  p <- tempfile(fileext = ".yaml")
  writeLines(c(
    "$version: 0.1.0",
    "name: test_dict",
    "tables:",
    "- name: A",
    "  columns:",
    "  - name: x",
    "    type: number",
    "- name: B",
    "  source:",
    "    parquet: /old/stale.parquet",
    "  columns:",
    "  - name: y",
    "    type: string",
    "- name: C",
    "  columns:",
    "  - name: z",
    "    type: string",
    "relationships:",
    "- columns: [A.x, C.z]",
    "glossary:",
    "  thing: a definition"
  ), p)
  p
}

.tbl <- function(y, name) Filter(function(t) identical(t$name, name), y$tables)[[1]]

test_that(".op_dict_for() injects a source and leaves the rest alone", {
  dict <- .dict_fixture(); data <- tempfile(fileext = ".parquet"); file.create(data)
  d <- .op_dict_for(data, "A", dict)
  expect_true(d$temp)
  y <- yaml::read_yaml(d$dict_path)

  expect_identical(.tbl(y, "A")$source$parquet, normalizePath(data))
  expect_identical(length(y$tables), 3L)
  # B keeps its own source, C still has none
  expect_identical(.tbl(y, "B")$source$parquet, "/old/stale.parquet")
  expect_null(.tbl(y, "C")$source)
  # columns survive the surgery
  expect_identical(.tbl(y, "A")$columns[[1]]$name, "x")
})

test_that(".op_dict_for() attaches the source to the LAST table, not to glossary", {
  # A table's block ends at the next UNINDENTED line, not the next `- name:`.
  # The last table has no next `- name:`, so a naive scan runs its block to
  # EOF -- and the injected `source:`, appended after that block, then lands
  # two spaces under whatever top-level key came last. Measured on this
  # fixture: the naive version leaves C with no source at all and puts it at
  # `glossary$source`. Those two assertions are the discriminating ones; the
  # rest confirm nothing else moved.
  dict <- .dict_fixture(); data <- tempfile(fileext = ".parquet"); file.create(data)
  y <- yaml::read_yaml(.op_dict_for(data, "C", dict)$dict_path)

  expect_identical(.tbl(y, "C")$source$parquet, normalizePath(data))
  expect_null(y$glossary$source)
  expect_identical(y$glossary$thing, "a definition")
  expect_false(is.null(y$relationships))
})

test_that(".op_dict_for() replaces an existing source without orphaning it", {
  # `source:` is 2-space indented but its `parquet:` value is deeper. Dropping
  # only the `source:` line leaves that value parented to nothing, which is a
  # YAML parse error rather than a wrong answer.
  dict <- .dict_fixture(); data <- tempfile(fileext = ".parquet"); file.create(data)
  d <- .op_dict_for(data, "B", dict)
  y <- expect_no_error(yaml::read_yaml(d$dict_path))

  expect_identical(.tbl(y, "B")$source$parquet, normalizePath(data))
  expect_identical(length(readLines(d$dict_path)[
    grepl("^  source:", readLines(d$dict_path))]), 1L)   # not two
  expect_false(any(grepl("stale.parquet", readLines(d$dict_path))))
})

test_that(".op_dict_for() uses the dictionary as-is when no data_path is given", {
  dict <- .dict_fixture()
  d <- .op_dict_for("", "B", dict)                    # B declares its own source
  expect_false(d$temp)
  expect_identical(d$dict_path, normalizePath(dict))
  expect_identical(d$run_dir, dirname(normalizePath(dict)))

  expect_error(.op_dict_for("", "A", dict), "no source defined")   # A does not
})

test_that(".op_dict_for() rejects a table the dictionary does not declare", {
  dict <- .dict_fixture()
  expect_error(.op_dict_for("", "NOPE", dict), "not found in dictionary")
})
