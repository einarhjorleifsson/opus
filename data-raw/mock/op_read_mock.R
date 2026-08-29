#' MOCK of the read side: opus::op_con() and the metadata accessors.
#'
#' Scoped deliberately narrowly, per the design decision: the archive is the
#' four raw exchange tables under a directory whose last path section is `raw`,
#' either the local staging dir or its published twin on the web. Nothing else.

suppressPackageStartupMessages({ library(DBI); library(duckdb); library(jsonlite) })

`%||%` <- function(x, y) if (is.null(x)) y else x

OP_TABLES <- c("HH", "HL", "CA", "LT")
OP_WEB    <- "https://heima.hafro.is/~einarhj/datras/raw"
OP_LOCAL  <- "/Users/einarhj/R/Pakkar/opus/.datras/to_https/raw"

# ---- connection ------------------------------------------------------------

#' Resolve the archive root. Local staging wins when present, else the web.
#' The invariant: the last path section is always `raw`.
op_archive <- function(path = getOption("opus.archive", NULL)) {
  path <- path %||% (if (dir.exists(OP_LOCAL)) OP_LOCAL else OP_WEB)
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
    if (is.null(con) || !DBI::dbIsValid(con))
      con <<- DBI::dbConnect(duckdb::duckdb(), shared_home = FALSE)
    con
  }
})

#' A lazy connection to one raw exchange table.
op_con <- function(table, path = op_archive()) {
  f <- .op_path(table, path)
  dplyr::tbl(.op_db(), dplyr::sql(sprintf("SELECT * FROM read_parquet('%s')", f)))
}

# ---- metadata --------------------------------------------------------------

# One footer read, cached per (file, key). This is the whole mechanism.
.op_kv <- local({
  cache <- new.env(parent = emptyenv())
  function(table, key, path = op_archive()) {
    f  <- .op_path(table, path)
    id <- paste(f, key)
    if (!is.null(cache[[id]])) return(cache[[id]])
    txt <- DBI::dbGetQuery(.op_db(), sprintf(
      "SELECT decode(value) AS v FROM parquet_kv_metadata('%s') WHERE key::VARCHAR = '%s'",
      f, key))$v
    if (!length(txt)) stop("No `", key, "` metadata in ", basename(f),
                           ". Was it built before the metadata pass?", call. = FALSE)
    out <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
    assign(id, out, envir = cache)
    out
  }
})

