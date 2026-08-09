#' WSDL-based rigid type casting for the raw XML -> parquet conversion
#'
#' Physical type only -- string/int/decimal, straight from each DATRAS
#' operation's own live WSDL response (getHHdata/getHLdata/getCAdata/
#' getLitterAssessmentOutput's ASMX pages). Deliberately does not know the
#' word "enum" exists: enum-ness is a curation conclusion about a string
#' field's value domain, reached by analyzing real archive data -- that
#' analysis is downstream of this stage, so it can't be an input to it
#' without becoming circular (you can't know a field is a clean two-value
#' enum before you can reliably read the field at all). The curated spec
#' (`inst/DATRAS-data-dict.yaml`) plays no role here and is never loaded by
#' this file or its callers -- see AGENTS.md's entry on this fix (2026-08-08)
#' for the bug this replaces.
#'
#' That bug: the previous yaml-based `apply_rigid_types()` checked
#' `rt %in% names(spec)`, but `spec` was the whole data-dict yaml object --
#' its top-level names are things like `tables`/`glossary`/`version`, never
#' a table name. The check was always true, so the function silently did
#' nothing, for every call, every column -- not just enums. Whatever type
#' each column ended up as was purely whatever R's own `read.delim()`
#' guessed from that one file's own values, with zero correction. Confirmed
#' via a real per-file schema scan: 16 CA columns and 8 HL columns end up
#' typed inconsistently across different files for the same column (e.g.
#' `GenSamp` -- int32 in files where every row happens to be the "-9"
#' sentinel, string in files with a real "Y"/"N" value) -- which is exactly
#' the kind of thing a single, explicit, per-column cast makes impossible.
#'
#' Usage: source this file, then call `apply_wsdl_types(df, rt)` right after
#' parsing each XML file, before any sentinel replacement. WSDL types are
#' fetched once per table and cached for the life of the R session --
#' `get_datras_operation_types()` (from `spec_00_operation_types.R`, sourced
#' below) does the live fetch/parse; this just adds the per-table
#' operation-name lookup, the cache, and the actual R-type cast.

source("data-raw/spec_00_operation_types.R")

.wsdl_type_cache <- new.env()

# DATRAS table -> the web service operation whose live ASMX page documents
# its fields (verified against get_datras_operations(), 2026-08-08).
.DATRAS_OPERATION <- c(
  HH = "getHHdata",
  HL = "getHLdata",
  CA = "getCAdata",
  LT = "getLitterAssessmentOutput"
)

#' Fetch (and cache) the WSDL field/type map for one DATRAS table
#'
#' @param rt Character scalar: DATRAS table (HH, HL, CA, LT).
#' @return Named character vector: field name (legacy/raw XML tag) -> WSDL
#'   type (`"string"`, `"int"`, or `"decimal"`).
get_wsdl_type_map <- function(rt) {
  if (!exists(rt, envir = .wsdl_type_cache, inherits = FALSE)) {
    op <- .DATRAS_OPERATION[[rt]]
    if (is.null(op)) {
      stop("No known WSDL operation for table '", rt, "'. Valid tables: ",
           paste(names(.DATRAS_OPERATION), collapse = ", "), call. = FALSE)
    }
    types <- get_datras_operation_types(op)
    assign(rt, setNames(types$type, types$field), envir = .wsdl_type_cache)
  }
  get(rt, envir = .wsdl_type_cache, inherits = FALSE)
}

#' Cast every column of a parsed XML dataframe to its WSDL-declared type
#'
#' Every column with a WSDL type gets explicitly cast -- not just numeric
#' ones. This is the fix: the old function's silence on string/enum columns
#' (leaving them as "whatever they already are") is exactly what let
#' per-file type drift happen.
#'
#' @param df Data frame: one parsed XML file's records, all columns still
#'   character (or whatever `read.delim()` guessed).
#' @param rt Character scalar: DATRAS table (HH, HL, CA, LT).
#' @return `df` with every WSDL-typed column explicitly cast. Columns with
#'   no WSDL entry (there shouldn't be any -- see Issue 5 in
#'   `data-raw/ICES_ISSUE_REPORT.md` for the two known exceptions,
#'   `DateofCalculation`/`Valid_Aphia`) are left untouched, not guessed at.
apply_wsdl_types <- function(df, rt) {
  type_map <- get_wsdl_type_map(rt)

  for (col_name in names(df)) {
    if (!(col_name %in% names(type_map))) next
    wsdl_type <- type_map[[col_name]]

    df[[col_name]] <- switch(wsdl_type,
      "int"     = suppressWarnings(as.integer(df[[col_name]])),
      "decimal" = suppressWarnings(as.numeric(df[[col_name]])),
      "string"  = as.character(df[[col_name]]),
      df[[col_name]]  # unrecognized WSDL type string -- leave as-is, don't guess
    )
  }

  df
}
