# Build a consolidated DATRAS reference artifact: Excel + DuckDB
#
# Consolidates four scattered ICES metadata sources into two output files:
#   data-raw/assets/DATRAS-reference.xlsx
#   data-raw/assets/DATRAS-reference.duckdb
#
# Both carry five sheets/tables:
#   fields          -- one row per unique legacy field name, with which tables it
#                      appears in, ICES-documented vs opus-curated type/description/mandatory
#   codes           -- one row per code per vocab_key, with scope annotation
#   corrections     -- every attribute where opus diverges from what ICES documents
#   ices_reference  -- ICES's own field description spreadsheet, as-is, keyed by
#                      ICES's own field names (which differ from on-the-wire legacy names)
#   field_values    -- full values/range detail for enum and constrained fields
#
# Sources:
#   data-raw/seed/DATRAS-exchange-dict-seed.yaml         (spec_01 output: "ICES says")
#   data-raw/seed/DATRAS-curated-legacy.yaml                    (spec_02 output: "opus says")
#   inst/DATRAS-imbus.yaml                           (spec_03 output: current names)
#   inst/DATRAS-vocab-correction.csv                     (audited vocab-key proposals)
#   .datras/ices-schemas/icesvocab_full_*.tsv            (full icesVocab snapshot)
#   .datras/ices-schemas/datras_field_descriptions_*.xlsx (ICES field description spreadsheet)
#
# NOTE on field naming: The DATRAS XML exchange format (what is actually on the wire)
# uses legacy field names (e.g. "Ship", "GearEx", "StNo"). The ICES field description
# spreadsheet uses ICES's own intended new names (e.g. "Platform", "GearExceptions",
# "StationName"). The `fields` table is keyed by legacy names (reality); the
# `ices_reference` sheet is keyed by ICES's names (aspiration). Both are included
# so the naming discrepancy is visible, not hidden.
#
# Run on demand from data-raw/audit/ -- NOT part of the spec or archive pipelines.
# Output is not shipped with the package; attach to ICES Datacenter communication.

library(dplyr)
library(tidyr)
library(purrr)
library(yaml)
library(readxl)
library(openxlsx2)
library(DBI)
library(duckdb)

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

# ── 0. Helpers ────────────────────────────────────────────────────────────────

# Parse seed or curated yaml into a flat (table × field) data frame
parse_yaml_cols <- function(path) {
  d <- yaml::read_yaml(path)
  map_dfr(d$tables, function(tbl) {
    map_dfr(tbl$columns, function(col) {
      vals_raw <- col$values
      if (is.null(vals_raw)) {
        values_codes  <- NA_character_
        values_labels <- NA_character_
      } else if (is.null(names(vals_raw))) {
        # Seed yaml: unlabelled list of code strings
        values_codes  <- paste(unlist(vals_raw), collapse = "|")
        values_labels <- NA_character_
      } else {
        # Curated yaml: named list code -> label
        values_codes  <- paste(names(vals_raw), collapse = "|")
        values_labels <- paste(unlist(vals_raw), collapse = "|")
      }
      range_raw   <- col$range %||% NULL
      range_str   <- if (!is.null(range_raw)) paste(range_raw, collapse = "–") else NA_character_
      constraints <- unlist(col$constraints) %||% character(0)
      tibble(
        table         = tbl$name,
        field         = col$name,
        type          = col$type        %||% NA_character_,
        description   = col$description %||% NA_character_,
        values_codes  = values_codes,
        values_labels = values_labels,
        range         = range_str,
        required      = "required" %in% constraints | "primary_key" %in% constraints
      )
    })
  })
}

