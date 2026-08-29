#' Build the Tier 1 parquet partitions from ICES's CSV download API
#'
#' An alternative to archive_02_download.R + archive_04_parse_phase2.R for the
#' three record types ICES serves as CSV. Same partition layout, same four
#' conversion steps, same current names -- but written to a SEPARATE tree, so
#' the XML-derived partitions stay intact and the two can be compared:
#'
#'   .datras/parquet/{HH,HL,CA,LT}/...        <- archive_02 + archive_04 (XML)
#'   .datras/parquet_csv/{HH,HL,CA}/...       <- this script
#'
#'   {root}/{RT}/Survey=<s>/Year=<y>/{RT}_{s}_{y}_Q{q}.parquet
#'
#' Consolidate either with archive_06_consolidate.R, which reads
#' OPUS_PARQUET_ROOT / OPUS_STAGE_DIR from the environment:
#'
#'   OPUS_PARQUET_ROOT=.datras/parquet_csv \
#'   OPUS_STAGE_DIR=.datras/to_https_csv/raw \
#'     Rscript data-raw/archive_06_consolidate.R HH HL CA
#'
#' Why bother: the ASMX XML route serves ~1.5 MB/s and one survey/year/quarter
#' at a time, so a full archive pull runs to hours. This endpoint returns a
#' whole survey (all years, all quarters) as one zipped CSV. Measured
#' 2026-08-29: all of NS-IBTS -- 37,180 HH rows, 4,101,389 HL, 2,020,963 CA --
#' in 86 seconds, against 31.5 s for a *single* CA survey/year/quarter by XML.
#' Roughly 128x smaller on the wire for CA.
#'
#' NOT COVERED, and these still need the XML route:
#'
#'  - **LT.** The endpoint serves only HH, HL and CA. `recordtype=LT` returns
#'    HTTP 200 with a zip whose CSV is 3 bytes -- a UTF-8 BOM and nothing else.
#'    Same for FL, Litter and LitterAssessmentOutput. Until ICES adds it, LT
#'    comes from archive_02/04 as before.
#'  - **CODS-Q4.** Present in the XML service (and in this archive: 2024 Q4 and
#'    2025 Q4) but absent from the download API, which returns a valid header
#'    and zero rows for it under any year/quarter combination. The other 28
#'    surveys all work, with byte-identical headers.
#'
#' Two hazards this endpoint has, both guarded below:
#'
#'  1. **It signals failure with HTTP 200.** An unsupported record type gives a
#'     3-byte CSV; an unsupported survey gives a full valid header with no data
#'     rows. Neither is an error at the HTTP or zip level, so a status check
#'     alone would silently ingest nothing. Row counts are asserted per request.
#'  2. **The HH CSV is malformed** -- 72-field header, 70-field rows, with
#'     EDOM and ReasonHaulDisruption absent and the trailing value being
#'     DateofCalculation (ices-tools-prod/icesDatras#63). Repaired by
#'     read_datras_csv_hh(), sourced below; see that file for the evidence.
#'     Left unrepaired, DuckDB's CSV reader silently collapses these files to
#'     two columns rather than 72.
#'
#' Usage: Rscript data-raw/archive_02b_download_csv.R          # all 3, all surveys
#'        Rscript data-raw/archive_02b_download_csv.R HH       # one record type
#'        Rscript data-raw/archive_02b_download_csv.R HL BITS  # one, one survey

suppressPackageStartupMessages({
  library(arrow)
  library(opus)
})

source("data-raw/issue-drafts/icesDatras-hh-workaround.R")  # read_datras_csv_hh()

API        <- "https://datras.ices.dk/Data_products/Download/DATRASDownloadAPI.aspx"
YEARS      <- "1965:2030"
QUARTERS   <- "1:4"
OUT_ROOT   <- Sys.getenv("OPUS_CSV_PARQUET_ROOT", ".datras/parquet_csv")
CSV_TYPES  <- c("HH", "HL", "CA")   # LT is not served; see header
CSV_SKIP   <- "CODS-Q4"             # served empty; see header

