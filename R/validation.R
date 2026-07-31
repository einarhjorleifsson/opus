#' Validate opus specs against real DATRAS data
#'
#' Thin R wrappers around the data-dict CLI for building and validating
#' opus YAML dictionaries. Use these in the development loop:
#' (1) curate YAML, (2) inspect real data, (3) validate, (4) refine YAML.
#'
#' These are development tools, not shipped API.

#' Check YAML dictionary conformance to data-dict.yaml spec
#'
#' @param dict_path Path to YAML dictionary (default: inst/DATRAS-data-dict.yaml)
#' @param cli_bin Path to data-dict CLI binary
#'
#' @return List: (valid = TRUE/FALSE, errors = character vector, raw_output = lines)
#' @export
op_validate_spec <- function(dict_path = "inst/DATRAS-data-dict.yaml",
                             cli_bin = "~/garbage/data-dict/target/release/data-dict") {
  cli_bin <- path.expand(cli_bin)
  dict_path <- path.expand(dict_path)

  if (!file.exists(cli_bin)) {
    stop("data-dict CLI not found at ", cli_bin, call. = FALSE)
  }

  if (!file.exists(dict_path)) {
    stop("Dictionary not found at ", dict_path, call. = FALSE)
  }

  output <- system2(cli_bin, c("validate-spec", dict_path),
                    stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status") %||% 0L

  list(
    valid       = (status == 0L),
    exit_status = status,
    output      = output,
    command     = paste(cli_bin, "validate-spec", dict_path)
  )
}

#' Inspect parquet file schema and sample
#'
#' See what data-dict CLI sees in a parquet file.
#'
#' @param parquet_path Path to parquet file
#' @param cli_bin Path to data-dict CLI binary
#'
#' @return List: (schema = JSON, raw_output = lines)
#' @export
op_inspect_parquet <- function(parquet_path,
                               cli_bin = "~/garbage/data-dict/target/release/data-dict") {
  cli_bin <- path.expand(cli_bin)
  parquet_path <- path.expand(parquet_path)

  if (!file.exists(cli_bin)) {
    stop("data-dict CLI not found at ", cli_bin, call. = FALSE)
  }

  if (!file.exists(parquet_path)) {
    stop("Parquet file not found at ", parquet_path, call. = FALSE)
  }

  output <- system2(cli_bin, c("types", "parquet", parquet_path),
                    stdout = TRUE, stderr = TRUE)

  list(
    output  = output,
    command = paste(cli_bin, "types parquet", parquet_path)
  )
}

#' Validate dataset metadata against dictionary
#'
#' Check that column names and types in the parquet file match the dictionary.
#'
#' @param data_path Path to parquet file
#' @param table Table name to validate
#' @param dict_path Path to dictionary YAML
#' @param cli_bin Path to data-dict CLI binary
#'
#' @return List: (valid = T/F, exit_status, result = JSON, raw_output, stderr)
#' @export
op_validate_meta <- function(data_path, table,
                             dict_path = "inst/DATRAS-data-dict.yaml",
                             cli_bin = "~/garbage/data-dict/target/release/data-dict") {
  .validate_via_dict("validate-meta", data_path, table, dict_path, cli_bin)
}

#' Validate dataset values against dictionary constraints
#'
#' Check that actual values in the parquet file match constraints, ranges, and enums.
#'
#' @param data_path Path to parquet file
#' @param table Table name to validate
#' @param dict_path Path to dictionary YAML
#' @param cli_bin Path to data-dict CLI binary
#'
#' @return List: (valid = T/F, exit_status, result = JSON, raw_output, stderr)
#' @export
op_validate_data <- function(data_path, table,
                             dict_path = "inst/DATRAS-data-dict.yaml",
                             cli_bin = "~/garbage/data-dict/target/release/data-dict") {
  .validate_via_dict("validate-data", data_path, table, dict_path, cli_bin)
}

#' Run full validation suite
#'
#' Convenience wrapper: run spec check + meta + data validation in sequence.
#'
#' @param data_path Path to parquet file
#' @param table Table name to validate
#' @param dict_path Path to dictionary YAML
#' @param cli_bin Path to data-dict CLI binary
#'
#' @return List: (spec_valid, meta_valid, data_valid, spec_output, meta_result, data_result)
#' @export
op_validate_full <- function(data_path, table,
                             dict_path = "inst/DATRAS-data-dict.yaml",
                             cli_bin = "~/garbage/data-dict/target/release/data-dict") {
  spec_check <- op_validate_spec(dict_path, cli_bin)
  meta_check <- op_validate_meta(data_path, table, dict_path, cli_bin)
  data_check <- op_validate_data(data_path, table, dict_path, cli_bin)

  list(
    spec_valid  = spec_check$valid,
    meta_valid  = meta_check$valid,
    data_valid  = data_check$valid,
    spec_output = spec_check$output,
    meta_result = meta_check$result,
    data_result = data_check$result
  )
}

# ============================================================================
# Internal helper
# ============================================================================

#' @keywords internal
.validate_via_dict <- function(subcommand, data_path, table, dict_path, cli_bin) {
  cli_bin <- normalizePath(path.expand(cli_bin))
  dict_path <- normalizePath(path.expand(dict_path))

  if (!file.exists(cli_bin)) {
    stop("data-dict CLI not found at ", cli_bin, call. = FALSE)
  }

  if (!file.exists(dict_path)) {
    stop("Dictionary not found at ", dict_path, call. = FALSE)
  }

  # Read dictionary to check if source exists
  dict_lines <- readLines(dict_path)
  table_idx <- which(grepl(paste0("^- name: ", table, "$"), dict_lines))

  if (length(table_idx) != 1) {
    stop("Table '", table, "' not found in dictionary", call. = FALSE)
  }

  # Find the end of this table's definition
  start_idx <- table_idx
  end_idx <- length(dict_lines)
  for (i in (start_idx + 1):length(dict_lines)) {
    if (grepl("^- name: ", dict_lines[i])) {
      end_idx <- i - 1
      break
    }
  }

  # Check if source exists in the table
  table_text <- dict_lines[start_idx:end_idx]
  has_source <- any(grepl("^  source:", table_text))

  # Determine which dictionary to use and where to run from
  if (nzchar(data_path)) {
    # If data_path provided, inject it into a temp dictionary
    data_path <- normalizePath(path.expand(data_path))
    if (!file.exists(data_path)) {
      stop("Data file not found at ", data_path, call. = FALSE)
    }

    tmp_dict <- tempfile(fileext = ".yaml")
    on.exit(unlink(tmp_dict), add = TRUE)

    # Remove existing source if present, then inject new one
    if (has_source) {
      source_idx <- which(grepl("^  source:", table_text))
      # Remove the source section
      table_text <- table_text[-source_idx]
    }

    # Reconstruct with injected source
    source_lines <- c(
      dict_lines[1:(start_idx - 1)],
      table_text,
      "  source:",
      paste0("    parquet: ", data_path),
      if (end_idx < length(dict_lines)) dict_lines[(end_idx + 1):length(dict_lines)]
    )
    writeLines(source_lines, tmp_dict)
    dict_to_use <- tmp_dict
    run_dir <- tempdir()
  } else {
    # No data_path provided, must use existing source
    if (!has_source) {
      stop("No data_path provided and no source defined in dictionary for table '", table, "'", call. = FALSE)
    }
    dict_to_use <- dict_path
    run_dir <- dirname(dict_path)
  }

  # Run validation from the appropriate directory
  args <- c(subcommand, basename(dict_to_use), "--table", table, "--json")
  err_file <- tempfile()
  on.exit(unlink(err_file), add = TRUE)

  old_wd <- setwd(run_dir)
  on.exit(setwd(old_wd), add = TRUE)

  stdout_lines <- system2(cli_bin, args, stdout = TRUE, stderr = err_file)
  status <- attr(stdout_lines, "status") %||% 0L
  stderr_lines <- if (file.exists(err_file)) readLines(err_file, warn = FALSE) else character(0)

  raw_stdout <- paste(stdout_lines, collapse = "\n")
  parsed <- tryCatch(
    jsonlite::fromJSON(raw_stdout, simplifyVector = FALSE),
    error = function(e) NULL
  )

  list(
    valid       = (status == 0L),
    exit_status = status,
    result      = parsed,
    raw_stdout  = stdout_lines,
    stderr      = stderr_lines,
    command     = paste(c(cli_bin, args), collapse = " ")
  )
}

#' Flag rows with violations against dictionary constraints
#'
#' Adds a `.flag` column to parquet data, marking rows that violate constraints.
#' Since data-dict CLI v0.0.1 reports violations but doesn't list row numbers,
#' this function computes violating rows by checking each constraint in the YAML.
#'
#' @param data_path Path to parquet file
#' @param table Table name to check
#' @param dict_path Path to dictionary YAML
#'
#' @return Data frame with `.flag` column. Value is NA for valid rows,
#'   or violation codes in format "ColumnName:ViolationCode" for violations.
#'   For example: "HaulNumber:D01_required", "Year:D04_range", or
#'   "HaulNumber:D01_required;Year:D04_range" for multiple violations.
#'   Violations are separated by semicolons.
#'
#' @export
op_flag_violations <- function(data_path, table,
                              dict_path = "inst/DATRAS-data-dict.yaml") {
  dict_path <- path.expand(dict_path)
  if (!file.exists(dict_path)) {
    stop("Dictionary not found at ", dict_path, call. = FALSE)
  }

  if (!file.exists(data_path)) {
    stop("Data file not found at ", data_path, call. = FALSE)
  }

  # Load dictionary and data
  dict <- yaml::read_yaml(dict_path)
  df <- arrow::read_parquet(data_path)

  # Find target table
  table_def <- NULL
  for (tbl in dict$tables) {
    if (tbl$name == table) {
      table_def <- tbl
      break
    }
  }

  if (is.null(table_def)) {
    stop("Table '", table, "' not found in dictionary", call. = FALSE)
  }

  # Initialize flag column
  df <- df |> dplyr::mutate(.flag = NA_character_)

  # Check each column for constraint violations (skip columns with no constraints)
  for (col_def in table_def$columns) {
    col_name <- col_def$name

    if (!(col_name %in% names(df))) {
      next # Column not in data, skip
    }

    # Skip if no constraints to check
    has_required <- !is.null(col_def$constraints) && "required" %in% col_def$constraints
    has_enum <- !is.null(col_def$values) && col_def$type == "enum"
    has_range <- !is.null(col_def$range) && col_def$type %in% c("number(ordinal)", "number(quantity)", "date", "datetime")
    if (!has_required && !has_enum && !has_range) next

    col_data <- df[[col_name]]

    # D01: Check required constraint (vectorized)
    if (has_required) {
      null_rows <- which(is.na(col_data))
      if (length(null_rows) > 0) {
        violation <- paste0(col_name, ":D01_required")
        new_flags <- is.na(df$.flag[null_rows])
        df$.flag[null_rows[new_flags]] <- violation
        df$.flag[null_rows[!new_flags]] <- paste0(df$.flag[null_rows[!new_flags]], ";", violation)
      }
    }

    # D04: Check enum constraint (vectorized)
    if (has_enum) {
      valid_values <- if (is.list(col_def$values)) names(unlist(col_def$values)) else col_def$values
      invalid_rows <- which(!is.na(col_data) & !(col_data %in% valid_values))
      if (length(invalid_rows) > 0) {
        violation <- paste0(col_name, ":D04_enum")
        new_flags <- is.na(df$.flag[invalid_rows])
        df$.flag[invalid_rows[new_flags]] <- violation
        df$.flag[invalid_rows[!new_flags]] <- paste0(df$.flag[invalid_rows[!new_flags]], ";", violation)
      }
    }

    # Range check (vectorized)
    if (has_range) {
      min_val <- col_def$range[[1]]
      max_val <- col_def$range[[2]]

      # Handle .inf (infinity)
      if (is.character(min_val) && min_val == ".inf") min_val <- Inf
      if (is.character(max_val) && max_val == ".inf") max_val <- Inf

      out_of_range <- which(!is.na(col_data) & (col_data < min_val | col_data > max_val))
      if (length(out_of_range) > 0) {
        violation <- paste0(col_name, ":D04_range")
        new_flags <- is.na(df$.flag[out_of_range])
        df$.flag[out_of_range[new_flags]] <- violation
        df$.flag[out_of_range[!new_flags]] <- paste0(df$.flag[out_of_range[!new_flags]], ";", violation)
      }
    }
  }

  df
}

# Null coalesce helper
`%||%` <- function(x, y) if (is.null(x)) y else x