# Read one table sheet from the ICES field description spreadsheet
read_desc_sheet <- function(path, sheet_name, tbl_name) {
  # Read without col_names to locate the "Field" header row robustly
  raw  <- readxl::read_excel(path, sheet = sheet_name, col_names = FALSE)
  col1 <- as.character(raw[[1]])
  hdr  <- which(col1 == "Field")[1]
  if (is.na(hdr)) stop("Cannot find 'Field' header in sheet: ", sheet_name)

  out <- readxl::read_excel(path, sheet = sheet_name, skip = hdr - 1,
                              col_names = TRUE, .name_repair = "unique")
  # Drop blank/auto-named columns that readxl adds for trailing empty cells
  out <- out[, !grepl("^\\.{3}|^$", names(out)), drop = FALSE]
  out <- out[, !is.na(names(out)), drop = FALSE]

  out |>
    filter(!is.na(Field), nchar(trimws(Field)) > 0) |>
    select(any_of(c("Field", "MaxWidth", "Mandatory", "DataType", "Vocab", "Description"))) |>
    mutate(
      table_ices     = tbl_name,
      mandatory_ices = !is.na(Mandatory) & tolower(trimws(Mandatory)) == "yes",
      .before        = 1
    ) |>
    rename(
      ices_field_name              = Field,
      datatype_ices                = DataType,
      description_ices_spreadsheet = Description
    ) |>
    select(-any_of("Mandatory"))
}

# Determine code scope for one field
compute_scope <- function(values_codes_opus, vocab_key_val, vocab_full) {
  if (is.na(values_codes_opus) || values_codes_opus == "") return("none")
  if (is.na(vocab_key_val)) return("standalone")
  datras_codes <- setdiff(strsplit(values_codes_opus, "\\|")[[1]], "-9")
  full_codes   <- vocab_full$code[vocab_full$vocab_key == vocab_key_val]
  if (length(full_codes) == 0) return("standalone")
  if (all(full_codes %in% datras_codes) && all(datras_codes %in% full_codes)) "full_vocab" else "datras_subset"
}

# ── 1. Load YAML sources ───────────────────────────────────────────────────────

seed    <- parse_yaml_cols("data-raw/seed/DATRAS-exchange-dict-seed.yaml")
curated <- parse_yaml_cols("data-raw/seed/DATRAS-curated-legacy.yaml")

# Build legacy→current name crosswalk positionally (spec_03 is a pure rename,
# same field order in both yamls)
legacy_yaml <- yaml::read_yaml("data-raw/seed/DATRAS-curated-legacy.yaml")
new_yaml    <- yaml::read_yaml("inst/DATRAS-imbus.yaml")

crosswalk <- map2_dfr(legacy_yaml$tables, new_yaml$tables, function(leg_tbl, new_tbl) {
  tibble(
    table        = leg_tbl$name,
    legacy_name  = map_chr(leg_tbl$columns, "name"),
    current_name = map_chr(new_tbl$columns, "name")
  )
})

# ── 2. Load vocab correction CSV ──────────────────────────────────────────────

vocab_correction <- readr::read_csv(
  "inst/DATRAS-vocab-correction.csv", show_col_types = FALSE
) |>
  select(table, field, legacy_field, proposed_vocab_key, data_fit) |>
  rename(legacy_name = legacy_field, vocab_key = proposed_vocab_key)

# ── 3. Load icesVocab snapshot ────────────────────────────────────────────────

vocab_snap_path <- list.files(
  ".datras/ices-schemas", pattern = "icesvocab_full_.*\\.tsv$", full.names = TRUE
) |> sort() |> tail(1)
cat("Using vocab snapshot:", basename(vocab_snap_path), "\n")

vocab_full <- readr::read_tsv(
  vocab_snap_path, show_col_types = FALSE, col_types = readr::cols(.default = "c")
) |>
  rename(vocab_key = type, code = key, code_label = description)

# ── 4. Load ICES field description spreadsheet ────────────────────────────────
#
# The spreadsheet uses ICES's own "new" field names (e.g. "Platform" not "Ship"),
# which are ICES's intended rename target. These often match opus's current names
# but differ from the on-the-wire legacy XML names. Included as `ices_reference`
# so the naming discrepancy is visible, not hidden.

desc_path <- list.files(
  ".datras/ices-schemas", pattern = "datras_field_descriptions_.*\\.xlsx$", full.names = TRUE
) |> sort() |> tail(1)
cat("Using field descriptions:", basename(desc_path), "\n")

