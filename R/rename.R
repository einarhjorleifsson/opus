# Legacy -> current field-name translation, applied as early in the
# conversion as the type cast allows.
#
# This is an INTERIM stage with an ICES-defined end date. ICES is migrating
# DATRAS from legacy to current names one table at a time; as of 2026-08-29
# only HL has flipped (getHLdataNewHeaders, whose 29 field names match this
# package's current names exactly). When the remaining operations gain their
# *NewHeaders variants -- watch op_datras_operations() -- the download can
# point at those and this whole file can be deleted.
#
# It is also self-retiring in the meantime: applied to data that already
# carries current names, the crosswalk matches nothing and the rename is a
# no-op, so an early flip breaks nothing.

.crosswalk_cache <- new.env(parent = emptyenv())

#' Fetch (and cache) the legacy -> current crosswalk for one table
#'
#' [op_datras_rename_crosswalk()] performs several live ICES requests, so the
#' per-file conversion loop must not call it directly.
#'
#' **The crosswalk is always built over all four Tier 1 tables and then
#' subset**, never requested for one table alone. This is not an
#' optimisation -- it is required for correctness.
#' [op_datras_field_list()]'s tier-2 rule resolves a rename by borrowing a
#' `confirmed` mapping for the same legacy name from *another* table, and LT
#' depends on it heavily: ICES's metadata service does not document
#' `Ship`/`StNo`/`HaulNo` (and 34 more) as renamed for LT, even though it
#' documents them correctly for HH/HL/CA. Asking for `"LT"` on its own leaves
#' nothing to borrow from, so those 37 fields silently fall to `no_evidence`
#' and keep their legacy names -- a rename that quietly does almost nothing.
#'
#' @param table Character scalar: `"HH"`, `"HL"`, `"CA"` or `"LT"`.
#' @return Data frame: `RecordHeader`, `old_name`, `new_name`.
#' @keywords internal
.rename_crosswalk <- function(table) {
  if (!exists("tier1", envir = .crosswalk_cache, inherits = FALSE)) {
    assign("tier1", op_datras_rename_crosswalk(), envir = .crosswalk_cache)
  }
  cw <- get("tier1", envir = .crosswalk_cache, inherits = FALSE)
  out <- cw[cw$RecordHeader == table, , drop = FALSE]
  if (nrow(out) == 0) {
    stop("No crosswalk rows for table '", table, "'.", call. = FALSE)
  }
  out
}

#' Rename a DATRAS table from ICES's legacy names to opus's current names
#'
#' Applies the ICES-derived, cross-verified crosswalk from
#' [op_datras_rename_crosswalk()]. Run **after** [op_cast_wsdl_types()]: the
#' WSDL type map is keyed by each operation's own field names, which are the
#' legacy ones for HH, CA and LT, so renaming first would break the type
#' lookup.
#'
#' Before renaming, the incoming columns are checked against the crosswalk.
#' That check is not decoration -- it is the ground-truth assertion that used
#' to live in `data-raw/archive_06_split_legacy_new.R`, and it is what would
#' catch a crosswalk that has drifted from what ICES actually serves.
#'
#' @param df Data frame carrying ICES's legacy (on-the-wire) column names.
#' @param table Character scalar: `"HH"`, `"HL"`, `"CA"` or `"LT"`.
#' @param strict Logical. If `TRUE` (default), every crosswalk column must be
#'   present in `df` and vice versa. Set `FALSE` to allow `df` to be missing
#'   some crosswalk columns (an unknown column in `df` is always an error,
#'   since that means the crosswalk is stale).
#' @return `df` with current column names.
#' @seealso [op_datras_rename_crosswalk()], [op_datras_operations()] to check
#'   whether ICES has retired the need for this step.
#' @examples
#' \dontrun{
#'   df <- op_cast_wsdl_types(df, "HL")
#'   df <- op_rename_to_new(df, "HL")
#' }
#' @export
op_rename_to_new <- function(df, table, strict = TRUE) {
  cw <- .rename_crosswalk(table)

  unknown <- setdiff(names(df), cw$old_name)
  # Columns already carrying current names are not "unknown" -- that is the
  # self-retiring case (ICES has flipped this operation), not an error.
  unknown <- setdiff(unknown, cw$new_name)
  if (length(unknown) > 0) {
    stop(sprintf(
      paste0("op_rename_to_new(): %d column(s) in the %s data are in neither ",
             "half of the crosswalk: %s. The crosswalk is stale, or this is ",
             "not a %s table."),
      length(unknown), table, paste(unknown, collapse = ", "), table
    ), call. = FALSE)
  }

  if (strict) {
    missing <- setdiff(cw$old_name, names(df))
    # Same carve-out: a column already renamed upstream is not missing.
    already <- cw$new_name[match(missing, cw$old_name)]
    missing <- missing[!already %in% names(df)]
    if (length(missing) > 0) {
      stop(sprintf(
        "op_rename_to_new(): %d crosswalk column(s) absent from the %s data: %s.",
        length(missing), table, paste(missing, collapse = ", ")
      ), call. = FALSE)
    }
  }

  map <- stats::setNames(cw$new_name, cw$old_name)
  hit <- names(df) %in% names(map)
  names(df)[hit] <- unname(map[names(df)[hit]])
  df
}
