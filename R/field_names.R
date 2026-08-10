#' Fetch a URL as a single text string, no package dependency beyond base R
#'
#' @keywords internal
.fetch_text <- function(url) {
  con <- url(url)
  on.exit(close(con), add = TRUE)
  paste(readLines(con, warn = FALSE), collapse = "\n")
}

#' Fetch ICES's live getDatrasFieldList metadata directly
#'
#' Fetches and parses the same live endpoint `icesDatras::getDatrasFieldList()`
#' wraps (RecordHeader/FieldName/FieldNameOld triples), without depending on
#' the icesDatras package -- this raw data is passed to
#' [op_datras_field_list()], which cross-verifies it against each
#' operation's own live response before trusting any claimed rename.
#'
#' @return Data frame: RecordHeader, FieldName, FieldNameOld, DataFormat,
#'   Description -- one row per field ICES's field-list service documents.
#'   A `FieldNameOld` of `"-"` (ICES's own placeholder for "never renamed")
#'   is left as-is; callers should treat it as equal to `FieldName`.
#' @keywords internal
.fetch_live_datras_field_list <- function() {
  xml <- .fetch_text("https://datras.ices.dk/WebServices/DATRASWebService.asmx/getDatrasFieldList")
  blocks <- regmatches(xml, gregexpr("(?s)<Cls_Datras_FieldList>.*?</Cls_Datras_FieldList>", xml, perl = TRUE))[[1]]
  # Sanity check, not a soft fallback: a transient/truncated response (seen
  # once, 2026-08-06, cause unconfirmed -- 174 records is the count observed
  # consistently otherwise) must fail loudly here rather than silently
  # produce a partial table that looks like genuine ICES gaps downstream.
  if (length(blocks) < 150) {
    stop("getDatrasFieldList returned only ", length(blocks), " records ",
         "(expected ~174) -- likely a truncated/transient response, not a ",
         "real change in ICES's data. Retry rather than trust this result.",
         call. = FALSE)
  }
  get_tag <- function(block, tag) {
    m <- regmatches(block, regexec(paste0("(?s)<", tag, ">(.*?)</", tag, ">"), block, perl = TRUE))[[1]]
    if (length(m) > 1) trimws(m[2]) else NA_character_
  }
  data.frame(
    RecordHeader = vapply(blocks, get_tag, character(1), tag = "RecordHeader"),
    FieldName    = vapply(blocks, get_tag, character(1), tag = "FieldName"),
    FieldNameOld = vapply(blocks, get_tag, character(1), tag = "FieldNameOld"),
    DataFormat   = vapply(blocks, get_tag, character(1), tag = "DataFormat"),
    Description  = vapply(blocks, get_tag, character(1), tag = "Description"),
    stringsAsFactors = FALSE, row.names = NULL
  )
}

#' Fetch the real field names an ICES DATRAS operation actually returns
#'
#' Reads the operation's own ASMX description page, which embeds a sample
#' SOAP response showing the field names and types the server's own code
#' actually generates for that operation -- independent of (and, per
#' [op_datras_field_list()]'s tracing, sometimes more accurate than) the
#' separately-maintained getDatrasFieldList metadata service. Ported from
#' `data-raw/spec_00_operation_types.R`'s crawler so this capability doesn't
#' require sourcing a data-raw file at package runtime.
#'
#' @param operation Character scalar: an ICES DATRAS web service operation
#'   name, e.g. `"getCAdata"`.
#' @return Character vector of field names, in the order the operation
#'   returns them.
#' @keywords internal
.fetch_datras_operation_fields <- function(operation) {
  base_url <- "https://datras.ices.dk/WebServices/DATRASWebService.asmx"
  page <- .fetch_text(paste0(base_url, "?op=", operation))
  result_pattern <- sprintf("&lt;%sResult&gt;([\\s\\S]*?)&lt;/%sResult&gt;", operation, operation)
  blocks <- regmatches(page, gregexpr(result_pattern, page, perl = TRUE))[[1]]
  if (length(blocks) == 0) {
    stop("No <", operation, "Result> block found for operation '", operation, "'", call. = FALSE)
  }
  field_pattern <- "&lt;([A-Za-z_][A-Za-z0-9_]*)&gt;<font class=value>[a-zA-Z0-9]+</font>&lt;/\\1&gt;"
  fields <- unique(unlist(lapply(blocks, function(b) {
    m <- regmatches(b, gregexpr(field_pattern, b, perl = TRUE))[[1]]
    sub(field_pattern, "\\1", m, perl = TRUE)
  })))
  fields
}

