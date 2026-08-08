#' Backfill partitioned LT parquet from XML already on disk
#'
#' .datras/manifest.tsv has no LT rows -- the LT XML under .datras/xml/LT
#' predates the current manifest-tracked downloader (archive_01_download_config.R
#' is scoped to a later 2025-2026 prototype run). HH/HL/CA already have their
#' partitioned .datras/parquet/{rt}/Survey=*/Year=*/ output; this fills the
#' same gap for LT by parsing every LT XML file directly instead of going
#' through the manifest, mirroring archive_04_parse_phase2.R's per-file logic
#' (python XML->TSV, sentinel replacement, rigid type casting from the opus
#' spec) so the output is identical in shape to the other three tables.
#'
#' Usage: Rscript data-raw/archive_05_backfill_lt_partitions.R

suppressPackageStartupMessages({
  library(arrow)
  library(yaml)
})

source("data-raw/archive_01_download_config.R")

GLOBAL_SENTINELS <- c("-9", "-99", "-999", "-1", "-5", "-95", "-100", "-900", "88888888")
DATRAS_PARQUET_DIR <- file.path(WORKSPACE, "parquet")
DATRAS_ISSUES_DIR <- file.path(WORKSPACE, "issues")
dir.create(DATRAS_ISSUES_DIR, showWarnings = FALSE, recursive = TRUE)

opus_spec <- read_yaml("inst/DATRAS-data-dict.yaml")

issues <- list()
record_issue <- function(survey, year, quarter, issue_type, detail) {
  key <- sprintf("LT_%s_%d_Q%d_%s", survey, year, quarter, issue_type)
  issues[[key]] <<- list(record_type = "LT", survey = survey, year = year,
                          quarter = quarter, issue_type = issue_type,
                          detail = detail, timestamp = Sys.time())
}

parse_xml_to_dataframe <- function(xml_path, survey, year, quarter) {
  tryCatch({
    output <- system(sprintf(
      "python3 << 'PYEOF'\nimport xml.etree.ElementTree as ET\nimport sys\nimport csv\n\nxml_path = '%s'\n\ntree = ET.parse(xml_path)\nroot = tree.getroot()\n\nns = ''\nif '}' in root.tag:\n  ns = root.tag.split('}')[0] + '}'\n\nrecords = list(root)\nif not records:\n  sys.exit(1)\n\nfields = []\nfor child in records[0]:\n  tag = child.tag\n  if '}' in tag:\n    tag = tag.split('}')[1]\n  fields.append(tag)\n\nwriter = csv.writer(sys.stdout, delimiter='\t')\nwriter.writerow(fields)\nfor record in records:\n  values = []\n  for field in fields:\n    elem = record.find(f'{ns}{field}')\n    if elem is None:\n      elem = record.find(field)\n    val = (elem.text or '').strip() if elem is not None else ''\n    values.append(val)\n  writer.writerow(values)\nPYEOF\n", xml_path
    ), intern = TRUE, ignore.stderr = TRUE)

    if (length(output) == 0) {
      record_issue(survey, year, quarter, "EMPTY_RECORDS", "XML contains no records")
      return(NULL)
    }

    con <- textConnection(output)
    df <- read.delim(con, stringsAsFactors = FALSE, na.strings = "")
    close(con)

    if (nrow(df) == 0) {
      record_issue(survey, year, quarter, "EMPTY_RECORDS", "XML contains no records")
      return(NULL)
    }

    # LT records carry no RecordType/RecordHeader field in the real archive --
    # ICES's getDatrasFieldList metadata claims one exists, but it's a phantom
    # (see data-raw/ICES_ISSUE_REPORT.md); the opus spec already omits it for LT.
    required_fields <- c("Survey", "Year", "Quarter")
    missing_cols <- setdiff(required_fields, names(df))
    if (length(missing_cols) > 0) {
      record_issue(survey, year, quarter, "MISSING_FIELDS",
                   sprintf("Missing required fields: %s", paste(missing_cols, collapse = ", ")))
      return(NULL)
    }

    df
  }, error = function(e) {
    record_issue(survey, year, quarter, "PARSE_ERROR", conditionMessage(e))
    NULL
  })
}

