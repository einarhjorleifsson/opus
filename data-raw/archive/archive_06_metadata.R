#' Build the `datras:` metadata payload embedded in each raw parquet file
#'
#' Sourced by data-raw/archive_06_consolidate.R, which writes the payload in
#' the same write_parquet() call that writes the data -- so no published file
#' ever exists without its own dictionary.
#'
#' Five keys, one concern each, so a consumer wanting only the crosswalk parses
#' ~4 KB rather than the whole dictionary, and so a rebuild's diff stays
#' legible (provenance/coverage change every build; dict rarely):
#'
#'   datras:dict          the table's slice of inst/DATRAS-data-dict.yaml, as
#'                        resolved by `data-dict export-spec`, plus three things
#'                        export-spec cannot know: legacy_name, parquet_type,
#'                        r_type.
#'   datras:provenance    who built this, from what, when.
#'   datras:sentinels     the strip/keep policy actually applied.
#'   datras:coverage      surveys, year range, survey/year/quarter combinations.
#'   datras:known_issues  the slice of DATRAS-known-issues.yaml naming this table.
#'
#' Deliberately NOT compressed: DuckDB has no general gunzip scalar, and the
#' whole point is that `SELECT decode(value) FROM parquet_kv_metadata(url)`
#' works with nothing but a DuckDB client. JSON rather than YAML for the same
#' reason -- DuckDB cannot parse YAML but has native json_extract.
#'
#' See PLAN-embedded-metadata.md for the measurements behind these choices.

suppressPackageStartupMessages({
  library(jsonlite)
  library(opus)
})

`%||%` <- function(x, y) if (is.null(x)) y else x

DM_CLI  <- path.expand("~/garbage/data-dict/target/release/data-dict")
DM_DICT <- "inst/DATRAS-data-dict.yaml"

# ---------------------------------------------------------------------------
# The dictionary, resolved once per run by data-dict itself.
#
# export-spec runs the same pass as validate-spec and fails with the same S##
# diagnostics, so a dictionary that would not validate never reaches a file.
# It resolves types, `range` to {min,max}, enum values/value_labels, joins and
# definitions -- none of which we re-derive here.
# ---------------------------------------------------------------------------
dm_export_spec <- function(dict_path = DM_DICT, cli_bin = DM_CLI) {
  if (!file.exists(cli_bin)) {
    stop("data-dict CLI not found at ", cli_bin,
         " -- needed to build the embedded dictionary.", call. = FALSE)
  }
  out <- system2(cli_bin, c("export-spec", dict_path),
                 stdout = TRUE, stderr = FALSE)
  status <- attr(out, "status") %||% 0L
  if (status != 0L) {
    stop("`data-dict export-spec ", dict_path, "` failed (exit ", status, ").",
         call. = FALSE)
  }
  jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE)
}

# ---------------------------------------------------------------------------
# The schema write_parquet() actually produces, learned by writing one row to a
# temp file rather than predicting it. One row is enough because the R class ->
# parquet type mapping is per column, not per value, and dm_assert_schema()
# below re-checks the finished file against what we embedded, so a wrong guess
# stops the build instead of shipping.
# ---------------------------------------------------------------------------
dm_logical <- function(lt) {
  v <- unlist(lt)
  if (!length(v)) return(NA_character_)
  # A logical type is a name plus optional parameters: render DATE as "DATE"
  # and a sized int as "INT(32,signed)", not as the raw "INT/32/TRUE".
  nm <- as.character(v[[1]])
  if (length(v) == 1) return(nm)
  args <- v[-1]
  args <- ifelse(args == "TRUE", "signed", ifelse(args == "FALSE", "unsigned", args))
  sprintf("%s(%s)", nm, paste(args, collapse = ","))
}

dm_written_schema <- function(df) {
  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)
  nanoparquet::write_parquet(
    utils::head(df, 1L), tmp, compression = "snappy",
    options = nanoparquet::parquet_options(write_arrow_metadata = FALSE))
  s <- as.data.frame(nanoparquet::read_parquet_schema(tmp))
  s <- s[!is.na(s$type), , drop = FALSE]          # drop the root schema element
  data.frame(name = s$name, type = s$type,
             logical_type = vapply(s$logical_type, dm_logical, ""),
             stringsAsFactors = FALSE)
}