#' Derive verified Tier 1 legacy field-name mappings, without icesDatras
#'
#' Replaces opus's former use of `icesDatras::getDatrasFieldList()` for
#' building the old-name -> new-name mapping used by the data-raw curation
#' pipeline. Traced 2026-08-06: ICES's own getDatrasFieldList metadata
#' service has confirmed errors and gaps (it's a separately-maintained
#' table, not generated from the live operations themselves), so this
#' function cross-verifies every claim against each operation's own live
#' response before trusting it, rather than taking getDatrasFieldList's
#' word for it the way icesDatras itself does.
#'
#' Algorithm, per table:
#' 1. **confirmed**: getDatrasFieldList documents old name X -> new name Y
#'    for this table, and X is confirmed present in this table's own live
#'    operation response.
#' 2. **cross_table_confirmed**: X isn't confirmed for *this* table, but
#'    some other Tier 1 table has a `confirmed` mapping for the same old
#'    name X -> Y, and this table's real field list also contains X (e.g.
#'    LT's real `Ship`/`StNo`/`HaulNo` columns, which getDatrasFieldList
#'    incorrectly claims are never renamed for LT specifically, even
#'    though it correctly documents Ship->Platform etc. for HH/HL/CA).
#' 3. **no_evidence**: neither of the above; the field is left unrenamed
#'    (old = new). If getDatrasFieldList has a "dangling" row for this
#'    table -- a claimed rename whose old name isn't in this table's real
#'    field list, and that isn't itself explained by tiers 1-2 -- that's
#'    recorded in `note` rather than used to guess a rename, since the
#'    dangling row's *new*-name half is unverified once its *old*-name
#'    half is already shown not to correspond to anything real (see CA's
#'    `IndividualAge`/`AgeRings`, which triggered this exact case: no
#'    other Tier 1 table's data explains it, so it stays `no_evidence`).
#'
#' Confirmed discrepancies as of 2026-08-06 (candidates for an ICES issue --
#' checked directly against the official `ices-tools-prod/icesDatras` on
#' GitHub, 2026-08-09: its `getDatrasFieldList()` has no patch of any kind,
#' so none of these are things "icesDatras already handles"; they're genuine
#' gaps in ICES's own live service that any consumer would hit):
#'   1. LT: getDatrasFieldList documents only 22 of LT's 58 real fields.
#'   2. LT: 3 of those 22 (Platform/StationName/HaulNumber) claim no
#'      rename; real data has Ship/StNo/HaulNo (resolved here via tier 2).
#'   3. LT: documents a RecordHeader/RecordType field that doesn't exist
#'      in LT's real data at all (neither the live response nor the
#'      archive) -- the reverse problem from #1.
#'   4. CA: IndividualAge's documented old name ("AgeRings") isn't a real
#'      field; real name is "Age" (resolved here as `no_evidence`, since
#'      the *new*-name half of that same row is consequently unverified).
#'   5. HH: DateofCalculation is a real field, undocumented under any name.
#'   6. HL: DateofCalculation and Valid_Aphia, same as #5.
#'
#' @param tables Character vector: which RecordHeaders to resolve (default
#'   opus's Tier 1 scope).
#' @return Data frame: RecordHeader, old_name, new_name, source_tier, note.
#' @export
op_datras_field_list <- function(tables = c("HH", "HL", "CA", "LT")) {
  operation_for <- c(HH = "getHHdata", HL = "getHLdata", CA = "getCAdata",
                     LT = "getLitterAssessmentOutput")
  tables <- intersect(tables, names(operation_for))

  fl <- .fetch_live_datras_field_list()
  fl <- fl[fl$RecordHeader %in% tables, ]
  fl$FieldNameOld[fl$FieldNameOld == "-"] <- fl$FieldName[fl$FieldNameOld == "-"]

  real_fields <- lapply(operation_for[tables], .fetch_datras_operation_fields)
  names(real_fields) <- tables

  confirmed_rows <- lapply(tables, function(rh) {
    sub <- fl[fl$RecordHeader == rh, ]
    sub[sub$FieldNameOld %in% real_fields[[rh]], c("FieldNameOld", "FieldName")]
  })
  cross_table_lookup <- unique(do.call(rbind, confirmed_rows))

  resolve_table <- function(rh) {
    sub <- fl[fl$RecordHeader == rh, ]
    out <- data.frame(RecordHeader = rh, old_name = real_fields[[rh]],
                       new_name = NA_character_, source_tier = NA_character_,
                       note = "", stringsAsFactors = FALSE)
    unresolved <- rep(TRUE, nrow(out))
    for (i in seq_len(nrow(out))) {
      on <- out$old_name[i]
      direct <- sub$FieldName[sub$FieldNameOld == on]
      if (length(direct) == 1) {
        out$new_name[i] <- direct
        out$source_tier[i] <- "confirmed"
        unresolved[i] <- FALSE
        next
      }
      x <- cross_table_lookup$FieldName[cross_table_lookup$FieldNameOld == on]
      if (length(unique(x)) == 1) {
        out$new_name[i] <- unique(x)
        out$source_tier[i] <- "cross_table_confirmed"
        unresolved[i] <- FALSE
      }
    }
    out$new_name[unresolved] <- out$old_name[unresolved]
    out$source_tier[unresolved] <- "no_evidence"

    dangling <- sub[!(sub$FieldNameOld %in% real_fields[[rh]]) &
                      sub$FieldNameOld != sub$FieldName &
                      !(sub$FieldName %in% out$new_name[!unresolved]), ]
    if (nrow(dangling) > 0 && any(unresolved)) {
      notes <- sprintf(
        "ICES documents a field '%s' paired with old-name '%s', not in this operation's live response -- unverified, not used to assign a rename (%d unexplained real field(s) remain: %s).",
        dangling$FieldName, dangling$FieldNameOld,
        sum(unresolved), paste(out$old_name[unresolved], collapse = ", ")
      )
      out$note[unresolved] <- paste(notes, collapse = " | ")
    }
    out
  }

  do.call(rbind, lapply(tables, resolve_table))
}

