#' Interim workaround for ices-tools-prod/icesDatras#63
#'
#' The HH CSV served by DATRASDownloadAPI.aspx has a 72-field header and
#' 70-field data rows. `fread(fill = TRUE)` pads at the END, so the trailing
#' value (DateofCalculation) is bound to the 70th header name (EDOM), and
#' ReasonHaulDisruption / DateofCalculation come back all-NA.
#'
#' This reads the file positionally instead, and binds the trailing value to
#' the LAST header name rather than the first unfilled one.
#'
#' Which two columns are missing was established empirically, not assumed
#' (2026-08-29, against the live API and opus's own XML-derived archive):
#'
#'   - Header positions 1-69 align with the data positions 1-69.
#'   - Data column 70 is a date (YYYYMMDD) or the -9 sentinel, nothing else,
#'     across every survey checked.
#'   - Joined to the XML-derived archive on the 8-field composite haul key:
#'     all 10,379 NS-IBTS rows where column 70 is -9 have a NULL
#'     DateofCalculation in the archive -- a perfect correspondence that no
#'     other column would produce -- and 20,267 of the 25,231 date-valued rows
#'     match the archive exactly. The 4,964 that differ all carry an OLDER
#'     stamp in the CSV, consistent with DateofCalculation being a per-product
#'     reprocessing timestamp rather than a per-haul fact.
#'   - For the small DWS survey the match is 72 of 72, exactly.
#'
#' So the missing columns are EDOM and ReasonHaulDisruption, and the trailing
#' value is DateofCalculation. They are returned as NA, because the CSV simply
#' does not carry them.
#'
#' NOTE this encodes an assumption about WHICH columns are absent. It is right
#' for the file ICES serves today; if the export changes, the ncol check below
#' stops it rather than silently re-misaligning. Prefer the upstream fix.

read_datras_csv_hh <- function(zip_path) {
  d <- tempfile(); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  utils::unzip(zip_path, exdir = d)
  csv <- list.files(d, pattern = "DATRASDataTable\\.csv$", full.names = TRUE)
  if (length(csv) != 1L) stop("expected exactly one DATRASDataTable.csv in ", zip_path)

  header <- scan(csv, what = "", nlines = 1L, sep = ",", quiet = TRUE,
                 fileEncoding = "UTF-8-BOM")
  body <- utils::read.csv(csv, header = FALSE, skip = 1L, colClasses = "character",
                          stringsAsFactors = FALSE, fileEncoding = "UTF-8-BOM")

  gap <- length(header) - ncol(body)
  if (gap == 0L) {                       # already fixed upstream: nothing to do
    names(body) <- header
    return(body)
  }
  if (gap != 2L || length(header) != 72L) {
    stop(sprintf(
      "Unexpected shape: %d header fields, %d data columns. The workaround for
icesDatras#63 assumes 72 and 70; refusing to guess.",
      length(header), ncol(body)), call. = FALSE)
  }
  missing_at <- c("EDOM", "ReasonHaulDisruption")
  if (!identical(header[70:71], missing_at)) {
    stop("Header positions 70-71 are ", paste(header[70:71], collapse = "/"),
         ", not ", paste(missing_at, collapse = "/"),
         " -- the export changed; re-verify before trusting this.", call. = FALSE)
  }

  # positions 1..69 map straight through; the trailing value is the LAST
  # header name, not the 70th.
  names(body) <- c(header[1:69], header[72])
  body[[missing_at[1]]] <- NA_character_
  body[[missing_at[2]]] <- NA_character_
  body[header]                            # restore the declared column order
}
