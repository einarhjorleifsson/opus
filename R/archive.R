#' Read the raw DATRAS archive and the dictionary embedded in it
#'
#' The archive is the four Tier-1 exchange tables (HH, HL, CA, LT) staged by
#' `data-raw/archive_06_consolidate.R`, each carrying its own dictionary in its
#' parquet footer under five `datras:` keys. These functions read those keys.
#'
#' Everything here is a footer read: DuckDB fetches only the parquet footer, so
#' `op_dict("HH")` against the published archive costs one HTTP range request
#' (~0.1s), not a download of the file.
#'
#' @name opus-archive
NULL

OP_TABLES <- c("HH", "HL", "CA", "LT")
OP_WEB    <- "https://heima.hafro.is/~einarhj/datras/raw"
OP_LOCAL  <- ".datras/to_https/raw"

#' Resolve the archive root
#'
#' An opus archive is a directory named `raw` holding the four exchange tables:
#' either the local staging directory or its published twin on the web. The
#' narrowness is deliberate -- it is what lets every accessor below assume the
#' `datras:` keys are present.
#'
#' @param path Archive root. Defaults to `getOption("opus.archive")`, then the
#'   local staging directory if it exists, then the published archive.
#' @return The resolved root, as a character string.
#' @export
#' @examples
#' \dontrun{
#' op_archive()
#' op_archive("https://heima.hafro.is/~einarhj/datras/raw")
#' }
op_archive <- function(path = getOption("opus.archive", NULL)) {
  if (is.null(path)) {
    path <- if (dir.exists(OP_LOCAL)) OP_LOCAL else OP_WEB
  }
  path <- sub("/+$", "", path.expand(path))
  if (basename(path) != "raw") {
    stop("An opus archive is a directory named `raw` (the four exchange tables ",
         "as staged by archive_06_consolidate.R). Got: ", path, call. = FALSE)
  }
  path
}

.op_path <- function(table, path = op_archive()) {
  table <- match.arg(table, OP_TABLES)
  file.path(path, paste0(table, ".parquet"))
}

.op_db <- local({
  con <- NULL
  function() {
    if (is.null(con) || !DBI::dbIsValid(con)) {
      con <<- DBI::dbConnect(duckdb::duckdb(), shared_home = FALSE)
    }
    con
  }
})

