# Seeds a first DRAFT of the Tier 1 (raw exchange) data-dict.yaml, using
# ONLY what is currently available live from ICES itself -- the DATRAS
# WSDL and the icesVocab web service. No local/hand-curated content, no
# domain knowledge opus or anyone else has accumulated separately: if ICES
# doesn't currently publish it, the field is left blank here, on purpose,
# so the gap is visible rather than papered over.
#
# Keyed by LEGACY (real, on-the-wire) field names throughout -- restructured
# 2026-08-09, was previously keyed by ICES's suggested new name. Two reasons:
# (1) legacy names need no inference at all, they're just what's really in
# the data, while a field's NEW name (especially LT's, see step 2 below)
# sometimes needs cross-table inference ICES's own field-list service
# doesn't provide -- resolving that here would reintroduce exactly the
# seed-time correction the seed-vs-curate split (Working principles, rule
# 11) exists to avoid. That inference now happens once, at translate time
# (data-raw/spec_03_translate_new_names.R), via op_datras_field_list() --
# not duplicated here. (2) icesVocab's own domain keys are legacy-name-shaped
# (TS_HaulVal, not TS_HaulValidity) -- keying the seed by legacy name means
# every downstream vocab lookup (this script's own `values` step 3 below,
# and the later full-field vocab audit) uses the field's real name directly,
# no legacy/new round-trip.
#
# Deliberately does NOT rely solely on `getDatrasFieldList()` (ICES's own
# field-list metadata service, whether accessed via `icesDatras` or directly
# as here) -- that service documents wrong types (e.g. CPUEL/CPUEA's `Area`,
# declared "int" there but "string" per ICES's own server and confirmed by
# real data). The actual authoritative source is each operation's own ASMX
# page, which is generated directly by the server from its real return type
# and so cannot drift the way a separately-maintained metadata service can.
#
# Data-raw helpers used here:
#   - spec_00_operation_types.R  (WSDL type/old-name crawl; ported from a
#     personal icesDatras development fork -- itself originally written for
#     obus -- not the official package, not yet independently packaged here)
#   - opus::op_vocab_* functions (icesVocab code-meaning lookup; now exported
#     via R/vocab.R in this package)
#
# This produces a SEED, not a finished dictionary. Manual curation happens
# in a later, separate stage: filling blanks, deciding type *measure*
# (number(id) vs (ordinal) vs (quantity)), adding units/constraints, and
# range/examples (every column needs one of values/range/examples per the
# data-dict.yaml spec before it ships). See AGENTS.md, "Seeding process".
#
# Deliberately does not apply any diagnostic diff report, live-pull
# cross-check, hand-curated description file, or type/name OVERRIDE at
# seed time (an earlier personal prototype -- a development fork of
# icesDatras, not the official package -- did all of this; corrected
# 2026-08-09, see AGENTS.md). Corrections happen in the curation stage,
# not here; this script only reports what ICES's own live services say,
# blanks and disagreements included. A source disagreeing with reality (or with
# another source) is exactly what DATRAS-known-issues.yaml is for, not
# something to quietly resolve while seeding. Restricted to Tier 1
# (HH/HL/CA/LT) only -- Tier 2 (FL, CPUEL, CPUEA, IDX) is a separate,
# not-yet-started step.
#
# Re-run this script whenever ICES's WSDL or field list changes; it
# overwrites the seed file, never the curated inst/*.yaml dictionaries
# directly.

library(dplyr)
library(tidyr)
library(purrr)
library(readr)
library(opus)


tier1_tables <- c("HH", "HL", "CA", "LT")
record_operations <- c(
  HH = "getHHdata",
  HL = "getHLdata",
  CA = "getCAdata",
  LT = "getLitterAssessmentOutput"
)

# WSDL type vocabulary: only string/int/decimal/float appear across all
# four operations -- enforced by map_wsdl_type()'s own stop() below, not
# just assumed. "float" is folded into the same "decimal" bucket as the
# WSDL's own "decimal" type.
wsdl_type_map <- c(string = "char", int = "int", decimal = "decimal", float = "decimal")

