# Builds inst/DATRAS-ices.yaml -- a faithful consolidation of what ICES's
# own DATRAS metadata sources currently document, keyed by ICES's new field
# names (ICES is migrating to them; each column's details also carries the
# legacy on-the-wire name, stamped by op_translate_dict_names()).
#
# Sources, and how each is used:
#   * spec_01's seed (data-raw/seed/DATRAS-exchange-dict-seed.yaml): field
#     names and types from the live WSDL, descriptions from
#     getDatrasFieldList, enum code lists from icesVocab (unfiltered).
#   * The DATRAS field-description spreadsheet (latest
#     .datras/ices-schemas/datras_field_descriptions_*.xlsx snapshot):
#     Description (preferred over getDatrasFieldList's text), Mandatory
#     ("Yes" -> `constraints: [required]`), DataType (cross-checked against
#     the WSDL type; disagreements noted in details, WSDL kept), and the
#     "Example file" sheet, whose example records supply `examples:`.
#
# NO opus corrections are applied: no curated types, no vocab-key fixes, no
# sentinel policy, no archive-derived constraints. Where ICES's own sources
# disagree with each other the conflict is noted in the field's details,
# not resolved. The one non-ICES content: `examples:` for fields ICES's own
# example records do not cover (all of LT, and any HH/HL/CA field left blank
# in the example file) are drawn from the published archive itself -- the
# data-dict spec requires a representative-values key on every typed column,
# and no ICES source provides LT examples. This is disclosed in the
# top-level description below.
#
# Gaps in ICES's own documentation stay visible as gaps: a field the
# spreadsheet does not document gets a details note saying so; enum fields
# keep icesVocab's full code list even where DATRAS submissions use only a
# subset (that divergence is IMBUS's DATRAS-imbus.yaml's business, and the
# diff between the two files).
#
# Usage: Rscript data-raw/spec/spec_04_build_ices_yaml.R   (after spec_01)

library(yaml)
library(purrr)
library(dplyr)
library(readxl)
library(opus)

seed <- read_yaml("data-raw/seed/DATRAS-exchange-dict-seed.yaml")
ices <- op_translate_dict_names(seed)

# --- Field-description spreadsheet ----------------------------------------

desc_path <- sort(
  list.files(".datras/ices-schemas", pattern = "^datras_field_descriptions_.*\\.xlsx$",
             full.names = TRUE),
  decreasing = TRUE
)[1]
if (is.na(desc_path)) {
  stop("No datras_field_descriptions_*.xlsx snapshot found -- run ",
       "data-raw/audit/build_field_description_snapshot.R first.", call. = FALSE)
}
message("Using field-description spreadsheet: ", basename(desc_path))

sheet_map <- c(
  HH = "HH-Unaggregated data",
  HL = "HL-Unaggregated data",
  CA = "CA-Unaggregated data",
  LT = "LT-Unaggregated litter data"
)

spreadsheet <- bind_rows(lapply(names(sheet_map), function(tbl) {
  read_excel(desc_path, sheet = sheet_map[[tbl]]) |>
    filter(!is.na(Field), nchar(trimws(Field)) > 0) |>
    mutate(table = tbl, .before = 1) |>
    select(table, Field, Mandatory, DataType, Description)
}))

# The example records: header rows ("RecordHeader", ...) each followed by
# data rows for one table's block; no LT block exists in the sheet.
example_raw <- read_excel(desc_path, sheet = "Example file", col_names = FALSE)
example_blocks <- list()
hdr_rows <- which(example_raw[[1]] == "RecordHeader")
for (bi in seq_along(hdr_rows)) {
  h <- hdr_rows[bi]
  block_end <- if (bi < length(hdr_rows)) hdr_rows[bi + 1] - 1 else nrow(example_raw)
  block <- example_raw[(h + 1):block_end, , drop = FALSE]
  block <- block[!is.na(block[[1]]), , drop = FALSE]
  if (nrow(block) == 0) next
  tname <- block[[1]][1]
  flds <- as.character(example_raw[h, ])
  keep <- !is.na(flds)
  block <- block[, keep, drop = FALSE]
  names(block) <- flds[keep]
  example_blocks[[tname]] <- block
}
message("Example blocks found: ", paste(names(example_blocks), collapse = ", "))

