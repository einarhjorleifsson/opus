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
  dict_path <- system.file("DATRAS-data-dict.yaml", package = "opus")
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

test_that("op_inspect_parquet returns schema", {
  skip_if_not(file.exists(hh_path), "HH.parquet not found")

  result <- op_inspect_parquet(hh_path)
  expect_type(result, "list")
  expect_true("output" %in% names(result))
  expect_true("command" %in% names(result))
  expect_type(result$output, "character")
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
