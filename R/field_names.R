#' Extract legacy field name from column details
#'
#' Parses the "Legacy field name:" prefix from a column's details field to
#' extract the old ICES field name. Used for backward compatibility and
#' cross-referencing with icesDatras.
#'
#' @param details Character string from a column's `details` field in data-dict.yaml
#'
#' @return Character: legacy field name, or `NA_character_` if not found
#'
#' @examples
#' \dontrun{
#'   # Typical usage: extract from parsed YAML
#'   details <- "Legacy field name: SweepLngt (see icesDatras::getDatrasFieldList())..."
#'   op_legacy_field_name(details)
#'   # Returns "SweepLngt"
#' }
#'
#' @details
#' Format: The legacy name is stored as a fixed-prefix line in the details field:
#' `Legacy field name: {OldName} (see icesDatras::getDatrasFieldList()).`
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