sheet_map <- c(
  "HH" = "HH-Unaggregated data",
  "HL" = "HL-Unaggregated data",
  "CA" = "CA-Unaggregated data",
  "LT" = "LT-Unaggregated litter data"
)

ices_spreadsheet <- map_dfr(names(sheet_map), \(tbl)
  read_desc_sheet(desc_path, sheet_map[[tbl]], tbl)
)

# Best-effort match from spreadsheet names to legacy names via current names
spreadsheet_to_legacy <- ices_spreadsheet |>
  distinct(table_ices, ices_field_name) |>
  left_join(
    crosswalk |> distinct(table, legacy_name, current_name),
    by = c("table_ices" = "table", "ices_field_name" = "current_name")
  )

# Mandatory per legacy field (any table marks it mandatory → TRUE)
mandatory_per_field <- ices_spreadsheet |>
  left_join(spreadsheet_to_legacy, by = c("table_ices", "ices_field_name")) |>
  filter(!is.na(legacy_name)) |>
  group_by(legacy_name) |>
  summarise(mandatory_ices = any(mandatory_ices, na.rm = TRUE), .groups = "drop")

# ── 5. Build FIELDS table ─────────────────────────────────────────────────────

# One row per unique legacy field name; boolean columns for which tables it appears in
field_tables <- curated |>
  distinct(table, field) |>
  mutate(present = TRUE) |>
  pivot_wider(names_from = table, values_from = present,
              names_prefix = "in_", values_fill = FALSE)

for (col in c("in_HH", "in_HL", "in_CA", "in_LT")) {
  if (!col %in% names(field_tables)) field_tables[[col]] <- FALSE
}

# Per-field attributes: first non-NA value across tables (type/description are
# consistent across tables for shared fields -- verified 2026-08-29)
curated_per_field <- curated |>
  group_by(field) |>
  summarise(
    type_opus          = first(na.omit(type)),
    description_opus   = first(na.omit(description)),
    range_opus         = first(na.omit(range)),
    required_opus      = any(required),
    values_codes_opus  = first(na.omit(values_codes)),
    values_labels_opus = first(na.omit(values_labels)),
    .groups = "drop"
  )

seed_per_field <- seed |>
  group_by(field) |>
  summarise(
    type_ices        = first(na.omit(type)),
    description_ices = first(na.omit(description)),
    values_codes_ices = first(na.omit(values_codes)),
    .groups = "drop"
  )

# Vocab key per legacy field
vocab_per_field <- vocab_correction |>
  filter(!is.na(vocab_key)) |>
  distinct(legacy_name, vocab_key) |>
  group_by(legacy_name) |>
  slice(1) |>
  ungroup()

# Current name: prefer HH, then first available table
current_per_field <- crosswalk |>
  arrange(match(table, c("HH", "HL", "CA", "LT"))) |>
  distinct(legacy_name, current_name) |>
  group_by(legacy_name) |>
  slice(1) |>
  ungroup()

fields <- field_tables |>
  left_join(curated_per_field,   by = "field") |>
  left_join(seed_per_field,      by = "field") |>
  left_join(vocab_per_field,     by = c("field" = "legacy_name")) |>
  left_join(mandatory_per_field, by = c("field" = "legacy_name")) |>
  left_join(current_per_field,   by = c("field" = "legacy_name")) |>
  rowwise() |>
  mutate(values_scope = compute_scope(values_codes_opus, vocab_key, vocab_full)) |>
  ungroup() |>
  select(
    legacy_name    = field,
    current_name,
    in_HH, in_HL, in_CA, in_LT,
    type_ices,
    type_opus,
    mandatory_ices,
    required_opus,
    description_ices,
    description_opus,
    vocab_key,
    values_scope,
    values_codes_opus,
    values_labels_opus,
    range_opus
  ) |>
  arrange(legacy_name)

cat("fields:", nrow(fields), "\n")

