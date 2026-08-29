# Type casting for the XML -> parquet conversion, in two separate phases.
#
# Phase A -- op_cast_wsdl_types(): physical types, from ICES's own WSDL.
# Phase C -- op_cast_to_spec():    semantic types the wire cannot express.
#
# They are deliberately separate, and the sentinel strip
# (op_strip_sentinels(), R/sentinels.R) runs BETWEEN them. Casting a
# YYYYMMDD column to Date while sentinels are still in it silently destroys
# them -- that is not hypothetical: the previously-published HL.parquet
# stored DateofCalculation as DATE with exactly 1,050,496 NULLs, precisely
# the count of -9 values in the same column. Phase C therefore refuses to
# convert anything it cannot parse rather than producing NA.
#
# Replaces data-raw/archive_00_wsdl_types.R.

.wsdl_type_cache <- new.env(parent = emptyenv())

# DATRAS table -> the web service operation whose ASMX page documents its
# fields. Verified against op_datras_operations().
.DATRAS_OPERATION <- c(
  HH = "getHHdata",
  HL = "getHLdata",
  CA = "getCAdata",
  LT = "getLitterAssessmentOutput"
)

# Per-field exceptions to the WSDL's declared type. The WSDL is the default;
# this list is the exception, one documented row per divergence, never a
# blanket correction.
#
# IMPORTANT: keyed by LEGACY field name, because Phase A runs before
# op_rename_to_new(). Most of these names are identical in both schemes, but
# not all -- SpeciesCategory is `CatIdentifier` on the wire.
#
# Two distinct kinds of override, distinguished by `kind`:
#   "ices-error"  -- ICES's WSDL is demonstrably wrong about the field.
#   "spec-driven" -- the WSDL is right about the wire, but opus's dictionary
#                    types the field `enum`, and an enum's underlying data
#                    must be string-like (data-dict validation.md, "Enum
#                    membership"); storing it as int is a guaranteed M01.
.WSDL_TYPE_OVERRIDES <- data.frame(
  table        = c("HL",          "CA",          "LT",                "HH",      "LT",      "HL"),
  legacy_field = c("Valid_Aphia", "Valid_Aphia", "DateofCalculation", "Tickler", "Tickler", "CatIdentifier"),
  wsdl         = c("string",      "string",      "string",            "int",     "int",     "int"),
  override     = c("int",         "int",         "int",               "string",  "string",  "string"),
  kind         = c("ices-error",  "ices-error",  "ices-error",        "spec-driven", "spec-driven", "spec-driven"),
  reason       = c(
    "Valid_Aphia holds a numeric WoRMS AphiaID; the dictionary types it number(id). ICES's WSDL declaring it string is an upstream error.",
    "Valid_Aphia holds a numeric WoRMS AphiaID; the dictionary types it number(id). ICES's WSDL declaring it string is an upstream error.",
    "HH, HL and CA all declare DateofCalculation int; only LT's operation declares string, for the same YYYYMMDD field. An ICES-side inconsistency, not a real difference.",
    "Dictionary types Tickler as enum: icesVocab TS_Tickler is a controlled code list (0-30 plus '-9' = 'no ticklers allowed', a real answer rather than a missing value). Enum data must be string-like, so the codes are stored as strings and keep their labels in the catalog.",
    "Dictionary types Tickler as enum: icesVocab TS_Tickler is a controlled code list (0-30 plus '-9' = 'no ticklers allowed', a real answer rather than a missing value). Enum data must be string-like, so the codes are stored as strings and keep their labels in the catalog.",
    "Dictionary types SpeciesCategory (wire name CatIdentifier) as enum: icesVocab TS_CatIdentifier is a controlled leveled code list of 56 codes plus '-9'. Enum data must be string-like, so the codes are stored as strings and keep their labels in the catalog."
  ),
  stringsAsFactors = FALSE
)

#' Fetch (and cache) the WSDL field/type map for one DATRAS table
#'
#' @param table Character scalar: `"HH"`, `"HL"`, `"CA"` or `"LT"`.
#' @return Named character vector: field name -> WSDL type.
#' @keywords internal
.wsdl_type_map <- function(table) {
  if (!table %in% names(.DATRAS_OPERATION)) {
    stop("No known WSDL operation for table '", table, "'. Valid tables: ",
         paste(names(.DATRAS_OPERATION), collapse = ", "), call. = FALSE)
  }
  if (!exists(table, envir = .wsdl_type_cache, inherits = FALSE)) {
    types <- op_datras_operation_types(.DATRAS_OPERATION[[table]])
    assign(table, stats::setNames(types$type, types$field),
           envir = .wsdl_type_cache)
  }
  get(table, envir = .wsdl_type_cache, inherits = FALSE)
}