# ---------------------------------------------------------------------------
# The CSV's own column names.
#
# Mostly opus's current names already -- which is why this route is worth
# taking -- but not entirely, and the divergences are not systematic: CA keeps
# a legacy-style `CANoAtLngt` while renaming Age to `IndividualAge`, and the
# Aphia column is spelled three ways across the two tables that carry it.
# Mapped explicitly rather than pattern-matched, and asserted complete below.
# ---------------------------------------------------------------------------
CSV_FIXUP <- list(
  HH = character(),
  HL = c(ValidAphiaID  = "Valid_Aphia"),
  CA = c(IndividualAge = "Age",
         CANoAtLngt    = "NumberAtLength",
         AphiaID       = "Valid_Aphia")
)

# Columns the CSV carries that opus's dictionary does not describe.
#
# Dropped for now, because archive_06 asserts the dictionary's columns match the
# file's exactly -- an undocumented column fails the build. But "dropped" is not
# the same verdict for all of them. Measured on the full NS-IBTS export,
# 2026-08-29:
#
#   HH SurveyIndexArea       37,180 rows, ALL -9. No information.
#   HH ReasonHaulDisruption  absent from every data row (that is icesDatras#63).
#   HH EDOM                  absent likewise; what appears under its header
#                            position is the trailing DateofCalculation value.
#   -> all three HH extras carry nothing; dropping them loses nothing.
#
#   HL ScientificName_WoRMS  834 distinct, populated in ALL 4,101,389 rows
#                            ("Merlangius merlangus", ...). REAL DATA.
#   CA Species               202 distinct, populated in ALL 2,020,963 rows.
#                            REAL DATA, the same concept under another name.
#   CA LiverWeight           1,328 real measurements (0.066%); the rest -9.0000.
#                            Sparse, but real, and not available via XML at all.
#
# So dropping the last three IS data loss, and this list should not be read as
# "these do not matter". Species/ScientificName_WoRMS are derivable from
# Valid_Aphia (they are the WoRMS name for that AphiaID) so nothing is
# unrecoverable there; LiverWeight is genuinely only in this route.
#
# Documenting them means deciding whether one dictionary can describe two
# archive shapes -- it cannot, as archive_06 is written. Open decision; see
# TODO.md. Until then they are dropped, deliberately and with the counts above
# recorded so the choice can be revisited on evidence.
CSV_EXTRA <- list(
  HH = c("SurveyIndexArea", "EDOM", "ReasonHaulDisruption"),
  HL = "ScientificName_WoRMS",
  CA = c("LiverWeight", "Species")
)

.fetch_survey_csv <- function(rt, survey) {
  url <- sprintf("%s?recordtype=%s&survey=%s&year=%s&quarter=%s",
                 API, rt, utils::URLencode(survey, reserved = TRUE), YEARS, QUARTERS)
  zip <- tempfile(fileext = ".zip")
  on.exit(unlink(zip), add = TRUE)
  ok <- tryCatch({ utils::download.file(url, zip, mode = "wb", quiet = TRUE); TRUE },
                 error = function(e) FALSE)
  if (!ok) stop(sprintf("download failed: %s / %s", rt, survey), call. = FALSE)

  df <- if (rt == "HH") {
    read_datras_csv_hh(zip)                       # repairs the ragged header
  } else {
    d <- tempfile(); on.exit(unlink(d, recursive = TRUE), add = TRUE)
    utils::unzip(zip, exdir = d)
    csv <- list.files(d, pattern = "DATRASDataTable\\.csv$", full.names = TRUE)
    if (length(csv) != 1L) stop("no DATRASDataTable.csv for ", rt, "/", survey, call. = FALSE)
    utils::read.csv(csv, colClasses = "character", stringsAsFactors = FALSE,
                    fileEncoding = "UTF-8-BOM", check.names = FALSE)
  }

  # Guard 1: the endpoint answers 200 for things it cannot serve.
  if (nrow(df) == 0L) {
    stop(sprintf("%s / %s returned 0 rows. The API answers HTTP 200 with an empty ",
                 "CSV for an unsupported survey or record type -- check coverage ",
                 "rather than retrying.", rt, survey), call. = FALSE)
  }
  df
}

