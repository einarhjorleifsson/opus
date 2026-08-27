#' Consolidate the partitioned archive into legacy- and new-named parquet,
#' staged for manual publish to the https catalog server
#'
#' Two linked outputs, written directly to .datras/to_https/ (the staging
#' directory manually copied to the https server -- see
#' data-raw/spec_04_build_catalog.R for the companion catalog.duckdb built
#' alongside these):
#' 1. .datras/to_https/{HH,HL,CA,LT}_legacy.parquet -- the full consolidated
#'    archive exactly as ICES names it today, built directly from the
#'    partitioned .datras/parquet/{table}/Survey=*/Year=*/ output
#'    (regenerated fresh every run, not migrated-once from an old file --
#'    see Step 1's own comment for why that changed 2026-08-09).
#' 2. .datras/to_https/{HH,HL,CA,LT}_new.parquet -- the same full archive
#'    under opus's curated ("final") names, built by renaming columns in
#'    (1). Column names are the only difference from (1); no type casting
#'    or other value changes.
#'
#' Deliberately just a rename, nothing else (reaffirmed 2026-08-27, after a
#' same-day detour that added a blanket "-9 -> NA" sentinel scrub and a
#' derived `.id` column here, then rolled both back out): opus's own scope
#' is the metadata construct (the yaml dictionaries) and validating data
#' against it, not domain QC or data transformation -- see DESCRIPTION
#' ("no domain QC or data transformation ... belongs downstream in
#' obus/imbus"). Sentinel handling, `.id`, and further derived products
#' (e.g. HL_length.parquet, HL_summary.parquet) belong in the new obus,
#' not here.
#'
#' (No longer produces a legacy-named YAML here -- restructured 2026-08-09:
#' inst/DATRAS-data-dict-legacy.yaml is now a real, primary package file,
#' written directly by data-raw/spec_02_curate_dict.R. This script only
#' ever produced a pure name-swapped derivative of the curated yaml; now
#' that the legacy yaml exists upstream as its own source, deriving a
#' second copy of it here would just be a duplicate.)
#'
#' Crosswalk source: op_datras_rename_crosswalk() (R/field_names.R) -- the
#' same one data-raw/spec_03_translate_new_names.R uses to build
#' inst/DATRAS-data-dict.yaml from inst/DATRAS-data-dict-legacy.yaml. Used
#' to be derived by extracting "Legacy field name: X" annotations back out
#' of inst/DATRAS-data-dict.yaml's `details` text (op_legacy_field_name());
#' that annotation convention no longer exists (see spec_02's own header),
#' and even before it was dropped, having two independent derivations of
#' the same old<->new mapping was exactly the kind of duplication that
#' already caused one bug this session (a hand-rolled copy of
#' op_legacy_field_name()'s regex silently drifting from the real function).
#'
#' Every table's resulting crosswalk is asserted against the real legacy
#' parquet's actual column names before anything is written -- not assumed.
#'
#' Usage: Rscript data-raw/archive_06_split_legacy_new.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(opus)
})

TABLES <- c("HH", "HL", "CA", "LT")
dir.create(".datras/to_https", showWarnings = FALSE, recursive = TRUE)

## ---- Step 1: consolidate the partitioned legacy parquet directly ----
#
# Used to migrate a pre-existing .datras/parquet/{t}.parquet (built by some
# earlier, never-fully-documented process -- see [[legacy_new_split_20260808]])
# via a one-time rename. Dropped that 2026-08-09: once the partitioned
# per-file output is itself correct and internally consistent (the WSDL
# type-casting fix), consolidating directly from it every run is simpler,
# has a fully-known provenance, and self-heals if the partitioned data is
# ever reprocessed again -- no "which of two files is current" ambiguity
# to resolve by hand.

for (t in TABLES) {
  part_dir <- file.path(".datras/parquet", t)
  legacy_path <- file.path(".datras/to_https", paste0(t, "_legacy.parquet"))

  if (!dir.exists(part_dir)) {
    stop("No partitioned directory ", part_dir, " for table ", t,
         " -- run data-raw/archive_05_backfill_lt_partitions.R first.")
  }

  df <- arrow::open_dataset(part_dir) |> dplyr::collect()
  arrow::write_parquet(df, legacy_path, compression = "snappy")
  message("Consolidated ", part_dir, " -> ", legacy_path,
          " (", nrow(df), " rows, ", ncol(df), " cols)")
}

## ---- Step 2: ground-truth the crosswalk against the real legacy parquet ----

crosswalk <- op_datras_rename_crosswalk(TABLES)

for (t in TABLES) {
  real_cols <- names(arrow::read_parquet(file.path(".datras/to_https", paste0(t, "_legacy.parquet"))))
  expected <- crosswalk$old_name[crosswalk$RecordHeader == t]

  only_in_crosswalk <- setdiff(expected, real_cols)
  only_in_parquet <- setdiff(real_cols, expected)

  if (length(only_in_crosswalk) > 0 || length(only_in_parquet) > 0) {
    stop(sprintf(
      "Table %s: crosswalk doesn't match the real legacy parquet.\n  In crosswalk, not in parquet: %s\n  In parquet, not in crosswalk: %s",
      t, paste(only_in_crosswalk, collapse = ", "), paste(only_in_parquet, collapse = ", ")
    ))
  }
  message("Ground-truthed ", t, ": all ", length(expected), " legacy names match the real parquet exactly")
}

## ---- Step 3: build full-scale new-named parquet from the legacy parquet ----

for (t in TABLES) {
  legacy_path <- file.path(".datras/to_https", paste0(t, "_legacy.parquet"))
  new_path <- file.path(".datras/to_https", paste0(t, "_new.parquet"))

  xw <- crosswalk[crosswalk$RecordHeader == t, ]
  rename_map <- setNames(xw$new_name, xw$old_name)  # old -> new, already ground-truthed 1:1 above

  df <- arrow::read_parquet(legacy_path)
  names(df) <- unname(rename_map[names(df)])  # already ground-truthed 1:1 above

  arrow::write_parquet(df, new_path, compression = "snappy")
  message("Wrote ", new_path, " (", nrow(df), " rows, ", ncol(df), " cols)")
}

message("")
message("Done. Legacy and new-named parquet now live side by side under .datras/to_https/")