#' Build a rename-ready legacy -> new name crosswalk for one or more tables
#'
#' Thin wrapper around [op_datras_field_list()] for callers that need a
#' clean, collision-free 1:1 `old_name` -> `new_name` map to actually rename
#' columns with (`data-raw/spec_03_translate_new_names.R`,
#' `data-raw/archive_06_split_legacy_new.R`) -- as opposed to
#' [op_datras_field_list()]'s own broader, diagnostic purpose (reporting
#' every candidate rename along with its confidence tier, for auditing).
#'
#' Applies one documented, opus-side correction on top of
#' [op_datras_field_list()]'s raw output: LT's real `Depth` column is
#' cross-table-inferred to rename to `BottomDepth` (HH's own confirmed
#' rename for the same old name), but LT genuinely has its own separate,
#' real `BottomDepth` column too -- byte-for-byte duplicate values, but two
#' distinct fields (ICES-side redundancy, not a naming variant; see
#' `data-raw/ICES_ISSUE_REPORT.md`, Issue 6). Renaming `Depth` -> `BottomDepth`
#' here would collide two real LT columns into one name. Left unrenamed
#' (`old_name == new_name == "Depth"`) instead.
#'
#' @param tables Character vector: which RecordHeaders to resolve (default
#'   opus's Tier 1 scope).
#' @return Data frame: RecordHeader, old_name, new_name -- exactly one row
#'   per real column, safe to use directly as a rename map (no table's
#'   new_name values collide with each other).
#' @export
op_datras_rename_crosswalk <- function(tables = c("HH", "HL", "CA", "LT")) {
  fl <- op_datras_field_list(tables)

  lt_depth <- fl$RecordHeader == "LT" & fl$old_name == "Depth"
  if (any(lt_depth)) fl$new_name[lt_depth] <- fl$old_name[lt_depth]

  # Guard, not a soft check: confirm no table ends up with a rename
  # collision (two old_names mapping to the same new_name) -- would break
  # any 1:1 rename applied directly from this crosswalk. Checks generally
  # rather than just re-testing the one known LT/Depth case, in case a
  # similar collision ever turns up elsewhere.
  for (rh in unique(fl$RecordHeader)) {
    sub <- fl[fl$RecordHeader == rh, ]
    dup <- sub$new_name[duplicated(sub$new_name)]
    if (length(dup) > 0) {
      stop("op_datras_rename_crosswalk(): table '", rh, "' has colliding ",
           "new_name(s): ", paste(unique(dup), collapse = ", "),
           " -- not safe to use as a rename map.", call. = FALSE)
    }
  }

  fl[, c("RecordHeader", "old_name", "new_name")]
}

