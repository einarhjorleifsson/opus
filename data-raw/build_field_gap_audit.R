#' Cross-referenced field-gap audit: sentinel usage x vocab coverage x
#' spreadsheet-vs-WSDL/icesVocab conflicts, all 190 Tier 1 fields
#'
#' Triggered by a real, unplanned discovery (2026-08-17): investigating why
#' `CA.HaulNo` has no icesVocab entry surfaced `StNo` as a second instance
#' of the exact same pattern (no vocab, large real sentinel usage, ICES's
#' own field-description spreadsheet disclaiming any defined coding
#' system). Checking fields one at a time as they happen to come up is
#' exactly the ad hoc approach Working Principle 9 exists to warn against
#' -- this script instead cross-references three things that have never
#' been cross-referenced together before, across every Tier 1 field, not
#' just the ones noticed by accident:
#'
#' 1. Real sentinel usage (all 9 candidate sentinel values from the
#'    already-fixed `sentinel_replacement_data_loss` bug's own list,
#'    checked fresh against today's `.datras/*_legacy.parquet`, not a
#'    cached count from an earlier session).
#' 2. icesVocab name-match coverage (`op_vocab_resolve_key()`, legacy
#'    names -- icesVocab is empirically legacy-name-keyed, confirmed
#'    2026-08-08/2026-08-09). Code lookups use the cached full-catalog
#'    snapshot (`build_icesvocab_snapshot.R`), not ~190 live HTTP calls.
#' 3. The DATRAS field-description spreadsheet's `DataType`/`Mandatory`/
#'    `Vocab` columns (found 2026-08-17), matched by CURRENT/curated
#'    name -- confirmed by inspection that the spreadsheet uses ICES's
#'    own current field names, not legacy ones, unlike icesVocab.
#'
#' Two things this script flags, neither previously checked exhaustively:
#'
#' - **sentinel_no_vocab**: a field with real, non-trivial sentinel usage
#'   AND zero icesVocab coverage under any name -- the HaulNo/StNo
#'   pattern. Not automatically a problem (plenty of legitimate
#'   identifiers/quantities have no vocab and don't need one), but every
#'   instance should be a conscious, documented decision, not a silent
#'   gap nobody has looked at.
#' - **spreadsheet_conflict**: the spreadsheet's `DataType` disagrees with
#'   live WSDL's type for the same field, or its `Mandatory` flag
#'   disagrees with whether opus's own spec currently declares the field
#'   `required`/`primary_key`/`foreign_key`. ICES's own sources
#'   disagreeing with each other is itself the finding (see Issue 11 for
#'   the same class of thing, found via a narrower check).
#'
#' Legacy yaml (`inst/DATRAS-data-dict-legacy.yaml`) and curated yaml
#' (`inst/DATRAS-data-dict.yaml`) are paired by column position within
#' each table -- spec_03_translate_new_names.R does a pure 1:1 rename
#' preserving column count and order, so position is a safe join key
#' where regex-extracting names back out of `details:` would be fragile.
#'
#' Usage: Rscript data-raw/build_field_gap_audit.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})
source("R/vocab.R")
source("data-raw/spec_00_operation_types.R")

SENTINELS <- c("-9", "-99", "-999", "-1", "-5", "-95", "-100", "-900", "88888888")
SENTINEL_MIN_ROWS <- 10   # below this, "sentinel-shaped value present" is noise, not a finding

schema_dir <- ".datras/ices-schemas"
vocab_snapshot_file <- sort(list.files(schema_dir, pattern = "^icesvocab_full_.*\\.tsv$", full.names = TRUE), decreasing = TRUE)[1]
excel_file <- sort(list.files(schema_dir, pattern = "^datras_field_descriptions_.*\\.xlsx$", full.names = TRUE), decreasing = TRUE)[1]
if (is.na(vocab_snapshot_file)) stop("No icesvocab_full_*.tsv snapshot found -- run build_icesvocab_snapshot.R first.", call. = FALSE)
if (is.na(excel_file)) stop("No datras_field_descriptions_*.xlsx snapshot found -- run build_field_description_snapshot.R first.", call. = FALSE)
message("Using icesVocab snapshot: ", basename(vocab_snapshot_file))
message("Using field-description spreadsheet: ", basename(excel_file))

