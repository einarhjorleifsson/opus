#' Check type/name mismatches between WSDL, curated, and inferred YAML
#'
#' Compares field names and types across three sources:
#' - Minimal YAML (types-only from WSDL): authoritative source of WSDL declarations
#' - Current curated YAML: production spec with field renames and enum expansions
#' - Stage 2 skeleton YAML: inferred from actual parquet data
#'
#' Flags:
#' - Field renames (old name in WSDL but different in curated)
#' - Type downgrades (e.g., number → string) in curated vs WSDL
#' - Type mismatches between WSDL and actual data (Stage 2)
#' - Missing legacy field name documentation
#'
#' @param minimal_yaml List: parsed minimal YAML with types from WSDL
#' @param curated_yaml List: parsed current production YAML
#' @param stage2_yaml List: parsed Stage 2 skeleton YAML
#' @param verbose Print detailed findings (default: TRUE)
#'
#' @return Data frame with columns:
#' \describe{
#'   \item{table}{Table name (HH, HL, CA, LT)}
#'   \item{wsdl_name}{Field name in WSDL/minimal}
#'   \item{current_name}{Field name in current curated YAML (or NA if missing)}
#'   \item{wsdl_type}{Type in WSDL/minimal}
#'   \item{current_type}{Type in current curated YAML}
#'   \item{stage2_type}{Inferred type from parquet (Stage 2)}
#'   \item{issue}{Issue description: rename, type_downgrade, type_mismatch, missing_legacy, etc.}
#'   \item{severity}{critical, warning, info}
#' }
#'
#' @details
#' Helps audit the curation process and catch type mismatches that could affect
#' Phase 3 enum enrichment or downstream validation.
#'
#' @export
op_check_type_mismatch <- function(minimal_yaml, curated_yaml, stage2_yaml, verbose = TRUE) {
  issues <- list()
  issue_count <- 0

  for (table in minimal_yaml$tables) {
    table_name <- table$name
    curated_table <- NULL
    stage2_table <- NULL

    # Find corresponding table in curated and stage2 YAML
    for (t in curated_yaml$tables) {
      if (t$name == table_name) {
        curated_table <- t
        break
      }
    }
    for (t in stage2_yaml$tables) {
      if (t$name == table_name) {
        stage2_table <- t
        break
      }
    }

    if (is.null(curated_table)) {
      issue_count <- issue_count + 1
      issues[[issue_count]] <- data.frame(
        table = table_name,
        wsdl_name = NA_character_,
        current_name = NA_character_,
        wsdl_type = NA_character_,
        current_type = NA_character_,
        stage2_type = NA_character_,
        issue = "Table missing in curated YAML",
        severity = "critical",
        stringsAsFactors = FALSE
      )
      next
    }

    # Build maps for easier lookup
    curated_cols <- list()
    if (!is.null(curated_table$columns)) {
      for (c in curated_table$columns) {
        curated_cols[[c$name]] <- c
      }
    }
    stage2_cols <- list()
    if (!is.null(stage2_table) && !is.null(stage2_table$columns)) {
      for (c in stage2_table$columns) {
        stage2_cols[[c$name]] <- c
      }
    }

    # Check each column in WSDL
    for (col in table$columns) {
      wsdl_name <- col$name
      wsdl_type <- col$type

      # Try to find field in curated by WSDL name first, then by legacy name
      curated_col <- curated_cols[[wsdl_name]]
      current_name <- wsdl_name
      is_renamed <- FALSE

      if (is.null(curated_col)) {
        # Search by legacy field name in details
        for (cc in curated_table$columns) {
          if (!is.null(cc$details)) {
            legacy <- op_legacy_field_name(cc$details)
            if (!is.na(legacy) && legacy == wsdl_name) {
              curated_col <- cc
              current_name <- cc$name
              is_renamed <- TRUE
              break
            }
          }
        }
      }

      stage2_col <- stage2_cols[[wsdl_name]] # Stage 2 should still have original names
      if (is.null(stage2_col) && is_renamed) {
        stage2_col <- stage2_cols[[current_name]] # Try curated name
      }

      current_type <- ifelse(!is.null(curated_col), curated_col$type, NA_character_)
      stage2_type <- ifelse(!is.null(stage2_col), stage2_col$type, NA_character_)

      # Flag issues
      if (is.null(curated_col)) {
        issue_count <- issue_count + 1
        issues[[issue_count]] <- data.frame(
          table = table_name,
          wsdl_name = wsdl_name,
          current_name = NA_character_,
          wsdl_type = wsdl_type,
          current_type = NA_character_,
          stage2_type = stage2_type,
          issue = "Field missing in curated YAML",
          severity = "critical",
          stringsAsFactors = FALSE
        )
      } else if (is_renamed && is.null(curated_col$details)) {
        issue_count <- issue_count + 1
        issues[[issue_count]] <- data.frame(
          table = table_name,
          wsdl_name = wsdl_name,
          current_name = current_name,
          wsdl_type = wsdl_type,
          current_type = current_type,
          stage2_type = stage2_type,
          issue = "Renamed field missing legacy name documentation",
          severity = "warning",
          stringsAsFactors = FALSE
        )
      } else if (is_renamed && !is_renamed && is.na(op_legacy_field_name(curated_col$details))) {
        # Field renamed but legacy name not documented
        issue_count <- issue_count + 1
        issues[[issue_count]] <- data.frame(
          table = table_name,
          wsdl_name = wsdl_name,
          current_name = current_name,
          wsdl_type = wsdl_type,
          current_type = current_type,
          stage2_type = stage2_type,
          issue = "Field renamed but legacy name not documented",
          severity = "warning",
          stringsAsFactors = FALSE
        )
      }

      # Check type mismatches
      if (!is.na(current_type) && wsdl_type != current_type) {
        # Downgrades (number → string, string → numeric) are critical
        # Expansions (string → enum) are expected curation
        if ((wsdl_type == "number" && current_type == "string") ||
            (wsdl_type == "string" && current_type == "number")) {
          issue_count <- issue_count + 1
          issues[[issue_count]] <- data.frame(
            table = table_name,
            wsdl_name = wsdl_name,
            current_name = current_name,
            wsdl_type = wsdl_type,
            current_type = current_type,
            stage2_type = stage2_type,
            issue = paste0("Type downgrade: ", wsdl_type, " → ", current_type),
            severity = "critical",
            stringsAsFactors = FALSE
          )
        } else if (wsdl_type == "string" && current_type == "enum") {
          # This is expected: string fields with fixed vocab become enums
          # No issue to flag
        }
      }

      # Check type mismatch between WSDL and actual data (Stage 2)
      if (!is.na(stage2_type) && wsdl_type != stage2_type) {
        issue_count <- issue_count + 1
        issues[[issue_count]] <- data.frame(
          table = table_name,
          wsdl_name = wsdl_name,
          current_name = current_name,
          wsdl_type = wsdl_type,
          current_type = current_type,
          stage2_type = stage2_type,
          issue = paste0("Type mismatch WSDL vs data: ", wsdl_type, " vs ", stage2_type),
          severity = "warning",
          stringsAsFactors = FALSE
        )
      }
    }
  }

  if (length(issues) == 0) {
    result <- data.frame(
      table = character(),
      wsdl_name = character(),
      current_name = character(),
      wsdl_type = character(),
      current_type = character(),
      stage2_type = character(),
      issue = character(),
      severity = character(),
      stringsAsFactors = FALSE
    )
  } else {
    result <- do.call(rbind, issues)
    rownames(result) <- NULL
  }

  if (verbose && nrow(result) > 0) {
    cat("\n=== Type/Name Mismatch Report ===\n")
    critical <- result[result$severity == "critical", ]
    if (nrow(critical) > 0) {
      cat("\nCRITICAL issues:\n")
      print(critical[, c("table", "wsdl_name", "current_name", "wsdl_type", "current_type", "issue")])
    }
    warnings <- result[result$severity == "warning", ]
    if (nrow(warnings) > 0) {
      cat("\nWarnings:\n")
      print(warnings[, c("table", "wsdl_name", "current_name", "wsdl_type", "current_type", "issue")])
    }
  }

  invisible(result)
}
