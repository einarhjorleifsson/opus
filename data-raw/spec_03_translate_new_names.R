# Translates the legacy-named curated dict into opus's own curated/new
# names -- the ONLY step in the pipeline that introduces new names at all.
# A pure rename: every type/units/range/examples/details/constraints/label
# value carries over completely unchanged, only `name` (and `source`'s
# parquet pointer) differ from inst/DATRAS-data-dict-legacy.yaml.
#
# Restructured 2026-08-09: previously, new names were introduced piecemeal
# -- mostly at seed time (spec_01 used to seed directly with ICES's
# suggested new name), with one further correction layered on top in
# spec_02 (an LT-specific cross-table rename step, since ICES's own
# field-list service doesn't document renames for LT) and legacy names
# then bolted on afterward as a `details:` annotation
# (`add_legacy_field_names()`). Now legacy names are primary throughout
# seeding and curation (see spec_01/spec_02's own headers for why), and
# every "what's this field's new name" question -- including LT's, which
# needs cross-table inference -- is answered exactly once, here, via
# op_datras_rename_crosswalk() (R/field_names.R). That function already
# carries the one known correction this needs (LT's real `Depth` column
# must NOT rename to `BottomDepth`, despite the naive cross-table inference
# suggesting it should -- LT has its own separate, real `BottomDepth`
# column too; see that function's own docs, or Issue 6 in
# data-raw/ICES_ISSUE_REPORT.md).
#
# Usage: Rscript data-raw/spec_03_translate_new_names.R

library(yaml)
library(purrr)
library(opus)

# yaml::read_yaml() silently collapses a single-element YAML sequence back
# into a bare scalar on read (confirmed directly: `constraints:\n- required`
# round-trips to a plain character "required", not a length-1 list) -- a
# data-dict spec violation on write-back, since the spec requires an array
# here regardless of length. A length>1 sequence round-trips fine as a plain
# atomic vector (confirmed: write_yaml() renders it back as a flat array,
# not nested) -- checking length, not is.list()/class(), is what actually
# distinguishes the broken case; an early is.list()-based version of this
# fix wrongly re-wrapped already-correct length>1 vectors into a nested
# single-element array, caught by the validator immediately (Quarter's
# `values: ['1','2','3','4']` became `values: [['1','2','3','4']]`). A
# NAMED length-1 map (e.g. RecordHeader's `values: {HH: ...}`) round-trips
# fine too and must NOT be touched -- excluded via the names() check below.
#
# Every other script in this pipeline builds these fields fresh in R (as
# list("required"), never reading a previously-written yaml back), so this
# round-trip loss is unique to this script, the only one that reads a
# curated yaml back in. Affects `constraints` (currently always length 1)
# and `examples` (usually longer, but LT's UnitItem is a genuine length-1
# case) -- `range` is excluded, always constructed as a 2-element min/max
# pair throughout this codebase, never a singleton.
rewrap_singleton_arrays <- function(dict) {
  array_fields <- c("constraints", "examples", "values")
  for (ti in seq_along(dict$tables)) {
    for (ci in seq_along(dict$tables[[ti]]$columns)) {
      col <- dict$tables[[ti]]$columns[[ci]]
      for (f in array_fields) {
        v <- col[[f]]
        if (!is.null(v) && length(v) == 1 && is.null(names(v))) col[[f]] <- list(v)
      }
      dict$tables[[ti]]$columns[[ci]] <- col
    }
  }
  dict
}

legacy <- rewrap_singleton_arrays(read_yaml("inst/DATRAS-data-dict-legacy.yaml"))

crosswalk <- op_datras_rename_crosswalk()

