# Live reads of ICES's DATRAS ASMX web service.
#
# These are the single implementation of "ask the DATRAS service what it
# exposes and what it returns". data-raw/ scripts call them; they must never
# re-implement this (see AGENTS.md -- no similar code in data-raw/ and R/).
# Replaces data-raw/spec_00_operation_types.R, whose crawler had been ported
# into R/field_names.R as a second copy.
#
# Deliberately base-R over `url()`/`readLines()` via .fetch_text(), not
# httr2: httr2 is a Suggests, not an Imports, so package code cannot depend
# on it.

#' List the DATRAS web service's currently exposed operations
#'
#' Reads the ASMX service-description page (no `?op=` parameter), which
#' lists every operation the service exposes as a link.
#'
#' Useful as a migration tripwire as well as a lookup: ICES is moving DATRAS
#' from legacy to current field names one table at a time, and each converted
#' table appears here as a new `*NewHeaders` operation. As of 2026-08-29 only
#' `getHLdataNewHeaders` exists; the appearance of `getHHdataNewHeaders` or
#' `getCAdataNewHeaders` is the signal that those tables have flipped.
#'
#' @param base_url The DATRAS web service endpoint.
#' @return Character vector of operation names, sorted.
#' @examples
#' \dontrun{
#'   ops <- op_datras_operations()
#'   grep("NewHeaders", ops, value = TRUE)
#' }
#' @export
op_datras_operations <- function(
    base_url = "https://datras.ices.dk/WebServices/DATRASWebService.asmx"
) {
  page <- .fetch_text(base_url)
  # Each operation appears as: <a href="...asmx?op=Name">Name</a>. The \1
  # backreference requires the href and the link text to agree, which keeps
  # unrelated links out.
  op_pattern <- '\\?op=([A-Za-z_][A-Za-z0-9_]*)">\\1</a>'
  matches <- regmatches(page, gregexpr(op_pattern, page, perl = TRUE))[[1]]
  sort(unique(sub(op_pattern, "\\1", matches, perl = TRUE)))
}

#' Fetch the field names and types a DATRAS operation actually returns
#'
#' Reads the operation's own ASMX description page, which embeds a sample
#' SOAP response with each field's type shown as a placeholder:
#' `&lt;Area&gt;<font class=value>string</font>&lt;/Area&gt;`.
#'
#' This is the server's **own** type declaration, generated from the
#' operation's actual server-side return type, so it cannot drift the way a
#' separately-maintained table can. That distinction is not theoretical:
#' this page reports CPUEL/CPUEA's `Area` as `string` while
#' `getDatrasFieldList()` reports `int`, and real EVHOE 2001 data (codes
#' `Gn`/`Cc`/`Cs`/`Gs`/`Cn`) proves the page right -- trusting the metadata
#' service there silently destroys real area codes.
#'
#' Only the operation's own result block is scanned, which excludes the
#' operation's *request* parameters (lowercase `survey`/`year`/`quarter`)
#' that sit outside it. The block repeats (SOAP 1.1 and 1.2 samples, and one
#' per example record for array-returning operations); duplicates collapse.
#'
#' @param operation Character scalar: an operation name, e.g. `"getCAdata"`.
#'   See [op_datras_operations()].
#' @param base_url The DATRAS web service endpoint.
#' @return Data frame with one row per field, in the order the operation
#'   returns them: `field` (character) and `type` (character -- ICES's own
#'   WSDL type, one of `string`, `int`, `decimal`, `float`).
#' @seealso [op_datras_operations()] for valid operation names,
#'   [op_datras_field_list()] for the legacy/current name crosswalk.
#' @examples
#' \dontrun{
#'   op_datras_operation_types("getHLdata")
#'   op_datras_operation_types("getHLdataNewHeaders")
#' }
#' @export
op_datras_operation_types <- function(
    operation,
    base_url = "https://datras.ices.dk/WebServices/DATRASWebService.asmx"
) {
  page <- .fetch_text(paste0(base_url, "?op=", operation))

  # [\s\S] rather than . so the match spans newlines -- the block is
  # multi-line.
  result_pattern <- sprintf("&lt;%sResult&gt;([\\s\\S]*?)&lt;/%sResult&gt;",
                            operation, operation)
  blocks <- regmatches(page, gregexpr(result_pattern, page, perl = TRUE))[[1]]

  if (length(blocks) == 0) {
    # Only now pay for the operations list, so the happy path stays one
    # request while a typo still gets a message naming the alternatives.
    valid <- tryCatch(op_datras_operations(base_url), error = function(e) character(0))
    if (length(valid) > 0 && !operation %in% valid) {
      stop("Invalid operation '", operation, "'. Valid operations are:\n  ",
           paste(valid, collapse = ", "), call. = FALSE)
    }
    stop("No <", operation, "Result> block found at ", base_url, "?op=", operation,
         " -- this operation may not return a schema-described record ",
         "(e.g. a void or scalar result); inspect the page directly.",
         call. = FALSE)
  }

  field_pattern <-
    "&lt;([A-Za-z_][A-Za-z0-9_]*)&gt;<font class=value>([a-zA-Z0-9]+)</font>&lt;/\\1&gt;"
  pairs <- lapply(blocks, function(b) {
    m <- regmatches(b, gregexpr(field_pattern, b, perl = TRUE))[[1]]
    data.frame(
      field = sub(field_pattern, "\\1", m, perl = TRUE),
      type  = sub(field_pattern, "\\2", m, perl = TRUE),
      stringsAsFactors = FALSE
    )
  })

  out <- unique(do.call(rbind, pairs))
  rownames(out) <- NULL
  out
}

#' Fetch ICES's getDatrasFieldList metadata, as ICES publishes it
#'
#' The raw, **unverified** metadata table ICES maintains alongside the DATRAS
#' service: one row per field it documents, with the legacy name it claims
#' each was renamed from.
#'
#' Not to be confused with [op_datras_field_list()], despite the similar
#' name. This is what ICES *says*; that function is what survives
#' cross-checking against each operation's real response. The difference is
#' not cosmetic -- this table is separately maintained rather than generated
#' from the live operations, and has confirmed errors and gaps (it documents
#' only 22 of LT's 58 fields, claims a RecordHeader field LT does not have,
#' and pairs CA's age field with a legacy name that is not real). Prefer
#' [op_datras_field_list()] unless you specifically want ICES's own claims.
#'
#' @return Data frame: `RecordHeader`, `FieldName`, `FieldNameOld`,
#'   `DataFormat`, `Description`. A `FieldNameOld` of `"-"` is ICES's
#'   placeholder for "never renamed"; callers should read it as equal to
#'   `FieldName`.
#' @seealso [op_datras_field_list()] for the cross-verified crosswalk.
#' @examples
#' \dontrun{
#'   fl <- op_datras_field_metadata()
#'   table(fl$RecordHeader)
#' }
#' @export
op_datras_field_metadata <- function() {
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
