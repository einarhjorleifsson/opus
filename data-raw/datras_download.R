#' Download raw DATRAS XML and store with manifest tracking
#'
#' Fetches raw XML from DATRAS web service, stores locally, and maintains
#' a manifest of all downloads for resume/audit purposes.
#'
#' Usage:
#'   Rscript data-raw/datras_download.R
#'
#' Or for periodic refresh:
#'   nohup Rscript data-raw/datras_download.R > logs/download_$(date +%F_%H%M%S).log 2>&1 &

suppressPackageStartupMessages({
  library(dplyr)
})

source("data-raw/datras_download_config.R")
source("data-raw/datras_catalog.R")  # Direct ICES API (no icesDatras dependency)

# ---- Helper: fetch raw XML from URL using curl ----
fetch_datras_raw_xml <- function(url) {
  # Use curl to fetch, return raw lines or error
  tryCatch({
    response <- curl::curl_fetch_memory(url)
    if (response$status_code != 200) {
      return(list(ok = FALSE, err = sprintf("HTTP %d: %s", response$status_code, rawToChar(response$content))))
    }
    xml_text <- rawToChar(response$content)
    xml_lines <- strsplit(xml_text, "\n")[[1]]
    list(ok = TRUE, xml = xml_lines)
  }, error = function(e) {
    list(ok = FALSE, err = conditionMessage(e))
  })
}

# ============================================================================
# ---- SETUP ----
# ============================================================================

log_msg("OPUS DATRAS raw XML download starting")
log_msg("Years: %s", paste(OPUS_YEARS, collapse = ", "))
log_msg("Record types: %s", paste(RECORD_TYPES, collapse = ", "))
if (!is.null(OPUS_SURVEYS)) log_msg("Surveys (filtered): %s", paste(OPUS_SURVEYS, collapse = ", "))