# ── 6. Build CODES table ──────────────────────────────────────────────────────
#
# scope values:
#   datras_subset   -- code is in icesVocab AND observed in DATRAS archive
#   full_vocab_only -- code is in icesVocab but NOT observed in DATRAS archive
#   standalone      -- code is from archive observation only (no icesVocab match)

codes_from_vocab <- fields |>
  filter(!is.na(vocab_key), values_scope %in% c("full_vocab", "datras_subset")) |>
  select(legacy_name, vocab_key, values_codes_opus) |>
  left_join(vocab_full |> select(vocab_key, code, code_label),
            by = "vocab_key", relationship = "many-to-many") |>
  mutate(
    datras_codes   = strsplit(values_codes_opus, "\\|"),
    in_datras_spec = map2_lgl(code, datras_codes, \(c, d) c %in% d)
  ) |>
  select(legacy_name, vocab_key, code, code_label, in_datras_spec) |>
  mutate(scope = if_else(in_datras_spec, "datras_subset", "full_vocab_only"))

codes_standalone <- fields |>
  filter(values_scope == "standalone", !is.na(values_codes_opus)) |>
  select(legacy_name, vocab_key, values_codes_opus, values_labels_opus) |>
  rowwise() |>
  mutate(
    code       = list(strsplit(values_codes_opus, "\\|")[[1]]),
    code_label = list(
      if (!is.na(values_labels_opus))
        strsplit(values_labels_opus, "\\|")[[1]]
      else
        rep(NA_character_, length(strsplit(values_codes_opus, "\\|")[[1]]))
    )
  ) |>
  ungroup() |>
  unnest(c(code, code_label)) |>
  mutate(in_datras_spec = TRUE, scope = "standalone") |>
  select(legacy_name, vocab_key, code, code_label, in_datras_spec, scope)

codes <- bind_rows(codes_from_vocab, codes_standalone) |>
  arrange(legacy_name, scope, code)

cat("codes:", nrow(codes), "\n")

# ── 7. Build CORRECTIONS table ────────────────────────────────────────────────

# 7a. Type changes: seed (ICES WSDL) vs curated (opus spec_02)
type_diffs <- fields |>
  filter(!is.na(type_ices), !is.na(type_opus), type_ices != type_opus) |>
  transmute(
    legacy_name,
    attribute = "type",
    ices_says = type_ices,
    opus_says = type_opus,
    rationale = "Type curated in spec_02; see data-raw/seed/DATRAS-curated-legacy.yaml for reasoning"
  )

# 7b. Mandatory vs required mismatches
req_diffs <- fields |>
  filter(!is.na(mandatory_ices), mandatory_ices != required_opus) |>
  transmute(
    legacy_name,
    attribute = "required",
    ices_says = if_else(mandatory_ices, "Mandatory", "not mandatory"),
    opus_says = if_else(required_opus,  "required",  "not required"),
    rationale = if_else(
      mandatory_ices & !required_opus,
      "ICES marks Mandatory but published archive is null-heavy after sentinel stripping; documented as todo rather than constraint",
      "opus marks required but ICES spreadsheet does not"
    )
  )

# 7c. icesVocab list is wider than DATRAS actually uses
scope_diffs <- fields |>
  filter(values_scope == "datras_subset", !is.na(vocab_key)) |>
  left_join(
    codes |>
      group_by(legacy_name) |>
      summarise(n_total        = n(),
                n_datras_codes = sum(in_datras_spec),
                n_vocab_only   = sum(!in_datras_spec),
                .groups = "drop"),
    by = "legacy_name"
  ) |>
  transmute(
    legacy_name,
    attribute = "vocab_scope",
    ices_says = paste0("icesVocab ", vocab_key, " (", n_total, " codes)"),
    opus_says = paste0(n_datras_codes, " of ", n_total, " codes observed in DATRAS archive"),
    rationale = "Full icesVocab list is misleading for submitters; DATRAS only uses a subset"
  )

