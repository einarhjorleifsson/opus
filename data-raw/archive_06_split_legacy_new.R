#' Split the curated data-dict into legacy (current ICES) and full-scale new-named parquet
#'
#' Three linked outputs:
#' 1. .datras/{HH,HL,CA,LT}_legacy.parquet -- the full consolidated archive
#'    exactly as ICES names it today (previously .datras/parquet/{table}.parquet).
#' 2. .datras/DATRAS-data-dict-legacy.yaml -- inst/DATRAS-data-dict.yaml with
#'    every column's `name` swapped back to its legacy ICES name. Pure name
#'    swap only: top-level metadata and every `details` string stay
#'    byte-for-byte identical to inst/DATRAS-data-dict.yaml, even where a
#'    `details` line now reads oddly (e.g. a column named RecordType whose
#'    details still say "Legacy field name: RecordType").
#' 3. .datras/{HH,HL,CA,LT}.parquet -- the same full archive under the new
#'    (opus-curated, "final") names, built by renaming columns in (1) via the
#'    same crosswalk. Column names are the only difference from (1); no type
#'    casting or value changes.
#'
#' Crosswalk source: the yaml's own `details` "Legacy field name: X" notes,
#' extracted via the real op_legacy_field_name() (R/field_names.R, sourced
#' below -- confirmed identical output against every column in the current
#' yaml before switching to this from a hand-rolled copy of its regex, which
#' would otherwise silently drift from the real function on its next edit).
#' NOT data-raw/seed/DATRAS-exchange-name-history-seed.csv -- that seed predates
#' the cross-table-inference correction described in AGENTS.md (~23 LT fields
#' renamed by inference from HH/HL/CA, e.g. Ship->Platform), so it's missing
#' a `new_name` entry for 22 of LT's 58 columns (Platform, StationName,
#' HaulNumber, the four *Lat/*Long fields, etc.) -- confirmed by running it.
#'
#' LT's BottomDepth used to have a wrong "Legacy field name: Depth" note --
#' confirmed against real raw XML (both Depth and BottomDepth appear as
#' distinct, byte-for-byte-identical legacy fields on the same LT record) and
#' already filed as Issue 6 in data-raw/ICES_ISSUE_REPORT.md. Fixed at the
#' source in inst/DATRAS-data-dict.yaml; this script only asserts it stays
#' fixed rather than patching around it.
#'
#' Every table's resulting crosswalk is asserted against the real legacy
#' parquet's actual column names before anything is written -- not assumed.
#'
#' Usage: Rscript data-raw/archive_06_split_legacy_new.R

suppressPackageStartupMessages({
  library(arrow)
  library(yaml)
})

source("R/field_names.R")  # op_legacy_field_name()

TABLES <- c("HH", "HL", "CA", "LT")

## ---- Step 1: move consolidated legacy parquet out of .datras/parquet/ ----

for (t in TABLES) {
  old_path <- file.path(".datras/parquet", paste0(t, ".parquet"))
  new_path <- file.path(".datras", paste0(t, "_legacy.parquet"))
  old_exists <- file.exists(old_path)
  new_exists <- file.exists(new_path)

  if (old_exists && new_exists) {
    stop(sprintf(
      "Table %s: both %s and %s exist. This move only happens once; a fresh %s means the raw pipeline wrote new consolidated legacy data after the earlier migration. Resolve by hand (decide which is current) rather than have this script guess which one wins.",
      t, old_path, new_path, old_path
    ))
  } else if (new_exists) {
    message(t, "_legacy.parquet already in place, nothing to move")
  } else if (old_exists) {
    file.rename(old_path, new_path)
    message("Moved ", old_path, " -> ", new_path)
  } else {
    stop("Neither ", old_path, " nor ", new_path, " exists for table ", t)
  }
}

## ---- Step 2a: derive the crosswalk from the yaml itself ----

dict <- read_yaml("inst/DATRAS-data-dict.yaml")

# op_legacy_field_name() returns NA when a column has no "Legacy field name:"
# note; that means unchanged (old name == new name), per its own contract
# (see R/field_names.R and op_field_name_map()'s has_legacy flag).
crosswalk <- do.call(rbind, lapply(dict$tables, function(tbl) {
  do.call(rbind, lapply(tbl$columns, function(col) {
    legacy <- op_legacy_field_name(col$details)
    data.frame(table = tbl$name, new_name = col$name,
               old_name = if (is.na(legacy)) col$name else legacy,
               stringsAsFactors = FALSE)
  }))
}))

# BottomDepth's wrong "Legacy field name: Depth" note was fixed at the
# source (inst/DATRAS-data-dict.yaml) rather than patched here. Assert it
# stays fixed instead of silently tolerating a regression.
bd <- crosswalk$table == "LT" & crosswalk$new_name == "BottomDepth"
stopifnot(sum(bd) == 1, crosswalk$old_name[bd] == "BottomDepth")

## ---- Step 2b: ground-truth the crosswalk against the real legacy parquet ----

for (t in TABLES) {
  real_cols <- names(arrow::read_parquet(file.path(".datras", paste0(t, "_legacy.parquet"))))
  expected <- crosswalk$old_name[crosswalk$table == t]

  only_in_dict <- setdiff(expected, real_cols)
  only_in_parquet <- setdiff(real_cols, expected)

  if (length(only_in_dict) > 0 || length(only_in_parquet) > 0) {
    stop(sprintf(
      "Table %s: crosswalk doesn't match the real legacy parquet.\n  In yaml, not in parquet: %s\n  In parquet, not in yaml: %s",
      t, paste(only_in_dict, collapse = ", "), paste(only_in_parquet, collapse = ", ")
    ))
  }
  message("Ground-truthed ", t, ": all ", length(expected), " legacy names match the real parquet exactly")
}

## ---- Step 2c: write the legacy yaml (pure name-swap, nothing else touched) ----

legacy_dict <- dict
for (ti in seq_along(legacy_dict$tables)) {
  tname <- legacy_dict$tables[[ti]]$name
  for (ci in seq_along(legacy_dict$tables[[ti]]$columns)) {
    col <- legacy_dict$tables[[ti]]$columns[[ci]]
    col$name <- crosswalk$old_name[crosswalk$table == tname & crosswalk$new_name == col$name]
    legacy_dict$tables[[ti]]$columns[[ci]] <- col
  }
}

write_yaml(legacy_dict, ".datras/DATRAS-data-dict-legacy.yaml")
message("Wrote .datras/DATRAS-data-dict-legacy.yaml")

## ---- Step 3: build full-scale new-named parquet from the legacy parquet ----

for (t in TABLES) {
  legacy_path <- file.path(".datras", paste0(t, "_legacy.parquet"))
  new_path <- file.path(".datras", paste0(t, ".parquet"))

  xw <- crosswalk[crosswalk$table == t, ]
  rename_map <- setNames(xw$new_name, xw$old_name)  # old -> new, both directions unique

  df <- arrow::read_parquet(legacy_path)
  names(df) <- unname(rename_map[names(df)])  # already ground-truthed 1:1 above

  arrow::write_parquet(df, new_path, compression = "snappy")
  message("Wrote ", new_path, " (", nrow(df), " rows, ", ncol(df), " cols)")
}

message("")
message("Done. Legacy and final parquet + yaml now live side by side under .datras/")