replace_sentinels <- function(df) {
  for (col in names(df)) {
    df[[col]][df[[col]] %in% GLOBAL_SENTINELS] <- NA_character_
  }
  df
}

apply_rigid_types <- function(df, spec) {
  table_spec <- spec$tables[[which(sapply(spec$tables, function(t) t$name == "LT"))]]
  if (is.null(table_spec$columns)) return(df)

  type_map <- list()
  for (col_spec in table_spec$columns) {
    if (!is.null(col_spec$name) && !is.null(col_spec$type)) {
      type_map[[col_spec$name]] <- col_spec$type
    }
  }

  for (col_name in names(df)) {
    if (col_name %in% names(type_map)) {
      col_type <- type_map[[col_name]]
      if (col_type %in% c("number(quantity)", "number")) {
        df[[col_name]] <- suppressWarnings(as.numeric(df[[col_name]]))
      } else if (col_type %in% c("number(ordinal)", "number(id)")) {
        df[[col_name]] <- suppressWarnings(as.integer(as.numeric(df[[col_name]])))
      }
    }
  }
  df
}

lt_xml_dir <- file.path(DATRAS_XML_DIR, "LT")
xml_files <- list.files(lt_xml_dir, pattern = "\\.xml$", recursive = TRUE, full.names = TRUE)
log_msg("Found %d LT XML files on disk", length(xml_files))

n_success <- 0
n_error <- 0
t_total_start <- Sys.time()

for (xml_file in xml_files) {
  rel <- sub(paste0("^", lt_xml_dir, "/"), "", xml_file)
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
  df <- parse_xml_to_dataframe(xml_file, s, y, q)
  if (is.null(df)) {
    log_msg("[LT %-12s %d Q%d] ERROR | parsing failed/skipped", s, y, q)
    n_error <- n_error + 1
    next
  }

  df <- replace_sentinels(df)
  df <- apply_rigid_types(df, opus_spec)

  pq_dir <- file.path(DATRAS_PARQUET_DIR, "LT", sprintf("Survey=%s", s), sprintf("Year=%d", y))
  dir.create(pq_dir, showWarnings = FALSE, recursive = TRUE)
  pq_file <- file.path(pq_dir, sprintf("LT_%s_%d_Q%d.parquet", s, y, q))

  tryCatch({
    arrow::write_parquet(df, pq_file, compression = "snappy")
    elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
    log_msg("[LT %-12s %d Q%d] ok | %6d rows | %ss", s, y, q, nrow(df), elapsed)
    n_success <- n_success + 1
  }, error = function(e) {
    log_msg("[LT %-12s %d Q%d] ERROR | write failed: %s", s, y, q, e$message)
    n_error <<- n_error + 1
  })
}

if (length(issues) > 0) {
  issues_df <- do.call(rbind, lapply(issues, as.data.frame, stringsAsFactors = FALSE))
  issues_file <- file.path(DATRAS_ISSUES_DIR, sprintf("LT_issues_%s.tsv", format(Sys.time(), "%Y%m%d_%H%M%S")))
  write.table(issues_df, issues_file, sep = "\t", quote = FALSE, row.names = FALSE)
  log_msg("Wrote %d issues to %s", nrow(issues_df), basename(issues_file))
}

elapsed_total <- round(as.numeric(difftime(Sys.time(), t_total_start, units = "secs")), 1)
log_msg("")
log_msg("LT backfill complete! Success: %d | Error: %d | Issues: %d | Total time: %ss",
        n_success, n_error, length(issues), elapsed_total)
log_msg("Output: %s", file.path(DATRAS_PARQUET_DIR, "LT"))