# 7d. Fields with curated values but no icesVocab key (standalone)
standalone_diffs <- fields |>
  filter(values_scope == "standalone") |>
  transmute(
    legacy_name,
    attribute = "vocab_key",
    ices_says = "icesVocab: no key documented for this field",
    opus_says = paste0("standalone values: ", values_codes_opus),
    rationale = "No icesVocab key resolves to this field; values defined from archive observation"
  )

corrections <- bind_rows(type_diffs, req_diffs, scope_diffs, standalone_diffs) |>
  arrange(legacy_name, attribute)

cat("corrections:", nrow(corrections), "\n")

# ── 8. Write Excel ────────────────────────────────────────────────────────────

out_dir   <- "data-raw/assets"
xlsx_path <- file.path(out_dir, "DATRAS-reference.xlsx")

add_sheet <- function(wb, name, df) {
  wb |>
    wb_add_worksheet(name) |>
    wb_add_data(sheet = name, x = df, na.strings = "") |>
    wb_freeze_pane(sheet = name, first_row = TRUE)
}

wb_workbook(creator = "opus (build_reference_artifact.R)") |>
  add_sheet("fields",       fields |> select(-values_codes_opus, -values_labels_opus, -range_opus)) |>
  add_sheet("codes",        codes) |>
  add_sheet("corrections",  corrections) |>
  # ICES's own spreadsheet: field names are ICES's new names, NOT the on-the-wire
  # legacy names in the 'fields' sheet. The discrepancy is intentional to surface.
  add_sheet("ices_reference", ices_spreadsheet) |>
  add_sheet("field_values", fields |>
    filter(!is.na(values_codes_opus) | !is.na(range_opus)) |>
    select(legacy_name, current_name, values_scope, values_codes_opus, values_labels_opus, range_opus)) |>
  wb_save(xlsx_path, overwrite = TRUE)

cat("Wrote:", xlsx_path, "\n")

# ── 9. Write DuckDB ───────────────────────────────────────────────────────────

duckdb_path <- file.path(out_dir, "DATRAS-reference.duckdb")
if (file.exists(duckdb_path)) file.remove(duckdb_path)

con <- dbConnect(duckdb::duckdb(), duckdb_path)

dbWriteTable(con, "fields",         fields)
dbWriteTable(con, "codes",          codes)
dbWriteTable(con, "corrections",    corrections)
dbWriteTable(con, "ices_reference", ices_spreadsheet)

# Convenience views
dbExecute(con, "
  CREATE VIEW field_codes AS
  SELECT
    f.legacy_name, f.current_name,
    f.in_HH, f.in_HL, f.in_CA, f.in_LT,
    f.type_opus, f.mandatory_ices, f.required_opus, f.values_scope,
    c.code, c.code_label, c.in_datras_spec, c.scope AS code_scope
  FROM fields f
  LEFT JOIN codes c USING (legacy_name)
")

dbExecute(con, "
  CREATE VIEW field_corrections AS
  SELECT
    f.legacy_name, f.current_name,
    f.in_HH, f.in_HL, f.in_CA, f.in_LT,
    cr.attribute, cr.ices_says, cr.opus_says, cr.rationale
  FROM fields f
  JOIN corrections cr USING (legacy_name)
")

dbExecute(con, sprintf("
  CREATE TABLE _provenance AS SELECT
    '%s' AS built_at,
    '%s' AS vocab_snapshot,
    '%s' AS field_desc_spreadsheet,
    '%s' AS seed_yaml,
    '%s' AS curated_yaml
  ",
  format(Sys.time(), "%%Y-%%m-%%dT%%H:%%M:%%S"),
  basename(vocab_snap_path),
  basename(desc_path),
  "data-raw/seed/DATRAS-exchange-dict-seed.yaml",
  "data-raw/seed/DATRAS-curated-legacy.yaml"
))

dbDisconnect(con)
cat("Wrote:", duckdb_path, "\n")

cat("\nDone. Two files in", out_dir, ":\n")
cat(" ", basename(xlsx_path), "\n")
cat(" ", basename(duckdb_path), "\n")
