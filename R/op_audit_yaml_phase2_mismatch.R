#' Audit mismatch between curated YAML and Phase 2 parquet
#'
#' Compares field names and types between:
#' - Phase 1 minimal YAML (WSDL types, original field names from XML)
#' - Phase 2 parquet files (generated from minimal YAML, has original names)
#' - Current curated YAML (curated names and types, for downstream use)
#'
#' This audit identifies:
#' 1. Fields renamed between parquet (original) and curated YAML
#' 2. Type expansions (string → enum, number → number(quantity))
#' 3. Fields in curated YAML not yet in parquet
#' 4. Fields in parquet not yet mapped in curated YAML
#'
#' @param minimal_yaml List: parsed minimal YAML (WSDL types)
#' @param curated_yaml List: parsed current production YAML
#' @param parquet_table Arrow Table or data.frame from parquet file
#' @param table_name Character: table name (HH, HL, CA, LT)
#'
#' @return Data frame with columns:
#' \describe{
#'   \item{status}{mapped, renamed, type_expanded, missing_in_parquet, missing_in_curated}
#'   \item{parquet_name}{Field name in parquet (from minimal YAML)}
#'   \item{curated_name}{Field name in curated YAML (or NA if not found)}
#'   \item{minimal_type}{Type in minimal YAML (WSDL authority)}
#'   \item{curated_type}{Type in curated YAML (or NA)}
#'   \item{legacy_documented}{Logical: is legacy field name documented in curated YAML}
#' }
#'
#' @export
op_audit_yaml_phase2_mismatch <- function(minimal_yaml, curated_yaml, parquet_table, table_name) {
  issues <- list()
  issue_count <- 0

  # Get table specs
  min_table <- NULL
  cur_table <- NULL
  for (t in minimal_yaml$tables) {
    if (t$name == table_name) {
      min_table <- t
      break
    }
  }
  for (t in curated_yaml$tables) {
    if (t$name == table_name) {
      cur_table <- t
      break
    }
  }

  if (is.null(min_table) || is.null(cur_table)) {
    stop("Table ", table_name, " not found in YAML(s)")
  }

  # Get parquet column names
  parquet_names <- colnames(parquet_table)

  # Build curated column map (by both current name and legacy name)
  cur_by_name <- list()
  cur_by_legacy <- list()
  for (col in cur_table$columns) {
    cur_by_name[[col$name]] <- col
    # Try to extract legacy name
    if (!is.null(col$details)) {
      legacy <- op_legacy_field_name(col$details)
      if (!is.na(legacy)) {
        cur_by_legacy[[legacy]] <- col
      }
    }
  }

  # Check each field in minimal YAML (these should all be in parquet)
  for (col in min_table$columns) {
    min_name <- col$name
    min_type <- col$type

    # Check if in parquet
    if (!(min_name %in% parquet_names)) {
      issue_count <- issue_count + 1
      issues[[issue_count]] <- data.frame(
        status = "missing_in_parquet",
        parquet_name = min_name,
        curated_name = NA_character_,
        minimal_type = min_type,
        curated_type = NA_character_,
        legacy_documented = NA,
        stringsAsFactors = FALSE
      )
      next
    }

    # Find in curated (by name or by legacy name)
    cur_col <- cur_by_name[[min_name]]
    if (is.null(cur_col)) {
      cur_col <- cur_by_legacy[[min_name]]
    }

    if (is.null(cur_col)) {
      # Field in minimal/parquet but not mapped in curated
      issue_count <- issue_count + 1
      issues[[issue_count]] <- data.frame(
        status = "missing_in_curated",
        parquet_name = min_name,
        curated_name = NA_character_,
        minimal_type = min_type,
        curated_type = NA_character_,
        legacy_documented = NA,
        stringsAsFactors = FALSE
      )
    } else {
      # Found in curated
      is_renamed <- cur_col$name != min_name
      legacy_doc <- ifelse(is_renamed && !is.null(cur_col$details), !is.na(op_legacy_field_name(cur_col$details)), NA)

      status <- "mapped"
      if (is_renamed) {
        status <- "renamed"
      }
      if (min_type != cur_col$type && !startsWith(cur_col$type, min_type)) {
        # Type was expanded (e.g., string → enum, number → number(quantity))
        if ((min_type == "string" && cur_col$type == "enum") ||
            (min_type == "number" && startsWith(cur_col$type, "number("))) {
          status <- "type_expanded"
        }
      }

      issue_count <- issue_count + 1
      issues[[issue_count]] <- data.frame(
        status = status,
        parquet_name = min_name,
        curated_name = cur_col$name,
        minimal_type = min_type,
        curated_type = cur_col$type,
        legacy_documented = legacy_doc,
        stringsAsFactors = FALSE
      )
    }
  }

  # Check for fields in curated not yet in parquet
  for (col in cur_table$columns) {
    cur_name <- col$name
    if (!(cur_name %in% parquet_names)) {
      # Check if it's a renamed field
      is_mapped <- FALSE
      if (!is.null(col$details)) {
        legacy <- op_legacy_field_name(col$details)
        if (!is.na(legacy) && legacy %in% parquet_names) {
          is_mapped <- TRUE
        }
      }

      if (!is_mapped) {
        issue_count <- issue_count + 1
        issues[[issue_count]] <- data.frame(
          status = "missing_in_parquet",
          parquet_name = NA_character_,
          curated_name = cur_name,
          minimal_type = NA_character_,
          curated_type = col$type,
          legacy_documented = NA,
          stringsAsFactors = FALSE
        )
      }
    }
  }

  if (length(issues) == 0) {
    result <- data.frame(
      status = character(),
      parquet_name = character(),
      curated_name = character(),
      minimal_type = character(),
      curated_type = character(),
      legacy_documented = logical(),
      stringsAsFactors = FALSE
    )
  } else {
    result <- do.call(rbind, issues)
    rownames(result) <- NULL
  }

  # Sort by status for readability
  status_order <- c("mapped", "renamed", "type_expanded", "missing_in_curated", "missing_in_parquet")
  result$status <- factor(result$status, levels = status_order)
  result <- result[order(result$status), ]
  result$status <- as.character(result$status)

  result
}
