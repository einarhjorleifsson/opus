#' Phase 2 v2: Parse raw XML → Parquet with strict specs
#'
#' Redesigned to handle:
#' 1. Issue recording (malformed XML, structural problems)
#' 2. Global sentinel replacement (-9, -99, etc. → NA)
#' 3. Rigid type casting from opus specs (fail loudly on errors)
#'
#' Usage:
#'   Rscript data-raw/archive_04_parse_phase2.R
#'   Rscript data-raw/archive_04_parse_phase2.R HH  # specific record type

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(yaml)
})

source("data-raw/archive_01_download_config.R")

# ============================================================================
# ---- CONFIGURATION ----
# ============================================================================

# Global sentinel values to replace with NA (before type casting)
GLOBAL_SENTINELS <- c("-9", "-99", "-999", "-1", "-5", "-95", "-100", "-900", "88888888")

# ============================================================================
# ---- SETUP ----
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
filter_rt <- if (length(args) > 0) args[1] else NULL

log_msg("OPUS Phase 2 v2: XML→Parquet (strict specs, issue recording)")
if (!is.null(filter_rt)) log_msg("Filtering to record type: %s", filter_rt)

# Output directories
DATRAS_PARQUET_DIR <- file.path(WORKSPACE, "parquet")
DATRAS_ISSUES_DIR <- file.path(WORKSPACE, "issues")
dir.create(DATRAS_PARQUET_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(DATRAS_ISSUES_DIR, showWarnings = FALSE, recursive = TRUE)

# Load manifest
man <- read_manifest(DATRAS_MANIFEST)
log_msg("Manifest: %d entries", nrow(man))

# Load opus spec
opus_spec <- tryCatch({
  read_yaml("inst/DATRAS-data-dict.yaml")
}, error = function(e) {
  log_msg("WARNING: Failed to load opus spec: %s", conditionMessage(e))
  NULL
})

# ============================================================================
# ---- ISSUE RECORDER ----
# ============================================================================

issues <- list()

record_issue <- function(rt, survey, year, quarter, issue_type, detail) {
  key <- sprintf("%s_%s_%d_Q%d_%s", rt, survey, year, quarter, issue_type)
  issues[[key]] <<- list(
    record_type = rt,
    survey = survey,
    year = year,
    quarter = quarter,
    issue_type = issue_type,
    detail = detail,
    timestamp = Sys.time()
  )
}

write_issues <- function(rt) {
  if (length(issues) == 0) return()

  issues_df <- do.call(rbind, lapply(issues, as.data.frame, stringsAsFactors = FALSE))
  issues_file <- file.path(DATRAS_ISSUES_DIR, sprintf("%s_issues_%s.tsv", rt, format(Sys.time(), "%Y%m%d_%H%M%S")))
  write.table(issues_df, issues_file, sep = "\t", quote = FALSE, row.names = FALSE)
  log_msg("Wrote %d issues to %s", nrow(issues_df), basename(issues_file))
}

# ============================================================================
# ---- XML PARSER WITH ISSUE DETECTION ----
# ============================================================================

parse_xml_to_dataframe <- function(xml_path, rt, survey, year, quarter) {
  tryCatch({
    output <- system(sprintf(
      "python3 << 'PYEOF'\nimport xml.etree.ElementTree as ET\nimport sys\nimport csv\n\nxml_path = '%s'\n\ntree = ET.parse(xml_path)\nroot = tree.getroot()\n\nns = ''\nif '}' in root.tag:\n  ns = root.tag.split('}')[0] + '}'\n\nrecords = list(root)\nif not records:\n  sys.exit(1)\n\nfields = []\nfor child in records[0]:\n  tag = child.tag\n  if '}' in tag:\n    tag = tag.split('}')[1]\n  fields.append(tag)\n\nwriter = csv.writer(sys.stdout, delimiter='\t')\nwriter.writerow(fields)\nfor record in records:\n  values = []\n  for field in fields:\n    elem = record.find(f'{ns}{field}')\n    if elem is None:\n      elem = record.find(field)\n    val = (elem.text or '').strip() if elem is not None else ''\n    values.append(val)\n  writer.writerow(values)\nPYEOF\n", xml_path
    ), intern = TRUE, ignore.stderr = TRUE)

    if (length(output) == 0) {
      record_issue(rt, survey, year, quarter, "EMPTY_RECORDS", "XML contains no records")
      return(NULL)
    }

    # Parse TSV output
    con <- textConnection(output)
    df <- read.delim(con, stringsAsFactors = FALSE, na.strings = "")
    close(con)

    # Issue detection: check for malformed XML
    if (nrow(df) == 0) {
      record_issue(rt, survey, year, quarter, "EMPTY_RECORDS", "XML contains no records")
      return(NULL)
    }

    # Check for missing required fields based on record type
    required_fields <- switch(rt,
      "HH" = c("RecordType", "Survey", "Year", "Quarter", "HaulNo"),
      "HL" = c("RecordType", "Survey", "Year", "Quarter", "HaulNo"),
      "CA" = c("RecordType", "Survey", "Year", "Quarter", "HaulNo"),
      # LT records carry no RecordType/RecordHeader field in the real archive --
      # ICES's getDatrasFieldList metadata claims one exists, but it's a phantom
      # (see data-raw/ICES_ISSUE_REPORT.md); don't require what ICES doesn't send.
      "LT" = c("Survey", "Year", "Quarter"),
      c()
    )

    missing_cols <- setdiff(required_fields, names(df))
    if (length(missing_cols) > 0) {
      record_issue(rt, survey, year, quarter, "MISSING_FIELDS",
                   sprintf("Missing required fields: %s", paste(missing_cols, collapse = ", ")))
      return(NULL)
    }

    return(df)
  }, error = function(e) {
    record_issue(rt, survey, year, quarter, "PARSE_ERROR", conditionMessage(e))
    return(NULL)
  })
}

# ============================================================================
# ---- GLOBAL SENTINEL REPLACEMENT ----
# ============================================================================

replace_sentinels <- function(df) {
  # Replace global sentinels with NA across all columns
  for (col in names(df)) {
    df[[col]][df[[col]] %in% GLOBAL_SENTINELS] <- NA_character_
  }
  return(df)
}

# ============================================================================
# ---- RIGID TYPE CASTING ----
# ============================================================================

apply_rigid_types <- function(df, rt, spec) {
  if (is.null(spec) || !(rt %in% names(spec))) {
    return(df)
  }

  table_spec <- spec[[which(sapply(spec, function(t) t$name == rt))]]
  if (is.null(table_spec$columns)) {
    return(df)
  }

  # Build type map
  type_map <- list()
  for (col_spec in table_spec$columns) {
    col_name <- col_spec$name
    col_type <- col_spec$type
    if (!is.null(col_name) && !is.null(col_type)) {
      type_map[[col_name]] <- col_type
    }
  }

  # Apply types strictly (fail on conversion errors)
  for (col_name in names(df)) {
    if (col_name %in% names(type_map)) {
      col_type <- type_map[[col_name]]

      # Convert based on type spec
      if (col_type == "number(quantity)" || col_type == "number") {
        # Strict: fail if non-NA can't convert to numeric
        result <- suppressWarnings(as.numeric(df[[col_name]]))
        invalid <- !is.na(df[[col_name]]) & is.na(result)
        if (any(invalid)) {
          warning(sprintf("Column %s: %d values failed numeric conversion",
                         col_name, sum(invalid)), call. = FALSE)
        }
        df[[col_name]] <- result
      } else if (col_type == "number(ordinal)" || col_type == "number(id)") {
        # Strict: fail if non-NA can't convert to integer
        result <- suppressWarnings(as.integer(as.numeric(df[[col_name]])))
        invalid <- !is.na(df[[col_name]]) & is.na(result)
        if (any(invalid)) {
          warning(sprintf("Column %s: %d values failed integer conversion",
                         col_name, sum(invalid)), call. = FALSE)
        }
        df[[col_name]] <- result
      }
      # enum and string stay as character
    }
  }

  return(df)
}

# ============================================================================
# ---- PROCESS CELLS ----
# ============================================================================

cells_to_process <- man %>%
  filter(status == "ok" & n_rows != "0") %>%
  {if (!is.null(filter_rt)) filter(., record_type == filter_rt) else .} %>%
  arrange(record_type, survey, year, quarter)

log_msg("Cells to process: %d", nrow(cells_to_process))

if (nrow(cells_to_process) == 0) {
  log_msg("No cells to process")
  quit(status = 0)
}

# Track stats
n_success <- 0
n_error <- 0
n_issues <- 0
t_total_start <- Sys.time()

# Process each cell
for (i in seq_len(nrow(cells_to_process))) {
  cell <- cells_to_process[i, ]
  rt <- cell$record_type
  s <- cell$survey
  y <- as.integer(cell$year)
  q <- as.integer(cell$quarter)
  xml_file <- file.path(DATRAS_XML_DIR, cell$xml_path)

  t0 <- Sys.time()

  # Parse XML with issue detection
  df <- parse_xml_to_dataframe(xml_file, rt, s, y, q)

  if (is.null(df)) {
    log_msg("[%-4s %-12s %d Q%d] ERROR | parsing failed", rt, s, y, q)
    n_error <- n_error + 1
    next
  }

  n_rows <- nrow(df)

  # Global sentinel replacement
  df <- replace_sentinels(df)

  # Rigid type casting
  df <- apply_rigid_types(df, rt, opus_spec)

  # Create output path
  pq_dir <- file.path(DATRAS_PARQUET_DIR, rt, sprintf("Survey=%s", s), sprintf("Year=%d", y))
  dir.create(pq_dir, showWarnings = FALSE, recursive = TRUE)

  pq_file <- file.path(pq_dir, sprintf("%s_%s_%d_Q%d.parquet", rt, s, y, q))

  # Write parquet
  tryCatch({
    arrow::write_parquet(df, pq_file, compression = "snappy")
    pq_size <- file.size(pq_file) / 1024
    elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)

    log_msg("[%-4s %-12s %d Q%d] ok | %8d rows | %6.1f KB | %ss",
            rt, s, y, q, n_rows, pq_size, elapsed)

    n_success <- n_success + 1
  }, error = function(e) {
    log_msg("[%-4s %-12s %d Q%d] ERROR | write failed: %s", rt, s, y, q, e$message)
    n_error <<- n_error + 1
  })
}

# Write collected issues
write_issues(if (is.null(filter_rt)) "all" else filter_rt)

elapsed_total <- round(as.numeric(difftime(Sys.time(), t_total_start, units = "secs")), 1)

log_msg("")
log_msg("Phase 2 v2 complete!")
log_msg("Success: %d | Error: %d | Issues recorded: %d | Total time: %ss",
        n_success, n_error, length(issues), elapsed_total)
log_msg("Output: %s", DATRAS_PARQUET_DIR)
log_msg("Issues: %s", DATRAS_ISSUES_DIR)