#' Cast a parsed DATRAS table to its WSDL-declared physical types
#'
#' Phase A of the conversion. Every column with a WSDL type is explicitly
#' cast -- including string columns, whose absence from the old
#' implementation is what allowed per-file type drift (a column could be
#' int32 in files where every row happened to be `"-9"` and string in files
#' with a real value).
#'
#' **Sentinel values are preserved exactly.** `"-9"` in an int column becomes
#' the integer `-9`, never `NA`. Deciding which sentinels mean "missing" is
#' [op_strip_sentinels()]'s job, per field and on recorded evidence.
#'
#' The WSDL is authoritative except for the small documented override list
#' returned by [op_wsdl_type_overrides()].
#'
#' @param df Data frame: one parsed DATRAS table, columns still character.
#' @param table Character scalar: `"HH"`, `"HL"`, `"CA"` or `"LT"`.
#' @return `df` with every WSDL-typed column cast. Columns with no WSDL
#'   entry are left untouched rather than guessed at.
#' @seealso [op_strip_sentinels()] (Phase B), [op_cast_to_spec()] (Phase C).
#' @examples
#' \dontrun{
#'   df <- op_cast_wsdl_types(df, "HL")
#' }
#' @export
op_cast_wsdl_types <- function(df, table) {
  type_map <- .wsdl_type_map(table)
  ov <- .WSDL_TYPE_OVERRIDES[.WSDL_TYPE_OVERRIDES$table == table, , drop = FALSE]

  for (col in names(df)) {
    if (!col %in% names(type_map)) next
    wsdl_type <- type_map[[col]]

    hit <- ov$legacy_field == col
    if (any(hit)) {
      # Only override when the WSDL still says what the override was written
      # against -- if ICES fixes it upstream, fall through to the WSDL and
      # let the now-stale row be noticed rather than silently applied.
      if (identical(ov$wsdl[hit][1], wsdl_type)) wsdl_type <- ov$override[hit][1]
    }

    df[[col]] <- switch(
      wsdl_type,
      "int"     = suppressWarnings(as.integer(df[[col]])),
      "decimal" = suppressWarnings(as.numeric(df[[col]])),
      "float"   = suppressWarnings(as.numeric(df[[col]])),
      "string"  = as.character(df[[col]]),
      {
        warning("Unhandled WSDL type '", wsdl_type, "' for ", table, ".", col,
                " -- left as-is. Add it to op_cast_wsdl_types().", call. = FALSE)
        df[[col]]
      }
    )
  }

  df
}

#' The documented WSDL type overrides
#'
#' The per-field exceptions to ICES's declared WSDL types, each with the
#' evidence for overriding it. Exposed so the list is inspectable rather than
#' buried in the caster.
#'
#' Keyed by **legacy** field name, because the cast runs before
#' [op_rename_to_new()] -- e.g. `SpeciesCategory` appears here under its wire
#' name `CatIdentifier`.
#'
#' @return Data frame: `table`, `legacy_field`, `wsdl` (what ICES declares),
#'   `override` (what opus uses instead), `kind` (`"ices-error"` where ICES is
#'   wrong, `"spec-driven"` where the dictionary's `enum` typing requires
#'   string-like storage), `reason`.
#' @examples
#' op_wsdl_type_overrides()
#' @export
op_wsdl_type_overrides <- function() {
  .WSDL_TYPE_OVERRIDES
}

#' Realise the semantic types the wire format cannot express
#'
#' Phase C of the conversion. The data dictionary's types are *measurement
#' scales*, deliberately coarser than storage -- `number` covers "integers
#' or floating-point", so the dictionary neither can nor should decide
#' int-vs-double or storage width. Those come from the WSDL in
#' [op_cast_wsdl_types()].
#'
#' This function therefore converts **only** the types where the dictionary
#' says something the wire genuinely cannot: `date` and `datetime`. Widening
#' it to act on `number(*)` would re-introduce exactly the parquet-vs-XML
#' type divergence this pipeline exists to remove.
#'
#' DATRAS dates arrive as `YYYYMMDD`. **Any value that fails to parse is an
#' error, not an `NA`** -- that guard is the whole point: converting a date
#' column while sentinels are still present is how the previously-published
#' archive silently lost 1,050,496 `-9` values. Run [op_strip_sentinels()]
#' first.
#'
#' @param df Data frame, already through [op_cast_wsdl_types()],
#'   [op_rename_to_new()] and [op_strip_sentinels()].
#' @param table Character scalar: `"HH"`, `"HL"`, `"CA"` or `"LT"`.
#' @return `df` with `date`/`datetime` columns converted.
#' @seealso [op_cast_wsdl_types()] (Phase A), [op_strip_sentinels()] (Phase B).
#' @examples
#' \dontrun{
#'   df <- op_cast_to_spec(df, "HL")
#' }
#' @export
op_cast_to_spec <- function(df, table) {
  spec <- op_field_spec(table_name = table)
  date_fields <- unique(spec$new_name[spec$type %in% c("date", "datetime")])
  targets <- intersect(date_fields, names(df))

  for (col in targets) {
    x <- df[[col]]
    if (inherits(x, "Date")) next

    chr <- as.character(x)
    out <- as.Date(chr, format = "%Y%m%d")

    lost <- which(!is.na(chr) & is.na(out))
    if (length(lost) > 0) {
      bad <- unique(chr[lost])
      stop(sprintf(
        paste0("op_cast_to_spec(): %d value(s) in %s.%s are not YYYYMMDD dates ",
               "and would become NA: %s%s. Refusing to convert -- run ",
               "op_strip_sentinels() first, or fix the dictionary if these are real."),
        length(lost), table, col,
        paste(utils::head(bad, 5), collapse = ", "),
        if (length(bad) > 5) sprintf(" (and %d more distinct)", length(bad) - 5) else ""
      ), call. = FALSE)
    }

    df[[col]] <- out
  }

  df
}
