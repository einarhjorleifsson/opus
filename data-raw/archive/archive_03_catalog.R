#' Direct ICES DATRAS catalog API calls (no icesDatras package dependency)
#'
#' Fetch survey metadata directly from ICES endpoints.

# ---- Helper: fetch and parse ICES XML response ----
.fetch_ices_xml <- function(url) {
  tryCatch({
    response <- curl::curl_fetch_memory(url)
    if (response$status_code != 200) {
      stop(sprintf("HTTP %d: %s", response$status_code, rawToChar(response$content)))
    }
    xml_text <- rawToChar(response$content)
    strsplit(xml_text, "\n")[[1]]
  }, error = function(e) {
    stop("Failed to fetch ICES catalog: ", conditionMessage(e), call. = FALSE)
  })
}

# ---- Helper: parse simple ICES XML responses ----
# ICES returns simple flat XML like: <string>NS-IBTS</string>, <int>2025</int>, etc.
.parse_ices_xml_values <- function(xml_lines, tag_name) {
  pattern <- sprintf("<%s>([^<]+)</%s>", tag_name, tag_name)
  matches <- regmatches(xml_lines, regexec(pattern, xml_lines))
  unlist(lapply(matches, function(m) if (length(m) > 1) m[2] else NULL))
}

# ---- Public: Get survey list ----
datras_get_surveys <- function() {
  url <- "https://datras.ices.dk/WebServices/DATRASWebService.asmx/getSurveyList"
  xml_lines <- .fetch_ices_xml(url)
  # trimws: at least one survey ("EVHOE") comes back fixed-width padded
  # (e.g. "EVHOE     "); untrimmed, it propagates into URLs downstream as
  # literal unencoded spaces, which curl rejects as a malformed URL.
  surveys <- trimws(.parse_ices_xml_values(xml_lines, "Survey"))
  # Filter out test surveys
  surveys[!grepl("^Test", surveys, ignore.case = TRUE)]
}

# ---- Public: Get years for a survey ----
datras_get_years <- function(survey) {
  url <- sprintf(
    "https://datras.ices.dk/WebServices/DATRASWebService.asmx/getSurveyYearList?survey=%s",
    URLencode(survey)
  )
  xml_lines <- .fetch_ices_xml(url)
  years_str <- .parse_ices_xml_values(xml_lines, "Year")
  as.integer(years_str)
}

# ---- Public: Get quarters for a survey year ----
datras_get_quarters <- function(survey, year) {
  url <- sprintf(
    "https://datras.ices.dk/WebServices/DATRASWebService.asmx/getSurveyYearQuarterList?survey=%s&year=%d",
    URLencode(survey), year
  )
  xml_lines <- .fetch_ices_xml(url)
  quarters_str <- .parse_ices_xml_values(xml_lines, "Quarter")
  as.integer(quarters_str)
}

# ---- Public: Get full catalog (survey x year x quarter) for given years ----
datras_get_catalog <- function(years) {
  surveys <- datras_get_surveys()

  catalog <- lapply(seq_along(surveys), function(i) {
    s <- surveys[i]
    yrs <- tryCatch(datras_get_years(s), error = function(e) integer(0))
    if (!length(yrs)) return(NULL)

    qts <- lapply(yrs, function(yr) {
      qs <- tryCatch(datras_get_quarters(s, yr), error = function(e) integer(0))
      if (length(qs) == 0) return(NULL)
      data.frame(survey = s, year = yr, quarter = qs, stringsAsFactors = FALSE)
    })
    dplyr::bind_rows(qts)
  }) |> dplyr::bind_rows()

  # Filter to requested years
  catalog[catalog$year %in% years, , drop = FALSE]
}

# ---- Public: Get DATRAS field list (metadata about field names, types, descriptions) ----
