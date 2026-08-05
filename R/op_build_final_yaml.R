#' Build final production YAML from curated spec + enriched enums
#'
#' Takes the curated YAML (with field names, types, descriptions) and the
#' enriched YAML (with icesVocab enum values) and merges them properly:
#' - Uses curated field names, types, descriptions, labels, constraints
#' - Replaces enum values with enriched icesVocab codes where available
#' - Keeps real examples from enriched YAML for non-enum fields
#' - Removes conflicting examples/values fields
#'
#' @param curated_yaml List: parsed curated production YAML
#' @param enriched_yaml List: parsed enriched YAML with icesVocab enums
#'
#' @return List: final YAML with proper structure
#'
#' @export
op_build_final_yaml <- function(curated_yaml, enriched_yaml) {
  result <- curated_yaml

  # For each table
  for (table_idx in seq_along(result$tables)) {
    result_table <- result$tables[[table_idx]]
    table_name <- result_table$name

    # Find enriched version of this table
    enr_table <- NULL
    for (t in enriched_yaml$tables) {
      if (t$name == table_name) {
        enr_table <- t
        break
      }
    }
    if (is.null(enr_table)) {
      next
    }

    # Build lookup of enriched columns by original name
    enr_by_orig <- list()
    for (col in enr_table$columns) {
      enr_by_orig[[col$name]] <- col
    }

    # Process each curated column
    for (col_idx in seq_along(result_table$columns)) {
      cur_col <- result_table$columns[[col_idx]]
      cur_name <- cur_col$name

      # Find enriched column (try by curated name first, then by legacy name)
      enr_col <- enr_by_orig[[cur_name]]
      if (is.null(enr_col) && !is.null(cur_col$details)) {
        # Try legacy name
        legacy <- op_legacy_field_name(cur_col$details)
        if (!is.na(legacy)) {
          enr_col <- enr_by_orig[[legacy]]
        }
      }

      # Merge data from enriched
      if (!is.null(enr_col)) {
        # If this field was enriched with enum values, use those
        if (!is.null(enr_col$values) && cur_col$type == "enum") {
          cur_col$values <- enr_col$values
          # Remove examples for enum fields (spec requires values only)
          cur_col$examples <- NULL
        }
        # For non-enum fields, keep real examples from enriched
        else if (is.null(cur_col$examples) && !is.null(enr_col$examples)) {
          cur_col$examples <- enr_col$examples
        }
      }

      # Ensure examples and constraints are lists
      if (!is.null(cur_col$examples) && !is.list(cur_col$examples)) {
        cur_col$examples <- list(cur_col$examples)
      }
      if (!is.null(cur_col$constraints) && !is.list(cur_col$constraints)) {
        cur_col$constraints <- list(cur_col$constraints)
      }

      result$tables[[table_idx]]$columns[[col_idx]] <- cur_col
    }
  }

  result
}
