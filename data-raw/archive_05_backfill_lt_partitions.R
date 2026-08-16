#' Rebuild partitioned parquet for any Tier 1 table directly from XML on disk
#'
#' Started as an LT-only backfill (.datras/manifest.tsv has no LT rows -- the
#' LT XML under .datras/xml/LT predates the manifest-tracked downloader) but
#' generalized 2026-08-08 to reprocess HH/HL/CA too: the manifest turned out
#' to be stale for the whole bulk archive, not just LT (it only has 10 rows,
#' all from one later NS-IBTS test run), so archive_04_parse_phase2.R's
#' normal manifest-driven path can't be used to bulk-reprocess any table --
#' this bypasses the manifest for all four, the same way it always did for
#' LT specifically. (Filename kept as-is to avoid another rename pass on an
#' already-long day; it now does more than LT.)
#'
#' Reprocessing became necessary the same day for a second reason: rigid
#' type casting is now apply_wsdl_types(df, rt) (data-raw/archive_00_wsdl_types.R),
#' replacing a yaml-based caster whose entry guard was broken and silently
#' did nothing -- confirmed via a real per-file schema scan to have produced
#' inconsistently-typed columns across different files for the same field
#' (16 CA columns, 8 HL columns; e.g. GenSamp: int32 in files where every
#' row happens to be the "-9" sentinel, string in files with a real "Y"/"N").
#' Re-running this script overwrites the existing (buggy) partition files in
#' place with correctly and consistently typed ones.
#'
#' Scope, deliberately narrow (2026-08-08): this stage converts each XML
#' file to parquet, conditional only on the type declared in live WSDL --
#' nothing else. It used to also reject a parsed record if some "required"
#' column (e.g. RecordType) was missing, with different rules hardcoded per
#' table -- removed. That was a completeness/validation judgment, not a
#' type-casting one, and it doesn't belong at this stage any more than the
#' yaml or the word "enum" do (same reasoning as archive_00_wsdl_types.R).
#' A file that's missing an expected column, or has a genuinely different
#' shape from its siblings, should still become parquet -- reconciling that
#' across files is a downstream (consolidation/validation) concern, not
#' something this stage should silently decide by dropping data. The only
#' things treated as hard failures here are ones with no other option: the
#' XML fails to parse at all, or has literally zero records to derive even
#' a column list from.
#'
#' A blanket "global sentinel" replacement (-9, -99, etc. -> NA across
#' every column) used to also live here -- removed 2026-08-16, same
#' reasoning as the required-fields gate above: whether a sentinel means
#' "genuinely absent" or a real, meaningful code is a curation conclusion,
#' not a type-casting one, and it's circular to bake it in here -- you
#' can't discover a code is meaningful from data this stage already erased.
#' HH/LT's Tickler declares -9 as a real, labeled icesVocab code ("No
#' ticklers are allowed"; confirmed 2,301+ real occurrences in a 30-file
#' XML sample), and CA's HaulNo/StNo -9 (the already-filed
#' ca_haulno_unlinkable_to_hh known issue) needs to survive as a real
#' value, not become NA, for its declared range ([0, 82483], deliberately
#' excluding -9) to flag it as the D04 violation it was designed to be.
#' The blanket scrub silently converted both into indistinguishable nulls.
#' At least 28 enum fields across all four tables declare "-9" as one of
#' their own curated codes (data-raw/spec_02_curate_dict.R); sentinel
#' interpretation for any of them now happens downstream, at curation
#' time, informed by the real (unscrubbed) archive -- exactly where
#' enum-ness already lives. See archive_04_parse_phase2.R's own header
#' for the fuller reasoning (same fix applied there too).
#'
#' Usage:
#'   Rscript data-raw/archive_05_backfill_lt_partitions.R        # all 4 tables
#'   Rscript data-raw/archive_05_backfill_lt_partitions.R CA     # one table

suppressPackageStartupMessages({
  library(arrow)
})

source("data-raw/archive_01_download_config.R")
source("data-raw/archive_00_wsdl_types.R")

DATRAS_PARQUET_DIR <- file.path(WORKSPACE, "parquet")
DATRAS_ISSUES_DIR <- file.path(WORKSPACE, "issues")
dir.create(DATRAS_ISSUES_DIR, showWarnings = FALSE, recursive = TRUE)

args <- commandArgs(trailingOnly = TRUE)
tables_to_run <- if (length(args) > 0) args[1] else c("HH", "HL", "CA", "LT")

issues <- list()
record_issue <- function(rt, survey, year, quarter, issue_type, detail) {
  key <- sprintf("%s_%s_%d_Q%d_%s", rt, survey, year, quarter, issue_type)
  issues[[key]] <<- list(record_type = rt, survey = survey, year = year,
                          quarter = quarter, issue_type = issue_type,
                          detail = detail, timestamp = Sys.time())
}

