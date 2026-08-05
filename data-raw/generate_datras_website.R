#' Generate DATRAS data dictionary as Quarto website with field dashboards
#'
#' Creates a multi-page website:
#' - One page per table (HH, HL, CA, LT)
#' - Each page has tabset with one tab per field
#' - Each field shown as complete dashboard card
#'
#' Usage: Rscript data-raw/generate_datras_website.R

suppressPackageStartupMessages({
  library(yaml)
})

cat("Loading DATRAS dictionary and known issues...\n")

dict <- read_yaml("inst/DATRAS-data-dict.yaml")
known_issues <- read_yaml("inst/DATRAS-known-issues.yaml")

dataset_name <- dict$name
dataset_desc <- dict$description
tables <- dict$tables

# Build quick index of known issues by field
issue_by_field <- list()
if (!is.null(known_issues$known_violations)) {
  for (issue in known_issues$known_violations) {
    if (!is.null(issue$field) && !is.null(issue$table)) {
      key <- paste0(issue$table, ":", issue$field)
      issue_by_field[[key]] <- issue
    }
  }
}

# ============================================================================
# ---- QUARTO CONFIG ----
# ============================================================================

quarto_config <- "project:
  type: website
  output-dir: DATRAS-data-dict-website

website:
  title: \"DATRAS Data Dictionary\"
  sidebar:
    contents:
      - section: \"DATRAS Dictionary\"
        contents:
          - index.qmd
          - text: \"---\"
          - tables.qmd

format:
  html:
    theme: cosmo
    css: [styles.css]
    toc: true
    toc-depth: 3
    code-fold: false
    smooth-scroll: true
"

writeLines(quarto_config, "inst/_quarto.yml")
cat("✓ Generated: inst/_quarto.yml\n")

# ============================================================================
# ---- INDEX PAGE ----
# ============================================================================

