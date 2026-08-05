#!/usr/bin/env Rscript

# Generates Quarto articles for DATRAS-data-dict YAML files
# with visual structure for reviewer clarity. Articles are built by pkgdown.
#
# Usage: Rscript data-raw/yaml_to_formatted_md.R
# Output: vignettes/articles/datras-data-dict-formatted.qmd

library(yaml)

# Read the YAML
dict_path <- "inst/DATRAS-data-dict.yaml"
dict <- read_yaml(dict_path)

# Format a single column with clean markdown (no CSS, no emoji)
format_column <- function(col, table_name) {
  lines <- character()

  # Column header with name
  lines <- c(lines, sprintf("### `%s`", col$name))
  lines <- c(lines, "")

  # Type
  if (!is.null(col$type)) {
    lines <- c(lines, sprintf("**Type:** `%s`", col$type))
  }

  # Label (if present)
  if (!is.null(col$label)) {
    lines <- c(lines, sprintf("**Label:** %s", col$label))
  }

  # Description
  if (!is.null(col$description)) {
    lines <- c(lines, sprintf("**Description:** %s", col$description))
  }

  # Values (for enums)
  if (!is.null(col$values) && col$type == "enum") {
    lines <- c(lines, "")
    lines <- c(lines, "**Values:**")
    lines <- c(lines, "")

    if (is.list(col$values)) {
      if (!is.null(names(col$values)) && length(names(col$values)) > 0) {
        # Map form with descriptions
        for (code in names(col$values)) {
          desc <- col$values[[code]]
          if (is.na(desc)) {
            desc <- code
          }
          lines <- c(lines, sprintf("- `%s`: %s", code, desc))
        }
      } else {
        # Array form
        for (code in col$values) {
          lines <- c(lines, sprintf("- `%s`", code))
        }
      }
    }
  }

  # Range (for numeric/temporal)
  if (!is.null(col$range)) {
    lines <- c(lines, "")
    min_val <- col$range[[1]]
    max_val <- col$range[[2]]
    lines <- c(lines, sprintf("**Range:** `[%s, %s]`", min_val, max_val))
  }

  # Examples
  if (!is.null(col$examples)) {
    lines <- c(lines, "")
    lines <- c(lines, "**Examples:** ")
    example_str <- paste(sprintf("`%s`", col$examples), collapse = ", ")
    lines <- c(lines, example_str)
  }

  # Units
  if (!is.null(col$units)) {
    lines <- c(lines, sprintf("**Units:** `%s`", col$units))
  }

  # Constraints
  if (!is.null(col$constraints)) {
    lines <- c(lines, "")
    constraint_str <- paste(sprintf("`%s`", col$constraints), collapse = ", ")
    lines <- c(lines, sprintf("**Constraints:** %s", constraint_str))
  }

  # Details
  if (!is.null(col$details) && !is.na(col$details)) {
    lines <- c(lines, "")
    lines <- c(lines, "**Details:**")
    lines <- c(lines, "")
    # Wrap in blockquote for visual distinction
    detail_lines <- strsplit(col$details, "\n")[[1]]
    for (detail_line in detail_lines) {
      if (nchar(detail_line) > 0) {
        lines <- c(lines, sprintf("> %s", detail_line))
      }
    }
  }

  lines <- c(lines, "")

  paste(lines, collapse = "\n")
}

# Format a table
format_table <- function(table) {
  lines <- character()

  # Table header
  lines <- c(lines, sprintf("## %s: %s", table$name, table$label %||% ""))
  lines <- c(lines, "")

  # Table description
  if (!is.null(table$description)) {
    lines <- c(lines, table$description)
    lines <- c(lines, "")
  }

  # Columns
  for (col in table$columns) {
    lines <- c(lines, format_column(col, table$name))
  }

  paste(lines, collapse = "\n")
}

# Generate Quarto document for full dict
generate_quarto <- function(dict, title, filename_slug) {
  lines <- character()

  # YAML frontmatter
  lines <- c(lines, "---")
  lines <- c(lines, sprintf("title: \"%s\"", title))
  lines <- c(lines, sprintf("subtitle: \"Formatted reference for %s\"", tolower(filename_slug)))
  lines <- c(lines, sprintf("date: %s", Sys.Date()))
  lines <- c(lines, "toc: true")
  lines <- c(lines, "---")
  lines <- c(lines, "")

  # Introduction
  lines <- c(lines, "This document provides a formatted view of the DATRAS data dictionary")
  lines <- c(lines, "for easy visual review. Each field is organized with its type, description,")
  lines <- c(lines, "values, and other metadata clearly labeled.")
  lines <- c(lines, "")

  if (!is.null(dict$description)) {
    lines <- c(lines, dict$description)
    lines <- c(lines, "")
  }

  if (!is.null(dict$version$date)) {
    lines <- c(lines, sprintf("**Version date:** `%s`", dict$version$date))
    lines <- c(lines, "")
  }

  # Tables
  for (table in dict$tables) {
    lines <- c(lines, format_table(table))
  }

  paste(lines, collapse = "\n")
}

# Generate formatted Quarto article
qmd_descriptive <- generate_quarto(
  dict,
  "DATRAS Data Dictionary (Descriptive)",
  "descriptive"
)

# Write output to vignettes/articles/
write(qmd_descriptive, "vignettes/articles/datras-data-dict-formatted.qmd")

cat("✓ Generated Quarto article:\n")
cat("  - vignettes/articles/datras-data-dict-formatted.qmd\n")
cat("\nThis will be built by pkgdown as part of the website.\n")
