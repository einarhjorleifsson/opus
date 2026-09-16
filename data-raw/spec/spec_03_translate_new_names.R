# Translates the curated legacy-named dictionary
# (data-raw/seed/DATRAS-curated-legacy.yaml) into opus's current names,
# producing inst/DATRAS-imbus.yaml -- the archive-side, empirically grounded
# dictionary opus ships. The ONLY step in the spec pipeline that introduces
# new names at all; a pure rename via opus::op_translate_dict_names()
# (R/field_names.R): every type/units/range/examples/details/constraints/
# label value carries over unchanged, relationships/definitions/assert
# expressions are rewritten to the new names, and each column's details is
# stamped with its legacy field name, so the shipped file is self-contained
# for both naming schemes (op_field_spec()/op_legacy_field_name() read the
# stamp back).
#
# The rename machinery moved from this script into R/ 2026-09-15
# (op_translate_dict_names()), when the pipeline started producing two
# shipped dictionaries from the same translation: this one (curated ->
# DATRAS-imbus.yaml) and spec_04's (seed + spreadsheet -> DATRAS-ices.yaml).
# Working Principle 7b: the logic lives in R/ once, scripts orchestrate.
#
# Usage: Rscript data-raw/spec/spec_03_translate_new_names.R

library(yaml)
library(purrr)
library(opus)

curated <- op_translate_dict_names(read_yaml("data-raw/seed/DATRAS-curated-legacy.yaml"))

# Top-level metadata: describe what this file is and where it came from.
curated$description <- paste(
  "Direct per-haul submissions to ICES DATRAS: HH (haul), HL (length),",
  "CA (age), LT (litter), as they actually exist in the published archive.",
  "The IMBUS/archive-side dictionary: curated from ICES's own sources and",
  "verified against real submissions (enum values restricted to",
  "archive-observed codes; physical non-negativity bounds expressed as",
  "assertions). Keyed by opus's current field names; each column's details",
  "carries the legacy on-the-wire name. See",
  "data-raw/spec/spec_02_curate_dict.R for the corrections and field-spec",
  "fills applied and why. For ICES's own documented view of the same",
  "format, see inst/DATRAS-ices.yaml."
)
curated$origin <- paste(
  "data-raw/spec/spec_01_seed_dict.R -> data-raw/spec/spec_02_curate_dict.R",
  "-> data-raw/spec/spec_03_translate_new_names.R"
)
curated$version <- list(date = as.character(Sys.Date()))

op_write_dict_yaml(curated, "inst/DATRAS-imbus.yaml")

# ---- FINAL: validate against the data-dict spec ---------------------------

validation_result <- op_validate_spec("inst/DATRAS-imbus.yaml")

if (!validation_result$valid) {
  cat("\n✗ YAML VALIDATION FAILED:\n\n")
  cat(paste(validation_result$output, collapse = "\n"))
  cat("\n\n")
  stop("YAML validation failed. Fix errors above before committing.", call. = FALSE)
} else {
  cat("\n✓ YAML validation passed!\n\n")
}

message(
  "Translated ", sum(map_int(curated$tables, \(t) length(t$columns))),
  " columns across ", length(curated$tables), " tables from legacy to ",
  "curated names. Wrote inst/DATRAS-imbus.yaml.\n",
  "✓ Validated against data-dict spec."
)
