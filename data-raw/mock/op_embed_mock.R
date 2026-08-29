#' MOCK of the write side: what data-raw/archive_06_consolidate.R would gain.
#'
#' Reads the staged raw/ parquet, builds the five `datras:` metadata keys, and
#' writes an annotated copy to a scratch directory. The real archive is never
#' touched.
#'
#' Usage: Rscript op_embed_mock.R [OUT_DIR] [TABLE ...]

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(jsonlite); library(opus)
})

`%||%` <- function(x, y) if (is.null(x)) y else x

SRC     <- "/Users/einarhj/R/Pakkar/opus/.datras/to_https/raw"
DICT    <- "/Users/einarhj/R/Pakkar/opus/inst/DATRAS-data-dict.yaml"
CLI     <- path.expand("~/garbage/data-dict/target/release/data-dict")
args    <- commandArgs(trailingOnly = TRUE)
OUT     <- if (length(args)) args[1] else "mock/raw"
TABLES  <- if (length(args) > 1) args[-1] else c("HH", "HL", "CA", "LT")

dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

## --- 1. export-spec: the payload, resolved by data-dict, not hand-rolled ----
message("export-spec ...")
spec_json <- system2(CLI, c("export-spec", DICT), stdout = TRUE, stderr = FALSE)
spec <- jsonlite::fromJSON(paste(spec_json, collapse = "\n"), simplifyVector = FALSE)

## --- 2. things export-spec cannot know --------------------------------------
crosswalk <- op_datras_rename_crosswalk()
ki        <- yaml::read_yaml(system.file("DATRAS-known-issues.yaml", package = "opus"))
sentinel  <- op_sentinels()$global[[1]]$value

opus_sha <- tryCatch(
  system2("git", c("-C", "/Users/einarhj/R/Pakkar/opus", "rev-parse", "--short", "HEAD"),
          stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
dict_sha <- tryCatch(
  sub(" .*", "", system2("shasum", c("-a", "256", DICT), stdout = TRUE)),
  error = function(e) NA_character_)
cli_ver <- tryCatch(system2(CLI, "--version", stdout = TRUE), error = function(e) NA_character_)

# Slice relationships to those that touch this table.
rels_for <- function(tbl) {
  Filter(function(r) {
    tabs <- unique(unlist(lapply(r$pairs, function(p) c(p$left$table, p$right$table))))
    tbl %in% tabs
  }, spec$relationships %||% list())
}

# Slice known issues to those naming this table.
issues_for <- function(tbl) {
  keep <- Filter(function(i) grepl(tbl, i$table %||% "", fixed = TRUE), ki$known_violations)
  lapply(keep, function(i) i[c("id", "severity", "scope", "field", "table", "issue", "extent")])
}

for (t in TABLES) {
  src <- file.path(SRC, paste0(t, ".parquet"))
  message("\n== ", t, " ==")

  tab <- arrow::read_parquet(src, as_data_frame = FALSE)   # arrow Table
  df  <- as.data.frame(tab)
  phys <- as.data.frame(nanoparquet::read_parquet_schema(src))[-1, ]

  ## -- datras:dict ---------------------------------------------------------
  tspec <- Filter(function(x) x$name == t, spec$tables)[[1]]
  xw    <- crosswalk[crosswalk$RecordHeader == t, ]

  # Assert the mapping is total and bijective BEFORE writing it (plan section 1.8).
  stopifnot(
    "every file column has a crosswalk entry" = all(names(df) %in% xw$new_name),
    "no crosswalk entry names a missing column" = all(xw$new_name %in% names(df)),
    "old_name unique" = !anyDuplicated(xw$old_name),
    "new_name unique" = !anyDuplicated(xw$new_name)
  )

  tspec$columns <- lapply(tspec$columns, function(col) {
    i <- match(col$name, phys$name)
    col$legacy_name  <- xw$old_name[match(col$name, xw$new_name)]
    col$parquet_type <- if (!is.na(i)) phys$type[i] else NULL
    lt <- if (!is.na(i)) paste(unlist(phys$logical_type[[i]]), collapse = "/") else ""
    col$logical_type <- if (nzchar(lt)) lt else NULL
    col$r_type       <- if (!is.na(i)) class(df[[col$name]])[1] else NULL
    col
  })

  # Assert dict and file agree, in order (plan section 4.4).
  stopifnot("dict columns == file columns, in order" =
              identical(vapply(tspec$columns, function(c) c$name, ""), names(df)))

  dict <- list(
    `$version`    = spec$`$version`,
    name          = spec$name,
    version       = spec$version,
    origin        = spec$origin,
    table         = tspec,
    relationships = rels_for(t),
    glossary      = spec$glossary
  )

  ## -- datras:provenance ---------------------------------------------------
  provenance <- list(
    table = t, n_rows = nrow(df), n_cols = ncol(df),
    source = "ICES DATRAS ASMX web service",
    built_utc = format(as.POSIXct(file.info(src)$mtime, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"),
    opus_version = as.character(utils::packageVersion("opus")),
    opus_git_sha = opus_sha, dict_sha256 = dict_sha,
    data_dict_cli = cli_ver, arrow_version = as.character(utils::packageVersion("arrow")),
    pipeline = "archive_02_download -> 04_parse_phase2 -> 05_backfill -> 06_consolidate"
  )

  ## -- datras:sentinels ----------------------------------------------------
  pol <- op_sentinel_policy(t)
  sentinels <- list(
    value = sentinel,
    meaning = op_sentinels()$global[[1]]$meaning,
    policy = lapply(split(pol, seq_len(nrow(pol))), function(r)
      list(field = r$field, action = r$action, why = r$why))
  )
  names(sentinels$policy) <- NULL

  ## -- datras:coverage -----------------------------------------------------
  key <- intersect(c("Survey", "Year", "Quarter"), names(df))
  cov <- df |> dplyr::count(dplyr::across(dplyr::all_of(key)), name = "n_rows")
  coverage <- list(
    surveys = sort(unique(as.character(df$Survey))),
    years   = range(df$Year, na.rm = TRUE),
    combinations = cov
  )

  ## -- datras:known_issues -------------------------------------------------
  known <- issues_for(t)

  ## -- write ---------------------------------------------------------------
  j <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA)
  md <- list(
    "datras:dict"         = as.character(j(dict)),
    "datras:provenance"   = as.character(j(provenance)),
    "datras:sentinels"    = as.character(j(sentinels)),
    "datras:coverage"     = as.character(j(coverage)),
    "datras:known_issues" = as.character(j(known))
  )
  for (k in names(md)) message(sprintf("   %-22s %8d B", k, nchar(md[[k]], "bytes")))

  # nanoparquet, NOT arrow. Two measured reasons (2026-08-29):
  #  1. arrow serializes custom metadata a SECOND time inside ARROW:schema
  #     (base64, ~1.37x), so a 124 KB payload costs 290 KB in the footer.
  #  2. ARROW:schema is arrow's own sidecar -- parquet does not require it and
  #     DuckDB never reads it. write_arrow_metadata = FALSE drops it entirely,
  #     leaving only the five datras: keys.
  # Types (incl. DateofCalculation's DATE logical type) verified identical.
  out <- file.path(OUT, paste0(t, ".parquet"))
  nanoparquet::write_parquet(
    df, out, compression = "snappy", metadata = unlist(md),
    options = nanoparquet::parquet_options(write_arrow_metadata = FALSE))
  message(sprintf("   -> %s (%s rows, %d cols, %.1f MB)",
                  out, format(nrow(df), big.mark = ","), ncol(df),
                  file.info(out)$size / 1024^2))
}

message("\nDone.")