#' Assert the finished file matches the dictionary embedded in it
#'
#' Called by archive_06_consolidate.R after the write. A file whose footer
#' claims a type the file does not hold is worse than one with no footer at all.
dm_assert_schema <- function(path, t) {
  act <- as.data.frame(nanoparquet::read_parquet_schema(path))
  act <- act[!is.na(act$type), , drop = FALSE]
  kv  <- nanoparquet::read_parquet_metadata(path)$file_meta_data$key_value_metadata[[1]]
  dict <- jsonlite::fromJSON(kv$value[kv$key == "datras:dict"], simplifyVector = FALSE)
  cols <- dict$table$columns

  bad <- character()
  for (col in cols) {
    i <- match(col$name, act$name)
    if (is.na(i)) { bad <- c(bad, sprintf("%s: not in file", col$name)); next }
    if (!identical(col$parquet_type, act$type[i])) {
      bad <- c(bad, sprintf("%s: dict says %s, file has %s",
                            col$name, col$parquet_type %||% "NULL", act$type[i]))
    }
    lt <- dm_logical(act$logical_type[[i]])
    dl <- col$logical_type %||% NA_character_
    if (!identical(as.character(dl), as.character(lt)) &&
        !(is.na(dl) && is.na(lt))) {
      bad <- c(bad, sprintf("%s: dict logical %s, file has %s",
                            col$name, dl, lt))
    }
  }
  if (length(bad)) {
    stop(sprintf("Table %s: embedded dictionary disagrees with the written file:\n  %s",
                 t, paste(bad, collapse = "\n  ")), call. = FALSE)
  }
  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# datras:dict
# ---------------------------------------------------------------------------
dm_dict <- function(t, df, spec, crosswalk) {
  tspec <- Filter(function(x) x$name == t, spec$tables)
  if (!length(tspec)) {
    stop("No table `", t, "` in ", DM_DICT, ".", call. = FALSE)
  }
  tspec <- tspec[[1]]
  xw <- crosswalk[crosswalk$RecordHeader == t, ]

  # The embedded crosswalk is only sufficient on its own if it is total and
  # bijective. It is (checked 2026-08-29 across all four tables) -- but assert
  # rather than trust, because a partial mapping is worse than none: the
  # rename keeps the original name on no match, so an un-renamed column would
  # pass through looking translated.
  stopifnot(
    "every file column has a crosswalk entry"    = all(names(df) %in% xw$new_name),
    "no crosswalk entry names a missing column"  = all(xw$new_name %in% names(df)),
    "crosswalk old_name is unique"               = !anyDuplicated(xw$old_name),
    "crosswalk new_name is unique"               = !anyDuplicated(xw$new_name)
  )

  # Physical types come from a real write, never from the YAML and never from
  # infer_parquet_schema(). Recording a type derived from the spec would defeat
  # the purpose of recording it -- and inference is the same mistake wearing a
  # different hat: infer_parquet_schema() reports DOUBLE for a Date column,
  # while write_parquet() actually lays down INT32 with a DATE logical type.
  # Found the hard way 2026-08-29, after it had already shipped a wrong
  # parquet_type for DateofCalculation into all four files.
  #
  # `type` (opus's curated semantic type) and `r_type` (what a reader gets
  # back) are allowed to disagree; making that divergence visible and
  # machine-checkable is the point.
  phys <- dm_written_schema(df)

  tspec$columns <- lapply(tspec$columns, function(col) {
    i <- match(col$name, phys$name)
    col$legacy_name <- xw$old_name[match(col$name, xw$new_name)]
    if (!is.na(i)) {
      col$parquet_type <- phys$type[i]
      if (!is.na(phys$logical_type[i]) && nzchar(phys$logical_type[i])) {
        col$logical_type <- phys$logical_type[i]
      }
      col$r_type <- class(df[[col$name]])[1]
    }
    col
  })

  # A dictionary that disagrees with its own file is worse than no dictionary.
  stopifnot(
    "dict columns match the file's, in order" =
      identical(vapply(tspec$columns, function(c) c$name, ""), names(df))
  )

  # Relationships that touch this table, so a consumer of one file still gets
  # its join keys and conflicts (the 8-column composite key, already authored).
  rels <- Filter(function(r) {
    tabs <- unique(unlist(lapply(r$pairs, function(p) c(p$left$table, p$right$table))))
    t %in% tabs
  }, spec$relationships %||% list())

  list(
    `$version`    = spec$`$version`,
    name          = spec$name,
    version       = spec$version,
    origin        = spec$origin,
    table         = tspec,
    relationships = rels,
    glossary      = spec$glossary
  )
}

# ---------------------------------------------------------------------------
# datras:provenance
#
# dict_sha256 is what lets a consumer tell whether the opus it has installed
# is the opus this file was built by, instead of silently preferring one.
# ---------------------------------------------------------------------------
dm_provenance <- function(t, df, dict_path = DM_DICT, cli_bin = DM_CLI) {
  sha <- function(f) tryCatch(sub(" .*", "", system2("shasum", c("-a", "256", f),
                                                     stdout = TRUE)),
                              error = function(e) NA_character_)
  git <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"),
                          stdout = TRUE, stderr = FALSE),
                  error = function(e) NA_character_)
  list(
    table         = t,
    n_rows        = nrow(df),
    n_cols        = ncol(df),
    source        = "ICES DATRAS ASMX web service",
    built_utc     = format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"),
    opus_version  = as.character(utils::packageVersion("opus")),
    opus_git_sha  = git,
    dict_sha256   = sha(dict_path),
    data_dict_cli = tryCatch(system2(cli_bin, "--version", stdout = TRUE),
                             error = function(e) NA_character_),
    writer        = paste("nanoparquet", utils::packageVersion("nanoparquet")),
    pipeline      = paste("archive_02_download -> archive_04_parse_phase2 ->",
                          "archive_05_backfill_lt_partitions -> archive_06_consolidate")
  )
}

