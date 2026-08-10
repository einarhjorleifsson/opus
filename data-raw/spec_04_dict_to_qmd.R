# Renders a data-dict.yaml document (any of opus's per-tier dictionaries in
# inst/) into a .qmd file that a user can render to HTML themselves
# (`quarto render` / knit button) -- opus doesn't ship rendered HTML, it ships
# the YAML plus this generator.
#
# Deliberately dumb: no styling opinions beyond a Quarto table-of-contents,
# one section per table, one markdown table of columns per table. Every
# data-dict.yaml field the spec allows on a column (label, description,
# details, type, units, time_zone, display, values, range, constraints,
# examples) is surfaced -- nothing invented, nothing dropped silently.

library(yaml)
library(purrr)

# ---- helpers ----------------------------------------------------------

# Markdown table cells can't contain literal pipes or newlines.
md_escape <- function(x) {
  x <- gsub("\\|", "\\\\|", x)
  x <- gsub("\\s*\n\\s*", " ", x)
  x
}

md_cell <- function(x) {
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) {
    return("")
  }
  md_escape(paste(x, collapse = "; "))
}

# `values` is either a plain vector (`[M, F, U]`) or a named map
# (`{M: Male, F: Female}`); render both as "code" or "code: label" pairs.
format_values <- function(values) {
  if (is.null(values)) {
    return(NULL)
  }
  nm <- names(values)
  if (is.null(nm) || all(nm == "")) {
    paste0("`", unlist(values), "`", collapse = ", ")
  } else {
    paste0("`", nm, "`: ", unlist(values), collapse = "; ")
  }
}

format_constraints <- function(constraints) {
  if (is.null(constraints)) {
    return(NULL)
  }
  map_chr(constraints, function(x) {
    if (is.list(x)) {
      paste0(x$assert, if (!is.null(x$description)) paste0(" (", x$description, ")") else "")
    } else {
      as.character(x)
    }
  }) |> paste(collapse = "; ")
}

# One "Notes" cell per column, folding together every optional field the
# spec allows beyond name/type/description -- keeps the main table to four
# columns instead of one column per (mostly-empty) spec field.
format_notes <- function(col) {
  notes <- c(
    if (!is.null(col$units)) paste0("units: ", col$units),
    if (!is.null(col$time_zone)) paste0("time zone: ", col$time_zone),
    if (!is.null(col$display)) paste0("display: ", col$display),
    if (!is.null(col$range)) paste0("range: [", paste(col$range, collapse = ", "), "]"),
    format_values(col$values),
    format_constraints(col$constraints),
    if (!is.null(col$examples)) paste0("examples: ", paste(col$examples, collapse = ", ")),
    if (!is.null(col$details)) col$details
  )
  paste(notes, collapse = "<br>")
}

column_row <- function(col) {
  sprintf(
    "| %s | %s | %s | %s |",
    md_cell(col$name %||% ""),
    md_cell(col$type %||% ""),
    md_cell(col$label %||% col$description %||% ""),
    md_cell(format_notes(col))
  )
}

table_section <- function(tbl, level = 2) {
  heading <- paste(strrep("#", level), tbl$name %||% "(unnamed table)")
  intro <- c(
    if (!is.null(tbl$label) && !identical(tbl$label, tbl$name)) paste0("*", tbl$label, "*"),
    tbl$description,
    tbl$details
  )
  header <- c("| Name | Type | Label / Description | Notes |", "|---|---|---|---|")
  rows <- map_chr(tbl$columns, column_row)
  c(heading, "", intro, "", header, rows, "")
}

# ---- main entry point ---------------------------------------------------

#' Render a data-dict.yaml document to a Quarto (.qmd) file
#'
#' @param yaml_path Path to a data-dict.yaml document (e.g. under `inst/`).
#' @param qmd_path Output path for the generated .qmd. Defaults to
#'   `data-raw/<basename of yaml_path>.qmd`.
#' @return `qmd_path`, invisibly.
data_dict_to_qmd <- function(yaml_path, qmd_path = NULL) {
  dict <- read_yaml(yaml_path)

  if (is.null(qmd_path)) {
    base <- tools::file_path_sans_ext(basename(yaml_path))
    qmd_path <- file.path("vignettes/articles", paste0(base, ".qmd"))
  }

  title <- dict$label %||% dict$name %||% basename(yaml_path)

  frontmatter <- c(
    "---",
    sprintf('title: "%s"', title),
    "---",
    ""
  )

  intro <- c(
    dict$description,
    dict$details,
    "",
    "::: {.callout-note}",
    sprintf(
      "Generated from `%s` by `data-raw/spec_04_dict_to_qmd.R`. Edit the YAML and regenerate -- don't hand-edit this file.",
      yaml_path
    ),
    ":::",
    ""
  )

  sections <- map(dict$tables, table_section) |> unlist()

  writeLines(c(frontmatter, intro, sections), qmd_path)
  invisible(qmd_path)
}

# ---- run for opus's dictionaries ----------------------------------------

if (sys.nframe() == 0) {
  yaml_files <- list.files("inst", pattern = "\\.ya?ml$", full.names = TRUE)
  walk(yaml_files, data_dict_to_qmd)
}