map_wsdl_type <- function(x) {
  unknown <- setdiff(unique(x), names(wsdl_type_map))
  if (length(unknown) > 0) {
    stop("Unmapped WSDL type(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  }
  unname(wsdl_type_map[x])
}

# 1. Crawl WSDL types + old (legacy, real) names directly from ICES's own
#    operation pages -----------------------------------------------------
message("Crawling WSDL operation pages for ", length(record_operations), " operations...")

crawled <-
  imap(record_operations, \(op, rh) {
    op_datras_operation_types(op) |>
      transmute(
        RecordHeader = rh,
        FieldNameOld = field,
        DataFormat = map_wsdl_type(type)
      )
  }) |>
  list_rbind()

# 2. Join FieldName/Description from today's getDatrasFieldList() -----------
# FieldName (ICES's own suggested NEW name) is kept here only as a
# reference/sanity-check side column -- it is NOT resolved into anything
# authoritative by this script. The anchor checks below are a cheap,
# fail-fast sanity check that ICES's basic (non-cross-table) rename
# metadata still behaves sanely, run here so a live-service regression is
# caught at seed time rather than surfacing downstream. The AUTHORITATIVE
# new-name resolution (including LT's cross-table inference, which this
# service doesn't cover) happens once, independently, in
# data-raw/spec_03_translate_new_names.R via op_datras_field_list() -- not
# by consuming this column.
#
# Still an ICES source (ICES's own field-list web service), just not the
# only one. Left blank (not self-mapped/guessed) where ICES's field list
# has no matching entry for a WSDL-crawled field -- the exception is
# FieldName, which is a structural necessity for the sanity check below,
# not an assertion that the WSDL's own name IS the field's "new" name.
#
# Was previously a direct call to `getDatrasFieldList()` via whichever
# `icesDatras` package was installed at the time. Replaced 2026-08-06 with
# opus's own direct fetch (`op_datras_field_metadata()`): the
# installed package turned out to be a personal development fork layering
# its own hand-typed patch on top of the same live endpoint (undocumented,
# not sourced from ICES -- confirmed 2026-08-09 against the official
# `ices-tools-prod/icesDatras`, which has no such patch at all -- see
# R/field_names.R's op_datras_field_list() for the traced evidence).
# Direct fetch remains the right design regardless: it doesn't depend on
# whichever icesDatras version happens to be locally installed, matching
# this seed's own stated design ("report ONLY what ICES's live services
# say, unfixed"). The raw fetch also normalizes
# ICES's own "-" placeholder (meaning "never renamed") to equal FieldName,
# fixing a latent bug below: without it, `has_distinct_new_name` was
# TRUE for every field ICES marks "-" (e.g. Survey), the opposite of
# what "-" means.
fl <-
  op_datras_field_metadata() |>
  filter(RecordHeader %in% tier1_tables) |>
  mutate(FieldNameOld = ifelse(FieldNameOld == "-", FieldName, FieldNameOld)) |>
  distinct(RecordHeader, FieldNameOld, .keep_all = TRUE) |>
  select(RecordHeader, FieldNameOld, FieldName, Description)

crawled <-
  crawled |>
  left_join(fl, by = c("RecordHeader", "FieldNameOld")) |>
  mutate(
    FieldName = coalesce(FieldName, FieldNameOld),
    Description = coalesce(Description, ""),
    has_distinct_new_name = FieldName != FieldNameOld
  )

# Self-verification, not a soft check: confirm a handful of
# independently-verified anchor mappings hold, and fail loudly (not
# silently write bad output) if they don't. LT is deliberately excluded --
# ICES's own getDatrasFieldList genuinely does not document Ship/StNo/
# HaulNo -> Platform/StationName/HaulNumber for LT specifically (only for
# HH/HL/CA), so the seed correctly leaves LT's own FieldName side column at
# its unrenamed, warts-and-all value; resolving that via cross-table
# inference is op_datras_field_list()'s job at translate time
# (data-raw/spec_03_translate_new_names.R), not this seed's (see AGENTS.md's
# seed-vs-curate split -- asserting the fix here would violate the seed's
# own "report ICES's sources literally, unfixed" design).
anchors <- list(
  c("HH", "Ship", "Platform"), c("HH", "StNo", "StationName"), c("HH", "HaulNo", "HaulNumber")
)
for (a in anchors) {
  got <- crawled$FieldName[crawled$RecordHeader == a[1] & crawled$FieldNameOld == a[2]]
  if (length(got) != 1 || got != a[3]) {
    stop("Anchor check failed: ", a[1], "/", a[2], " resolved to '",
         paste(got, collapse=","), "', expected '", a[3], "'. ",
         "This run's data is untrustworthy -- re-run rather than proceed.",
         call. = FALSE)
  }
}
message("Anchor checks passed: ", length(anchors), "/", length(anchors))

# NOTE: no correction/override step here, deliberately. An earlier personal
# prototype (a development fork of icesDatras, not the official package)
# applied a documented override at this point (HL/CA's Valid_Aphia: WSDL
# says "char", but it's a WoRMS AphiaID and real data is always numeric) --
# that's a curation decision, not a seeding one, and not something ICES's
# own web services currently assert either way. This script reports the
# WSDL's own answer as-is, char and all.
# TODO (curation stage): Valid_Aphia (HL, CA) -- WSDL crawl reports "char";
# real archive data confirms it's always numeric (independently verified
# against the live service, not just inherited from that old prototype).
# Candidate DATRAS-known-issues.yaml entry once that stage starts.

# 3. icesVocab code meanings -> data-dict.yaml's `values` -------------------
# icesVocab (vocab.ices.dk) is itself an ICES web service, independent of
# DATRAS's own WSDL -- in scope for this "web-only" seed. data-dict.yaml has
# a native, structured place for a code/label list: `values` as a map, e.g.
# `{D: Day, N: Night}` (see ~/garbage/data-dict/site/spec.md,
# "Representative values") -- used here in preference to embedding the same
# information as prose in `description`. Built directly from icesVocab's
# own structured code/description pairs, not by parsing text back out of
# anything. Description itself is left untouched (ICES's/getDatrasFieldList's
# text, blank where step 2 found none). Resolved by legacy name
# (FieldNameOld), matching icesVocab's own legacy-name-shaped domain keys.
VOCAB_CODE_LIMIT <- 20  # fields with more codes than this get no `values` (e.g.
                        # Survey, StatRec -- hundreds of codes, not a usable enum)
vocab_types <- op_vocab_get_types()

get_values_map <- function(field_name_old) {
  vocab <- op_vocab_first_usable(field_name_old, vocab_types)
  if (is.na(vocab$key) || nrow(vocab$codes) == 0 || nrow(vocab$codes) > VOCAB_CODE_LIMIT) {
    return(NULL)
  }
  # Return codes as array (string vector) for data-dict v0.0.1 compatibility.
  # Labels are moved to description/details during curation.
  as.character(vocab$codes$Key)
}

message("Looking up icesVocab code meanings for `values`...")
crawled <- crawled |>
  mutate(values = map(FieldNameOld, get_values_map))

# --- Transform into a data-dict.yaml draft ----------------------------------
# NOTE: tables are ordered HH, HL, CA, LT (opus's deliberate tier ordering --
# see AGENTS.md), via the factor level order below. Fields *within* each
# table are deliberately not arranged/sorted -- kept exactly as the WSDL
# crawl (data-raw/spec_00_operation_types.R) returns them, not alphabetized.

map_type <- function(data_format) {
  case_when(
    data_format %in% c("int", "decimal") ~ "number",
    data_format == "char" ~ "string",
    TRUE ~ NA_character_
  )
}

seed <-
  crawled |>
  transmute(
    RecordHeader = factor(RecordHeader, levels = tier1_tables),
    name = FieldNameOld,
    # `enum` whenever icesVocab resolved a `values` map for this field;
    # otherwise the coarse WSDL-derived type. Per the spec, `values` is only
    # meaningful paired with `type: enum`.
    type = if_else(map_lgl(values, negate(is.null)), "enum", map_type(DataFormat)),
    description = Description,
    values = values,
    # Not shipped in inst/*.yaml (data-dict.yaml has no alias concept -- see
    # AGENTS.md); kept here only as a reference/sanity-check side column
    # (see step 2's comment above) -- the authoritative new-name resolution
    # happens independently in data-raw/spec_03_translate_new_names.R.
    field_name_new = FieldName
  )

dir.create("data-raw/seed", showWarnings = FALSE)

# One data-dict.yaml `tables` entry per RecordHeader, sketch only (`range`/
# `examples` not filled in yet -- added by hand during curation; `values` is
# included where icesVocab resolved one). `.by` (rather than a grouped
# nest()) preserves each table's fields in their original (unsorted) order;
# the subsequent `arrange()` only reorders the *tables* themselves, to
# HH/HL/CA/LT, and does not touch field order within a table. `compact()`
# drops `values` from a column's list when NULL, rather than writing a
# `values: ~` no one wants.
tables <-
  seed |>
  select(RecordHeader, name, type, description, values) |>
  nest(.by = RecordHeader, columns = c(name, type, description, values)) |>
  arrange(RecordHeader) |>
  mutate(
    columns = map(columns, \(df) pmap(df, \(name, type, description, values) {
      # An empty description (nothing available from ICES/getDatrasFieldList)
      # is written by OMITTING the key, not as `description: ''` -- the
      # spec's `description` is plain `string`, not nullable, and this
      # crate's YAML layer collapses an empty string to null, which is a
      # type error that halts validation before it reaches anything else.
      # Omitting the key still fully exposes "nothing available here" (an
      # absent key, same as an unstarted column) -- it's a fix to how
      # absence is represented, not a fix to what's missing.
      compact(list(
        name = name,
        type = type,
        description = if (nzchar(description)) description else NULL,
        values = values
      ))
    }))
  ) |>
  transmute(name = as.character(RecordHeader), columns) |>
  pmap(list)

draft <- list(
  `$version` = "0.1.0",
  name = "datras_exchange",
  label = "ICES DATRAS Exchange Data (Tier 1 -- raw haul-grain submissions)",
  description = paste(
    "Direct per-haul submissions to ICES DATRAS: HH (haul), HL (length),",
    "CA (age), LT (litter). SEED ONLY, from ICES's own live WSDL +",
    "getDatrasFieldList() + icesVocab -- no local/curated content; blank",
    "where ICES currently publishes nothing. Not yet curated -- see AGENTS.md.",
    "Keyed by ICES's own legacy (real, on-the-wire) field names -- see",
    "data-raw/spec_03_translate_new_names.R for the curated/new-named version."
  ),
  tables = tables
)

yaml::write_yaml(draft, "data-raw/seed/DATRAS-exchange-dict-seed.yaml")

seed |>
  select(RecordHeader, name, field_name_new) |>
  write_csv("data-raw/seed/DATRAS-exchange-name-history-seed.csv")

message(
  "Seeded ", nrow(seed), " fields across ", length(tier1_tables), " tables to ",
  "data-raw/seed/. Not curated -- do not copy directly into inst/."
)