# --- Merge spreadsheet + examples into the translated seed -----------------

# Spreadsheet DataType vs the dictionary's WSDL-derived type. enum columns
# are skipped: their type is an icesVocab overlay, not the WSDL type.
map_spreadsheet_type <- function(dt) {
  if (is.na(dt)) return(NA_character_)
  if (dt == "char") return("string")
  if (grepl("^int", dt) || grepl("^decimal", dt)) return("number")
  NA_character_
}

# `examples` must match the column's type (S12): numbers for number columns,
# quoted strings for string columns. Example-sheet values are all character;
# numeric conversion failures are dropped with a message.
coerce_examples <- function(values, type) {
  values <- values[!is.na(values) & nchar(trimws(values)) > 0]
  values <- unique(values)
  if (length(values) == 0) return(NULL)
  values <- head(values, 5)
  if (identical(type, "number")) {
    num <- suppressWarnings(as.numeric(values))
    if (any(is.na(num))) {
      return(NULL)  # caller falls back to the archive for this column
    }
    return(as.list(num))
  }
  as.list(values)
}

archive_examples <- function(tname, col_name, type) {
  ds <- arrow::open_dataset(file.path(".datras/to_https/raw", paste0(tname, ".parquet")))
  if (!(col_name %in% names(ds))) return(NULL)
  vals <- ds |>
    dplyr::distinct(dplyr::across(dplyr::all_of(col_name))) |>
    dplyr::collect() |>
    dplyr::pull(1)
  vals <- vals[!is.na(vals)]
  if (length(vals) == 0) return(NULL)
  vals <- utils::head(sort(unique(vals)), 5)
  if (identical(type, "number")) return(as.list(as.numeric(vals)))
  as.list(as.character(vals))
}

n_desc_from_sheet <- 0L
n_required_from_sheet <- 0L
n_type_conflicts <- 0L
n_absent_from_sheet <- 0L
n_examples_from_sheet <- 0L
n_examples_from_archive <- 0L
unmatched_sheet_fields <- character(0)

for (ti in seq_along(ices$tables)) {
  tname <- ices$tables[[ti]]$name
  ss <- spreadsheet[spreadsheet$table == tname, ]
  ex_block <- example_blocks[[tname]]

  for (ci in seq_along(ices$tables[[ti]]$columns)) {
    col <- ices$tables[[ti]]$columns[[ci]]

    row <- ss[ss$Field == col$name, ]
    if (nrow(row) == 0) {
      n_absent_from_sheet <- n_absent_from_sheet + 1L
      note <- sprintf(paste0("Not documented under this name in ICES's field-description ",
                             "spreadsheet (snapshot %s). 'Under this name': the spreadsheet ",
                             "uses ICES's new field names, which do not all agree with the ",
                             "names ICES's own field-list service documents."),
                      basename(desc_path))
      col$details <- if (is.null(col$details)) note else paste(col$details, note)
    } else {
      row <- row[1, ]
      if (!is.na(row$Description) && nchar(trimws(row$Description)) > 0) {
        col$description <- trimws(row$Description)
        n_desc_from_sheet <- n_desc_from_sheet + 1L
      }
      if (!is.na(row$Mandatory) && trimws(row$Mandatory) == "Yes") {
        existing <- if (is.null(col$constraints)) character(0) else as.character(unlist(col$constraints))
        if (!("required" %in% existing)) {
          col$constraints <- as.list(c(existing, "required"))
          n_required_from_sheet <- n_required_from_sheet + 1L
        }
      }
      ss_type <- map_spreadsheet_type(row$DataType)
      if (!is.na(ss_type) && !is.null(col$type) && col$type != "enum" && ss_type != col$type) {
        n_type_conflicts <- n_type_conflicts + 1L
        note <- sprintf(
          paste0("Spreadsheet DataType '%s' disagrees with the live WSDL type ",
                 "(served as '%s'); the WSDL type is kept -- it is what the ",
                 "service actually returns."),
          row$DataType, col$type)
        col$details <- if (is.null(col$details)) note else paste(col$details, note)
      }
    }

    # examples: only for types that need them (enum carries values instead)
    if (!is.null(col$type) && col$type != "enum" && is.null(col$examples)) {
      ex_vals <- NULL
      if (!is.null(ex_block) && col$name %in% names(ex_block)) {
        ex_vals <- coerce_examples(ex_block[[col$name]], col$type)
        if (!is.null(ex_vals)) n_examples_from_sheet <- n_examples_from_sheet + 1L
      }
      if (is.null(ex_vals)) {
        ex_vals <- archive_examples(tname, col$name, col$type)
        if (!is.null(ex_vals)) n_examples_from_archive <- n_examples_from_archive + 1L
      }
      if (!is.null(ex_vals)) col$examples <- ex_vals
    }

    ices$tables[[ti]]$columns[[ci]] <- col
  }

  unmatched <- setdiff(ss$Field, vapply(ices$tables[[ti]]$columns, function(c) c$name, character(1)))
  if (length(unmatched) > 0) unmatched_sheet_fields <- c(unmatched_sheet_fields, paste0(tname, ".", unmatched))
}

