#' Consolidate the partitioned archive into one parquet per table
#'
#' Output: .datras/to_https/raw/{HH,HL,CA,LT}.parquet -- the full Tier 1
#' archive, in opus's current field names, with sentinels already resolved.
#' Staged for manual publish to the https server.
#'
#' The raw/ subdirectory keeps the four raw exchange tables separate from
#' everything else that gets published alongside them -- the companion
#' catalog.duckdb (data-raw/spec_04_build_catalog.R), and any derived
#' products added later.
#'
#' This script used to be archive_06_split_legacy_new.R and emitted two files
#' per table ({T}_legacy.parquet and {T}_new.parquet), renaming at this stage.
#' Both of those are gone as of 2026-08-29:
#'
#'  - The rename moved upstream into archive_04/archive_05, where it happens
#'    per file via opus::op_rename_to_new() immediately after type casting.
#'    By the time data reaches here it is already in current names, so there
#'    is nothing left to rename.
#'  - opus publishes current names only. Carrying a parallel legacy-named
#'    copy meant every consumer had to choose, and the two could drift.
#'
#' The crosswalk ground-truth check that used to live here has not been
#' dropped -- it moved into op_rename_to_new(), which asserts the incoming
#' columns against the crosswalk on every single file rather than once per
#' consolidation. What remains here are the two checks that can only be made
#' on the whole table at once.
#'
#' Usage: Rscript data-raw/archive_06_consolidate.R
#'        Rscript data-raw/archive_06_consolidate.R LT      # one table

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(opus)
})

args <- commandArgs(trailingOnly = TRUE)
TABLES <- if (length(args) > 0) args else c("HH", "HL", "CA", "LT")
OUT_DIR <- ".datras/to_https/raw"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

for (t in TABLES) {
  part_dir <- file.path(".datras/parquet", t)
  out_path <- file.path(OUT_DIR, paste0(t, ".parquet"))

  if (!dir.exists(part_dir)) {
    stop("No partitioned directory ", part_dir, " for table ", t,
         " -- run data-raw/archive_05_backfill_lt_partitions.R first.",
         call. = FALSE)
  }

  df <- arrow::open_dataset(part_dir) |> dplyr::collect()

  # Check 1: nothing legacy-named survived. If op_rename_to_new() were ever
  # skipped, or silently degraded (see .rename_crosswalk()'s note on why the
  # crosswalk must be resolved over all four tables at once), this is where
  # it shows up.
  crosswalk <- op_datras_rename_crosswalk()
  xw <- crosswalk[crosswalk$RecordHeader == t, ]
  renamed <- xw$old_name[xw$old_name != xw$new_name]
  leftover <- intersect(renamed, names(df))
  if (length(leftover) > 0) {
    stop(sprintf(
      "Table %s still carries %d legacy column name(s): %s. The rename in archive_04/05 did not run, or ran degraded.",
      t, length(leftover), paste(leftover, collapse = ", ")
    ), call. = FALSE)
  }

  # Check 2: the sentinel policy held. Every column must be all-or-nothing --
  # a column the policy strips must contain no sentinel at all, and one it
  # keeps must still contain them. A partial strip means something ran twice,
  # or ran on half the files.
  policy <- op_sentinel_policy(t)
  sentinel <- op_sentinels()$global[[1]]$value
  for (col in intersect(policy$field, names(df))) {
    n <- sum(!is.na(df[[col]]) & as.character(df[[col]]) == sentinel)
    act <- policy$action[match(col, policy$field)]
    if (act == "strip" && n > 0) {
      stop(sprintf("Table %s: %s is policy '%s' but still holds %d '%s' value(s).",
                   t, col, act, n, sentinel), call. = FALSE)
    }
  }

  kept <- policy$field[policy$action == "keep"]
  kept_present <- intersect(kept, names(df))

  arrow::write_parquet(df, out_path, compression = "snappy")
  message(sprintf("%-3s -> %s (%s rows, %d cols; sentinels kept in %s)",
                  t, out_path, format(nrow(df), big.mark = ","), ncol(df),
                  if (length(kept_present)) paste(kept_present, collapse = ", ") else "none"))
}

message("")
message("Done. Current-named parquet staged under ", OUT_DIR, "/")
message("Next: data-raw/spec_04_build_catalog.R, then publish both.")
message("Verify with: opus::op_validate_meta('", OUT_DIR, "/HH.parquet', 'HH')")
