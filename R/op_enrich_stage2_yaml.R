#' Enrich Stage 2 YAML with icesVocab enum values
#'
#' Takes Stage 2 skeleton YAML (with original field names and inferred types)
#' and enriches string fields with icesVocab codes where applicable.
#'
#' Process:
#' 1. For each string field with cardinality < max_codes (default 50)
#' 2. Use op_vocab_resolve_key() to find candidate vocabulary keys
#' 3. Use op_vocab_get_codes() to fetch code:description pairs
#' 4. Populate field type: enum and values: {code: description}
#' 5. Keep non-enum fields as-is (open lists like Survey, Country, Platform)
#'
#' @param stage2_yaml List: parsed Stage 2 skeleton YAML
#' @param parquet_path Character: path to parquet file for cardinality checks
#' @param table_name Character: table name (HH, HL, CA, LT)
#' @param max_codes Integer: max codes to auto-populate (default 50). Fields with
#'   more codes are marked as TODO instead.
#' @param dry_run Logical: if TRUE, just report what would change (default FALSE)
#'
#' @return List: enriched YAML with enum values populated where icesVocab matches
#'
#' @details
#' Fields marked TODO in skeleton (cardinality < 50) are candidates for enrichment.
#' Skips fields that:
#' - Are already enums (type != string)
#' - Didn't match a vocabulary key
#' - Have > max_codes distinct values
#'
#' The enriched YAML retains all Stage 2 metadata (source, examples, constraints)
#' and adds a `vocabulary_source: icesVocab` note for enriched fields.
#'
#' @export
op_enrich_stage2_yaml <- function(stage2_yaml_path, parquet_path, table_name,
                                   max_codes = 50, dry_run = FALSE) {
  # Load YAML (support both path and pre-loaded list)
  if (is.character(stage2_yaml_path)) {
    stage2_yaml <- yaml::yaml.load_file(stage2_yaml_path)
  } else {
    stage2_yaml <- stage2_yaml_path
  }
  # Get table from YAML
  table_idx <- NULL
  for (i in seq_along(stage2_yaml$tables)) {
    if (stage2_yaml$tables[[i]]$name == table_name) {
      table_idx <- i
      break
    }
  }
  if (is.null(table_idx)) {
    stop("Table ", table_name, " not found in YAML")
  }

  table <- stage2_yaml$tables[[table_idx]]

  # Read parquet to check cardinality
  parquet_data <- arrow::read_parquet(parquet_path)

  # Get vocabulary types (for field name resolution)
  vocab_types <- op_vocab_get_types()

  # Track what was enriched
  enriched <- list()
  skipped <- list()

  # Process each column
  for (col_idx in seq_along(table$columns)) {
    col <- table$columns[[col_idx]]

    # Skip non-string fields
    if (col$type != "string") {
      next
    }

    field_name <- col$name

    # Skip if column not in parquet (shouldn't happen)
    if (!(field_name %in% names(parquet_data))) {
      skipped[[field_name]] <- "column not in parquet"
      next
    }

    # Get cardinality
    cardinality <- length(unique(na.omit(parquet_data[[field_name]])))

    # Skip if too many unique values
    if (cardinality > max_codes) {
      skipped[[field_name]] <- sprintf("cardinality=%d > max_codes=%d", cardinality, max_codes)
      next
    }

    # Try to resolve vocabulary key
    resolved <- op_vocab_resolve_key(field_name, vocab_types)

    if (length(resolved$candidates) == 0) {
      skipped[[field_name]] <- "no vocab match"
      next
    }

    # Try candidates in order (TS > bare > AC)
    vocab_key <- NULL
    codes <- NULL
    for (candidate in resolved$candidates) {
      codes <- op_vocab_get_codes(candidate)
      if (!is.null(codes) && nrow(codes) > 0) {
        vocab_key <- candidate
        break
      }
    }

    if (is.null(vocab_key)) {
      skipped[[field_name]] <- sprintf("no usable codes for candidates: %s",
        paste(resolved$candidates, collapse = ", "))
      next
    }

    # Build enum values list (codes are in Key column, descriptions in Description)
    values_list <- as.list(codes$Description)
    names(values_list) <- codes$Key

    if (!dry_run) {
      # Enrich the column
      col$type <- "enum"
      col$values <- values_list
      if (is.null(col$details)) {
        col$details <- ""
      }
      col$details <- sprintf("%s\nEnriched from icesVocab key: %s", col$details, vocab_key)

      table$columns[[col_idx]] <- col
    }

    enriched[[field_name]] <- list(
      vocab_key = vocab_key,
      code_count = nrow(codes),
      cardinality = cardinality,
      ambiguous = resolved$ambiguous
    )
  }

  # Update YAML if not dry_run
  if (!dry_run) {
    stage2_yaml$tables[[table_idx]] <- table
  }

  # Report
  cat("\n=== Stage 3 Enrichment Report (", table_name, ") ===\n")
  if (length(enriched) > 0) {
    cat("\nEnriched fields (string → enum):\n")
    for (field in names(enriched)) {
      info <- enriched[[field]]
      ambig_note <- ifelse(info$ambiguous, " [AMBIGUOUS - check domain match]", "")
      cat(sprintf("  %s: %d codes from %s (data cardinality: %d)%s\n",
        field, info$code_count, info$vocab_key, info$cardinality, ambig_note))
    }
  } else {
    cat("\nNo fields enriched.\n")
  }

  if (length(skipped) > 0) {
    cat("\nSkipped fields:\n")
    for (field in names(skipped)) {
      cat(sprintf("  %s: %s\n", field, skipped[[field]]))
    }
  }

  if (dry_run) {
    cat("\n(dry_run=TRUE, no changes made to YAML)\n")
  }

  invisible(stage2_yaml)
}
