#' Download and cache ICES's DATRAS field-description spreadsheet
#'
#' A fourth ICES data source, found 2026-08-17 while investigating why
#' CA.HaulNo has no icesVocab entry (see AGENTS.md's Data Sources section
#' and DEVLOG.md's 2026-08-17 entry): a hand-maintained Excel file --
#' "DATRAS_Field_descriptions_and_example_file_{Month}{Year}.xlsx" --
#' published at the URL below, linked from
#' https://www.ices.dk/data/data-portals/Pages/DATRAS_format_description.aspx.
#' This is the closest thing to the "Technical Reference" AGENTS.md has
#' always cited as one of opus's three consolidated sources, but which had
#' never actually been fetched or checked against anything before this
#' date -- aspirational, not verified, until now.
#'
#' Unlike WSDL/getDatrasFieldList/icesVocab (opus's other three sources,
#' all live APIs), this is a versioned document ICES republishes every few
#' months under a dated filename -- there is no stable, permanent URL for
#' "the current version." Cached with the same hash-stamped provenance
#' convention as archive_02_download.R's getDatrasFieldList snapshot and
#' build_icesvocab_snapshot.R, so re-running this script later will fetch
#' whatever ICES currently publishes and produce a new, distinctly-named
#' snapshot rather than silently overwriting the old one -- staleness stays
#' visible, not hidden (same reasoning behind flagging inst/*.parquet's own
#' undecided staleness as a real problem -- see TODO.md's D1 item).
#'
#' The file has 6 sheets: "General Notes" (free text, includes the
#' ICES-wide "-9 for no information" convention and per-field version-note
#' changelog), "HH/HL/CA-Unaggregated data" and "LT-Unaggregated litter
#' data" (one row per field: MaxWidth, Mandatory, DataType, Vocab,
#' Description), and "Example file". The `Vocab` column is populated in
#' only 1 of 154 field rows as of the December 2025 version (CA's
#' PreservationMethod, a direct codetypeguid link) -- so this file mostly
#' does NOT double as an icesVocab cross-reference; don't assume it will
#' for other fields without checking.
#'
#' Usage: Rscript data-raw/build_field_description_snapshot.R

source("data-raw/archive_01_download_config.R")

FIELD_DESC_URL <- "https://www.ices.dk/data/Documents/DATRAS/DATRAS_Field_descriptions_and_example_file_December2025.xlsx"

log_msg("Downloading DATRAS field-description spreadsheet...")
log_msg("  Source: %s", FIELD_DESC_URL)

tmp <- tempfile(fileext = ".xlsx")
resp <- tryCatch({
  utils::download.file(FIELD_DESC_URL, tmp, mode = "wb", quiet = TRUE)
  TRUE
}, error = function(e) {
  log_msg("ERROR: download failed: %s", conditionMessage(e))
  FALSE
})

if (!resp || !file.exists(tmp) || file.size(tmp) == 0) {
  stop("Failed to download field-description spreadsheet from ", FIELD_DESC_URL, call. = FALSE)
}

file_sha <- digest::digest(file = tmp, algo = "sha256")
dir.create(DATRAS_SCHEMAS, showWarnings = FALSE, recursive = TRUE)
dest <- file.path(DATRAS_SCHEMAS,
                   sprintf("datras_field_descriptions_%s_%s.xlsx",
                           format(Sys.time(), "%Y%m%d_%H%M%S"),
                           substr(file_sha, 1, 8)))
file.copy(tmp, dest, overwrite = TRUE)
unlink(tmp)

log_msg("Field-description spreadsheet cached: %s (%d bytes, SHA256: %s)",
        basename(dest), file.size(dest), file_sha)

if (requireNamespace("readxl", quietly = TRUE)) {
  sheets <- readxl::excel_sheets(dest)
  log_msg("Sheets: %s", paste(sheets, collapse = " | "))
} else {
  log_msg("NOTE: readxl not installed -- sheet contents not verified, only downloaded.")
}