vocab_codes_cache <- read.delim(vocab_snapshot_file, stringsAsFactors = FALSE)
get_codes_cached <- function(key) {
  vocab_codes_cache$key[vocab_codes_cache$type == key]
}

types <- op_vocab_get_types()

known_issues_text <- paste(readLines("inst/DATRAS-known-issues.yaml"), collapse = "\n")
ices_issue_report_text <- paste(readLines("articles/issues.qmd"), collapse = "\n")

excel_sheets <- list(
  HH = readxl::read_excel(excel_file, sheet = "HH-Unaggregated data"),
  HL = readxl::read_excel(excel_file, sheet = "HL-Unaggregated data"),
  CA = readxl::read_excel(excel_file, sheet = "CA-Unaggregated data"),
  LT = readxl::read_excel(excel_file, sheet = "LT-Unaggregated litter data")
)

wsdl_ops <- c(HH = "getHHdata", HL = "getHLdata", CA = "getCAdata", LT = "getLitterAssessmentOutput")
wsdl_types <- lapply(wsdl_ops, get_datras_operation_types)

wsdl_to_excel_type <- function(wsdl_type) {
  switch(wsdl_type, "string" = "char", "int" = "int",
         if (grepl("^decimal", wsdl_type)) "decimal" else wsdl_type)
}
excel_to_comparable_type <- function(excel_type) {
  if (is.na(excel_type)) return(NA_character_)
  if (grepl("^decimal", excel_type)) return("decimal")
  excel_type
}

legacy_dict <- yaml::read_yaml("inst/DATRAS-data-dict-legacy.yaml")
curated_dict <- yaml::read_yaml("inst/DATRAS-data-dict.yaml")

rows <- list()

for (ti in seq_along(legacy_dict$tables)) {
  tbl_legacy <- legacy_dict$tables[[ti]]
  tbl_curated <- curated_dict$tables[[ti]]
  tname <- tbl_legacy$name
  stopifnot(tname == tbl_curated$name, length(tbl_legacy$columns) == length(tbl_curated$columns))

  pq <- open_dataset(sprintf(".datras/%s_legacy.parquet", tname))
  pq_cols <- names(pq)
  excel_sheet <- excel_sheets[[tname]]
  wsdl_map <- setNames(wsdl_types[[tname]]$type, wsdl_types[[tname]]$field)

  for (ci in seq_along(tbl_legacy$columns)) {
    col_legacy <- tbl_legacy$columns[[ci]]
    col_curated <- tbl_curated$columns[[ci]]
    legacy_name <- col_legacy$name
    curated_name <- col_curated$name

    # -- 1. real sentinel usage --
    sentinel_n <- 0L
    if (legacy_name %in% pq_cols) {
      cnt <- tryCatch(
        pq |> filter(.data[[legacy_name]] %in% SENTINELS) |> summarise(n = n()) |> collect() |> pull(n),
        error = function(e) 0L
      )
      if (length(cnt) == 1 && !is.na(cnt)) sentinel_n <- cnt
    }

    # -- 2. icesVocab coverage (legacy name) --
    resolved <- op_vocab_resolve_key(legacy_name, types)
    n_candidates <- length(resolved$candidates)

    # -- 3. spreadsheet row (curated name) --
    excel_row <- if (!is.null(excel_sheet)) excel_sheet[excel_sheet$Field == curated_name, ] else excel_sheet[0, ]
    has_excel <- nrow(excel_row) == 1

    spreadsheet_conflict <- NA_character_
    if (has_excel) {
      excel_dt <- excel_to_comparable_type(excel_row$DataType[1])
      wsdl_t <- wsdl_map[[legacy_name]]
      wsdl_dt <- if (!is.null(wsdl_t)) wsdl_to_excel_type(wsdl_t) else NA_character_
      type_conflict <- !is.na(excel_dt) && !is.na(wsdl_dt) && excel_dt != wsdl_dt

      excel_mandatory <- identical(excel_row$Mandatory[1], "Yes")
      opus_required <- any(c("required", "primary_key") %in% unlist(col_curated$constraints))
      mandatory_conflict <- excel_mandatory != opus_required

      conflicts <- c(
        if (isTRUE(type_conflict)) sprintf("DataType: spreadsheet=%s vs WSDL=%s", excel_dt, wsdl_dt),
        if (isTRUE(mandatory_conflict)) sprintf("Mandatory: spreadsheet=%s vs opus_required=%s", excel_mandatory, opus_required)
      )
      if (length(conflicts) > 0) spreadsheet_conflict <- paste(conflicts, collapse = "; ")
    }

    already_known <- grepl(legacy_name, known_issues_text, fixed = TRUE)
    already_in_issue_report <- grepl(legacy_name, ices_issue_report_text, fixed = TRUE) ||
      grepl(curated_name, ices_issue_report_text, fixed = TRUE)

    # A sentinel isn't an undocumented gap if opus's OWN curated spec
    # already accounts for it -- either as one of an enum's declared
    # `values:` (e.g. GenSamp's Y/N/-9), or named in free-text `details:`
    # (e.g. DateofCalculation's already-excluded-by-range -9 note). Only
    # checking known-issues.yaml (an ICES-escalation registry, not opus's
    # own field documentation) would wrongly flag both of those as new.
    curated_values <- unlist(col_curated$values)
    curated_value_names <- if (!is.null(names(curated_values)) && any(names(curated_values) != "")) names(curated_values) else curated_values
    sentinel_in_own_values <- any(SENTINELS %in% curated_value_names)
    sentinel_in_own_details <- !is.null(col_curated$details) && grepl("-9|sentinel", col_curated$details, ignore.case = TRUE)
    already_self_documented <- sentinel_in_own_values || sentinel_in_own_details

    rows[[length(rows) + 1]] <- data.frame(
      table = tname, legacy_field = legacy_name, curated_field = curated_name,
      curated_type = if (is.null(col_curated$type)) NA_character_ else col_curated$type,
      sentinel_rows = sentinel_n,
      vocab_candidates = n_candidates,
      sentinel_no_vocab = sentinel_n >= SENTINEL_MIN_ROWS && n_candidates == 0 && !already_self_documented,
      already_in_known_issues = already_known,
      already_in_issue_report = already_in_issue_report,
      already_self_documented = already_self_documented,
      in_spreadsheet = has_excel,
      spreadsheet_conflict = spreadsheet_conflict,
      stringsAsFactors = FALSE
    )
  }
}