# One footer read per (file, key), cached for the session. `decode()` rather
# than a plain VARCHAR cast: the value is a BLOB, and the cast hex-escapes
# every quote in the JSON.
.op_kv <- local({
  cache <- new.env(parent = emptyenv())
  function(table, key, path = op_archive()) {
    f  <- .op_path(table, path)
    id <- paste(f, key)
    if (!is.null(cache[[id]])) return(cache[[id]])
    txt <- DBI::dbGetQuery(.op_db(), sprintf(
      "SELECT decode(value) AS v FROM parquet_kv_metadata('%s')
        WHERE key::VARCHAR = '%s'", f, key))$v
    if (!length(txt)) {
      stop("No `", key, "` metadata in ", basename(f),
           ". Was this file built before the metadata pass?", call. = FALSE)
    }
    out <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
    assign(id, out, envir = cache)
    out
  }
})

#' Connect to one raw exchange table
#'
#' @param table One of `"HH"`, `"HL"`, `"CA"`, `"LT"`.
#' @param path Archive root; see [op_archive()].
#' @return A lazy `tbl`. Pipe dplyr verbs and call [dplyr::collect()].
#' @export
#' @examples
#' \dontrun{
#' op_con("HH") |> dplyr::filter(Survey == "NS-IBTS", Year == 2022) |> dplyr::collect()
#' }
op_con <- function(table, path = op_archive()) {
  f <- .op_path(table, path)
  dplyr::tbl(.op_db(), dplyr::sql(sprintf("SELECT * FROM read_parquet('%s')", f)))
}

#' List the metadata keys a file carries
#'
#' @inheritParams op_con
#' @return A data frame of `key` and `bytes`.
#' @export
op_keys <- function(table, path = op_archive()) {
  DBI::dbGetQuery(.op_db(), sprintf(
    "SELECT key::VARCHAR AS key, octet_length(value) AS bytes
       FROM parquet_kv_metadata('%s') ORDER BY key", .op_path(table, path)))
}

# export-spec renders prose to HTML so web consumers need no Markdown
# implementation. At an R console the tags are noise, so strip them on read and
# leave the file faithful to what data-dict produced.
.op_detag <- function(x) {
  if (is.null(x)) return(NA_character_)
  trimws(gsub("<[^>]+>", "", gsub("</p>[[:space:]]*<p>", " ", x)))
}

#' The data dictionary, one row per column
#'
#' Carries three type views per column, deliberately: `type` is opus's curated
#' semantic type, `parquet_type`/`logical_type` are what is physically stored,
#' and `r_type` is what a reader gets back. They are allowed to disagree --
#' making that divergence visible is the point.
#'
#' @inheritParams op_con
#' @return A data frame with one row per column of the table.
#' @export
#' @examples
#' \dontrun{
#' op_dict("HH")[, c("name", "legacy_name", "type", "r_type")]
#' }
op_dict <- function(table, path = op_archive()) {
  cols <- .op_kv(table, "datras:dict", path)$table$columns
  do.call(rbind, lapply(cols, function(c) data.frame(
    name         = c$name,
    legacy_name  = c$legacy_name  %||% NA_character_,
    type         = c$type         %||% NA_character_,
    parquet_type = c$parquet_type %||% NA_character_,
    logical_type = c$logical_type %||% NA_character_,
    r_type       = c$r_type       %||% NA_character_,
    units        = c$units        %||% NA_character_,
    constraints  = paste(unlist(c$constraints), collapse = ", "),
    range_min    = if (is.null(c$range$min)) NA_character_ else as.character(c$range$min),
    range_max    = if (is.null(c$range$max)) NA_character_ else as.character(c$range$max),
    n_values     = length(c$values %||% list()),
    label        = c$label %||% NA_character_,
    description  = .op_detag(c$description),
    stringsAsFactors = FALSE)))
}

#' The legacy/current name crosswalk, read from the file itself
#'
#' No external list is involved: the mapping is written into the footer at build
#' time and read back from the same file as the data it describes, so it cannot
#' describe a different vintage of the archive than the one you loaded.
#'
#' @inheritParams op_con
#' @return A data frame of `old_name` and `new_name`.
#' @export
op_crosswalk <- function(table, path = op_archive()) {
  d  <- op_dict(table, path)
  xw <- data.frame(old_name = d$legacy_name, new_name = d$name,
                   stringsAsFactors = FALSE)
  # The mapping is only sufficient on its own if it is total and bijective.
  # A partial one is worse than none: op_rename() keeps the original name on no
  # match, so an un-renamed column would pass through looking translated.
  if (anyNA(xw) || anyDuplicated(xw$old_name) || anyDuplicated(xw$new_name)) {
    stop("Embedded crosswalk for ", table, " is not 1:1 and total.", call. = FALSE)
  }
  xw
}

#' Rename between the legacy and current naming schemes
#'
#' @param d A data frame or lazy `tbl`.
#' @param table One of `"HH"`, `"HL"`, `"CA"`, `"LT"`.
#' @param to `"legacy"` for ICES's on-the-wire names, `"current"` for opus's.
#' @param path Archive root; see [op_archive()].
#' @return `d` with its columns renamed. Unmatched columns are left alone.
#' @export
#' @examples
#' \dontrun{
#' hh <- op_con("HH") |> head(3) |> dplyr::collect()
#' op_rename(hh, "HH", to = "legacy")   # Platform -> Ship, HaulNumber -> HaulNo
#' }
op_rename <- function(d, table, to = c("legacy", "current"), path = op_archive()) {
  to <- match.arg(to)
  xw <- op_crosswalk(table, path)
  from_col <- if (to == "legacy") "new_name" else "old_name"
  to_col   <- if (to == "legacy") "old_name" else "new_name"
  dplyr::rename_with(d, function(nm) {
    hit <- xw[[to_col]][match(nm, xw[[from_col]])]
    ifelse(is.na(hit), nm, hit)
  })
}

#' Enum code/label pairs
#'
#' @inheritParams op_con
#' @param column Restrict to one column. Default: all enum columns.
#' @return A data frame of `column`, `code`, `label`.
#' @export
op_enums <- function(table, column = NULL, path = op_archive()) {
  cols <- .op_kv(table, "datras:dict", path)$table$columns
  cols <- Filter(function(c) identical(c$type, "enum") && length(c$value_labels), cols)
  if (!is.null(column)) cols <- Filter(function(c) c$name == column, cols)
  if (!length(cols)) return(NULL)
  do.call(rbind, lapply(cols, function(c) data.frame(
    column = c$name, code = names(c$value_labels),
    label  = unlist(c$value_labels, use.names = FALSE),
    stringsAsFactors = FALSE)))
}

#' Reusable definitions and their translations
#'
#' Definitions are the dictionary's named filters, metrics and derived values.
#' Each arrives with code already rendered for R and DuckDB, so the same rule
#' can be applied eagerly or pushed down to the database.
#'
#' @inheritParams op_con
#' @return A data frame of `name`, `kind`, `expression`, `r`, `sql`, or `NULL`.
#' @export
op_definitions <- function(table, path = op_archive()) {
  defs <- .op_kv(table, "datras:dict", path)$table$definitions %||% list()
  if (!length(defs)) return(NULL)
  do.call(rbind, lapply(defs, function(d) {
    tr <- function(target) {
      hit <- Filter(function(x) x$target == target, d$translations %||% list())
      if (length(hit)) hit[[1]]$code else NA_character_
    }
    data.frame(name = d$name, kind = d$kind %||% NA_character_,
               expression = d$expression, r = tr("R(tidyverse)"),
               sql = tr("SQL(duckdb)"), stringsAsFactors = FALSE)
  }))
}

#' Apply a named filter definition
#'
#' @param d A data frame or lazy `tbl`.
#' @param table One of `"HH"`, `"HL"`, `"CA"`, `"LT"`.
#' @param name Definition name; see [op_definitions()].
#' @param path Archive root; see [op_archive()].
#' @return `d`, filtered.
#' @export
op_define <- function(d, table, name, path = op_archive()) {
  defs <- op_definitions(table, path)
  if (is.null(defs) || !name %in% defs$name) {
    stop("No definition `", name, "` in ", table, ".", call. = FALSE)
  }
  code <- defs$r[defs$name == name]
  if (is.na(code)) {
    stop("Definition `", name, "` has no R translation.", call. = FALSE)
  }
  dplyr::filter(d, !!str2lang(code))
}

#' Resolved join keys and column conflicts
#'
#' @inheritParams op_con
#' @return A list, one entry per relationship touching the table, each with
#'   `left`, `right`, `by`, `cardinality` and `conflicts`.
#' @export
op_relationships <- function(table, path = op_archive()) {
  rels <- .op_kv(table, "datras:dict", path)$relationships %||% list()
  lapply(rels, function(r) list(
    left        = r$pairs[[1]]$left$table,
    right       = r$pairs[[1]]$right$table,
    by          = vapply(r$pairs, function(p) p$left$column, ""),
    cardinality = r$cardinality,
    conflicts   = unlist(r$conflicts %||% list())))
}

#' What the archive actually covers
#'
#' @inheritParams op_con
#' @return A data frame of the survey/year/quarter combinations present.
#' @export
op_coverage <- function(table, path = op_archive()) {
  cov <- .op_kv(table, "datras:coverage", path)$combinations
  as.data.frame(lapply(cov, unlist), stringsAsFactors = FALSE)
}

#' The survey list, without a live ICES call
#'
#' @inheritParams op_con
#' @return A character vector of survey acronyms.
#' @export
op_surveys <- function(table = "HH", path = op_archive()) {
  unlist(.op_kv(table, "datras:coverage", path)$surveys)
}

#' The sentinel policy actually applied to this file
#'
#' Records, per field, whether the `-9` sentinel was stripped to `NA` or kept.
#' Reading it is how a consumer knows which columns still carry sentinels
#' without having opus's YAML to hand.
#'
#' @inheritParams op_con
#' @return A data frame of `field`, `action`, `why`.
#' @export
op_sentinel_meta <- function(table, path = op_archive()) {
  s <- .op_kv(table, "datras:sentinels", path)
  out <- do.call(rbind, lapply(s$policy, function(p) data.frame(
    field = p$field, action = p$action, why = p$why %||% NA_character_,
    stringsAsFactors = FALSE)))
  attr(out, "sentinel") <- s$value
  attr(out, "meaning")  <- s$meaning
  out
}

#' Who built this file, from what
#'
#' @inheritParams op_con
#' @return A one-row data frame.
#' @export
op_provenance <- function(table, path = op_archive()) {
  as.data.frame(.op_kv(table, "datras:provenance", path), stringsAsFactors = FALSE)
}

#' Known issues affecting this table
#'
#' @inheritParams op_con
#' @return A data frame, or `NULL` when none apply.
#' @export
op_known_issues <- function(table, path = op_archive()) {
  ki <- .op_kv(table, "datras:known_issues", path)
  if (!length(ki)) return(NULL)
  do.call(rbind, lapply(ki, function(i) data.frame(
    id = i$id, severity = i$severity %||% NA_character_,
    scope = i$scope %||% NA_character_, field = i$field %||% NA_character_,
    issue = i$issue %||% NA_character_, stringsAsFactors = FALSE)))
}

#' Build the SQL catalog from the files' own footers
#'
#' Reconstructs, in memory, everything the former published `catalog.duckdb`
#' offered: a view per table over the archive, `COMMENT ON TABLE`/`COLUMN` from
#' the dictionary's descriptions, and the `enum_labels`, `range_constraints` and
#' `field_constraints` lookup tables.
#'
#' The difference is where it comes from. `catalog.duckdb` was a separate
#' published file describing other files: nothing forced it to be rebuilt when
#' the parquet was, and a consumer who downloaded one table alone got no
#' dictionary. This reads the same content out of the four footers on demand, so
#' it cannot describe a different vintage than the data it sits beside.
#'
#' Checked against the catalog it replaces (2026-08-29): `enum_labels` (869 rows)
#' and the column comments (169) are identical. It differs in two places, in both
#' cases by being more faithful to the dictionary:
#'
#' * `DateofCalculation`'s upper bound is `NA`, not the string `"Inf"`. The YAML
#'   declares `.inf` -- a deliberately open bound, since the field is a live
#'   ICES recalculation stamp -- and `export-spec` resolves that to null. The old
#'   builder coerced it to `"Inf"`, which nothing can meaningfully compare a date
#'   against.
#' * 111 `field_constraints` rather than 97. `export-spec` expands `primary_key`
#'   into `primary_key, unique, required`; the old builder's YAML walk recorded
#'   only what was written literally.
#'
#' @param path Archive root; see [op_archive()].
#' @param tables Which tables to include.
#' @return A DBI connection to an in-memory DuckDB. Close it with
#'   [DBI::dbDisconnect()] (`shutdown = TRUE`).
#' @export
#' @examples
#' \dontrun{
#' con <- op_catalog()
#' DBI::dbGetQuery(con, "SELECT * FROM HH LIMIT 5")
#' DBI::dbGetQuery(con, "SELECT * FROM enum_labels WHERE column_name = 'DataType'")
#' DBI::dbGetQuery(con, "SELECT table_name, column_name, comment FROM duckdb_columns()")
#' DBI::dbDisconnect(con, shutdown = TRUE)
#' }
op_catalog <- function(path = op_archive(), tables = OP_TABLES) {
  con <- DBI::dbConnect(duckdb::duckdb(), shared_home = FALSE)
  esc <- function(x) gsub("'", "''", x, fixed = TRUE)

  DBI::dbExecute(con, "CREATE TABLE enum_labels (table_name VARCHAR, column_name VARCHAR,
                       code VARCHAR, label VARCHAR)")
  # Bounds are VARCHAR: the range types include date and datetime as well as the
  # numeric measures, and a date bound cannot be held in a DOUBLE. Consumers cast
  # per the column's own declared type, which op_dict() carries.
  DBI::dbExecute(con, "CREATE TABLE range_constraints (table_name VARCHAR, column_name VARCHAR,
                       min_value VARCHAR, max_value VARCHAR)")
  DBI::dbExecute(con, "CREATE TABLE field_constraints (table_name VARCHAR, column_name VARCHAR,
                       constraint_type VARCHAR)")

  for (t in tables) {
    dict <- .op_kv(t, "datras:dict", path)
    DBI::dbExecute(con, sprintf("CREATE VIEW %s AS SELECT * FROM read_parquet('%s')",
                                t, esc(.op_path(t, path))))

    tc <- dict$table$description %||% dict$table$label
    if (!is.null(tc)) {
      DBI::dbExecute(con, sprintf("COMMENT ON TABLE %s IS '%s'", t, esc(.op_detag(tc))))
    }

    for (col in dict$table$columns) {
      cc <- col$description %||% col$label
      if (!is.null(cc)) {
        DBI::dbExecute(con, sprintf("COMMENT ON COLUMN %s.%s IS '%s'",
                                    t, col$name, esc(.op_detag(cc))))
      }
      if (identical(col$type, "enum") && length(col$value_labels)) {
        for (code in names(col$value_labels)) {
          DBI::dbExecute(con, "INSERT INTO enum_labels VALUES (?, ?, ?, ?)",
                         params = list(t, col$name, code, col$value_labels[[code]]))
        }
      }
      if (!is.null(col$range)) {
        DBI::dbExecute(con, "INSERT INTO range_constraints VALUES (?, ?, ?, ?)",
                       params = list(t, col$name,
                                     as.character(col$range$min %||% NA),
                                     as.character(col$range$max %||% NA)))
      }
      for (cn in unlist(col$constraints %||% list())) {
        DBI::dbExecute(con, "INSERT INTO field_constraints VALUES (?, ?, ?)",
                       params = list(t, col$name, cn))
      }
    }
  }
  con
}
