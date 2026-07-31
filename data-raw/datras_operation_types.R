# STATUS (2026-07-23): foundation tool, not yet the final generation script.
# Built from the obus side while diagnosing why data-raw/DATASET_RAW.R's
# rebuild crashed consolidating CPUEL (see AGENTS.md's "Authoritative schema
# project" section for the full story and the strategic plan this feeds).
# The next step is to turn this into a real data-raw/ script that walks every
# operation, builds one verified field/type/name table, and ships it as a
# package data object -- that doesn't exist yet. This file is the crawler
# these functions depend on.
#
# Fetch the declared variable name/type pairs for a DATRAS web service
# operation from its ASMX operation-description page, e.g.:
#   https://datras.ices.dk/WebServices/DATRASWebService.asmx?op=getCPUELength
#
# The page embeds a sample SOAP response inside a <pre> block, HTML-escaped,
# with each field's type shown as a placeholder:
#   &lt;Area&gt;<font class=value>string</font>&lt;/Area&gt;
# This is the server's OWN authoritative type declaration for that field --
# generated directly from the operation's actual server-side return type, so
# it cannot drift from reality the way a separately-maintained table (e.g.
# getDatrasFieldList()) can. Verified concretely, not just in principle: this
# page says CPUEL/CPUEA's Area is "string"; getDatrasFieldList() says "int";
# real EVHOE 2001 data (Gn/Cc/Cs/Gs/Cn) proves the WSDL page right and
# getDatrasFieldList() wrong -- applyDatrasTypeSchema() trusting the latter
# silently destroys real area codes as NA whenever fix_types = TRUE.
#
# Isolating the <op>Result>...</op>Result> block (rather than scanning the
# whole page) deliberately excludes the operation's REQUEST parameters
# (e.g. lowercase survey/year/quarter), which sit outside it and aren't part
# of the returned record's schema. The block appears twice (SOAP 1.1 + SOAP
# 1.2 samples, identical content) and, for array-returning operations, twice
# more within each (one per example record) -- unique() collapses all of that
# to one row per field.

# Fetch the full list of currently valid DATRAS web service operation names,
# from the ASMX service description page (no ?op= parameter -- lists every
# operation the service exposes as a link). Meant to be run occasionally to
# refresh the valid-operations reference, NOT on every single
# get_datras_operation_types() call -- pass its result in via
# `valid_operations` to skip re-fetching when checking many operations.
get_datras_operations <- function(
    base_url = "https://datras.ices.dk/WebServices/DATRASWebService.asmx"
) {
  resp <- httr2::request(base_url) |> httr2::req_perform()
  page <- httr2::resp_body_string(resp)

  # Each operation appears as: <a href="...asmx?op=OperationName">OperationName</a>
  op_pattern <- '\\?op=([A-Za-z_][A-Za-z0-9_]*)">\\1</a>'
  matches <- regmatches(page, gregexpr(op_pattern, page, perl = TRUE))[[1]]
  ops <- sub(op_pattern, "\\1", matches, perl = TRUE)
  sort(unique(ops))
}

get_datras_operation_types <- function(
    operation,
    base_url = "https://datras.ices.dk/WebServices/DATRASWebService.asmx",
    valid_operations = NULL
) {
  # Validate the operation name against the server's own current operation
  # list before doing anything else -- catches typos/renamed operations with
  # a clear message instead of a confusing downstream regex-match failure.
  if (is.null(valid_operations)) valid_operations <- get_datras_operations(base_url)
  if (!operation %in% valid_operations) {
    stop("Invalid operation '", operation, "'. Valid operations are:\n  ",
         paste(valid_operations, collapse = ", "), call. = FALSE)
  }

  url  <- paste0(base_url, "?op=", operation)
  resp <- httr2::request(url) |> httr2::req_perform()
  page <- httr2::resp_body_string(resp)

  # [\s\S] (not .) so the match spans newlines -- the block is multi-line.
  result_pattern <- sprintf("&lt;%sResult&gt;([\\s\\S]*?)&lt;/%sResult&gt;", operation, operation)
  blocks <- regmatches(page, gregexpr(result_pattern, page, perl = TRUE))[[1]]
  if (length(blocks) == 0) {
    stop("No <", operation, "Result> block found at ", url,
         " -- this operation may not return a schema-described record ",
         "(e.g. a void or scalar result); inspect the page directly.")
  }

  field_pattern <- "&lt;([A-Za-z_][A-Za-z0-9_]*)&gt;<font class=value>([a-zA-Z0-9]+)</font>&lt;/\\1&gt;"
  pairs <- lapply(blocks, function(b) {
    matches <- regmatches(b, gregexpr(field_pattern, b, perl = TRUE))[[1]]
    data.frame(
      field = sub(field_pattern, "\\1", matches, perl = TRUE),
      type  = sub(field_pattern, "\\2", matches, perl = TRUE),
      stringsAsFactors = FALSE
    )
  })

  out <- unique(do.call(rbind, pairs))
  rownames(out) <- NULL
  out
}

# BUILT (2026-07-23): the generation step lives in data-raw/build_datras_schema.R, which
# sources this file for its two crawler functions. One correction made along the way, worth
# knowing before reading that script: step 3 as originally sketched here (derive old<->new
# name mappings by calling each operation with new_names = TRUE/FALSE and matching positions)
# turned out to be CIRCULAR -- applyDatrasNameSchema() derives the "new" name FROM
# getDatrasFieldList() itself, so such a call just mirrors whatever this repo's own table
# already says, not an independent source. FieldName/Description are relocated from
# getDatrasFieldList() (hot-fix included) instead of re-derived; only DataFormat and
# FieldNameOld come from this file's live WSDL crawl, which genuinely is independent.
# build_datras_schema.R also joins in two more fields not in the original sketch:
# DescriptionNew (from obus's hand-curated dr_lookup_fields) and an empty Comment column.
# See AGENTS.md's "Authoritative schema project" section for the full rationale, the two
# standing decisions (fork not mother repo; keep the four parseDatras()/
# applyDatrasTypeSchema() fixes, retire the getDatrasFieldList() hot-fix-block patches once
# this lands), and the 2026-07-23 update recording what the first full run found.
#
# PHASE B NOT YET DONE: wiring datras_schema into applyDatrasTypeSchema()/
# applyDatrasNameSchema() in place of the live getDatrasFieldList() call is a deliberate
# follow-up, pending review of data-raw/datras_schema_diff.csv.

if (sys.nframe() == 0) {
  op <- commandArgs(trailingOnly = TRUE)[1]
  if (is.na(op)) op <- "getCPUELength"
  print(get_datras_operation_types(op))
}
