#' Build catalog.duckdb from the shipped yaml dictionaries
#'
#' Compiles both inst/DATRAS-data-dict.yaml (curated names) and
#' inst/DATRAS-data-dict-legacy.yaml (legacy/ICES on-the-wire names) into one
#' .datras/to_https/catalog.duckdb: a small, self-describing companion to
#' the parquet files data-raw/archive_06_split_legacy_new.R writes to the
#' same directory. Consumers ATTACH this file (locally, or once manually
#' copied to the https server, remotely) and get typed, documented,
#' validated SQL access with nothing but a DuckDB client -- no yaml parsing,
#' no opus/obus R package required.
#'
#' Mirrors the same yaml-walking logic already used by op_flag_violations()
#' (R/validation.R) for interpreting `values`/`range`/`constraints` --
#' emitting SQL instead of computing violation flags, including that
#' function's own `.inf` handling verbatim (maps to positive Inf on both the
#' min and max side, not -Inf on the min side -- kept consistent with the
#' existing function rather than silently diverging from it).
#'
#' Per table, per name variant (curated / legacy), generates:
#' - a VIEW over the (future) https-hosted parquet -- `{table}_new` for
#'   curated names, `{table}_legacy` for ICES on-the-wire names, matching
#'   archive_06_split_legacy_new.R's own file naming
#' - COMMENT ON TABLE/COLUMN from each table/column's description
#' - enum_labels rows for every `type: enum` column's `values:` map
#' - range_constraints rows for every ordinal/quantity/date/datetime column
#'   with a declared `range:`
#' - field_constraints rows for `constraints:` (required, primary_key, ...)
#'
#' Usage: Rscript data-raw/spec_04_build_catalog.R

suppressPackageStartupMessages({
  library(duckdb)
  library(DBI)
  library(yaml)
})

BASE_URL <- "https://heima.hafro.is/~einarhj/datras"
CATALOG_PATH <- ".datras/to_https/catalog.duckdb"
RANGE_TYPES <- c("number(ordinal)", "number(quantity)", "date", "datetime")

dir.create(".datras/to_https", showWarnings = FALSE, recursive = TRUE)
unlink(CATALOG_PATH)

sql_escape <- function(x) gsub("'", "''", x, fixed = TRUE)

build_catalog_for_dict <- function(con, dict_path, name_suffix, base_url) {
  dict <- yaml::read_yaml(dict_path)

  for (tbl in dict$tables) {
    view_name <- paste0(tbl$name, name_suffix)
    url <- paste0(base_url, "/", view_name, ".parquet")

    dbExecute(con, sprintf(
      "CREATE VIEW %s AS SELECT * FROM read_parquet('%s')",
      view_name, sql_escape(url)
    ))

    tbl_comment <- tbl$description %||% tbl$label
    if (!is.null(tbl_comment)) {
      dbExecute(con, sprintf(
        "COMMENT ON TABLE %s IS '%s'", view_name, sql_escape(tbl_comment)
      ))
    }

    for (col_def in tbl$columns) {
      col_comment <- col_def$description %||% col_def$label
      if (!is.null(col_comment)) {
        dbExecute(con, sprintf(
          "COMMENT ON COLUMN %s.%s IS '%s'",
          view_name, col_def$name, sql_escape(col_comment)
        ))
      }

      has_enum <- !is.null(col_def$values) && identical(col_def$type, "enum")
      if (has_enum) {
        codes <- names(col_def$values)
        labels <- unlist(col_def$values, use.names = FALSE)
        for (i in seq_along(codes)) {
          dbExecute(
            con, "INSERT INTO enum_labels VALUES (?, ?, ?, ?)",
            params = list(view_name, col_def$name, codes[i], labels[i])
          )
        }
      }

      has_range <- !is.null(col_def$range) && !is.null(col_def$type) &&
        col_def$type %in% RANGE_TYPES
      if (has_range) {
        min_val <- col_def$range[[1]]
        max_val <- col_def$range[[2]]
        # Mirrors op_flag_violations() verbatim: .inf maps to Inf on EITHER side.
        if (is.character(min_val) && min_val == ".inf") min_val <- Inf
        if (is.character(max_val) && max_val == ".inf") max_val <- Inf
        dbExecute(
          con, "INSERT INTO range_constraints VALUES (?, ?, ?, ?)",
          params = list(view_name, col_def$name, as.numeric(min_val), as.numeric(max_val))
        )
      }

      if (!is.null(col_def$constraints)) {
        for (constraint in col_def$constraints) {
          dbExecute(
            con, "INSERT INTO field_constraints VALUES (?, ?, ?)",
            params = list(view_name, col_def$name, constraint)
          )
        }
      }
    }

    message("Built ", view_name, ": ", length(tbl$columns), " columns")
  }
}

con <- dbConnect(duckdb(dbdir = CATALOG_PATH))

dbExecute(con, "CREATE TABLE enum_labels (table_name VARCHAR, column_name VARCHAR, code VARCHAR, label VARCHAR)")
dbExecute(con, "CREATE TABLE range_constraints (table_name VARCHAR, column_name VARCHAR, min_value DOUBLE, max_value DOUBLE)")
dbExecute(con, "CREATE TABLE field_constraints (table_name VARCHAR, column_name VARCHAR, constraint_type VARCHAR)")

build_catalog_for_dict(con, "inst/DATRAS-data-dict.yaml", "_new", BASE_URL)
build_catalog_for_dict(con, "inst/DATRAS-data-dict-legacy.yaml", "_legacy", BASE_URL)

dbDisconnect(con, shutdown = TRUE)

message("")
message("Done. ", CATALOG_PATH, " built from both yaml dictionaries.")