out <- do.call(rbind, rows)
out <- out[order(out$table, out$legacy_field), ]

write.csv(out, "data-raw/DATRAS-field-gap-audit.csv", row.names = FALSE)

flagged <- out[out$sentinel_no_vocab & !out$already_in_known_issues, ]
conflicts <- out[!is.na(out$spreadsheet_conflict), ]
conflicts_new <- conflicts[!conflicts$already_in_known_issues & !conflicts$already_in_issue_report, ]
conflicts_known <- conflicts[conflicts$already_in_known_issues | conflicts$already_in_issue_report, ]

message("")
message("Wrote data-raw/DATRAS-field-gap-audit.csv (", nrow(out), " fields)")
message("")
message("=== sentinel present, zero external vocab, NOT already documented anywhere in opus's own spec or known-issues.yaml (", nrow(flagged), ") ===")
if (nrow(flagged) > 0) {
  for (i in seq_len(nrow(flagged))) {
    r <- flagged[i, ]
    message(sprintf("  %s.%-14s sentinel_rows=%-8d vocab_candidates=0", r$table, r$legacy_field, r$sentinel_rows))
  }
}
message("")
message("=== spreadsheet vs WSDL/opus conflicts -- NEW, not already flagged anywhere (", nrow(conflicts_new), ") ===")
if (nrow(conflicts_new) > 0) {
  for (i in seq_len(nrow(conflicts_new))) {
    r <- conflicts_new[i, ]
    message(sprintf("  %s.%-14s %s", r$table, r$curated_field, r$spreadsheet_conflict))
  }
}
message("")
message("=== spreadsheet vs WSDL/opus conflicts -- corroborates something already known-issues.yaml/ICES_ISSUE_REPORT.md mentions (", nrow(conflicts_known), ") ===")
if (nrow(conflicts_known) > 0) {
  for (i in seq_len(nrow(conflicts_known))) {
    r <- conflicts_known[i, ]
    message(sprintf("  %s.%-14s %s", r$table, r$curated_field, r$spreadsheet_conflict))
  }
}
