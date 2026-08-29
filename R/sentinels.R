# Sentinel resolution: turning DATRAS's "-9" into a real NULL, where and only
# where it means absence.
#
# Until now nothing in R/ read inst/DATRAS-known-issues.yaml at all. That gap
# is why the downstream obus package could not implement sentinel handling
# without parsing opus's YAML behind its back.
#
# The policy itself lives in the registry (sentinels: resolution), not here.
# This file is the mechanism.

#' Read the sentinel registry
#'
#' Direct accessor for `inst/DATRAS-known-issues.yaml`'s `sentinels:` block.
#' Returns the registry as recorded, without interpretation -- see
#' [op_sentinel_policy()] for the resolved per-column verdict.
#'
#' @return List with `global`, `field_specific` and `resolution` components.
#' @examples
#' str(op_sentinels()$resolution$labels_meaning_absent)
#' @export
op_sentinels <- function() {
  yaml::read_yaml(system.file("DATRAS-known-issues.yaml", package = "opus"))$sentinels
}

# "HH, LT" -> c("HH", "LT"). The registry stores multi-table entries as one
# comma-separated string.
.split_tables <- function(x) trimws(strsplit(x, ",", fixed = TRUE)[[1]])

#' Resolve, per column, whether a sentinel means absence
#'
#' Applies the registry's documented resolution order to every column of a
#' table: an explicit `keep` entry wins; otherwise an `enum` whose `values:`
#' map documents the sentinel is kept unless its label means absence;
#' otherwise the sentinel is stripped.
#'
#' ICES overloads `-9`: of the 29 Tier 1 enum fields that document it, 24
#' label it as absence ("Not known", "Not available", ...) and 5 as a real
#' answer ("No ticklers are allowed", "No plus group", "Invalid hauls"). So
#' presence in the vocabulary decides nothing and the label decides
#' everything. An unrecognised label resolves to `keep`, never to `strip` --
#' silently destroying a documented code is the one failure this whole
#' mechanism exists to prevent.
#'
#' @param table Character scalar: `"HH"`, `"HL"`, `"CA"` or `"LT"`.
#' @param sentinel The sentinel value, as a string. Defaults to the
#'   registry's global value.
#' @return Data frame, one row per column: `table`, `field`, `type`,
#'   `action` (`"strip"` or `"keep"`), `label` (the documented label, or
#'   `NA`), `why`.
#' @seealso [op_strip_sentinels()] applies this; [op_sentinel_audit()]
#'   measures it against real data.
#' @examples
#' p <- op_sentinel_policy("HH")
#' p[p$action == "keep", c("field", "label")]
#' @export
op_sentinel_policy <- function(table, sentinel = NULL) {
  reg <- op_sentinels()
  if (is.null(sentinel)) sentinel <- reg$global[[1]]$value

  absent <- tolower(trimws(unlist(reg$resolution$labels_meaning_absent)))

  keep_index <- list()
  for (k in reg$resolution$keep) {
    for (tb in .split_tables(k$table)) {
      if (sentinel %in% k$values) keep_index[[paste(tb, k$field)]] <- k
    }
  }

  dict <- yaml::read_yaml(system.file("DATRAS-data-dict.yaml", package = "opus"))
  tnames <- vapply(dict$tables, function(t) t$name, character(1))
  if (!table %in% tnames) {
    stop("Unknown table '", table, "'. Valid: ", paste(tnames, collapse = ", "),
         call. = FALSE)
  }
  cols <- dict$tables[[which(tnames == table)]]$columns

  rows <- lapply(cols, function(cc) {
    key <- paste(table, cc$name)
    label <- NA_character_

    if (!is.null(keep_index[[key]])) {
      return(data.frame(table = table, field = cc$name, type = cc$type,
                        action = "keep", label = keep_index[[key]]$label,
                        why = "registry: documented real answer",
                        stringsAsFactors = FALSE))
    }

    if (identical(cc$type, "enum") && !is.null(names(cc$values)) &&
        sentinel %in% names(cc$values)) {
      label <- as.character(cc$values[[sentinel]])
      is_absent <- tolower(trimws(label)) %in% absent
      return(data.frame(
        table = table, field = cc$name, type = cc$type,
        action = if (is_absent) "strip" else "keep", label = label,
        why = if (is_absent) "vocabulary label means absence"
              else "vocabulary label is not a known absence label",
        stringsAsFactors = FALSE))
    }

    data.frame(table = table, field = cc$name, type = cc$type,
               action = "strip", label = label,
               why = "no documented code for this sentinel",
               stringsAsFactors = FALSE)
  })

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' Replace sentinels with NA, where they mean absence
#'
#' Phase B of the conversion. Runs **after** [op_rename_to_new()] -- the
#' registry and the dictionary are both keyed by current field names -- and
#' **before** [op_cast_to_spec()], because a `Date` column cannot hold `-9`.
#'
#' @param df Data frame carrying current field names.
#' @param table Character scalar: `"HH"`, `"HL"`, `"CA"` or `"LT"`.
#' @param sentinel The sentinel value, as a string. Defaults to the
#'   registry's global value.
#' @param quiet Logical; if `FALSE`, report what was stripped and kept.
#' @return `df` with absence-meaning sentinels replaced by `NA`. Columns
#'   resolved to `keep` are untouched.
#' @seealso [op_sentinel_policy()] for why each column is treated as it is.
#' @examples
#' \dontrun{
#'   df <- op_strip_sentinels(df, "HH")
#' }
#' @export
op_strip_sentinels <- function(df, table, sentinel = NULL, quiet = TRUE) {
  policy <- op_sentinel_policy(table, sentinel)
  if (is.null(sentinel)) sentinel <- op_sentinels()$global[[1]]$value

  to_strip <- intersect(policy$field[policy$action == "strip"], names(df))
  n_hit <- 0L

  for (col in to_strip) {
    x <- df[[col]]
    hit <- !is.na(x) & as.character(x) == sentinel
    if (any(hit)) {
      n_hit <- n_hit + sum(hit)
      x[hit] <- NA
      df[[col]] <- x
    }
  }

  if (!quiet) {
    kept <- policy$field[policy$action == "keep"]
    message(sprintf(
      "%s: replaced %d '%s' value(s) with NA across %d column(s); kept in %d documented column(s)%s",
      table, n_hit, sentinel, length(to_strip), length(kept),
      if (length(kept)) paste0(" (", paste(kept, collapse = ", "), ")") else ""
    ))
  }

  df
}

#' Count sentinel values per column in a parquet file
#'
#' The evidence sweep behind every strip/keep decision, and the regression
#' check after a rebuild: a column must either lose all its sentinels (and
#' gain exactly that many nulls) or keep every one of them. Anything in
#' between is a bug.
#'
#' @param path Path or URL to a parquet file.
#' @param table Character scalar: `"HH"`, `"HL"`, `"CA"` or `"LT"`; used to
#'   attach each column's resolved policy.
#' @param sentinel The sentinel value, as a string. Defaults to the
#'   registry's global value.
#' @return Data frame, one row per column that contains the sentinel:
#'   `field`, `n` (sentinel count), `n_rows`, `pct`, `n_null`, `action`,
#'   `label`. Sorted by `pct` descending.
#' @examples
#' \dontrun{
#'   op_sentinel_audit(".datras/to_https/HH.parquet", "HH")
#' }
#' @export
op_sentinel_audit <- function(path, table, sentinel = NULL) {
  if (is.null(sentinel)) sentinel <- op_sentinels()$global[[1]]$value
  policy <- op_sentinel_policy(table, sentinel)

  d <- arrow::read_parquet(path, as_data_frame = TRUE)
  n_rows <- nrow(d)

  rows <- lapply(names(d), function(col) {
    x <- d[[col]]
    n <- sum(!is.na(x) & as.character(x) == sentinel)
    if (n == 0) return(NULL)
    i <- match(col, policy$field)
    data.frame(
      field = col, n = n, n_rows = n_rows, pct = round(100 * n / n_rows, 2),
      n_null = sum(is.na(x)),
      action = if (is.na(i)) NA_character_ else policy$action[i],
      label  = if (is.na(i)) NA_character_ else policy$label[i],
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, rows)
  if (is.null(out)) {
    return(data.frame(field = character(), n = integer(), n_rows = integer(),
                      pct = numeric(), n_null = integer(),
                      action = character(), label = character(),
                      stringsAsFactors = FALSE))
  }
  out <- out[order(-out$pct), ]
  rownames(out) <- NULL
  out
}
