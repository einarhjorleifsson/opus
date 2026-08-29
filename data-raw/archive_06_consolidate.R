#' Consolidate the partitioned archive into one parquet per table
#'
#' Output: .datras/to_https/raw/{HH,HL,CA,LT}.parquet -- the full Tier 1
#' archive, in opus's current field names, with sentinels already resolved,
#' and each file carrying its own dictionary in its parquet footer.
#' Staged for manual publish to the https server.
#'
#' The raw/ subdirectory keeps the four raw exchange tables separate from any
#' derived products added later.
#'
#' Each file embeds five `datras:` metadata keys (data-raw/archive_06_metadata.R)
#' in the same write that lays down the data, so no published file ever exists
#' without its own dictionary. That replaces the former companion
#' catalog.duckdb, which was a separate file describing other files: nothing
#' forced it to be rebuilt when the parquet was, and a consumer who downloaded
#' one table alone got no dictionary at all. Embedded metadata cannot drift
#' from the data it describes, and travels with the file.
#'
#' The writer is nanoparquet, not arrow. arrow serializes custom metadata a
#' second time inside its own ARROW:schema key (base64, ~1.37x), so a 124 KB
#' payload costs 290 KB in the footer; and ARROW:schema is arrow's own sidecar
#' that parquet does not require and DuckDB never reads. nanoparquet with
#' write_arrow_metadata = FALSE writes the payload once and nothing else.
#' Round-trip verified identical to arrow's across all four tables (names,
#' dimensions, column classes and data, 20.6M rows) on 2026-08-29, including
#' DateofCalculation's DATE logical type. See PLAN-embedded-metadata.md.
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

source("data-raw/archive_06_metadata.R")

args <- commandArgs(trailingOnly = TRUE)
TABLES <- if (length(args) > 0) args else c("HH", "HL", "CA", "LT")
# Both roots are overridable so the CSV-derived tree (archive_02b) can be
# consolidated alongside the XML one rather than replacing it.
PART_ROOT <- Sys.getenv("OPUS_PARQUET_ROOT", ".datras/parquet")
OUT_DIR   <- Sys.getenv("OPUS_STAGE_DIR", ".datras/to_https/raw")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# Resolved once for the whole run, not per table: export-spec runs validate-spec
# internally, so a dictionary that would not validate stops the build here
# rather than after some files have already been rewritten.
message("Resolving ", DM_DICT, " via data-dict export-spec ...")
SPEC <- dm_export_spec()
CROSSWALK <- op_datras_rename_crosswalk()

for (t in TABLES) {
  part_dir <- file.path(PART_ROOT, t)
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
  xw <- CROSSWALK[CROSSWALK$RecordHeader == t, ]
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

  # Build the footer payload before writing: dm_dict() asserts the crosswalk is
  # total and bijective and that the dictionary's columns match the file's, in
  # order, so a mismatch stops the build rather than shipping a file whose
  # dictionary disagrees with it.
  md <- dm_build(t, df, SPEC, CROSSWALK)

  nanoparquet::write_parquet(
    df, out_path, compression = "snappy", metadata = md,
    options = nanoparquet::parquet_options(write_arrow_metadata = FALSE))

  # And check the finished article against its own footer: every column's
  # declared parquet_type and logical_type must be what the file actually holds.
  dm_assert_schema(out_path, t)

  message(sprintf("%-3s -> %s (%s rows, %d cols; sentinels kept in %s)",
                  t, out_path, format(nrow(df), big.mark = ","), ncol(df),
                  if (length(kept_present)) paste(kept_present, collapse = ", ") else "none"))
  message(sprintf("    footer: %s (%s)",
                  paste(sprintf("%s %s", sub("^datras:", "", names(md)),
                                format(nchar(md, "bytes"), big.mark = ",")),
                        collapse = " | "),
                  format(structure(file.info(out_path)$size, class = "object_size"),
                         units = "auto")))
}

message("")
message("Done. Current-named parquet staged under ", OUT_DIR, "/,")
message("each carrying its own dictionary in its footer.")
message("Verify with: opus::op_validate_meta('", OUT_DIR, "/HH.parquet', 'HH')")
message("         or: SELECT decode(value) FROM parquet_kv_metadata('",
        OUT_DIR, "/HH.parquet') WHERE key = 'datras:dict';")