index_qmd <- sprintf('---
title: \"DATRAS Data Dictionary\"
subtitle: \"Reference for HH, HL, CA, LT exchange data structures\"
---

## Overview

%s

This reference documents the DATRAS data structures as submitted to ICES, with known data quality issues identified during validation (Tier 1, 2026-07-29).

### How to Use

- **Navigate by table:** Use the sidebar to select HH, HL, CA, or LT
- **Explore fields:** Each table has tabs for every field
- **View details:** Type, constraints, description, examples, and known issues in one place
- **Check validity:** See enum values, ranges, and any data quality flags

## Sentinel Values

Missing/not-recorded values in DATRAS are represented as:

- **Global:** `-9` (default across most numeric columns)
- **Field-specific:**
  - `HaulDuration` (HH): `-9`, `0` → missing/invalid duration
  - `AgeSource` (CA): `-1`, `-5`, `-95` → age source not determined

During Phase 2 parsing, these sentinels are converted to `NA`.

## Known Issues & Data Quality Violations

Identified during Tier 1 validation (2026-07-29):

', dataset_desc)

if (!is.null(known_issues$known_violations)) {
  for (issue in known_issues$known_violations) {
    severity <- issue$severity
    id <- issue$id

    callout_type <- switch(severity,
                          "A" = "danger",
                          "B" = "warning",
                          "C" = "warning",
                          "D" = "important",
                          "info")

    index_qmd <- paste0(index_qmd, sprintf('\n::: {.callout-%s}\n', callout_type))
    index_qmd <- paste0(index_qmd, sprintf('### %s (Severity: %s)\n\n', id, severity))

    if (!is.null(issue$field) && !is.null(issue$table)) {
      index_qmd <- paste0(index_qmd, sprintf('**Field:** [`%s`](#%s) in [**%s**](%s.qmd)\n\n',
                                            issue$field, tolower(issue$field),
                                            issue$table, tolower(issue$table)))
    }

    issue_desc <- issue$constraint %||% issue$issue
    if (!is.null(issue_desc)) {
      index_qmd <- paste0(index_qmd, sprintf('**Issue:** %s\n\n', issue_desc))
    }

    if (!is.null(issue$extent)) {
      index_qmd <- paste0(index_qmd, sprintf('**Extent:** %s\n\n', issue$extent))
    } else if (!is.null(issue$examples)) {
      index_qmd <- paste0(index_qmd, sprintf('**Examples:**\n\n- %s\n\n',
                                            paste(issue$examples, collapse = '\n- ')))
    }

    if (!is.null(issue$implication)) {
      index_qmd <- paste0(index_qmd, sprintf('**Implication:** %s\n\n', issue$implication))
    }

    index_qmd <- paste0(index_qmd, ':::\n\n')
  }
}

writeLines(index_qmd, "inst/index.qmd")
cat("✓ Generated: inst/index.qmd\n")

# ============================================================================
# ---- UNIFIED TABLES PAGE (with top-level tabs) ----
# ============================================================================

qmd <- sprintf('---
title: \"DATRAS Tables\"
subtitle: \"HH, HL, CA, LT field explorer\"
---

Explore fields for each table using the tabs below. The left sidebar shows fields for the selected table.

::: {.panel-tabset}

')

for (table in tables) {
  tbl_name <- table$name
  tbl_desc <- table$description

  # Tab heading
  qmd <- paste0(qmd, sprintf('## %s\n\n%s\n\n', tbl_name, tbl_desc))

  if (!is.null(table$columns)) {
    for (col in table$columns) {
      col_name <- col$name
      col_type <- col$type
      col_desc <- col$description
      col_details <- col$details
      col_values <- col$values
      col_constraints <- col$constraints

      # Field as section heading (appears in TOC sidebar within this tab)
      qmd <- paste0(qmd, sprintf('### %s\n\n', col_name))

      # Type and constraints as info box
      type_info <- sprintf('**Type:** `%s`', col_type)
      if (!is.null(col_constraints) && length(col_constraints) > 0) {
        type_info <- paste0(type_info, '\n\n**Constraints:** ',
                           paste(sprintf('`%s`', col_constraints), collapse = ', '))
      }
      qmd <- paste0(qmd, sprintf('::: {.callout-info}\n%s\n:::\n\n', type_info))

      # Description
      if (!is.null(col_desc)) {
        qmd <- paste0(qmd, sprintf('**Description**\n\n%s\n\n', col_desc))
      }

      # Details
      if (!is.null(col_details)) {
        qmd <- paste0(qmd, sprintf('::: {.callout-note}\n**Details:**\n\n%s\n:::\n\n',
                                  col_details))
      }

      # Known issues for this field
      issue_key <- paste0(tbl_name, ":", col_name)
      if (!is.null(issue_by_field[[issue_key]])) {
        issue <- issue_by_field[[issue_key]]
        severity <- issue$severity

        callout_type <- switch(severity,
                              "A" = "danger",
                              "B" = "warning",
                              "C" = "warning",
                              "D" = "important",
                              "info")

        qmd <- paste0(qmd, sprintf('::: {.callout-%s}\n', callout_type))
        qmd <- paste0(qmd, sprintf('**Known Issue:** %s (Severity: %s)\n\n',
                                  issue$id, severity))
        qmd <- paste0(qmd, sprintf('%s\n\n', issue$issue %||% issue$constraint))
        if (!is.null(issue$extent)) {
          qmd <- paste0(qmd, sprintf('**Extent:** %s\n\n', issue$extent))
        }
        if (!is.null(issue$implication)) {
          qmd <- paste0(qmd, sprintf('**Implication:** %s\n\n', issue$implication))
        }
        qmd <- paste0(qmd, ':::\n\n')
      }

      # Enum values
      if (!is.null(col_values) && length(col_values) > 0) {
        val_names <- names(col_values)
        val_descs <- unlist(col_values)

        if (length(val_names) > 0 && length(val_descs) > 0) {
          qmd <- paste0(qmd, '**Valid Values**\n\n')
          qmd <- paste0(qmd, '| Code | Description |\n')
          qmd <- paste0(qmd, '|------|-------------|\n')

          for (i in seq_len(length(val_names))) {
            code <- val_names[i]
            desc <- val_descs[i]
            qmd <- paste0(qmd, sprintf('| `%s` | %s |\n', code, desc))
          }
          qmd <- paste0(qmd, '\n')
        }
      }

      qmd <- paste0(qmd, '\n\n')
    }
  }
}

# Close tabset
qmd <- paste0(qmd, ':::\n')

# Write unified file
outfile <- "inst/tables.qmd"
writeLines(qmd, outfile)
total_fields <- sum(sapply(tables, function(t) if (!is.null(t$columns)) length(t$columns) else 0))
cat(sprintf("✓ Generated: %s (%d total fields across 4 tables)\n", outfile, total_fields))

# ============================================================================
# ---- SUMMARY ----
# ============================================================================

cat("\n")
cat("✓ DATRAS Field Dashboard Generated!\n")
cat("\nStructure:\n")
cat("  inst/_quarto.yml      (website config)\n")
cat("  inst/index.qmd        (overview + known issues)\n")
cat("  inst/tables.qmd       (unified page: HH/HL/CA/LT as top-level tabs)\n")
cat("\nFeatures:\n")
cat("  • Table tabs at top (HH, HL, CA, LT)\n")
cat("  • Sidebar shows only fields for selected table\n")
cat("  • Quick jump between tables\n")
cat("  • Known issues integrated per field\n")
cat("\nTo render:\n")
cat("  cd inst/\n")
cat("  quarto render\n")
cat("\nOutput:\n")
cat("  inst/DATRAS-data-dict-website/\n")
