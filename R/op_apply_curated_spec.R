#' Apply curated spec (renames + type details) to enriched YAML
#'
#' Takes enriched Stage 3 YAML (with icesVocab enums, original field names)
#' and applies curated specification:
#' - Field renames (Ship → Platform, SweepLngt → SweepLength, etc.)
#' - Type refinements (number → number(quantity), string → enum if not already)
#' - Detailed descriptions and domain documentation
#' - Label information
#'
#' Uses op_field_name_map() to find renames via legacy field name lookup.
#'
#' @param enriched_yaml List: enriched Stage 3 YAML with icesVocab enums
#' @param curated_yaml List: parsed curated reference YAML from inst/
#' @param table_name Character: table name to process (HH, HL, CA, LT)
#'
#' @return List: YAML with curated names, types, and documentation applied.
#'   Retains enriched enums and real examples from parquet.
#'
#' @details
#' Field lookup strategy:
#' 1. Try to find curated column by enriched column name
#' 2. If not found, search curated columns' legacy names
#' 3. Copy over: name, type, description, label, constraints
#' 4. Preserve from enriched: examples, source metadata, values (enums)
#'
#' If enriched field not found in curated, keeps original (with warning).
#'
#' @export
op_apply_curated_spec <- function(enriched_yaml, curated_yaml, table_name) {
  # Get tables
  enr_table_idx <- NULL
  cur_table_idx <- NULL

  for (i in seq_along(enriched_yaml$tables)) {
    if (enriched_yaml$tables[[i]]$name == table_name) {
      enr_table_idx <- i
      break
    }
  }
  for (i in seq_along(curated_yaml$tables)) {
    if (curated_yaml$tables[[i]]$name == table_name) {
      cur_table_idx <- i
      break
    }
  }

  if (is.null(enr_table_idx) || is.null(cur_table_idx)) {
    stop("Table ", table_name, " not found in one or both YAMLs")
  }

  enr_table <- enriched_yaml$tables[[enr_table_idx]]
  cur_table <- curated_yaml$tables[[cur_table_idx]]

  # Build curated column lookup: by name and by legacy name
  cur_by_name <- list()
  cur_by_legacy <- list()
  for (col in cur_table$columns) {
    cur_by_name[[col$name]] <- col
    if (!is.null(col$details)) {
      legacy <- op_legacy_field_name(col$details)
      if (!is.na(legacy)) {
        cur_by_legacy[[legacy]] <- col
      }
    }
  }

  # Process each enriched column
  result_columns <- list()
  for (enr_col in enr_table$columns) {
    enr_name <- enr_col$name

    # Find curated version
    cur_col <- cur_by_name[[enr_name]]
    if (is.null(cur_col)) {
      cur_col <- cur_by_legacy[[enr_name]]
    }

    if (is.null(cur_col)) {
      # Keep enriched column as-is with warning
      warning("No curated spec found for field: ", enr_name, " (kept unchanged)")
      result_columns[[length(result_columns) + 1]] <- enr_col
      next
    }

    # Build result column: merge curated spec with enriched data
    result_col <- enr_col

    # Apply curated name (may differ from original)
    result_col$name <- cur_col$name

    # Apply curated type (may be refined e.g. number → number(quantity))
    result_col$type <- cur_col$type

    # Apply curated description (if not TODO)
    if (!is.null(cur_col$description) && !startsWith(cur_col$description, "TODO")) {
      result_col$description <- cur_col$description
    }

    # Apply curated label if present
    if (!is.null(cur_col$label)) {
      result_col$label <- cur_col$label
    }

    # Preserve curated details (which contains legacy name and notes)
    if (!is.null(cur_col$details)) {
      result_col$details <- cur_col$details
    }

    # If enriched column is not an enum but curated says it should be, and enr doesn't
    # have values yet, try to use curated values
    if (!is.null(cur_col$values) && is.null(enr_col$values) &&
        (is.null(enr_col$type) || enr_col$type != "enum")) {
      result_col$type <- "enum"
      result_col$values <- cur_col$values
    }

    # Preserve enriched enum values if present (they override curated)
    if (!is.null(enr_col$values)) {
      result_col$values <- enr_col$values
    }

    # Preserve constraints if present
    if (!is.null(cur_col$constraints)) {
      result_col$constraints <- cur_col$constraints
    }

    result_columns[[length(result_columns) + 1]] <- result_col
  }

  # Build result YAML
  result_yaml <- enriched_yaml
  result_yaml$tables[[enr_table_idx]]$columns <- result_columns

  # Update description to note curation
  if (!is.null(result_yaml$description)) {
    result_yaml$description <- enriched_yaml$tables[[enr_table_idx]]$description
  }

  result_yaml
}