#' CSV names -> opus legacy names, so the existing conversion chain applies.
.csv_to_legacy <- function(df, rt, crosswalk) {
  fx <- CSV_FIXUP[[rt]]
  if (length(fx)) {
    hit <- names(df) %in% names(fx)
    names(df)[hit] <- fx[names(df)[hit]]
  }
  df <- df[, setdiff(names(df), CSV_EXTRA[[rt]]), drop = FALSE]

  x <- crosswalk[crosswalk$RecordHeader == rt, ]
  legacy <- x$old_name[match(names(df), x$new_name)]

  # Guard 2: every column must map, and every expected column must be present.
  if (anyNA(legacy)) {
    stop(sprintf("%s: CSV columns not in opus's crosswalk: %s", rt,
                 paste(names(df)[is.na(legacy)], collapse = ", ")), call. = FALSE)
  }
  missing <- setdiff(x$new_name, names(df))
  if (length(missing)) {
    stop(sprintf("%s: CSV is missing columns opus expects: %s", rt,
                 paste(missing, collapse = ", ")), call. = FALSE)
  }
  names(df) <- legacy
  df
}

args    <- commandArgs(trailingOnly = TRUE)
TABLES  <- if (length(args) > 0) intersect(args, CSV_TYPES) else CSV_TYPES
ONE_SVY <- if (length(args) > 1) args[-1] else NULL
if (length(args) > 0 && !length(TABLES)) {
  stop("This route serves only ", paste(CSV_TYPES, collapse = "/"),
       ". LT must come from the XML pipeline.", call. = FALSE)
}

crosswalk <- op_datras_rename_crosswalk()
surveys   <- setdiff(ONE_SVY %||% op_surveys(path = ".datras/to_https/raw"), CSV_SKIP)
if (is.null(ONE_SVY)) {
  message("Surveys: ", length(surveys), " (skipping ", CSV_SKIP, " -- not served by this API)")
}

for (rt in TABLES) {
  total <- 0L; t0 <- Sys.time()
  for (s in surveys) {
    df <- .fetch_survey_csv(rt, s)
    df <- .csv_to_legacy(df, rt, crosswalk)

    df <- op_cast_wsdl_types(df, rt)   # A: physical types, sentinels intact
    df <- op_rename_to_new(df, rt)     # legacy -> current names
    df <- op_strip_sentinels(df, rt)   # B: -9 -> NA where it means absence
    df <- op_cast_to_spec(df, rt)      # C: semantic types (date, ...)

    for (y in sort(unique(df$Year))) {
      for (q in sort(unique(df$Quarter[df$Year == y]))) {
        part <- df[df$Year == y & df$Quarter == q, , drop = FALSE]
        if (!nrow(part)) next
        dir <- file.path(OUT_ROOT, rt, sprintf("Survey=%s", s), sprintf("Year=%d", y))
        dir.create(dir, showWarnings = FALSE, recursive = TRUE)
        arrow::write_parquet(part,
          file.path(dir, sprintf("%s_%s_%d_Q%d.parquet", rt, s, y, q)),
          compression = "snappy")
      }
    }
    total <- total + nrow(df)
    message(sprintf("  %-3s %-12s %9s rows", rt, s, format(nrow(df), big.mark = ",")))
  }
  message(sprintf("%-3s done: %s rows in %.0fs", rt, format(total, big.mark = ","),
                  as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

message("")
message("Partitions written under ", OUT_ROOT, "/ for ", paste(TABLES, collapse = ", "), ".")
message("The XML-derived tree under .datras/parquet/ is untouched -- LT lives there,")
message("and both can be consolidated separately for comparison. Next:")
message("  OPUS_PARQUET_ROOT=", OUT_ROOT, " OPUS_STAGE_DIR=.datras/to_https_csv/raw \\")
message("    Rscript data-raw/archive_06_consolidate.R ", paste(TABLES, collapse = " "))
