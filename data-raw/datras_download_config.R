# Configuration for raw DATRAS XML download pipeline
# Stores raw XML from DATRAS web service with manifest tracking.
# Unlike obus (which consolidates to parquet), opus keeps raw XML and applies
# its own type/validation specs during a separate parse stage.
#
# Record types: HH (haul), HL (length), CA (age)
# Scope: Prototype test with 2025-2026

## ---- Configuration ----
OPUS_YEARS <- 1965:2026               # 1965-2026: full DATRAS history (62 years)
OPUS_SURVEYS <- NULL                  # NULL = all surveys; or e.g. c("NS-IBTS", "BTS", "BITS")
RECORD_TYPES <- c("HH", "HL", "CA", "LT")  # Exchange data (HH/HL/CA) + Litter assessment (LT)
WORKSPACE <- ".datras"                # Relative to package root

## ---- Paths (relative to opus package root) ----
DATRAS_XML_DIR <- file.path(WORKSPACE, "xml")
DATRAS_MANIFEST <- file.path(WORKSPACE, "manifest.tsv")
DATRAS_SCHEMAS <- file.path(WORKSPACE, "ices-schemas")
DATRAS_CATALOG <- file.path(WORKSPACE, "catalog.tsv")

## ---- Manifest schema ----
# One row per (record_type, survey, year, quarter)
# Keys: record_type, survey, year, quarter (uniquely identifies a cell)
MANIFEST_COLS <- c(
  "record_type", "survey", "year", "quarter",
  "status",           # "ok" = fetched successfully, "empty" = ICES returned 0 rows,
                      # "none" = record type doesn't exist for this cell,
                      # "error" = network/transient failure
  "n_rows",           # number of records returned
  "downloaded_at",    # ISO8601 timestamp
  "fetch_seconds",    # how long the HTTP call took
  "xml_sha256",       # SHA256 of the raw XML file (for integrity/lineage)
  "xml_path",         # relative path to stored XML file
  "ices_fieldlist_sha256",  # which ICES field list snapshot was authoritative
  "opus_dict_version",      # which opus spec version was noted at download time
  "error_msg"         # error message if status == "error"
)

## ---- Logging ----
log_msg <- function(fmt, ...) {
  message(format(Sys.time(), "%Y-%m-%d %H:%M:%S  "), sprintf(fmt, ...))
}

## ---- Manifest I/O ----
read_manifest <- function(path, cols = MANIFEST_COLS) {
  if (file.exists(path)) {
    return(utils::read.delim(path, colClasses = "character", na.strings = "NA"))
  }
  # Empty manifest with correct columns
  m <- as.data.frame(matrix(character(), nrow = 0, ncol = length(cols)),
                     stringsAsFactors = FALSE)
  names(m) <- cols
  m
}

upsert_manifest <- function(man, row, key_cols = c("record_type", "survey", "year", "quarter")) {
  # Remove any existing row matching all key columns, append new row
  key <- Reduce(`&`, lapply(key_cols, function(k) man[[k]] == row[[k]]))
  dplyr::bind_rows(man[!key, , drop = FALSE], row)
}

flush_manifest <- function(man, path, cols = MANIFEST_COLS) {
  # Write manifest, ensuring column order
  utils::write.table(man[, cols], path, sep = "\t", quote = FALSE,
                     row.names = FALSE, na = "NA")
}

## ---- ICES Catalog ----
# The survey x year x quarter universe (from ICES, not record-type specific).
# Read once at pipeline start to know which cells can exist.
read_catalog <- function(path) {
  if (!file.exists(path)) return(NULL)
  cat <- utils::read.delim(path, colClasses = c(survey = "character",
                                                  year = "integer",
                                                  quarter = "integer"))
  cat[order(cat$survey, cat$year, cat$quarter), , drop = FALSE]
}

write_catalog <- function(cat, path) {
  utils::write.table(cat, path, sep = "\t", quote = FALSE, row.names = FALSE)
}

## ---- Package metadata ----
pkg_ver <- function(p) {
  tryCatch(
    as.character(utils::packageVersion(p)),
    error = function(e) "dev"
  )
}