parse_xml_to_dataframe <- function(xml_path, rt, survey, year, quarter) {
  tryCatch({
    output <- system(sprintf(
      "python3 << 'PYEOF'\nimport xml.etree.ElementTree as ET\nimport sys\nimport csv\n\nxml_path = '%s'\n\ntree = ET.parse(xml_path)\nroot = tree.getroot()\n\nns = ''\nif '}' in root.tag:\n  ns = root.tag.split('}')[0] + '}'\n\nrecords = list(root)\nif not records:\n  sys.exit(1)\n\nfields = []\nfor child in records[0]:\n  tag = child.tag\n  if '}' in tag:\n    tag = tag.split('}')[1]\n  fields.append(tag)\n\nwriter = csv.writer(sys.stdout, delimiter='\t')\nwriter.writerow(fields)\nfor record in records:\n  values = []\n  for field in fields:\n    elem = record.find(f'{ns}{field}')\n    if elem is None:\n      elem = record.find(field)\n    val = (elem.text or '').strip() if elem is not None else ''\n    values.append(val)\n  writer.writerow(values)\nPYEOF\n", xml_path
    ), intern = TRUE, ignore.stderr = TRUE)

    if (length(output) == 0) {
      record_issue(rt, survey, year, quarter, "EMPTY_RECORDS", "XML contains no records")
      return(NULL)
    }

    con <- textConnection(output)
    df <- read.delim(con, stringsAsFactors = FALSE, na.strings = "")
    close(con)

    if (nrow(df) == 0) {
      record_issue(rt, survey, year, quarter, "EMPTY_RECORDS", "XML contains no records")
      return(NULL)
    }

    df
  }, error = function(e) {
    record_issue(rt, survey, year, quarter, "PARSE_ERROR", conditionMessage(e))
    NULL
  })
}

t_total_start <- Sys.time()
grand_success <- 0
grand_error <- 0

for (rt in tables_to_run) {
  rt_xml_dir <- file.path(DATRAS_XML_DIR, rt)
  if (!dir.exists(rt_xml_dir)) {
    log_msg("%s: no XML directory found, skipping", rt)
    next
  }
  xml_files <- list.files(rt_xml_dir, pattern = "\\.xml$", recursive = TRUE, full.names = TRUE)
  log_msg("%s: found %d XML files on disk", rt, length(xml_files))

  n_success <- 0
  n_error <- 0
  t_start <- Sys.time()

  for (xml_file in xml_files) {
    rel <- sub(paste0("^", rt_xml_dir, "/"), "", xml_file)
    parts <- strsplit(rel, "/")[[1]]

    if (length(parts) != 3 ||
        !grepl("^Survey=", parts[1]) || !grepl("^Year=", parts[2])) {
      log_msg("SKIP | unexpected path shape: %s", rel)
      n_error <- n_error + 1
      next
    }

    s <- sub("^Survey=", "", parts[1])
    y <- as.integer(sub("^Year=", "", parts[2]))
    qm <- regmatches(parts[3], regexec("_Q(\\d)_", parts[3]))[[1]]

    if (length(qm) != 2) {
      log_msg("SKIP | can't find quarter in filename: %s", parts[3])
      n_error <- n_error + 1
      next
    }
    q <- as.integer(qm[2])

    t0 <- Sys.time()
    df <- parse_xml_to_dataframe(xml_file, rt, s, y, q)
    if (is.null(df)) {
      log_msg("[%-2s %-12s %d Q%d] ERROR | parsing failed/skipped", rt, s, y, q)
      n_error <- n_error + 1
      next
    }

    df <- apply_wsdl_types(df, rt)

    pq_dir <- file.path(DATRAS_PARQUET_DIR, rt, sprintf("Survey=%s", s), sprintf("Year=%d", y))
    dir.create(pq_dir, showWarnings = FALSE, recursive = TRUE)
    pq_file <- file.path(pq_dir, sprintf("%s_%s_%d_Q%d.parquet", rt, s, y, q))

    tryCatch({
      arrow::write_parquet(df, pq_file, compression = "snappy")
      elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
      log_msg("[%-2s %-12s %d Q%d] ok | %6d rows | %ss", rt, s, y, q, nrow(df), elapsed)
      n_success <- n_success + 1
    }, error = function(e) {
      log_msg("[%-2s %-12s %d Q%d] ERROR | write failed: %s", rt, s, y, q, e$message)
      n_error <<- n_error + 1
    })
  }

  elapsed <- round(as.numeric(difftime(Sys.time(), t_start, units = "secs")), 1)
  log_msg("%s: done. Success: %d | Error: %d | %ss", rt, n_success, n_error, elapsed)
  grand_success <- grand_success + n_success
  grand_error <- grand_error + n_error
}

if (length(issues) > 0) {
  issues_df <- do.call(rbind, lapply(issues, as.data.frame, stringsAsFactors = FALSE))
  issues_file <- file.path(DATRAS_ISSUES_DIR, sprintf("reprocess_issues_%s.tsv", format(Sys.time(), "%Y%m%d_%H%M%S")))
  write.table(issues_df, issues_file, sep = "\t", quote = FALSE, row.names = FALSE)
  log_msg("Wrote %d issues to %s", nrow(issues_df), basename(issues_file))
}

elapsed_total <- round(as.numeric(difftime(Sys.time(), t_total_start, units = "secs")), 1)
log_msg("")
log_msg("All done! Success: %d | Error: %d | Issues: %d | Total time: %ss",
        grand_success, grand_error, length(issues), elapsed_total)
log_msg("Output: %s", DATRAS_PARQUET_DIR)