#' Extract legacy field name from column details
#'
#' Parses the "Legacy field name:" prefix from a column's details field to
#' extract the old ICES field name. Used for backward compatibility and
#' cross-referencing with ICES's own field-list metadata (fetched directly
#' via [op_datras_field_list()], not the icesDatras package).
#'
#' @param details Character string from a column's `details` field in data-dict.yaml
#'
#' @return Character: legacy field name, or `NA_character_` if not found
#'
#' @examples
#' \dontrun{
#'   # Typical usage: extract from parsed YAML
#'   details <- "Legacy field name: SweepLngt (verified via op_datras_field_list())..."
#'   op_legacy_field_name(details)
#'   # Returns "SweepLngt"
#' }
#'
#' @details
#' Format: The legacy name is stored as a fixed-prefix line in the details field:
#' `Legacy field name: \{OldName\} (verified via op_datras_field_list()).`
#'
#' This approach:
#' - Complies with data-dict v0.1.0 spec (details is free-text)
#' - Is human-readable AND machine-readable (regex extraction)
#' - Survives YAML round-trips (write_yaml → read_yaml)
#' - Requires no non-standard YAML keys
#'
#' See `vignettes/articles/technical-notes.md` for design rationale.
#'
#' @export
op_legacy_field_name <- function(details) {
  if (is.null(details) || is.na(details)) {
    return(NA_character_)
  }

  m <- regexec("Legacy field name: (\\w+)", details)
  match <- regmatches(details, m)

  if (length(match) > 0 && length(match[[1]]) > 1) {
    match[[1]][2]
  } else {
    NA_character_
  }
}

#' Build field name mapping from data-dict YAML
#'
#' Extracts legacy → new field name mappings for all columns in a parsed
#' data-dict YAML. Useful for building equivalence tables, validating
#' coverage, or generating documentation.
#'
#' @param dict List: parsed DATRAS-data-dict.yaml (from `yaml::read_yaml()`)
#' @param table_name Character: optional filter to one table (HH, HL, CA, LT)
#'
#' @return Data frame with columns:
#' \describe{
#'   \item{RecordHeader}{Table name (HH, HL, CA, LT)}
#'   \item{new_name}{Current field name (from YAML column `name`)}
#'   \item{old_name}{Legacy field name (extracted from `details`), or NA}
#'   \item{has_legacy}{Logical: TRUE if a legacy name was found}
#' }
#'
#' @examples
#' \dontrun{
#'   dict <- yaml::read_yaml("inst/DATRAS-data-dict.yaml")
#'   mapping <- op_field_name_map(dict)
#'
#'   # All HH table field renames
#'   hh_map <- op_field_name_map(dict, table_name = "HH")
#'
#'   # Count coverage
#'   sum(hh_map$has_legacy)  # How many HH fields have legacy name documented?
#' }
#'
#' @details
#' Iterates over all tables and columns, extracts legacy names via
#' `op_legacy_field_name()`, and returns as a flat data frame for
#' easier analysis/reporting.
#'
#' @export
op_field_name_map <- function(dict, table_name = NULL) {
  rows <- list()
  row_count <- 0

  for (table in dict$tables) {
    if (!is.null(table_name) && table$name != table_name) {
      next
    }

    for (col in table$columns) {
      old <- op_legacy_field_name(col$details)
      row_count <- row_count + 1
      rows[[row_count]] <- data.frame(
        RecordHeader = table$name,
        new_name = col$name,
        old_name = old,
        has_legacy = !is.na(old),
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0) {
    # Return empty data frame with correct columns
    data.frame(
      RecordHeader = character(),
      new_name = character(),
      old_name = character(),
      has_legacy = logical(),
      stringsAsFactors = FALSE
    )
  } else {
    do.call(rbind, rows)
  }
}