#' Which metadata keys a file carries, and how big they are.
op_keys <- function(table, path = op_archive()) {
  DBI::dbGetQuery(.op_db(), sprintf(
    "SELECT key::VARCHAR AS key, octet_length(value) AS bytes
       FROM parquet_kv_metadata('%s') ORDER BY key", .op_path(table, path)))
}

#' The data dictionary, one row per column.
op_dict <- function(table, path = op_archive()) {
  cols <- .op_kv(table, "datras:dict", path)$table$columns
  strip <- function(x) if (is.null(x)) NA_character_ else
    trimws(gsub("<[^>]+>", "", gsub("</p>\\s*<p>", " ", x)))
  do.call(rbind, lapply(cols, function(c) data.frame(
    name         = c$name,
    legacy_name  = c$legacy_name  %||% NA_character_,
    type         = c$type         %||% NA_character_,
    parquet_type = c$parquet_type %||% NA_character_,
    logical_type = c$logical_type %||% NA_character_,
    r_type       = c$r_type       %||% NA_character_,
    units        = c$units        %||% NA_character_,
    constraints  = paste(unlist(c$constraints), collapse = ", "),
    range_min    = if (is.null(c$range$min)) NA else as.character(c$range$min),
    range_max    = if (is.null(c$range$max)) NA else as.character(c$range$max),
    n_values     = length(c$values %||% list()),
    label        = c$label %||% NA_character_,
    description  = strip(c$description),
    stringsAsFactors = FALSE)))
}

#' The legacy <-> current name mapping, read from the file itself.
op_crosswalk <- function(table, path = op_archive()) {
  d <- op_dict(table, path)
  xw <- data.frame(old_name = d$legacy_name, new_name = d$name, stringsAsFactors = FALSE)
  # The guarantee the embedded mapping rests on -- assert, don't trust.
  if (anyDuplicated(xw$old_name) || anyDuplicated(xw$new_name) || anyNA(xw))
    stop("Embedded crosswalk for ", table, " is not 1:1 and total.", call. = FALSE)
  xw
}

#' Rename between the two naming schemes using only the file's own metadata.
op_rename <- function(d, table, to = c("legacy", "current"), path = op_archive()) {
  to <- match.arg(to); xw <- op_crosswalk(table, path)
  from_col <- if (to == "legacy") "new_name" else "old_name"
  to_col   <- if (to == "legacy") "old_name" else "new_name"
  dplyr::rename_with(d, function(nm) {
    hit <- xw[[to_col]][match(nm, xw[[from_col]])]
    ifelse(is.na(hit), nm, hit)
  })
}

#' Code -> label for enum columns.
op_enums <- function(table, column = NULL, path = op_archive()) {
  cols <- .op_kv(table, "datras:dict", path)$table$columns
  cols <- Filter(function(c) identical(c$type, "enum") && length(c$value_labels), cols)
  if (!is.null(column)) cols <- Filter(function(c) c$name == column, cols)
  do.call(rbind, lapply(cols, function(c) data.frame(
    column = c$name, code = names(c$value_labels),
    label = unlist(c$value_labels, use.names = FALSE), stringsAsFactors = FALSE)))
}

#' Reusable definitions, with their translations into R and SQL.
op_definitions <- function(table, path = op_archive()) {
  defs <- .op_kv(table, "datras:dict", path)$table$definitions %||% list()
  do.call(rbind, lapply(defs, function(d) {
    tr <- function(target) {
      hit <- Filter(function(t) t$target == target, d$translations %||% list())
      if (length(hit)) hit[[1]]$code else NA_character_
    }
    data.frame(name = d$name, kind = d$kind %||% NA, expression = d$expression,
               r = tr("R(tidyverse)"), sql = tr("SQL(duckdb)"),
               stringsAsFactors = FALSE)
  }))
}

#' Apply a definition to a data frame, using the code the file carries.
op_define <- function(d, table, name, path = op_archive()) {
  defs <- op_definitions(table, path)
  if (!name %in% defs$name) stop("No definition `", name, "` in ", table, call. = FALSE)
  code <- defs$r[defs$name == name]
  dplyr::filter(d, !!rlang::parse_expr(code))
}

#' The resolved join keys and column conflicts.
op_relationships <- function(table, path = op_archive()) {
  rels <- .op_kv(table, "datras:dict", path)$relationships %||% list()
  lapply(rels, function(r) list(
    left  = r$pairs[[1]]$left$table, right = r$pairs[[1]]$right$table,
    by    = vapply(r$pairs, function(p) p$left$column, ""),
    cardinality = r$cardinality, conflicts = unlist(r$conflicts %||% list())))
}

#' Provenance, sentinel policy, coverage, known issues.
op_provenance <- function(table, path = op_archive())
  as.data.frame(.op_kv(table, "datras:provenance", path))

op_sentinel_meta <- function(table, path = op_archive()) {
  s <- .op_kv(table, "datras:sentinels", path)
  cbind(value = s$value, do.call(rbind, lapply(s$policy, as.data.frame)))
}

op_coverage <- function(table, path = op_archive()) {
  cov <- .op_kv(table, "datras:coverage", path)
  do.call(rbind, lapply(cov$combinations, as.data.frame))
}

#' The survey list, from the file -- no live ICES call.
op_surveys <- function(table = "HH", path = op_archive())
  unlist(.op_kv(table, "datras:coverage", path)$surveys)

op_known_issues <- function(table, path = op_archive()) {
  ki <- .op_kv(table, "datras:known_issues", path)
  do.call(rbind, lapply(ki, function(i) data.frame(
    id = i$id, severity = i$severity, field = i$field,
    issue = substr(i$issue, 1, 90), stringsAsFactors = FALSE)))
}
