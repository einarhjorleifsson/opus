#' Validate opus specs against real DATRAS data
#'
#' Thin R wrappers around the data-dict CLI for building and validating
#' opus YAML dictionaries. Use these in the development loop:
#' (1) curate YAML, (2) inspect real data, (3) validate, (4) refine YAML.
#'
#' **Note**: `op_describe_parquet()` and `op_draft_from_parquet()` require
#' the `describe-command` and `draft-command` branches of data-dict to be
#' merged and built. They will error gracefully if unavailable.
#'
#' These are development tools, not shipped API.

#' Check YAML dictionary conformance to data-dict.yaml spec
#'
#' @param dict_path Path to YAML dictionary (default: inst/DATRAS-imbus.yaml)
#' @param json Logical: also request the structured JSON report (steps +
#'   problems + run info), parsed into `$report`? (default: FALSE, plain-text
#'   `$output` only, for backward compatibility). `validate-spec --json` is a
#'   newer CLI capability (not available when this function was first
#'   written); `op_validate_meta()`/`op_validate_data()` have exposed the
#'   equivalent structured report via their own `$result` all along.
#' @param cli_bin Path to the data-dict CLI binary. Defaults to the first
#'   of \code{$OPUS_DATA_DICT}, \code{data-dict} on \code{$PATH}, or a local
#'   release build; an explicit value is never overridden.
#'
#' @return List: (valid = TRUE/FALSE, exit_status, output = plain-text lines,
#'   report = parsed JSON report when json=TRUE (NULL otherwise), command)
#' @export
op_validate_spec <- function(dict_path = "inst/DATRAS-imbus.yaml",
                             json = FALSE,
                             cli_bin = .op_cli()) {
  cli_bin <- path.expand(cli_bin)
  dict_path <- path.expand(dict_path)

  if (!file.exists(cli_bin)) {
    stop("data-dict CLI not found at ", cli_bin, call. = FALSE)
  }

  if (!file.exists(dict_path)) {
    stop("Dictionary not found at ", dict_path, call. = FALSE)
  }

  args <- c("validate-spec", dict_path, if (json) "--json")
  output <- system2(cli_bin, args, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status") %||% 0L

  report <- if (json) {
    tryCatch(jsonlite::fromJSON(paste(output, collapse = "\n"), simplifyVector = FALSE),
             error = function(e) NULL)
  } else NULL

  list(
    valid       = (status == 0L),
    exit_status = status,
    output      = output,
    report      = report,
    command     = paste(c(cli_bin, args), collapse = " ")
  )
}

#' Inspect parquet file schema
#'
#' See what data-dict CLI sees in a parquet file.
#' Uses `describe --json` to profile the file and extract schema information.
#'
#' **Note**: Prior to data-dict v0.0.3 (2026-08-04), this used `types parquet`.
#' It now uses `describe --json` since `types parquet` was removed.
#'
#' @param parquet_path Path to parquet file
#' @param cli_bin Path to the data-dict CLI binary. Defaults to the first
#'   of \code{$OPUS_DATA_DICT}, \code{data-dict} on \code{$PATH}, or a local
#'   release build; an explicit value is never overridden.
#'
#' @return List: (valid = T/F, columns = data.frame with name/type/parquet_type,
#'   raw_output = JSON text, command)
#' @export
op_inspect_parquet <- function(parquet_path,
                               cli_bin = .op_cli()) {
  cli_bin <- path.expand(cli_bin)
  parquet_path <- path.expand(parquet_path)

  if (!file.exists(cli_bin)) {
    stop("data-dict CLI not found at ", cli_bin, call. = FALSE)
  }

  if (!file.exists(parquet_path)) {
    stop("Parquet file not found at ", parquet_path, call. = FALSE)
  }

  output <- system2(cli_bin, c("describe", parquet_path, "--json"),
                    stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status") %||% 0L
  raw_json <- paste(output, collapse = "\n")

  if (status == 0) {
    parsed <- jsonlite::fromJSON(raw_json, simplifyVector = FALSE)
    columns <- do.call(rbind, lapply(parsed$columns, function(col) {
      data.frame(
        name = col$name,
        type = col$type,
        parquet_type = col$parquet_type,
        stringsAsFactors = FALSE
      )
    }))
    list(
      valid       = TRUE,
      columns     = columns,
      raw_output  = raw_json,
      command     = paste(cli_bin, "describe", parquet_path, "--json")
    )
  } else {
    list(
      valid       = FALSE,
      error       = paste(output, collapse = "\n"),
      raw_output  = raw_json,
      command     = paste(cli_bin, "describe", parquet_path, "--json")
    )
  }
}

#' Validate dataset metadata against dictionary
#'
#' Check that column names and types in the parquet file match the dictionary.
#'
#' @param data_path Path to parquet file
#' @param table Table name to validate
#' @param dict_path Path to dictionary YAML
#' @param cli_bin Path to the data-dict CLI binary. Defaults to the first
#'   of \code{$OPUS_DATA_DICT}, \code{data-dict} on \code{$PATH}, or a local
#'   release build; an explicit value is never overridden.
#'
#' @return List: (valid = T/F, exit_status, result = JSON, raw_output, stderr)
#' @export
op_validate_meta <- function(data_path, table,
                             dict_path = "inst/DATRAS-imbus.yaml",
                             cli_bin = .op_cli()) {
  .validate_via_dict("validate-meta", data_path, table, dict_path, cli_bin)
}

#' Validate dataset values against dictionary constraints
#'
#' Check that actual values in the parquet file match constraints, ranges, and enums.
#'
#' @param data_path Path to parquet file
#' @param table Table name to validate
#' @param dict_path Path to dictionary YAML
#' @param cli_bin Path to the data-dict CLI binary. Defaults to the first
#'   of \code{$OPUS_DATA_DICT}, \code{data-dict} on \code{$PATH}, or a local
#'   release build; an explicit value is never overridden.
#'
#' @return List: (valid = T/F, exit_status, result = JSON, raw_output, stderr)
#' @export
op_validate_data <- function(data_path, table,
                             dict_path = "inst/DATRAS-imbus.yaml",
                             cli_bin = .op_cli()) {
  .validate_via_dict("validate-data", data_path, table, dict_path, cli_bin)
}

#' Run full validation suite
#'
#' Convenience wrapper: run spec check + meta + data validation in sequence.
#'
#' @param data_path Path to parquet file
#' @param table Table name to validate
#' @param dict_path Path to dictionary YAML
#' @param cli_bin Path to the data-dict CLI binary. Defaults to the first
#'   of \code{$OPUS_DATA_DICT}, \code{data-dict} on \code{$PATH}, or a local
#'   release build; an explicit value is never overridden.
#'
#' @return List: (spec_valid, meta_valid, data_valid, spec_output, meta_result, data_result)
#' @export
op_validate_full <- function(data_path, table,
                             dict_path = "inst/DATRAS-imbus.yaml",
                             cli_bin = .op_cli()) {
  # NAMED, not positional: op_validate_spec()'s second parameter is `json`,
  # so `op_validate_spec(dict_path, cli_bin)` bound a path to it and died in
  # `if (json)`. This function could never run. Nothing caught it because the
  # only test that calls it skips on a fixture deleted in 57b34c0.
  spec_check <- op_validate_spec(dict_path, cli_bin = cli_bin)
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
# Internal helpers
# ============================================================================

# Where the data-dict CLI lives.
#
# opus shells out to `data-dict`, an external Rust binary
# (github.com/tidyverse/data-dict). It is not an R package, so it cannot be
# declared in DESCRIPTION and cannot be installed by pak -- every caller needs
# some way to say where it is. Resolution order, first hit wins:
#
#   1. an explicit `cli_bin` argument (never overridden)
#   2. $OPUS_DATA_DICT
#   3. `data-dict` on $PATH
#   4. the conventional local build, ~/garbage/data-dict/target/release
#
# (4) is a developer convenience and nothing more. Until 2026-09-09 it was the
# hardcoded DEFAULT of all ten exported functions here, and was baked into
# their generated man pages, so on any machine but one those ten errored out
# of the box. Keeping it last means the local build still works without
# configuration and no longer decides the contract.
#
# NOTE the binary carries no usable version signal: `--version` reported 0.0.3
# both before and after a 13-commit upstream pull (checked 2026-09-09), so a
# stale build is indistinguishable from a current one. Whatever ends up
# recording validator provenance must record the CLI's git SHA, not `--version`.
.op_cli <- function() {
  p <- Sys.getenv("OPUS_DATA_DICT", "")
  if (nzchar(p)) return(path.expand(p))

  p <- unname(Sys.which("data-dict"))
  if (nzchar(p)) return(p)

  p <- path.expand("~/garbage/data-dict/target/release/data-dict")
  if (file.exists(p)) return(p)

  stop("data-dict CLI not found. opus shells out to the data-dict binary ",
       "(https://github.com/tidyverse/data-dict), which is not an R package. ",
       "Point opus at it with Sys.setenv(OPUS_DATA_DICT = \"/path/to/data-dict\"), ",
       "put `data-dict` on PATH, or pass `cli_bin`. Searched: $OPUS_DATA_DICT, ",
       "PATH, and ", p, ".", call. = FALSE)
}

#' @keywords internal
# Build the dictionary the CLI should actually read.
#
# The CLI finds a table's data through the dictionary's own `source:` stanza,
# not through an argument, so pointing it at a parquet means editing the
# dictionary. Extracted 2026-09-09, when op_render_report() became the second
# caller: the surgery below has real corners -- a table's block runs to the
# next UNINDENTED line rather than to the next `- name:` (which is what makes
# it work for the last table, whose block would otherwise swallow
# `relationships:`/`glossary:`), and dropping a `source:` line without its
# nested value lines yields invalid YAML -- so a second copy would drift.
#
# Returns the path to read, the directory to read it from, and whether that
# path is a temporary file. It deliberately registers no on.exit(): the file
# has to outlive this call, so unlinking is the CALLER's job.
.op_dict_for <- function(data_path, table, dict_path) {
  dict_path <- normalizePath(path.expand(dict_path))

  if (!file.exists(dict_path)) {
    stop("Dictionary not found at ", dict_path, call. = FALSE)
  }

  # Read dictionary to check if source exists
  dict_lines <- readLines(dict_path)
  table_idx <- which(grepl(paste0("^- name: ", table, "$"), dict_lines))

  if (length(table_idx) != 1) {
    stop("Table '", table, "' not found in dictionary", call. = FALSE)
  }

  # Find the end of this table's definition. Every table's content is
  # indented (>= 2 spaces); the next boundary -- another table's `- name:`,
  # or a top-level key that follows `tables:` entirely (`relationships:`,
  # `glossary:`, etc.) -- always starts at column 0. Scanning for any
  # unindented line (not just the next `- name:`) is what makes this work
  # for the LAST table too, whose block would otherwise run to EOF and
  # swallow `relationships:`/`glossary:` into the reconstructed temp YAML.
  start_idx <- table_idx
  end_idx <- length(dict_lines)
  for (i in (start_idx + 1):length(dict_lines)) {
    if (grepl("^\\S", dict_lines[i])) {
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

    # Remove existing source if present, then inject new one. `source:`
    # itself is a 2-space-indented key, but its value (`    parquet: ...`)
    # lives on its own, more-indented line(s) below -- dropping only the
    # `source:` line orphans those, producing invalid YAML ("mapping values
    # are not allowed in this context"). Walk forward while lines stay
    # nested (>= 3 leading spaces) to remove the whole block.
    if (has_source) {
      source_idx <- which(grepl("^  source:", table_text))
      source_end <- source_idx
      if (source_idx < length(table_text)) {
        for (i in (source_idx + 1):length(table_text)) {
          if (!grepl("^   ", table_text[i])) break
          source_end <- i
        }
      }
      table_text <- table_text[-(source_idx:source_end)]
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
    return(list(dict_path = tmp_dict, run_dir = tempdir(), temp = TRUE))
  } else {
    # No data_path provided, must use existing source
    if (!has_source) {
      stop("No data_path provided and no source defined in dictionary for table '", table, "'", call. = FALSE)
    }
    return(list(dict_path = dict_path, run_dir = dirname(dict_path),
                temp = FALSE))
  }

}

.validate_via_dict <- function(subcommand, data_path, table, dict_path, cli_bin) {
  cli_bin <- normalizePath(path.expand(cli_bin))
  if (!file.exists(cli_bin))
    stop("data-dict CLI not found at ", cli_bin, call. = FALSE)

  d <- .op_dict_for(data_path, table, dict_path)
  dict_to_use <- d$dict_path
  run_dir     <- d$run_dir
  if (isTRUE(d$temp)) on.exit(unlink(dict_to_use), add = TRUE)

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
#' Adds a `.flag` column to parquet data, marking EVERY row that violates
#' `required`/`enum`/`range` constraints for a given table.
#'
#' The data-dict CLI's own JSON report (see `op_validate_data()`'s `$result`,
#' or `op_validate_spec(json = TRUE)`'s `$report`) now covers this ground too
#' -- and more check kinds (D01/D02/D04/D05/D07) -- but each report `problem`
#' caps its listed `rows`/`values` at the first 5 (see
#' `site/report.md#counting-and-capping` in the data-dict repo; there is no
#' CLI flag to raise this), by design, so a production pipeline's report
#' doesn't balloon on a wholly-broken column. This function exists
#' specifically for the case the capped report can't serve: marking every
#' single violating row (not just a sample) so they can all be filtered or
#' inspected downstream. Prefer the CLI's own report for anything that only
#' needs a count and a sample; keep using this for exhaustive, uncapped
#' row-level marking.
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
                              dict_path = "inst/DATRAS-imbus.yaml") {
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

#' Flatten a data-dict validation report's problems into a data frame
#'
#' A pure reshaping helper: takes the already-parsed JSON report from
#' `op_validate_spec(json = TRUE)$report`, `op_validate_meta()$result`, or
#' `op_validate_data()$result` (all three levels share the same report
#' shape -- see `site/report.md` in the data-dict repo) and flattens its
#' `problems` array into a data frame, one row per problem. No new checks,
#' no re-evaluation of the dictionary or the data -- everything here was
#' already decided by the CLI; this only makes it easier to work with from
#' R (`table()`, `dplyr::filter()`, etc.) than a nested list.
#'
#' @param report A parsed report (has a `problems` element), or the whole
#'   object a validate function returned -- `op_validate_spec(json = TRUE)`,
#'   `op_validate_meta()` or `op_validate_data()`. The wrapper is unwrapped
#'   for you: the three do not agree on where they put the report
#'   (`$report` for spec, `$result` for meta and data), so requiring the
#'   caller to know which is a trap. Anything carrying no `problems` at
#'   either level is an error, not an empty result.
#'
#' @return Data frame with one row per problem: code, severity, kind, table,
#'   columns (comma-joined), message, count, rows (comma-joined -- capped at
#'   the first 5 by the CLI itself, see `op_flag_violations()`'s own docs
#'   for when that cap matters), redacted. Empty (0-row) data frame if
#'   `report` is NULL or genuinely carries no problems. \strong{Errors} if
#'   handed something that is not a report: a real report always has a
#'   `problems` element, empty or not (verified 2026-09-09 -- even a valid
#'   HH meta report lists its 11 `S31` unresolved-todo warnings), so
#'   returning "no problems" for an unrecognised object would fabricate a
#'   clean bill of health. That is how
#'   `op_validation_problems(op_validate_data(...))` used to report 0 rows
#'   against a report holding 20 problems.
#'
#' @examples
#' \dontrun{
#'   res <- op_validate_data("inst/CA.parquet", "CA")
#'   op_validation_problems(res)          # wrapper -- unwrapped for you
#'   op_validation_problems(res$result)   # or the report itself
#' }
#'
#' @export
op_validation_problems <- function(report) {
  cols <- c("code", "severity", "kind", "table", "columns", "message", "count", "rows", "redacted")
  empty <- as.data.frame(stats::setNames(lapply(cols, function(x) character(0)), cols))

  if (is.null(report)) return(empty)
  if (!is.list(report))
    stop("`report` must be a parsed data-dict validation report (a list), ",
         "not ", class(report)[1], ".", call. = FALSE)

  # Accept the wrapper as well as the report. The three validate functions
  # disagree on the slot -- `$report` for spec, `$result` for meta and data --
  # so the obvious call matched neither and fell through to the empty frame.
  if (is.null(report$problems)) {
    for (slot in c("result", "report")) {
      if (slot %in% names(report) && !is.null(report[[slot]]$problems)) {
        report <- report[[slot]]
        break
      }
    }
  }

  if (is.null(report$problems)) {
    if (all(c("meta_result", "data_result") %in% names(report)))
      stop("`report` looks like op_validate_full()'s return, which carries ",
           "two reports. Pass one of them: `$meta_result` or `$data_result`.",
           call. = FALSE)
    stop("`report` carries no `problems`, at the top level or under ",
         "`$result`/`$report`, so it is not a validation report. Returning ",
         "an empty frame here would read as 'no problems found'.",
         call. = FALSE)
  }

  if (length(report$problems) == 0) return(empty)

  rows_list <- lapply(report$problems, function(p) {
    data.frame(
      code     = p$code %||% NA_character_,
      severity = p$severity %||% NA_character_,
      kind     = p$kind %||% NA_character_,
      table    = p$table %||% NA_character_,
      columns  = paste(unlist(p$columns), collapse = ", "),
      message  = p$message %||% NA_character_,
      count    = p$count %||% NA_integer_,
      rows     = paste(unlist(p$rows), collapse = ", "),
      redacted = if (is.null(p$redacted)) NA else p$redacted,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows_list)
}

#' Describe columns of a parquet file
#'
#' Profiles a parquet file and summarizes each column: type, distinct/null counts,
#' histograms (numeric/temporal), or most common values (string/boolean).
#'
#' Requires `describe-command` branch of data-dict to be built. Call
#' `op_describe_parquet()` to check availability.
#'
#' @param parquet_path Path to parquet file
#' @param column Optional: summarize only this column (default: all)
#' @param json Logical: return JSON output? (default: FALSE returns formatted text)
#' @param cli_bin Path to the data-dict CLI binary. Defaults to the first
#'   of \code{$OPUS_DATA_DICT}, \code{data-dict} on \code{$PATH}, or a local
#'   release build; an explicit value is never overridden.
#'
#' @return List: (available = T/F, output = text/JSON, raw_output = lines, exit_status)
#' @export
op_describe_parquet <- function(parquet_path, column = NULL,
                               json = FALSE,
                               cli_bin = .op_cli()) {
  cli_bin <- path.expand(cli_bin)
  parquet_path <- path.expand(parquet_path)

  if (!file.exists(cli_bin)) {
    return(list(
      available = FALSE,
      error = paste("data-dict CLI not found at", cli_bin),
      note = "The 'describe' command requires describe-command branch to be merged and built"
    ))
  }

  if (!file.exists(parquet_path)) {
    stop("Parquet file not found at ", parquet_path, call. = FALSE)
  }

  args <- c("describe", parquet_path)
  if (!is.null(column)) {
    args <- c(args, column)
  }
  if (json) {
    args <- c(args, "--json")
  }

  output <- system2(cli_bin, args, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status") %||% 0L

  list(
    available  = TRUE,
    valid      = (status == 0L),
    exit_status = status,
    output     = if (json) jsonlite::fromJSON(paste(output, collapse = "\n")) else paste(output, collapse = "\n"),
    raw_output = output,
    command    = paste(c(cli_bin, args), collapse = " ")
  )
}

#' Draft a data-dict.yaml from parquet files
#'
#' Generates a skeleton `data-dict.yaml` by profiling one or more parquet files.
#' Creates one table per input file, with inferred types, observed ranges/examples,
#' and `# TODO:` markers for human decisions.
#'
#' Requires `draft-command` branch of data-dict to be built. The output file
#' always passes `validate-spec`, so you can refine it incrementally.
#'
#' @param parquet_paths Character vector: paths to parquet files to describe
#' @param output Path to write output YAML (default: `"./data-dict.yaml"`)
#'   Use `"-"` for stdout.
#' @param cli_bin Path to the data-dict CLI binary. Defaults to the first
#'   of \code{$OPUS_DATA_DICT}, \code{data-dict} on \code{$PATH}, or a local
#'   release build; an explicit value is never overridden.
#'
#' @return List: (available = T/F, exit_status, output_path, skipped = files already in dict,
#'   created = new tables, raw_output, stderr)
#' @export
op_draft_from_parquet <- function(parquet_paths,
                                 output = "./data-dict.yaml",
                                 cli_bin = .op_cli()) {
  cli_bin <- path.expand(cli_bin)
  output <- path.expand(output)

  if (!file.exists(cli_bin)) {
    return(list(
      available = FALSE,
      error = paste("data-dict CLI not found at", cli_bin),
      note = "The 'draft' command requires draft-command branch to be merged and built"
    ))
  }

  # Validate input files exist
  missing <- parquet_paths[!file.exists(parquet_paths)]
  if (length(missing) > 0) {
    stop("Parquet file(s) not found: ", paste(missing, collapse = ", "), call. = FALSE)
  }

  args <- c("draft", parquet_paths, "--output", output)
  err_file <- tempfile()
  on.exit(unlink(err_file), add = TRUE)

  stdout_lines <- system2(cli_bin, args, stdout = TRUE, stderr = err_file)
  status <- attr(stdout_lines, "status") %||% 0L
  stderr_lines <- if (file.exists(err_file)) readLines(err_file, warn = FALSE) else character(0)

  list(
    available   = TRUE,
    valid       = (status == 0L),
    exit_status = status,
    output_path = if (output != "-") output else NA_character_,
    raw_output  = stdout_lines,
    stderr      = stderr_lines,
    command     = paste(c(cli_bin, args), collapse = " ")
  )
}

#' Export dictionary as fully-resolved JSON
#'
#' Renders a data-dict.yaml as JSON with all references resolved: enum keys
#' expanded to their full definitions, descriptions populated, types normalized.
#'
#' @param dict_path Path to data-dict.yaml or directory containing one
#'   (default: `"inst/DATRAS-imbus.yaml"`)
#' @param pretty Logical: pretty-print JSON? (default: FALSE for compact output)
#' @param cli_bin Path to the data-dict CLI binary. Defaults to the first
#'   of \code{$OPUS_DATA_DICT}, \code{data-dict} on \code{$PATH}, or a local
#'   release build; an explicit value is never overridden.
#'
#' @return List: (valid = T/F, spec = parsed JSON, raw_output = JSON text,
#'   exit_status, command)
#' @export
op_export_spec <- function(dict_path = "inst/DATRAS-imbus.yaml",
                          pretty = FALSE,
                          cli_bin = .op_cli()) {
  cli_bin <- path.expand(cli_bin)
  dict_path <- path.expand(dict_path)

  if (!file.exists(cli_bin)) {
    stop("data-dict CLI not found at ", cli_bin, call. = FALSE)
  }

  if (!file.exists(dict_path)) {
    stop("Dictionary not found at ", dict_path, call. = FALSE)
  }

  args <- c("export-spec", dict_path)
  if (pretty) {
    args <- c(args, "--pretty")
  }

  output <- system2(cli_bin, args, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status") %||% 0L
  raw_json <- paste(output, collapse = "\n")

  parsed <- tryCatch(
    jsonlite::fromJSON(raw_json, simplifyVector = FALSE),
    error = function(e) NULL
  )

  list(
    valid       = (status == 0L),
    exit_status = status,
    spec        = parsed,
    raw_output  = raw_json,
    command     = paste(c(cli_bin, args), collapse = " ")
  )
}

#' Export dictionary with per-column data profiles
#'
#' Renders a data-dict.yaml as JSON with per-column profiles: statistics,
#' distinct counts, value distributions, and example values for each column.
#'
#' @param dict_path Path to data-dict.yaml or directory containing one
#'   (default: `"inst/DATRAS-imbus.yaml"`)
#' @param pretty Logical: pretty-print JSON? (default: FALSE for compact output)
#' @param cli_bin Path to the data-dict CLI binary. Defaults to the first
#'   of \code{$OPUS_DATA_DICT}, \code{data-dict} on \code{$PATH}, or a local
#'   release build; an explicit value is never overridden.
#'
#' @return List: (valid = T/F, data = parsed JSON, raw_output = JSON text,
#'   exit_status, command)
#' @export
op_export_data <- function(dict_path = "inst/DATRAS-imbus.yaml",
                          pretty = FALSE,
                          cli_bin = .op_cli()) {
  cli_bin <- path.expand(cli_bin)
  dict_path <- path.expand(dict_path)

  if (!file.exists(cli_bin)) {
    stop("data-dict CLI not found at ", cli_bin, call. = FALSE)
  }

  if (!file.exists(dict_path)) {
    stop("Dictionary not found at ", dict_path, call. = FALSE)
  }

  args <- c("export-data", dict_path)
  if (pretty) {
    args <- c(args, "--pretty")
  }

  output <- system2(cli_bin, args, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status") %||% 0L
  raw_json <- paste(output, collapse = "\n")

  parsed <- tryCatch(
    jsonlite::fromJSON(raw_json, simplifyVector = FALSE),
    error = function(e) NULL
  )

  list(
    valid       = (status == 0L),
    exit_status = status,
    data        = parsed,
    raw_output  = raw_json,
    command     = paste(c(cli_bin, args), collapse = " ")
  )
}

#' Render a data dictionary as a self-contained HTML page
#'
#' Thin wrapper around data-dict CLI's `render-spec` command: one HTML file with
#' a relationship diagram, a searchable index of tables and columns, and the
#' glossary. Profiles each table's `source` data (row counts, histograms,
#' missing values) when present.
#'
#' Nothing rendered by this function is shipped or committed -- opus's own
#' documentation-architecture decision (2026-08-16) is to keep `render` an
#' on-demand tool, not a checked-in artifact, matching the same "ship the
#' YAML, not a rendered copy" philosophy the hand-rolled Quarto generator it
#' replaced already had. `dict_path`'s own declared `source:` fields point
#' at the small, shippable `inst/*.parquet` samples; pass `data_dir` (e.g.
#' `"~/R/Pakkar/opus/.datras"`) to profile against the full real archive
#' instead -- that archive is local and gitignored, so a page built from it
#' can only ever be a point-in-time export you generate and share yourself,
#' never something the repo keeps in sync.
#'
#' @param dict_path Path to data-dict.yaml or directory containing one
#'   (default: `"inst/DATRAS-imbus.yaml"`)
#' @param output Path to write the HTML page. Default `NULL` writes to a
#'   tempfile and opens it in the browser; pass a path to keep a copy instead.
#' @param data_dir Optional directory holding `TABLE.parquet` files (e.g.
#'   `.datras/`) to profile against instead of `dict_path`'s own declared
#'   `source:`. A table whose name has no matching file in `data_dir` keeps
#'   its original declared source unchanged. Implemented as a text
#'   substitution on a temp copy of the YAML (not a `yaml::read_yaml()` /
#'   `write_yaml()` round-trip), deliberately -- see
#'   `data-raw/spec/spec_03_translate_new_names.R`'s own comment on
#'   `rewrap_singleton_arrays()` for the round-trip bug that mechanism
#'   would otherwise risk reintroducing.
#' @param diagram Draw the relationship diagram at the top of the page
#'   (default `TRUE`); `FALSE` passes the CLI's `--no-diagram`. The joins
#'   the diagram draws still show in the index -- each column keeps its
#'   join markers and each table its related-table chips -- so only the
#'   picture goes.
#' @param cli_bin Path to the data-dict CLI binary. Defaults to the first
#'   of \code{$OPUS_DATA_DICT}, \code{data-dict} on \code{$PATH}, or a local
#'   release build; an explicit value is never overridden.
#'
#' @return List: (valid = T/F, exit_status, output_path, raw_output, command)
#' @export
op_render_spec <- function(dict_path = "inst/DATRAS-imbus.yaml",
                          output = NULL,
                          data_dir = NULL,
                          diagram = TRUE,
                          cli_bin = .op_cli()) {
  cli_bin <- path.expand(cli_bin)
  dict_path <- path.expand(dict_path)

  if (!file.exists(cli_bin)) {
    stop("data-dict CLI not found at ", cli_bin, call. = FALSE)
  }

  if (!file.exists(dict_path)) {
    stop("Dictionary not found at ", dict_path, call. = FALSE)
  }

  render_path <- dict_path
  if (!is.null(data_dir)) {
    data_dir <- normalizePath(path.expand(data_dir), mustWork = FALSE)
    lines <- readLines(dict_path)

    # Point any source: the dictionary already declares at `data_dir`.
    lines <- gsub(
      "^(\\s*parquet:\\s*)([A-Za-z0-9_]+)\\.parquet\\s*$",
      paste0("\\1", data_dir, "/\\2.parquet"),
      lines
    )

    # ...and give a source to any table that declares none. Without this the
    # render is spec-only: data-dict profiles row counts, histograms and
    # missing values into the page only when at least one table's source file
    # is present. The shipped dictionary deliberately declares no source --
    # the archive is not part of the repository, so a committed path would
    # dangle for everyone but whoever built it -- which makes injecting one
    # here the whole point of `data_dir`.
    table_starts <- grep("^- name: [A-Za-z0-9_]+\\s*$", lines)
    for (i in rev(table_starts)) {
      tbl <- sub("^- name: ", "", lines[i])
      block_end <- if (i == max(table_starts)) length(lines) else {
        nxt <- table_starts[table_starts > i][1]
        nxt - 1L
      }
      if (any(grepl("^  source:\\s*$", lines[i:block_end]))) next
      pq <- file.path(data_dir, paste0(trimws(tbl), ".parquet"))
      if (!file.exists(pq)) next
      lines <- append(lines, c("  source:", paste0("    parquet: ", pq)),
                      after = i)
    }

    tmp_dict <- tempfile(fileext = ".yaml")
    on.exit(unlink(tmp_dict), add = TRUE)
    writeLines(lines, tmp_dict)
    render_path <- tmp_dict
  }

  open_in_browser <- is.null(output)
  if (open_in_browser) {
    output <- tempfile(fileext = ".html")
  } else {
    output <- path.expand(output)
  }

  # `render-spec`, not `render`: the CLI split the subcommand in two on
  # 2026-09-08 (tidyverse/data-dict#245) -- `render-spec` for a dictionary,
  # `render-report` for a validation run -- with no alias for the old name.
  # The argument shape is unchanged: path positional, `-o` for the output.
  args <- c("render-spec", render_path, "-o", output)
  if (!diagram) {
    args <- c(args, "--no-diagram")
  }
  raw_output <- system2(cli_bin, args, stdout = TRUE, stderr = TRUE)
  status <- attr(raw_output, "status") %||% 0L

  if (status == 0L && open_in_browser) {
    utils::browseURL(output)
  }

  list(
    valid       = (status == 0L),
    exit_status = status,
    output_path = output,
    raw_output  = raw_output,
    # The command actually run. It names the temporary dictionary when
    # `data_dir` was given, because that -- not the shipped file -- is what
    # was rendered. Reporting `--data-dir` here would be doubly wrong: the
    # CLI has no such flag, and the shipped dictionary alone renders
    # spec-only.
    command     = paste(c(cli_bin, args), collapse = " ")
  )
}

#' Validate a table and render the report as a self-contained HTML page
#'
#' Runs exactly the checks \code{\link{op_validate_data}} runs, and writes the
#' run's report as one HTML file that works opened straight from disk. Wrapper
#' around data-dict CLI's `render-report`, which arrived 2026-09-08
#' (tidyverse/data-dict#245) when `render` was split into `render-spec` and
#' this.
#'
#' \strong{Why this is more than a rendering of \code{op_validate_data()}.}
#' The report names the rows that failed, and it names them by the
#' dictionary's declared primary key rather than by row offset. For HH that
#' key is `Survey`, `Year`, `Quarter`, `Country`, `Platform`, `Gear`,
#' `StationName`, `HaulNumber` -- the same eight fields, in the same order,
#' that obus pastes into its `.id`. So a failing row can be joined straight
#' onto obus's published tables with no adapter:
#'
#' ```
#' # keys the report emitted for HH's ThermoCline failures
#' ids <- c("BITS:2022:4:PL:67BC:TVL:25010:7", "BITS:2022:4:PL:67BC:TVL:25011:8")
#' obus::dr_con("HH") |> dplyr::filter(.id %in% ids) |> dplyr::collect()
#' ```
#'
#' Verified 2026-09-09: both resolve, and both carry the lower-case
#' `ThermoCline` value the dictionary's own `details` records as a submitter
#' case slip -- on hauls HH marks `HaulValidity == "V"`, so a validity filter
#' does not remove them. The dictionary says how many such rows exist; this
#' says which.
#'
#' \strong{Exit status 1 is the normal case, not a failure.} It means the
#' data has problems, which is why one usually runs this at all, and the page
#' is still written. A run that could not be started writes nothing. That is
#' why the return value has no `valid` field: `data_valid` is the data's
#' verdict and `rendered` is this function's, and collapsing the two into one
#' `valid` is exactly the conflation that made these wrappers hard to read.
#'
#' The CLI's `--live` mode is deliberately not exposed. It serves the page and
#' blocks until interrupted, which does not fit a function that returns a
#' value; run it from a shell when you want it.
#'
#' @param data_path Path to the parquet file to validate.
#' @param table Table name as declared in the dictionary, e.g. `"HH"`.
#' @param dict_path Path to data-dict.yaml or a directory containing one.
#' @param output Where to write the page. `NULL` (default) writes to a
#'   temporary file and opens it in a browser.
#' @param cli_bin Path to the data-dict CLI binary. Defaults to the first
#'   of \code{$OPUS_DATA_DICT}, \code{data-dict} on \code{$PATH}, or a local
#'   release build; an explicit value is never overridden.
#'
#' @return A list with `data_valid` (did the data pass), `rendered` (was a
#'   page written), `exit_status`, `output_path`, `raw_output` and the
#'   `command` actually run.
#'
#' @seealso \code{\link{op_validate_data}} for the same checks as data,
#'   \code{\link{op_validation_problems}} to flatten them, and
#'   \code{\link{op_render_spec}} to render the dictionary instead.
#' @export
#'
#' @examples
#' \dontrun{
#'   op_render_report(".datras/to_https/raw/HH.parquet", "HH")
#' }
op_render_report <- function(data_path, table,
                             dict_path = "inst/DATRAS-imbus.yaml",
                             output = NULL,
                             cli_bin = .op_cli()) {
  cli_bin <- normalizePath(path.expand(cli_bin))
  if (!file.exists(cli_bin))
    stop("data-dict CLI not found at ", cli_bin, call. = FALSE)

  d <- .op_dict_for(data_path, table, dict_path)
  if (isTRUE(d$temp)) on.exit(unlink(d$dict_path), add = TRUE)

  open_in_browser <- is.null(output)
  output <- if (open_in_browser) tempfile(fileext = ".html") else path.expand(output)

  # Absolute, because the CLI is run from the dictionary's directory (which is
  # tempdir() when a source was injected) and a relative -o would land there.
  output <- file.path(normalizePath(dirname(output), mustWork = FALSE),
                      basename(output))

  args <- c("render-report", basename(d$dict_path), "--table", table,
            "-o", output)

  old_wd <- setwd(d$run_dir)
  on.exit(setwd(old_wd), add = TRUE)

  raw_output <- system2(cli_bin, args, stdout = TRUE, stderr = TRUE)
  status <- attr(raw_output, "status") %||% 0L
  rendered <- file.exists(output)

  # On `rendered`, not on `status`: status 1 means the data has problems and
  # the page was still written, which is the case worth looking at.
  if (rendered && open_in_browser) utils::browseURL(output)

  list(
    data_valid  = (status == 0L),
    rendered    = rendered,
    exit_status = status,
    output_path = output,
    raw_output  = raw_output,
    command     = paste(c(cli_bin, args), collapse = " ")
  )
}

# Null coalesce helper
`%||%` <- function(x, y) if (is.null(x)) y else x
