#' Phase 2 Stage 1: Parse raw XML → Parquet
#'
#' Simple, focused stage: XML → type casting → Parquet files
#' Input: minimal YAML from WSDL (types only)
#' Output: .datras/parquet/ with typed parquet files per table
#'
#' No sentinels, no issue recording, no other complications.
#' Just types from inst/DATRAS-data-dict-minimal.yaml
#'
#' Usage:
#'   Rscript data-raw/datras_phase2_stage1.R
#'   Rscript data-raw/datras_phase2_stage1.R HH  # specific record type

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(yaml)
})

source("data-raw/datras_download_config.R")

# ============================================================================
# ---- SETUP ----
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
filter_rt <- if (length(args) > 0) args[1] else NULL

log_msg("OPUS Phase 2 Stage 1: XML → Parquet (types only, minimal YAML)")
if (!is.null(filter_rt)) log_msg("Filtering to record type: %s", filter_rt)

# Output directories
DATRAS_PARQUET_DIR <- file.path(WORKSPACE, "parquet")
DATRAS_ISSUES_DIR <- file.path(WORKSPACE, "issues")
dir.create(DATRAS_PARQUET_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(DATRAS_ISSUES_DIR, showWarnings = FALSE, recursive = TRUE)

# XML issues log
xml_issues <- list()

# Load minimal spec (types only from WSDL)
# Note: inst/DATRAS-types-minimal.R is not a valid data-dict YAML (missing examples),
# but has the structure Phase 2 needs: tables → columns → name/type
minimal_spec <- tryCatch({
  read_yaml("inst/DATRAS-types-minimal.R")
}, error = function(e) {
  stop("Failed to load types spec: ", conditionMessage(e), call. = FALSE)
})

log_msg("Loaded minimal YAML with tables: %s", paste(sapply(minimal_spec$tables, `[[`, "name"), collapse = ", "))

# Load manifest to find XML files
man <- read_manifest(DATRAS_MANIFEST)
log_msg("Found %d manifest entries", nrow(man))

# ============================================================================
# ---- ISSUE RECORDING ----
# ============================================================================

record_xml_issue <- function(xml_file, rt, issue_type, detail) {
  issue <- list(
    xml_file = xml_file,
    record_type = rt,
    issue_type = issue_type,
    detail = detail,
    timestamp = Sys.time()
  )
  xml_issues[[length(xml_issues) + 1]] <<- issue
}

write_xml_issues <- function() {
  if (length(xml_issues) == 0) return(invisible(NULL))

  issues_df <- do.call(rbind, lapply(xml_issues, as.data.frame, stringsAsFactors = FALSE))
  issues_file <- file.path(DATRAS_ISSUES_DIR, sprintf("xml_issues_%s.tsv", format(Sys.time(), "%Y%m%d_%H%M%S")))
  write.table(issues_df, issues_file, sep = "\t", quote = FALSE, row.names = FALSE, col.names = TRUE)
  log_msg("Wrote %d XML issues to %s", nrow(issues_df), basename(issues_file))
}

# ============================================================================
# ---- XML PARSER ----
# ============================================================================

parse_xml_to_dataframe <- function(xml_path) {
  output <- system(sprintf(
    "python3 << 'PYEOF'\nimport xml.etree.ElementTree as ET\nimport sys\nimport csv\n\nxml_path = '%s'\n\ntree = ET.parse(xml_path)\nroot = tree.getroot()\n\nns = ''\nif '}' in root.tag:\n  ns = root.tag.split('}')[0] + '}'\n\nrecords = list(root)\nif not records:\n  sys.exit(1)\n\nfields = []\nfor child in records[0]:\n  tag = child.tag\n  if '}' in tag:\n    tag = tag.split('}')[1]\n  fields.append(tag)\n\nwriter = csv.writer(sys.stdout, delimiter='\t')\nwriter.writerow(fields)\nfor record in records:\n  values = []\n  for field in fields:\n    elem = record.find(f'{ns}{field}')\n    if elem is None:\n      elem = record.find(field)\n    val = (elem.text or '').strip() if elem is not None else ''\n    values.append(val)\n  writer.writerow(values)\nPYEOF\n", xml_path
  ), intern = TRUE, ignore.stderr = TRUE)

  con <- textConnection(output)
  # Keep all columns as strings initially (don't guess types)
  df <- read.delim(con, stringsAsFactors = FALSE, na.strings = "", colClasses = "character")
  close(con)
  df
}

# ============================================================================
# ---- TYPE CASTING ----
# ============================================================================

apply_types <- function(df, rt, spec) {
  # Find the table spec by name (tables is unnamed array)
  table_spec <- NULL
  for (t in spec$tables) {
    if (t$name == rt) {
      table_spec <- t
      break
    }
  }

  if (is.null(table_spec)) {
    log_msg("  WARNING: No spec for %s, returning as-is", rt)
    return(df)
  }

  col_specs <- table_spec$columns
  if (is.null(col_specs)) {
    return(df)
  }

  # Build type map
  type_map <- list()
  for (col_spec in col_specs) {
    if (!is.null(col_spec$name) && !is.null(col_spec$type)) {
      type_map[[col_spec$name]] <- col_spec$type
    }
  }

  # Apply types from minimal YAML
  for (col_name in names(df)) {
    if (col_name %in% names(type_map)) {
      col_type <- type_map[[col_name]]

      if (col_type == "number") {
        # Convert to numeric (handles both int and decimal from WSDL)
        df[[col_name]] <- suppressWarnings(as.numeric(df[[col_name]]))
      } else if (col_type == "string") {
        # Keep as character
        df[[col_name]] <- as.character(df[[col_name]])
      }
    }
  }

  df
}

# ============================================================================
# ---- MAIN PROCESSING LOOP ----
# ============================================================================

# Determine which record types to process
rt_list <- sapply(minimal_spec$tables, `[[`, "name")
if (!is.null(filter_rt)) {
  if (!filter_rt %in% rt_list) {
    stop("Record type '", filter_rt, "' not in minimal YAML", call. = FALSE)
  }
  rt_list <- filter_rt
}

# Group manifest by record type (add .datras/xml/ prefix)
rt_files <- list()
for (rt in rt_list) {
  rel_paths <- man$xml_path[man$record_type == rt]
  rt_files[[rt]] <- file.path(WORKSPACE, "xml", rel_paths)
}

for (rt in rt_list) {
  files <- rt_files[[rt]]
  if (length(files) == 0) {
    log_msg("%s: no files found", rt)
    next
  }

  log_msg("%s: processing %d files", rt, length(files))

  all_data <- NULL
  for (f in files) {
    if (!file.exists(f)) {
      log_msg("  SKIP (not found): %s", basename(f))
      next
    }

    tryCatch({
      df <- parse_xml_to_dataframe(f)
      log_msg("  OK: %s (%d rows, %d cols)", basename(f), nrow(df), ncol(df))

      # Apply types
      df <- apply_types(df, rt, minimal_spec)

      # Bind to accumulated data
      if (is.null(all_data)) {
        all_data <- df
      } else {
        all_data <- bind_rows(all_data, df)
      }
    }, error = function(e) {
      log_msg("  ERROR: %s — %s", basename(f), conditionMessage(e))
      record_xml_issue(basename(f), rt, "PARSE_ERROR", conditionMessage(e))
    })
  }

  if (!is.null(all_data)) {
    # Write parquet
    output_file <- file.path(DATRAS_PARQUET_DIR, paste0(rt, ".parquet"))
    write_parquet(all_data, output_file)
    log_msg("%s: wrote %s (%d rows total)", rt, basename(output_file), nrow(all_data))
  } else {
    log_msg("%s: no data to write", rt)
  }
}

# Write any XML issues
write_xml_issues()

log_msg("\n✓ Phase 2 Stage 1 complete. Parquet files in: %s", DATRAS_PARQUET_DIR)