# Ensure workspace directories exist
dir.create(DATRAS_XML_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(DATRAS_SCHEMAS, showWarnings = FALSE, recursive = TRUE)

# Load existing manifest
man <- read_manifest(DATRAS_MANIFEST)
log_msg("Manifest: %d existing entries", nrow(man))

opus_v <- pkg_ver("opus")
ices_v <- pkg_ver("icesDatras")

# ============================================================================
# ---- BUILD CATALOG (what cells exist at ICES) ----
# ============================================================================

# Check for cached catalog (builds once, reuse on subsequent runs)
CATALOG_CACHE_TTL <- 86400 * 30  # 30 days

catalog <- NULL
if (file.exists(DATRAS_CATALOG)) {
  cache_age_days <- as.numeric(difftime(Sys.time(),
                                        file.mtime(DATRAS_CATALOG),
                                        units = "days"))
  if (cache_age_days < 30) {
    log_msg("Using cached ICES catalog (%.1f days old)", cache_age_days)
    catalog <- read_catalog(DATRAS_CATALOG)

    # Verify cache covers requested years
    if (!all(OPUS_YEARS %in% catalog$year)) {
      log_msg("  Cache incomplete for requested years; rebuilding...")
      catalog <- NULL
    }
  } else {
    log_msg("Catalog cache stale (%.1f days); rebuilding...", cache_age_days)
  }
}

# If no fresh cache, build new catalog
if (is.null(catalog)) {
  log_msg("Fetching ICES survey x year x quarter catalog (this takes ~2-3 min)...")
  all_surveys <- datras_get_surveys()
  log_msg("Found %d total surveys at ICES", length(all_surveys))

  surveys <- if (!is.null(OPUS_SURVEYS)) {
    found <- intersect(OPUS_SURVEYS, all_surveys)
    missing <- setdiff(OPUS_SURVEYS, all_surveys)
    if (length(missing) > 0) log_msg("WARNING: Requested surveys not found: %s", paste(missing, collapse = ", "))
    found
  } else {
    all_surveys
  }
  log_msg("Processing %d surveys", length(surveys))

  catalog <- lapply(seq_along(surveys), function(i) {
    s <- surveys[i]
    log_msg("  [%d/%d] %s: fetching years...", i, length(surveys), s)

    yrs <- tryCatch(datras_get_years(s), error = function(e) integer(0))
    if (!length(yrs)) {
      log_msg("    → no years found")
      return(NULL)
    }

    log_msg("    → found %d years, fetching quarters...", length(yrs))

    # Get quarters for each year
    qts <- lapply(yrs, function(yr) {
      qs <- tryCatch(datras_get_quarters(s, yr), error = function(e) integer(0))
      if (length(qs) == 0) return(NULL)
      data.frame(survey = s, year = yr, quarter = qs, stringsAsFactors = FALSE)
    })
    qts_df <- dplyr::bind_rows(qts)
    if (nrow(qts_df) > 0) log_msg("    → %d (year, quarter) cells", nrow(qts_df))
    qts_df
  }) |> dplyr::bind_rows()

  # Write full catalog to cache (for future runs)
  write_catalog(catalog, DATRAS_CATALOG)
  log_msg("Catalog cached for future runs")
}

# Filter to requested years
catalog <- catalog[catalog$year %in% OPUS_YEARS, , drop = FALSE]
catalog <- catalog[order(catalog$survey, catalog$year, catalog$quarter), , drop = FALSE]

log_msg("Catalog: %d (survey x year x quarter) cells in %d-%d",
        nrow(catalog), min(OPUS_YEARS), max(OPUS_YEARS))

# ============================================================================
# ---- FETCH ICES FIELD LIST SNAPSHOT ----
# ============================================================================
# This is metadata about field types/names from ICES, used during parse stage
# to validate/map field names. Fetch once per run and snapshot it.

log_msg("Fetching ICES field list metadata...")
ices_fieldlist <- tryCatch({
  datras_get_field_list()
}, error = function(e) {
  log_msg("WARNING: Failed to fetch ICES field list: %s", e$message)
  return(NULL)
})

if (!is.null(ices_fieldlist) && nrow(ices_fieldlist) > 0) {
  # Write snapshot with timestamp
  fieldlist_sha <- digest::digest(ices_fieldlist, algo = "sha256")
  fieldlist_file <- file.path(DATRAS_SCHEMAS,
                              sprintf("ices_fieldlist_%s_%s.tsv",
                                      format(Sys.time(), "%Y%m%d_%H%M%S"),
                                      substr(fieldlist_sha, 1, 8)))
  utils::write.table(ices_fieldlist, fieldlist_file, sep = "\t", quote = FALSE, row.names = FALSE)
  log_msg("ICES field list snapshot: %s (SHA256: %s)", basename(fieldlist_file), fieldlist_sha)
} else {
  log_msg("WARNING: No ICES field list available")
  fieldlist_sha <- NA_character_
}

# ============================================================================
# ---- DOWNLOAD RAW XML ----
# ============================================================================

log_msg("Starting download of raw XML...")

for (rt in RECORD_TYPES) {
  log_msg("")
  log_msg("=== %s (exchange data) ===", rt)

  # Filter catalog to this record type (all exist for all cells, so no filter really needed)
  cells <- catalog
  n_cells <- nrow(cells)
  n_attempted <- 0
  n_ok <- 0
  n_empty <- 0
  n_error <- 0

  for (i in seq_len(n_cells)) {
    s <- cells$survey[i]
    y <- cells$year[i]
    q <- cells$quarter[i]

    # Check manifest: have we already fetched this cell?
    prev <- man %>%
      filter(record_type == rt & survey == s & year == as.character(y) & quarter == as.character(q))

    if (nrow(prev) > 0 && prev$status[1] %in% c("ok", "empty", "none")) {
      # Already successfully fetched (or confirmed empty); skip
      next
    }

    n_attempted <- n_attempted + 1

    # Construct URL for raw XML (special case for LT which uses getLitterAssessmentOutput)
    if (rt == "LT") {
      url <- sprintf(
        "https://datras.ices.dk/WebServices/DATRASWebService.asmx/getLitterAssessmentOutput?survey=%s&year=%i&quarter=%i",
        s, y, q
      )
    } else {
      url <- sprintf(
        "https://datras.ices.dk/WebServices/DATRASWebService.asmx/get%sdata?survey=%s&year=%i&quarter=%i",
        rt, s, y, q
      )
    }

    t0 <- Sys.time()
    result <- fetch_datras_raw_xml(url)
    secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)

    if (!result$ok) {
      # Network error or empty response
      status <- "error"
      n_rows <- 0L
      err_msg <- result$err
      xml_sha <- NA_character_
      xml_file <- NA_character_

      n_error <- n_error + 1
      log_msg("[%-4s %-12s %d Q%d] %-5s | %s | %ss",
              rt, s, y, q, status, "ERROR", secs)
    } else {
      # Successfully fetched XML
      xml_lines <- result$xml

      # Detect record count from XML (count Cls_DatrasExchange_* opening tags)
      # Format: <Cls_DatrasExchange_HH>, <Cls_DatrasExchange_HL>, etc.
      tag_pattern <- sprintf("<Cls_DatrasExchange_%s>", rt)
      n_rows <- length(grep(tag_pattern, xml_lines, fixed = TRUE))

      if (n_rows == 0) {
        # Clean zero-row response: ICES has no data for this cell
        status <- "empty"
        n_empty <- n_empty + 1
      } else {
        status <- "ok"
        n_ok <- n_ok + 1
      }

      # Compute SHA256 of raw XML
      xml_text <- paste(xml_lines, collapse = "\n")
      xml_sha <- digest::digest(xml_text, algo = "sha256")

      # Write XML to disk
      # Path: .datras/xml/{RT}/Survey={survey}/Year={year}/Quarter={quarter}/{RT}_{survey}_{year}_Q{quarter}_{timestamp}.xml
      xml_dir <- file.path(DATRAS_XML_DIR, rt, sprintf("Survey=%s", s), sprintf("Year=%d", y))
      dir.create(xml_dir, showWarnings = FALSE, recursive = TRUE)

      xml_filename <- sprintf("%s_%s_%d_Q%d_%s.xml",
                              rt, s, y, q,
                              format(Sys.time(), "%Y%m%d_%H%M%S"))
      xml_path <- file.path(xml_dir, xml_filename)

      writeLines(xml_lines, xml_path)
      err_msg <- NA_character_

      # Relative path for manifest
      xml_file <- file.path(rt, sprintf("Survey=%s", s), sprintf("Year=%d", y), xml_filename)

      log_msg("[%-4s %-12s %d Q%d] %-5s | %10d rows | %ss",
              rt, s, y, q, status, n_rows, secs)
    }

    # Update manifest
    row <- data.frame(
      record_type = rt,
      survey = s,
      year = as.character(y),
      quarter = as.character(q),
      status = status,
      n_rows = as.character(n_rows),
      downloaded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      fetch_seconds = as.character(secs),
      xml_sha256 = xml_sha,
      xml_path = xml_file,
      ices_fieldlist_sha256 = fieldlist_sha,
      opus_dict_version = "0.2.0",  # Current opus spec version
      error_msg = err_msg,
      stringsAsFactors = FALSE
    )

    man <- upsert_manifest(man, row)
    flush_manifest(man, DATRAS_MANIFEST)
  }

  log_msg("%s summary: %d attempted, %d ok, %d empty, %d error",
          rt, n_attempted, n_ok, n_empty, n_error)
}

log_msg("")
log_msg("Download complete!")
log_msg("Manifest: %s (%d rows)", DATRAS_MANIFEST, nrow(man))
log_msg("Catalog: %s", DATRAS_CATALOG)
log_msg("Raw XML: %s", DATRAS_XML_DIR)