## ---- Ground-truth the crosswalk against the legacy yaml's real columns ----
# Not assumed: every column the legacy yaml actually has must resolve to
# exactly one new name, and vice versa -- a mismatch here means either the
# curation stage or the crosswalk source has drifted, and should fail loudly
# rather than silently rename only some columns.
for (tbl in legacy$tables) {
  expected_old <- map_chr(tbl$columns, "name")
  xw <- crosswalk[crosswalk$RecordHeader == tbl$name, ]

  only_in_dict <- setdiff(expected_old, xw$old_name)
  only_in_crosswalk <- setdiff(xw$old_name, expected_old)

  if (length(only_in_dict) > 0 || length(only_in_crosswalk) > 0) {
    stop(sprintf(
      "Table %s: crosswalk doesn't match inst/DATRAS-data-dict-legacy.yaml's real columns.\n  In yaml, not in crosswalk: %s\n  In crosswalk, not in yaml: %s",
      tbl$name, paste(only_in_dict, collapse = ", "), paste(only_in_crosswalk, collapse = ", ")
    ))
  }
  message("Ground-truthed ", tbl$name, ": all ", length(expected_old),
          " legacy names resolve to exactly one new name")
}

## ---- Rename every column -----------------------------------------------

translated <- legacy
rename_maps <- list()  # accumulated per table, reused below to translate `relationships`
for (ti in seq_along(translated$tables)) {
  tname <- translated$tables[[ti]]$name
  xw <- crosswalk[crosswalk$RecordHeader == tname, ]
  rename_map <- setNames(xw$new_name, xw$old_name)  # ground-truthed 1:1 above
  rename_maps[[tname]] <- rename_map

  for (ci in seq_along(translated$tables[[ti]]$columns)) {
    col <- translated$tables[[ti]]$columns[[ci]]
    col$name <- unname(rename_map[[col$name]])
    translated$tables[[ti]]$columns[[ci]] <- col
  }
}

## ---- Translate `relationships`' join expressions -----------------------
# Same crosswalk data as the column rename above, applied to `join` text
# instead of a `name` field -- not a second source of truth. A join
# expression is `table.column` tokens joined by `AND`/comparison operators
# (see site/spec.md's Relationships section); this rewrites every such
# token in place, wherever it appears in the expression.
if (!is.null(translated$relationships)) {
  token_pattern <- "([A-Za-z_][A-Za-z0-9_]*)\\.([A-Za-z_][A-Za-z0-9_]*)"

  translate_join <- function(join_expr) {
    m <- gregexpr(token_pattern, join_expr, perl = TRUE)
    tokens <- regmatches(join_expr, m)[[1]]
    regmatches(join_expr, m)[[1]] <- vapply(tokens, function(tok) {
      parts <- strsplit(tok, ".", fixed = TRUE)[[1]]
      new_col <- rename_maps[[parts[1]]][[parts[2]]]
      if (is.null(new_col)) {
        stop("No rename mapping for '", tok, "' in a relationship's join -- ",
             "crosswalk/relationships have drifted apart.", call. = FALSE)
      }
      paste0(parts[1], ".", new_col)
    }, character(1))
    join_expr
  }

  for (ri in seq_along(translated$relationships)) {
    translated$relationships[[ri]]$join <- translate_join(translated$relationships[[ri]]$join)
  }

  # Ground-truth, same rigor as the column-rename check above: every
  # translated reference must actually exist on its (already-renamed) table.
  for (rel in translated$relationships) {
    tokens <- regmatches(rel$join, gregexpr(token_pattern, rel$join, perl = TRUE))[[1]]
    for (tok in tokens) {
      parts <- strsplit(tok, ".", fixed = TRUE)[[1]]
      tbl <- translated$tables[[which(map_chr(translated$tables, "name") == parts[1])]]
      if (!(parts[2] %in% map_chr(tbl$columns, "name"))) {
        stop("Translated relationship references '", tok, "', not a real column of ", parts[1], call. = FALSE)
      }
    }
  }
  message("Translated ", length(translated$relationships), " relationship join(s) to curated names")
}

## ---- Translate table `definitions`' expressions -------------------------
# Same idea as relationships' join translation above, but a definition's
# `expr` is single-table (bare column names, not table.column-qualified) --
# this replaces whole-word identifier tokens that match one of THAT table's
# own legacy column names, via its own rename_map. A token that isn't a real
# column name for that table (an operator keyword, a function name) never
# matches a rename_map entry, so it's left untouched automatically -- no
# separate keyword list needed.
identifier_pattern <- "[A-Za-z_][A-Za-z0-9_]*"

