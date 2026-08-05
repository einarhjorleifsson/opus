#' Fetch DATRAS Field List from ICES Web Service
#'
#' Calls the ICES DATRAS web service to retrieve the current field list
#' (RecordHeader, FieldName, FieldNameOld, DataFormat, Description).
#' This is opus's direct interface to the ICES field metadata source,
#' bypassing the icesDatras package wrapper.
#'
#' @param use_cache Logical. If TRUE (default), cache results for 24 hours.
#'
#' @return Data frame with columns:
#'   - RecordHeader: Table (HH, HL, CA, LT)
#'   - FieldName: Current field name
#'   - FieldNameOld: Legacy field name
#'   - DataFormat: Type (char, int, decimal)
#'   - Description: Field description
#'
#' @details
#' Source: https://datras.ices.dk/WebServices/DATRASWebService.asmx/getDatrasFieldList
#'
#' This endpoint is the authoritative source for DATRAS field mappings (old → new names)
#' and descriptions. Note: DataFormat values can diverge from WSDL; opus prefers WSDL
#' types directly for seeding. This function is primarily used for field name mappings.
#'
#' @keywords internal
op_fetch_datras_field_list <- function(use_cache = TRUE) {
  url <- "https://datras.ices.dk/WebServices/DATRASWebService.asmx/getDatrasFieldList"

  # Cached wrapper if requested
  if (use_cache) {
    return(.cached_datras_field_list(url))
  }

  # Fetch fresh
  .fetch_datras_field_list_uncached(url)
}


#' Fetch Vocabulary Codes from ICES Vocabulary Service (Development Tool)
#'
#' Internal function for data-raw curation scripts.
#' Calls the ICES Vocabulary web service to retrieve code definitions
#' and descriptions for a named vocabulary (e.g., "Gear", "TS_Sex").
#' This is opus's direct interface to icesVocab, bypassing the icesVocab
#' package wrapper.
#'
#' @param vocab_key Character. Vocabulary key (e.g., "Gear", "TS_Sex", "LTSZC")
#'
#' @return Data frame with columns:
#'   - Key: Code name
#'   - Description: Code description
#'   - Deprecated: Logical. TRUE if code is deprecated.
#'   - Modified: Character. Last modification timestamp.
#'
#' @details
#' Source: https://vocab.ices.dk/services/api/Code/{vocab_key}
#'
#' icesVocab is a cross-domain ICES vocabulary service. opus filters to
#' vocabularies applicable to DATRAS fields. Caching is automatic (per
#' icesVocab's own service-side settings, typically 24 hours).
#'
#' @importFrom jsonlite fromJSON
#'
#' @keywords internal
op_fetch_vocab_codes <- function(vocab_key) {
  if (!is.character(vocab_key) || length(vocab_key) != 1) {
    stop("vocab_key must be a single character string", call. = FALSE)
  }

  url <- sprintf("https://vocab.ices.dk/services/api/Code/%s", vocab_key)

  # Fetch and parse JSON
  response <- tryCatch(
    readLines(url, warn = FALSE),
    error = function(e) {
      stop("Failed to fetch ", vocab_key, " from icesVocab: ", e$message, call. = FALSE)
    }
  )

  json_text <- paste(response, collapse = "\n")

  # Parse JSON
  df <- tryCatch(
    jsonlite::fromJSON(json_text),
    error = function(e) {
      stop("Failed to parse icesVocab response for ", vocab_key, ": ", e$message, call. = FALSE)
    }
  )

  # icesVocab returns a dataframe with lowercase column names
  # Standardize to uppercase for consistent API
  if (is.data.frame(df) && nrow(df) > 0) {
    # Select and rename columns
    cols_present <- intersect(c("key", "description", "deprecated", "modified"), tolower(names(df)))
    if (length(cols_present) > 0) {
      result <- df[, cols_present, drop = FALSE]
      names(result) <- toupper(names(result))
      return(result)
    }
  }

  # Return empty dataframe if no codes found or parsing failed
  data.frame(Key = character(), Description = character(),
             Deprecated = logical(), Modified = character(),
             stringsAsFactors = FALSE)
}


# ---- Internal helpers (memoized/cached) ----

.cached_datras_field_list <- function(url) {
  # Simple 24-hour cache using package environment
  cache_key <- "datras_field_list_cache"
  cache_time_key <- "datras_field_list_time"

  cache_env <- parent.env(environment())

  # Check if cached and fresh
  if (exists(cache_key, envir = cache_env, inherits = FALSE)) {
    cache_time <- get(cache_time_key, envir = cache_env)
    if (Sys.time() - cache_time < 86400) {  # 24 hours
      return(get(cache_key, envir = cache_env))
    }
  }

  # Fetch fresh
  result <- .fetch_datras_field_list_uncached(url)

  # Store in cache
  assign(cache_key, result, envir = cache_env)
  assign(cache_time_key, Sys.time(), envir = cache_env)

  result
}

.fetch_datras_field_list_uncached <- function(url) {
  # Fetch XML from ICES service
  response <- tryCatch(
    readLines(url, warn = FALSE),
    error = function(e) {
      stop("Failed to fetch DATRAS field list: ", e$message, call. = FALSE)
    }
  )

  xml_text <- paste(response, collapse = "\n")

  # Fix malformed namespace (same fix as icesDatras does)
  xml_text <- gsub(
    'xmlns="ices.dk.local/DATRAS"',
    'xmlns="https://ices.dk.local/DATRAS"',
    xml_text,
    fixed = TRUE
  )

  # Parse XML to dataframe (requires XML package)
  if (!requireNamespace("XML", quietly = TRUE)) {
    stop("Package 'XML' required to parse DATRAS field list. Install with: install.packages('XML')", call. = FALSE)
  }

  df <- tryCatch(
    XML::xmlToDataFrame(xml_text),
    error = function(e) {
      stop("Failed to parse DATRAS field list XML: ", e$message, call. = FALSE)
    }
  )

  # Trim whitespace from all values
  df[] <- lapply(df, trimws)
  as.data.frame(df, stringsAsFactors = FALSE)
}
