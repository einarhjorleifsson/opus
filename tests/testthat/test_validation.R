hh_path <- system.file("HH.parquet", package = "opus")

test_that("op_validate_spec validates YAML dictionary", {
  dict_path <- system.file("DATRAS-data-dict.yaml", package = "opus")
  result <- op_validate_spec(dict_path = dict_path)
  expect_type(result, "list")
  expect_true("valid" %in% names(result))
  expect_true("exit_status" %in% names(result))
  expect_type(result$valid, "logical")
  expect_type(result$exit_status, "integer")
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
  expect_type(result$valid, "logical")
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
  expect_type(result$valid, "logical")
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
  expect_type(result$spec_valid, "logical")
  expect_type(result$meta_valid, "logical")
  expect_type(result$data_valid, "logical")
})