translate_definition_expr <- function(expr, rename_map) {
  m <- gregexpr(identifier_pattern, expr, perl = TRUE)
  tokens <- regmatches(expr, m)[[1]]
  regmatches(expr, m)[[1]] <- vapply(tokens, function(tok) {
    new_col <- rename_map[[tok]]
    if (is.null(new_col)) tok else new_col
  }, character(1))
  expr
}

n_defs <- 0
for (ti in seq_along(translated$tables)) {
  tbl <- translated$tables[[ti]]
  if (is.null(tbl$definitions)) next
  rename_map <- rename_maps[[tbl$name]]
  for (di in seq_along(tbl$definitions)) {
    tbl$definitions[[di]]$expr <- translate_definition_expr(tbl$definitions[[di]]$expr, rename_map)
  }
  translated$tables[[ti]] <- tbl
  n_defs <- n_defs + length(tbl$definitions)
}
if (n_defs > 0) message("Translated ", n_defs, " table definition(s) to curated names")

## ---- Top-level metadata: point at the new-named parquet, describe origin ----

translated$description <- paste(
  "Direct per-haul submissions to ICES DATRAS: HH (haul), HL (length),",
  "CA (age), LT (litter). Translated from",
  "inst/DATRAS-data-dict-legacy.yaml -- see",
  "data-raw/spec_03_translate_new_names.R. A pure rename: every",
  "type/units/range/examples/details/constraints/label value is carried",
  "over unchanged from the legacy version; only column names (opus's own",
  "curated names, in place of ICES's legacy on-the-wire names) differ."
)
translated$origin <- paste(
  "data-raw/spec_01_seed_dict.R -> data-raw/spec_02_curate_dict.R",
  "-> data-raw/spec_03_translate_new_names.R"
)
translated$version <- list(date = as.character(Sys.Date()))

write_yaml(translated, "inst/DATRAS-data-dict.yaml")

# Post-process YAML to quote number-looking string examples (same
# requirement, same mechanism as spec_02_curate_dict.R -- yaml::write_yaml()
# doesn't preserve quote style for strings like "74E9", but only for
# `string` columns; `number(id)` examples should remain unquoted numbers).
# Re-run here because this is a brand-new write_yaml() call, with the same
# quoting behavior to correct.
for (outfile in c("inst/DATRAS-data-dict.yaml")) {
  lines <- readLines(outfile)
  i <- 1
  while (i <= length(lines)) {
    if (grepl("^\\s+type: string\\s*$", lines[i])) {
      j <- i + 1
      while (j <= length(lines) && !grepl("^\\s+- name: ", lines[j])) {
        if (grepl("^\\s+examples:\\s*$", lines[j])) {
          j <- j + 1
          while (j <= length(lines) && grepl("^\\s+- ", lines[j])) {
            match <- regexpr("- (.+)$", lines[j])
            if (match > 0) {
              value <- regmatches(lines[j], match)
              value <- sub("^- ", "", value)
              if (!grepl("^['\"]", value) && (grepl("^[0-9A-Fa-f]+$", value) || grepl("^[0-9A-Fa-f]*[E|D]", value))) {
                indent <- regmatches(lines[j], regexpr("^\\s+", lines[j]))
                lines[j] <- paste0(indent, "- '", value, "'")
              }
            }
            j <- j + 1
          }
          break
        }
        j <- j + 1
      }
    }
    i <- i + 1
  }
  writeLines(lines, outfile)
}

## ---- FINAL: validate against the data-dict spec -------------------------

source("R/validation.R")

validation_result <- op_validate_spec("inst/DATRAS-data-dict.yaml")

if (!validation_result$valid) {
  cat("\n✗ YAML VALIDATION FAILED:\n\n")
  cat(paste(validation_result$output, collapse = "\n"))
  cat("\n\n")
  stop("YAML validation failed. Fix errors above before committing.", call. = FALSE)
} else {
  cat("\n✓ YAML validation passed!\n\n")
}

message(
  "Translated ", sum(map_int(translated$tables, \(t) length(t$columns))),
  " columns across ", length(translated$tables), " tables from legacy to ",
  "curated names. Wrote inst/DATRAS-data-dict.yaml.\n",
  "✓ Validated against data-dict spec."
)