message("Spreadsheet merge: ", n_desc_from_sheet, " descriptions, ",
        n_required_from_sheet, " required constraints, ",
        n_type_conflicts, " DataType/WSDL conflicts noted, ",
        n_absent_from_sheet, " fields absent from the spreadsheet")
if (length(unmatched_sheet_fields) > 0) {
  message("Spreadsheet fields matching no dictionary column (naming-gap evidence): ",
          paste(unmatched_sheet_fields, collapse = ", "))
}
message("Examples: ", n_examples_from_sheet, " from ICES's example records, ",
        n_examples_from_archive, " from the published archive (fallback)")

# --- Top-level metadata -----------------------------------------------------

ices$`$learn_more` <- "http://data-dict.tidyverse.org/"
ices$name <- "datras_exchange_ices"
ices$label <- "ICES DATRAS Exchange Data (Tier 1) -- as documented by ICES's own sources"
ices$description <- paste(
  "Direct per-haul submissions to ICES DATRAS: HH (haul), HL (length),",
  "CA (age), LT (litter), as documented by ICES's own metadata sources:",
  "the live DATRAS WebService WSDL (field types), getDatrasFieldList",
  "(descriptions), icesVocab (code lists, unfiltered), and the DATRAS",
  "field-description spreadsheet (descriptions, Mandatory, DataType,",
  "example records). A faithful consolidation: no corrections applied;",
  "where ICES's sources disagree with each other the conflict is noted in",
  "the field's details, not resolved. The one non-ICES content: examples",
  "for fields ICES's own example records do not cover (all of LT, and any",
  "HH/HL/CA field left blank in the example file) are drawn from the",
  "published archive itself, because the data-dict format requires a",
  "representative-values key on every typed column. Keyed by ICES's new",
  "field names; each column's details carries the legacy on-the-wire name.",
  "For the archive-verified view of the same format, see",
  "inst/DATRAS-imbus.yaml."
)
ices$origin <- "data-raw/spec/spec_01_seed_dict.R -> data-raw/spec/spec_04_build_ices_yaml.R"
ices$version <- list(date = as.character(Sys.Date()))

op_write_dict_yaml(ices, "inst/DATRAS-ices.yaml")

# --- FINAL: validate against the data-dict spec ------------------------------

validation_result <- op_validate_spec("inst/DATRAS-ices.yaml")

if (!validation_result$valid) {
  cat("\n✗ YAML VALIDATION FAILED:\n\n")
  cat(paste(validation_result$output, collapse = "\n"))
  cat("\n\n")
  stop("YAML validation failed. Fix errors above before committing.", call. = FALSE)
} else {
  cat("\n✓ YAML validation passed!\n\n")
}

message(
  "Built inst/DATRAS-ices.yaml: ", sum(map_int(ices$tables, \(t) length(t$columns))),
  " columns across ", length(ices$tables), " tables.\n",
  "✓ Validated against data-dict spec."
)