# ---------------------------------------------------------------------------
# datras:sentinels
#
# archive_06 already computes and asserts this, then throws it away. A file
# that has had sentinels stripped from some columns and not others should say
# so in its own footer (AGENTS.md Working Principle 2) -- a consumer may not
# have opus installed to look the policy up. It is also half of the
# definition-vs-policy cross-check: a definition written against `-9` is
# meaningless on a column the policy stripped.
# ---------------------------------------------------------------------------
dm_sentinels <- function(t) {
  pol  <- op_sentinel_policy(t)
  glob <- op_sentinels()$global[[1]]
  list(
    value   = glob$value,
    meaning = glob$meaning,
    policy  = unname(lapply(split(pol, seq_len(nrow(pol))), function(r) {
      out <- list(field = r$field, action = r$action)
      if (!is.na(r$why))   out$why   <- r$why
      if (!is.na(r$label)) out$label <- r$label
      out
    }))
  )
}

# ---------------------------------------------------------------------------
# datras:coverage
#
# Column-wise arrays rather than one object per group: an object-per-group
# encoding repeats the three key names 972 times and ran to 55 KB, as large as
# the dictionary itself. Per-group row counts are dropped -- nothing needs them,
# and parquet already carries exact row counts in its own footer.
#
# This is what lets the parquet path answer "which surveys are in the archive?"
# without a live ICES call.
# ---------------------------------------------------------------------------
dm_coverage <- function(df) {
  key <- intersect(c("Survey", "Year", "Quarter"), names(df))
  cmb <- unique(df[, key, drop = FALSE])
  cmb <- cmb[do.call(order, unname(as.list(cmb))), , drop = FALSE]

  out <- list(
    surveys = sort(unique(as.character(df$Survey))),
    years   = if ("Year" %in% names(df)) range(df$Year, na.rm = TRUE) else NULL,
    n_groups = nrow(cmb)
  )
  out$combinations <- lapply(cmb, function(col) unname(col))
  out
}

# ---------------------------------------------------------------------------
# datras:known_issues
#
# The NS-IBTS 2022 Q1 HL row-count anomaly, the CA HaulNo orphans, and the rest
# are exactly the kind of fact that should travel with the data rather than sit
# in a sibling package's YAML.
# ---------------------------------------------------------------------------
dm_known_issues <- function(t) {
  ki <- yaml::read_yaml(system.file("DATRAS-known-issues.yaml", package = "opus"))
  keep <- Filter(function(i) grepl(t, i$table %||% "", fixed = TRUE),
                 ki$known_violations %||% list())
  unname(lapply(keep, function(i)
    i[intersect(c("id", "severity", "scope", "field", "table",
                  "issue", "extent", "discovered", "resolved"), names(i))]))
}

# ---------------------------------------------------------------------------
# Assemble. Returns a named character vector, the shape
# nanoparquet::write_parquet(metadata =) wants.
# ---------------------------------------------------------------------------
dm_build <- function(t, df, spec, crosswalk) {
  j <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE,
                                                 null = "null", digits = NA))
  c(
    "datras:dict"         = j(dm_dict(t, df, spec, crosswalk)),
    "datras:provenance"   = j(dm_provenance(t, df)),
    "datras:sentinels"    = j(dm_sentinels(t)),
    "datras:coverage"     = j(dm_coverage(df)),
    "datras:known_issues" = j(dm_known_issues(t))
  )
}
