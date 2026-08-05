# Curates the Tier 1 (raw exchange) data-dict.yaml from the seed, applying
# known domain-knowledge corrections. Deliberately diffable against the
# seed, so the two together show the whole workflow at a glance:
#
#   diff data-raw/seed/DATRAS-exchange-dict-seed.yaml inst/DATRAS-data-dict.yaml
#
# This is a separate script from DATASET_seed_dict.R on purpose (AGENTS.md's
# Working principles, rule 11 / seed-vs-curate split): the seed reports
# ICES's sources literally, unfixed; corrections happen only here, and each
# one is written down explicitly below, not silently applied while seeding.
#
# Each correction is a stand-in for a future DATRAS-known-issues.yaml row --
# that registry doesn't exist yet (filing/tracking issues formally is a
# later step, see AGENTS.md). The `issue_id`s used here are kept consistent
# with the illustrative examples already used in AGENTS.md, so they resolve
# cleanly once the registry exists instead of needing renaming.

library(yaml)
library(purrr)

seed <- read_yaml("data-raw/seed/DATRAS-exchange-dict-seed.yaml")

# Shared by corrections/field_specs/shared_field_specs below: looks up one
# table's column by name and applies whichever of type/units/range/
# examples/constraints/details are supplied. `details` APPENDS to any
# existing details rather than overwriting -- needed so a correction's
# issue_id pointer (set first) survives a later field_specs/shared_field_specs
# pass adding its own, separate details to the same column (e.g. LT's
# DateofCalculation: corrections notes the type-mismatch issue, field_specs
# separately notes the open-ended-range rationale -- both need to survive on
# the same column, not have the second overwrite the first).
apply_col_update <- function(dict, table, field, updates) {
  ti <- which(map_chr(dict$tables, "name") == table)
  ci <- which(map_chr(dict$tables[[ti]]$columns, "name") == field)
  col <- dict$tables[[ti]]$columns[[ci]]
  if (!is.null(updates$type))        col$type <- updates$type
  if (!is.null(updates$label))       col$label <- updates$label
  if (!is.null(updates$units))       col$units <- updates$units
  if (!is.null(updates$range))       col$range <- updates$range
  if (!is.null(updates$examples))    col$examples <- updates$examples
  # Special case: updates$values can be NULL to explicitly REMOVE the values field
  if ("values" %in% names(updates)) {
    if (is.null(updates$values)) col$values <- NULL else col$values <- updates$values
  }
  if (!is.null(updates$constraints)) col$constraints <- updates$constraints
  if (!is.null(updates$details)) {
    col$details <- if (is.null(col$details)) updates$details else paste(col$details, updates$details)
  }
  dict$tables[[ti]]$columns[[ci]] <- col
  dict
}

apply_table_update <- function(dict, table, updates) {
  ti <- which(map_chr(dict$tables, "name") == table)
  if (length(ti) == 0) stop("Table '", table, "' not found")
  tbl <- dict$tables[[ti]]
  if (!is.null(updates$label))       tbl$label <- updates$label
  if (!is.null(updates$description)) tbl$description <- updates$description
  if (!is.null(updates$details))     tbl$details <- updates$details
  if (!is.null(updates$origin))      tbl$origin <- updates$origin
  if (!is.null(updates$constraints)) tbl$constraints <- updates$constraints
  dict$tables[[ti]] <- tbl
  dict
}

# One row per correction. Add to this list as curation finds more; nothing
# here is inferred or guessed -- each entry traces to a specific, verified
# disagreement between what ICES's WSDL declares and what the field
# actually is/contains (see `mechanism`).
corrections <- list(
  list(
    table = "HL", field = "Valid_Aphia", type = "number(id)",
    issue_id = "valid_aphia_type_mismatch",
    mechanism = paste(
      "ICES's WSDL declares this field character, but the live service",
      "always returns it numeric -- it's a WoRMS AphiaID (an identifier,",
      "hence number(id), not a quantity)."
    )
  ),
  list(
    table = "CA", field = "Valid_Aphia", type = "number(id)",
    issue_id = "valid_aphia_type_mismatch",
    mechanism = paste(
      "ICES's WSDL declares this field character, but the live service",
      "always returns it numeric -- it's a WoRMS AphiaID (an identifier,",
      "hence number(id), not a quantity)."
    )
  ),
  list(
    table = "LT", field = "DateofCalculation", type = "number(ordinal)",
    issue_id = "dateofcalculation_type_mismatch",
    mechanism = paste(
      "ICES's WSDL declares this field character for LT's own retrieval",
      "operation (getLitterAssessmentOutput), while HH/HL/CA's own",
      "operations all declare it int/decimal -- but real LT data (verified",
      "2026-07-29) is the identical 8-digit YYYYMMDD stamp (e.g.",
      "\"20260625\"), just returned as a string by that one operation.",
      "Digit order (month before day) confirmed consistent with HH/HL/CA."
    )
  ),
  list(
    table = "HH", field = "SwellHeight", type = "number(quantity)",
    units = "m",
    range = list(0.0, 3.0),
    values = NULL,
    issue_id = "swell_height_type_mismatch",
    mechanism = paste(
      "icesVocab declares this an enum (codes H/L/M/N/NR/VH for height classes).",
      "Real HH archive data (verified 2026-07-30) contains continuous numeric values",
      "(0.0-2.0+ metres), not categorical codes. Archive and ICES specification",
      "disagree on whether this is a measured quantity or a categorized class.",
      "Candidate for DATRAS-known-issues.yaml formal escalation to imbus/ICES."
    )
  )
)

apply_correction <- function(dict, correction) {
  apply_col_update(dict, correction$table, correction$field, list(
    type = correction$type,
    units = correction$units,
    range = correction$range,
    values = correction$values,
    details = paste0(
      "See known issue ", correction$issue_id,
      " (DATRAS-known-issues.yaml, not yet filed): ", correction$mechanism
    )
  ))
}

curated <- reduce(corrections, apply_correction, .init = seed)

# --- Enrich with legacy field names from icesDatras (critical for icesVocab lookups) ---
#
# icesVocab code lookups are DEPENDENT on field names, and those names are
# both old (legacy ICES names) and new (current names). Many fields have
# vocabularies ONLY under the old name (e.g., Sex has TS_Sex, but no
# TS_IndividualSex), so we must document the mapping for downstream code
# and validation tools.
#
# Format: Add "Legacy field name: {OldName}" prefix to details field.
# This approach is:
#   - Fully data-dict spec-compliant (details is free-text)
#   - Machine-readable via regex: /Legacy field name: (\w+)/
#   - Human-readable and easy to scan
#   - Survives YAML round-trips
#
# See vignettes/articles/technical-notes.md for design rationale and
# the icesVocab dependency discovery.
#
add_legacy_field_names <- function(dict) {
  # Get old->new name mapping from icesDatras (the authoritative source)
  fl <- icesDatras::getDatrasFieldList()

  # Build lookup: table::new_name -> old_name
  legacy_names <- list()
  for (i in seq_len(nrow(fl))) {
    old <- fl$FieldNameOld[i]
    new <- fl$FieldName[i]
    rec <- fl$RecordHeader[i]

    if (old != new) {
      key <- paste(rec, new, sep = "::")
      legacy_names[[key]] <- old
    }
  }

  # Apply legacy names to curated dict
  for (table_idx in seq_along(dict$tables)) {
    table <- dict$tables[[table_idx]]
    for (col_idx in seq_along(table$columns)) {
      col <- table$columns[[col_idx]]
      key <- paste(table$name, col$name, sep = "::")

      if (key %in% names(legacy_names)) {
        old_name <- legacy_names[[key]]
        legacy_note <- sprintf("Legacy field name: %s (see icesDatras::getDatrasFieldList()).", old_name)

        # Append to existing details, or create new (separated by two newlines for clarity)
        if (is.null(col$details) || is.na(col$details)) {
          col$details <- legacy_note
        } else {
          # Append with double newline to separate legacy note from existing details
          col$details <- paste(col$details, legacy_note, sep = "\n\n")
        }

        dict$tables[[table_idx]]$columns[[col_idx]] <- col
      }
    }
  }

  dict
}

curated <- add_legacy_field_names(curated)

# Fills type MEASURE (id/ordinal/quantity -- the seed deliberately leaves
# these bare, see DATASET_seed_dict.R's own header), `units` (quantity
# columns only, per spec), `range`/`examples`, and `constraints` where
# directly verified. Kept as its own step, distinct from `corrections`
# above: these are gap-fills the seed always intended for hand curation, not
# fixes for something ICES's WSDL got wrong, so none of them carry an
# issue_id.
#
# `range` on a quantity/ordinal column is the VALID domain, not a literal
# transcript of whatever obus's archive happens to contain -- data-dict.yaml's
# `range` exists so a validator can catch a real dataset violating the spec,
# so a known-implausible archive value (e.g. a negative HaulDuration, a
# 999-degree TowDirection) must not silently widen it. Every exclusion is
# named in that column's `details`, never just dropped silently.
#
# Empirically grounded via data-raw/tier1_field_stats.R against obus's
# staged exchange archive (data-raw/to_https/xml/{HH,HL,CA,LT} there) --
# see that script's own header for a caveat that applies to every range
# below: obus fetched via icesDatras with fix_types = TRUE, whose
# parseDatras()/applyDatrasTypeSchema() (R/utilities.R) scrub literal -9 to
# NA for every numeric column regardless of whether -9 is that field's own
# documented sentinel, upstream of any obus/opus choice and not fixable by
# re-fetching.
#
# This is a first curation pass from data patterns alone, not a
# domain-expert review -- a handful of borderline calls (e.g. LengthClass's
# plausible max fish/elasmobranch length) are left wide rather than
# tightened without that input; flagged inline in the affected fields' own
# `details`, not resolved by guessing.
#
# HH verified 2026-07-29 against the full archive (150,262 hauls,
# 1965-2026). HL (14,400,747 length records) and CA (5,966,950 age records)
# same date. LT (79,451 litter records) same date, completing Tier 1's bare
# `number` fields -- except DateofCalculation, settled for all four tables
# earlier (see shared_field_specs's own note on why it ISN'T in that list
# despite recurring everywhere).
#
# GOTCHAS (yaml::as.yaml()):
#   - An 8+-digit R double renders in scientific notation regardless of
#     options(scipen=) -- an integer literal (20120419L, not 20120419)
#     avoids it.
#   - Inf renders cleanly as `.inf` (confirmed 2026-07-29), matching the
#     spec's open-bound syntax for an unknown/moving upper extent -- but
#     mixing an integer literal with Inf needs list(...), not c(): c(20120419L,
#     Inf) would silently coerce the integer to a double first, reintroducing
#     the scientific-notation gotcha above.
field_specs <- list(
  # ---- RecordHeader: HH, HL, CA (confirmed absent from LT's own exchange
  # columns -- not seeded there at all, checked 2026-07-29) ------------------
  # NOT a shared_field_specs entry despite recurring across three tables:
  # unlike SweepLength/HaulNumber/Year (rule 12's main case -- one haul's own
  # fact reproduced verbatim), RecordHeader's valid value differs BY TABLE --
  # it's the record-type tag itself (which exchange file this row came from),
  # not a haul-level measurement, so "shared" would be wrong here (found
  # 2026-07-29). Verified against the full archive: 100% constant per table
  # (HH: 150,262/150,262 rows = "HH"; HL: 14,400,747/14,400,747 = "HL"; CA:
  # 5,966,950/5,966,950 = "CA"), matching the seed's own RecordHeader
  # description ("HH=Haul Information", "HL=Length Frequency Distribution",
  # "CA=individual fish recordings with biological information") exactly --
  # retyped enum accordingly, one single-key values map per table. The
  # description itself is left as-is (still useful general context covering
  # all four record types), `values` adds this table's own specific code.
  list(table = "HH", field = "RecordHeader", type = "enum",
       values = list(HH = "Haul Information")),
  list(table = "HL", field = "RecordHeader", type = "enum",
       values = list(HL = "Length Frequency Distribution")),
  list(table = "CA", field = "RecordHeader", type = "enum",
       values = list(CA = "individual fish recordings with biological information")),

  # ---- HH-only fields (no LT/HL/CA counterpart) ---------------------------
  list(table = "HH", field = "DepthStratum",
       examples = list("D2", "10", "9", "11", "D1"),
       details = "Field's own description says depth strata are survey-specific, not an ICES-wide vocabulary -- examples illustrate the shape seen in practice (mix of letter-prefixed and bare-number codes), not an exhaustive domain. Verified 2026-07-29 against the full HH archive: 194 distinct values, only 75,753 of 150,262 rows populated (roughly half of surveys don't report it)."),
  list(table = "HH", field = "HydrographicStationID",
       examples = list("74SC0000", "88888888", "1", "0", "3"),
       details = "National station numbering (field's own description), so examples are illustrative only, not an exhaustive domain -- 18,373 distinct values, only 79,371 of 150,262 rows populated. '88888888' recurs 1,635 times and reads like an undocumented all-8s placeholder/sentinel (the same kind of pattern seen elsewhere in HH, e.g. HaulDuration's zeros) rather than a real station ID, but is kept in `examples` (unlike a `range` exclusion, `examples` isn't a validity gate) since a reader should know it's a real recurring value. Verified 2026-07-29 against the full archive."),
  list(table = "HH", field = "Buoyancy", type = "number(quantity)", units = "kg", range = c(0, 398)),
  list(table = "HH", field = "KiteArea", type = "number(quantity)", units = "m2", range = c(0, 1),
       details = "Coarse, equipment-spec values (0, 0.5, 0.7, 0.72, 0.8, 1) rather than a continuously measured quantity -- only 6 distinct values across 30,116 rows."),
  list(table = "HH", field = "GroundRopeWeight", type = "number(quantity)", units = "kg", range = c(0, 2212)),
  list(table = "HH", field = "SurfaceCurrentDirection", type = "number(quantity)", units = "degrees", range = c(0, 360),
       details = "Two single-occurrence values just above 360 (392, 390) excluded; the rest of the archive is densely populated right up to 360."),
  list(table = "HH", field = "SurfaceCurrentSpeed", type = "number(quantity)", units = "m/s", range = c(0, 9.3),
       details = "99 (marker) and 46.3 and 16 (each a single, isolated occurrence with no support nearby) excluded; a smoother, better-populated tail resumes at 9.3 (3 rows) and below."),
  list(table = "HH", field = "BottomCurrentDirection", type = "number(quantity)", units = "degrees", range = c(0, 359)),
  list(table = "HH", field = "BottomCurrentSpeed", type = "number(quantity)", units = "m/s", range = c(0, 9.9),
       details = "9.9 (1 row) is unusually high for a bottom current and resembles the '9-family' marker pattern seen elsewhere in HH, but a genuinely fast tidal-race reading can't be ruled out -- kept in range rather than excluded, unlike the more clear-cut cases above."),
  list(table = "HH", field = "SurfaceTemperature", type = "number(quantity)", units = "degC", range = c(-1.5, 36)),
  list(table = "HH", field = "BottomTemperature", type = "number(quantity)", units = "degC", range = c(-1, 35.4)),
  list(table = "HH", field = "SurfaceSalinity", type = "number(quantity)", units = "PSU", range = c(0, 38.52)),
  list(table = "HH", field = "BottomSalinity", type = "number(quantity)", units = "PSU", range = c(3.13, 39.93)),
  list(table = "HH", field = "ThermoClineDepth", type = "number(quantity)", units = "m", range = c(0, 90)),
  list(table = "HH", field = "SecchiDepth", type = "number(quantity)", units = "m", range = c(0, 9)),
  list(table = "HH", field = "Turbidity", type = "number(quantity)", units = "NTU", range = c(0, 0),
       details = "Only 202 of 150,262 hauls carry a value at all, and every one of them is exactly 0 -- too sparse to characterize a real range; this reflects what was actually observed, not a claim that Turbidity never varies."),
  list(table = "HH", field = "TidePhase", type = "number(quantity)", units = "min", range = c(-540, 780),
       details = "Strong clustering at exact-hour multiples (e.g. 660 min: 1095 rows, 600 min: 1093, 540 min: 949) versus sparse off-hour values reads as providers rounding to the nearest hour, not an error. Separately: a genuine reading of exactly -9 minutes (9 minutes before high tide) would be indistinguishable from missing, since icesDatras's fetch pipeline scrubs literal -9 to NA for every numeric column regardless of whether -9 is that field's own sentinel -- see data-raw/tier1_field_stats.R's header."),
  list(table = "HH", field = "TideSpeed", type = "number(quantity)", units = "m/s", range = c(0, 7)),
  list(table = "HH", field = "MinTrawlDepth", type = "number(quantity)", units = "m", range = c(0, 699),
       details = "Unit is inferred, not stated in ICES's own field description ('Highest point of the pelagic trawling') -- assumed metres by convention with the rest of HH's depth fields."),
  list(table = "HH", field = "MaxTrawlDepth", type = "number(quantity)", units = "m", range = c(0, 712),
       details = "Same inferred-unit caveat as MinTrawlDepth above."),

  # ---- DateofCalculation, all four tables --------------------------------
  # Recurs everywhere but does NOT go in shared_field_specs below: its own
  # minimum can genuinely differ per table (found 2026-07-29: LT's own is
  # 2015-11-27, years after HH/HL/CA's shared 2012-04-19 -- LT/litter
  # reporting began later than the main survey program). Wording is shared
  # (same YYYYMMDD/open-bound/ICES-Datacenter facts), but each table keeps
  # its own verified minimum. Upper bound left open (.inf) on every table:
  # this is a live, continuously-advancing "last recalculated" stamp (the
  # ICES Datacenter reprocesses records on an ongoing basis; not something
  # data providers submit), so any fixed max would go stale immediately.
  list(table = "HH", field = "DateofCalculation", type = "number(ordinal)", range = list(20120419L, Inf),
       details = "8-digit YYYYMMDD stamp, digit order (month before day) verified consistent across all four Tier 1 tables. Upper bound deliberately left open: a live, continuously-advancing ICES Datacenter 'last recalculated' stamp, not submitted by data providers, so a fixed max would go stale immediately. Lower bound is this table's own verified minimum -- NOT forced identical across tables the way SweepLength/HaulNumber/Year are, since a genuine table-specific difference is plausible here (confirmed: LT's own minimum is years later)."),
  list(table = "HL", field = "DateofCalculation", type = "number(ordinal)", range = list(20120419L, Inf),
       details = "8-digit YYYYMMDD stamp, digit order (month before day) verified consistent across all four Tier 1 tables. Upper bound deliberately left open: a live, continuously-advancing ICES Datacenter 'last recalculated' stamp, not submitted by data providers, so a fixed max would go stale immediately. Lower bound is this table's own verified minimum -- NOT forced identical across tables the way SweepLength/HaulNumber/Year are, since a genuine table-specific difference is plausible here (confirmed: LT's own minimum is years later)."),
  list(table = "CA", field = "DateofCalculation", type = "number(ordinal)", range = list(20120419L, Inf),
       details = "8-digit YYYYMMDD stamp, digit order (month before day) verified consistent across all four Tier 1 tables. Upper bound deliberately left open: a live, continuously-advancing ICES Datacenter 'last recalculated' stamp, not submitted by data providers, so a fixed max would go stale immediately. Lower bound is this table's own verified minimum -- NOT forced identical across tables the way SweepLength/HaulNumber/Year are, since a genuine table-specific difference is plausible here (confirmed: LT's own minimum is years later)."),
  list(table = "LT", field = "DateofCalculation", type = "number(ordinal)", range = list(20151127L, Inf),
       details = "Same open-upper-bound, ICES-Datacenter-inserted basis as HH/HL/CA's DateofCalculation, but this table's OWN verified minimum (2015-11-27) is genuinely years later than theirs (2012-04-19) -- consistent with LT/litter reporting being a newer addition to DATRAS than the main haul/length/age exchange."),

  # ---- HL (remaining fields) ----------------------------------------------
  list(table = "HL", field = "SpeciesCode", type = "number(id)",
       examples = c(55L, 122388L, 127196L, 159048L, 1789435L),
       constraints = list("required"),
       details = "Official WoRMS AphiaID as submitted by the data provider -- contrast with Valid_Aphia, the ICES Datacenter's own validated/corrected version of the same concept, inserted server-side (see Valid_Aphia's own details below)."),
  list(table = "HL", field = "SpeciesCategory", type = "number(id)",
       examples = c(1L, 4L, 12L, 21L, 31L),
       details = "Real values are {1-5, 11-14, 21-23, 31} -- a coded scheme (verified 2026-07-29 against the full archive), not a sequence, despite 'category' sounding ordinal."),
  list(table = "HL", field = "TotalNumber", type = "number(quantity)", range = c(0, 3581592),
       details = "Per the field's own description, TotalNo=SUM(HLNoAtLngt); values in the hundreds of thousands and non-integer values (7.7% of populated rows) both trace to the same documented mechanism -- DataType C records are standardised to 60 minutes, which can inflate very abundant small-bodied catches to large, non-integer counts. Top values all have real support (9-30 occurrences each, a smooth tail), not isolated errors."),
  list(table = "HL", field = "SubsampledNumber", type = "number(quantity)", range = c(0, 578731),
       details = "Same DataType C standardisation basis as TotalNumber above; top values are all well-supported (4-10 occurrences each), not isolated errors."),
  list(table = "HL", field = "SubsamplingFactor", type = "number(quantity)", range = c(1, 10997.1834),
       details = "356 of 14,256,091 rows (0.0025%) show values below 1, contradicting the field's own description (documented as always >=1, for every DataType) -- excluded. The high end is genuine, not an error: top values cluster at power-of-2-like numbers (4096 recurs 133 times; 8192, 5120, 6144 also recur with real support), consistent with repeatedly halving a very abundant catch to reach a manageable subsample."),
  list(table = "HL", field = "SubsampleWeight", type = "number(quantity)", units = "g", range = c(0, 3519200)),
  list(table = "HL", field = "SpeciesCategoryWeight", type = "number(quantity)", units = "g", range = c(0, 35568000),
       details = "-900 (2562 rows) and -100 (1 row) are excluded as a 'not weighed' placeholder, the same pattern seen in several HH fields. The high end is genuine: top values all have real support (3-18 occurrences each)."),
  list(table = "HL", field = "LengthClass", type = "number(quantity)", range = c(0, 4500),
       details = "Unit varies by the sibling LengthCode field (mm or cm; see LengthCode's own values map), so no fixed units here. Two isolated outliers excluded, 2026-07-29: 11930 (LengthCode '.', i.e. 11.93m) and 900 (LengthCode '1', i.e. 9m) -- each a lone occurrence far above the next-highest real value. Everything else, including a cluster around 420-460 under LengthCode '1' (4.2-4.6m -- large but not implausible for occasional large elasmobranch/tuna bycatch), is kept as-is: this is a first curation pass from data patterns alone, not a domain-expert review, and a tighter bound wasn't asserted without one. CA's own LengthClass is curated separately (a different sampling population, not assumed identical -- see CA's own pass)."),
  list(table = "HL", field = "NumberAtLength", type = "number(quantity)", range = c(0, 940339.35),
       details = "Same DataType C standardisation basis as TotalNumber above. Top values are each a unique one-off but decline smoothly with no marker/gap pattern, consistent with genuine (if rare) very large hauls of abundant small-bodied species. CA's own NumberAtLength is curated separately (a different sampling population -- aged individuals only, not the whole catch -- so not assumed identical)."),
  list(table = "HL", field = "Valid_Aphia",
       examples = c(55L, 117258L, 126757L, 140474L, 1895010L)),

  # ---- CA (remaining fields) -----------------------------------------------
  # `examples` fill for CA's own remaining S07 findings, 2026-07-29 (TODO.md's
  # "remaining ~18" item) -- same real-archive-verified approach as the
  # string-field pass above. GeneticSamplingFlag/StomachSamplingFlag/
  # ParasiteSamplingFlag are retyped enum: each is a 100%-clean two-value
  # split (Y/N, zero exceptions across 800k+ non-null rows) AND the seed's
  # own description ("Flag whether X was taken/performed") independently
  # confirms boolean intent -- same evidentiary bar as RecordHeader. `values`
  # is the ARRAY form (`["Y", "N"]`), not a labelled map (`{Y: Yes, N: No}`):
  # the map form hits tidyverse/data-dict#144 too, just via a different
  # trigger than ThermoCline's -- confirmed 2026-07-29 by testing both forms
  # directly against the CLI. quarto-yaml discards quote style the same way
  # for boolean-looking words as for numeric-looking ones, so a quoted 'N'
  # gets re-read as YAML 1.1's boolean false, not the string "N"; the array
  # form sidesteps it exactly like #144's own writeup predicted for the
  # array/map asymmetry. The rest
  # stay `string` + `examples` even where the observed set looks small
  # (AreaType: 17 values; IndividualMaturity: 48) because, unlike the flags,
  # nothing here rules out a wider true domain than this one archive
  # happens to show, and none of these fields carry an ICES-sourced
  # description confirming a complete code list the way Quarter/DayNight's
  # icesVocab-backed enums do -- inventing closure would risk the same
  # mistake the numeric `range` philosophy above already warns against
  # (describing "what was observed" as if it were "the full valid domain").
  list(table = "CA", field = "AreaType",
       examples = list("0", "13", "2", "12", "6"),
       details = "Field's own description ('Age sampling aggregation level') doesn't explain what the codes themselves mean, but icesVocab's TS_AreaType resolves them (checked 2026-07-29, data-raw/datras_vocabulary.R): '0'=ICES Statistical Rectangles, '2'=Standard NS Roundfish Areas, '6'=EVHOE areas, '12'=Spanish North Areas, '13'=ICES Divisions. Not retyped enum because TS_AreaType has 27 official codes total, over the seed's own VOCAB_CODE_LIMIT (20, data-raw/DATASET_seed_dict.R) for a usable `values` map -- and confirms the true domain genuinely is wider than what's observed here (17 of 27 codes appear in this archive). Verified 2026-07-29 against the full CA archive."),
  list(table = "CA", field = "AreaCode",
       examples = list("VIa", "38G3", "43G1", "37G1", "44G0"),
       details = "Field's own description says coding is 'according to AreaType' (its sibling field) -- meaning depends on that field's own value, same pattern as LengthClass/LengthCode. Codes mix ICES-area style (VIIg) and rectangle-like style (38G3). 635 distinct values, 1,898,151 of 5,966,950 rows unpopulated. Verified 2026-07-29 against the full CA archive."),
  list(table = "CA", field = "IndividualMaturity",
       examples = list("61", "62", "1", "2", "B"),
       details = "Field's own description says the scheme depends on the sibling MaturityScale field ('MaturityScale should be filled in when...') -- explains the observed mix of numeric (61, 62, 1, 2) and letter (B, A) codes, different maturity scales using different code sets, not an inconsistency. 48 distinct values, 3,173,580 of 5,966,950 rows unpopulated. Verified 2026-07-29 against the full CA archive."),
  list(table = "CA", field = "FishID",
       examples = list("1", "2", "3", "4", "5"),
       details = "Reads as a sequential per-sample identifier (dense run of small integers-as-strings), open-ended and illustrative only, not an exhaustive domain -- 170,774 distinct values, only 1,118,002 of 5,966,950 rows populated (~18.7%). Verified 2026-07-29 against the full CA archive."),
  list(table = "CA", field = "GeneticSamplingFlag", type = "enum",
       values = list("Y", "N"),
       details = "Field's own description ('Flag whether genetic sample was taken') confirms boolean intent; verified 100% clean two-value split against the full archive, 2026-07-29 (N: 829,547 rows; Y: 13,793; zero other values across 843,340 non-null rows, 5,123,610 unpopulated)."),
  list(table = "CA", field = "StomachSamplingFlag", type = "enum",
       values = list("Y", "N"),
       details = "Field's own description ('Flag whether stomach sampling was performed') confirms boolean intent; verified 100% clean two-value split against the full archive, 2026-07-29 (N: 1,018,036 rows; Y: 39,403; zero other values across 1,057,439 non-null rows, 4,909,511 unpopulated)."),
  list(table = "CA", field = "ParasiteSamplingFlag", type = "enum",
       values = list("Y", "N"),
       details = "Field's own description ('Flag whether parasites sampling was performed') confirms boolean intent; verified 100% clean two-value split against the full archive, 2026-07-29 (N: 893,790 rows; Y: 76,620; zero other values across 970,410 non-null rows, 4,996,540 unpopulated)."),
  list(table = "CA", field = "SpeciesCode", type = "number(id)",
       examples = c(213L, 126326L, 127118L, 158513L, 1667212L),
       constraints = list("required"),
       details = "Official WoRMS AphiaID as submitted by the data provider -- contrast with Valid_Aphia, the ICES Datacenter's own validated/corrected version of the same concept, inserted server-side (see Valid_Aphia's own details below)."),
  list(table = "CA", field = "Valid_Aphia",
       examples = c(213L, 105872L, 126412L, 141452L, 1667212L),
       details = "CA's own instance was missed when HL's Valid_Aphia was originally filled (found 2026-07-29 via validate-spec's S07 check) -- same concept as HL's Valid_Aphia (ICES Datacenter's validated AphiaID) but a different sampling population (aged individuals only), so queried independently rather than assumed identical (Working principles, rule 12). 667 distinct values, 0 unpopulated (always present). Verified 2026-07-29 against the full CA archive."),
  list(table = "CA", field = "LengthClass", type = "number(quantity)", range = c(0, 5630),
       details = "Unit varies by the sibling LengthCode field (mm or cm; see LengthCode's own values map), so no fixed units here. One isolated outlier excluded, 2026-07-29: 932 (LengthCode '1', i.e. 9.32m) -- a lone occurrence with a 2.3x gap to the next-highest value (405). Curated separately from HL's own LengthClass: CA's population is aged individuals only, a different (and differently distributed) subset from HL's whole-catch length-frequency tally, so the two are not assumed identical (Working principles, rule 12)."),
  list(table = "CA", field = "IndividualAge", type = "number(quantity)", units = "years", range = c(0, 99),
       details = "-1 (1757 rows) reads as a systematic, undocumented 'not determined' sentinel; -5 and -95 (1 row each) are isolated anomalies -- all three excluded. 99 (54 rows) is kept: real, repeated support, not a fluke -- reads like a plus-group/max-age reporting convention, though that mechanism isn't confirmed here, just noted as an observation."),
  list(table = "CA", field = "NumberAtLength", type = "number(quantity)", range = c(1, 218),
       details = "Distinct population from HL's own NumberAtLength: this counts aged individuals only, not the whole catch, hence the much smaller scale -- not assumed identical (Working principles, rule 12)."),
  list(table = "CA", field = "IndividualWeight", type = "number(quantity)", units = "g", range = c(0, 97000)),

  # ---- LT (remaining fields not shared with HH) ---------------------------
  # 24 of LT's 27 bare `number` fields turned out to be exact HH duplicates
  # (found 2026-07-29 comparing field lists) and are handled once, below, in
  # shared_field_specs. Only these three are genuinely LT-specific.
  #
  # The 9 `examples` fills directly below (OSPARArea through EEZ) are
  # LT-specific litter/area classification fields, TODO.md's "remaining ~18"
  # item, 2026-07-29 -- none carry an ICES-sourced description (confirmed:
  # all nine are bare `string` with no `description` at all in the seed), so
  # none are retyped enum even where the observed set is small (MSFDArea: 2
  # values; UnitItem: 1) -- same reasoning as CA's AreaType/IndividualMaturity
  # above: no source confirms these archive-observed sets are the complete
  # valid domain, so closing them would risk asserting more than is known.
  list(table = "LT", field = "OSPARArea",
       examples = list("II", "III", "IV", "V"),
       details = "OSPAR maritime area code (Roman-numeral regions); 4 distinct values observed, 14,498 of 79,451 rows unpopulated. No description present to confirm whether this is the complete official OSPAR region set. Verified 2026-07-29 against the full LT archive."),
  list(table = "LT", field = "MSFDArea",
       examples = list("North-east Atlantic Ocean", "Baltic Sea"),
       details = "Marine Strategy Framework Directive region name; only 2 distinct values observed, 4,295 of 79,451 rows unpopulated. The EU MSFD framework has more than two regions overall -- DATRAS's own survey coverage may simply never reach the others, so not treated as a closed/exhaustive set. Verified 2026-07-29 against the full LT archive."),
  list(table = "LT", field = "PARAM",
       examples = list("A2", "LT-TOT", "A5", "A7", "A14"),
       details = "Litter parameter/category code, no description present. icesVocab resolves a PARAM list (checked 2026-07-29, data-raw/datras_vocabulary.R) -- 'LT-TOT'='Litter - total' confirmed there among 1,938 total codes -- but 'A2'/'A3'/'A5'/'A6'/'A7'/'A14' do NOT appear in it under any description, despite being common real values here (checked directly, not just absent from a sample). A real discrepancy between this archive's own PARAM usage and icesVocab's published list, not investigated further -- candidate for DATRAS-known-issues.yaml once that registry exists (see AGENTS.md). Not retyped enum regardless: 1,938 codes is far past the seed's VOCAB_CODE_LIMIT of 20. 50 distinct values, 2 of 79,451 rows unpopulated. Verified 2026-07-29 against the full LT archive."),
  list(table = "LT", field = "LTSZC",
       examples = list("A", "B", "C", "D", "13"),
       details = "Litter size class code (mix of letter and numeric codes), no description present. icesVocab's LTSZC list confirms all five (checked 2026-07-29): 'A'='squared centimetre <5*5cm=25cm2' through 'D'='<50*50cm=2500cm2' (area-based classes), '13'='centimetre 15-49.99cm' (a length-based class) -- two different measurement bases coexisting under one code list. 23 of 41 official codes observed here; not retyped enum since 41 exceeds the seed's VOCAB_CODE_LIMIT of 20. 16,508 of 79,451 rows unpopulated. Verified 2026-07-29 against the full LT archive."),
  list(table = "LT", field = "UnitWeight",
       examples = list("kg/haul", "g/haul"),
       details = "Unit of the sibling LT_Weight field (see LT_Weight's own details below); exactly 2 values observed across the full archive (48,758 kg/haul, 26,437 g/haul), 4,256 of 79,451 rows unpopulated. No description present to confirm this is the complete valid unit set. Verified 2026-07-29 against the full LT archive."),
  list(table = "LT", field = "UnitItem",
       examples = list("items/haul"),
       details = "Unit of the sibling LT_Items field (see LT_Items's own details below); only one value ever observed (79,415 of 79,451 rows), 36 unpopulated -- a single example, not five, because no second real value exists in the archive to show. Verified 2026-07-29 against the full LT archive."),
  list(table = "LT", field = "TYPPL",
       examples = list("PE", "PP", "PET", "PS", "UPL"),
       details = "Litter (plastic) type code, no description present. icesVocab's TYPPL list confirms all five (checked 2026-07-29): PE=Polyethylene, PET=Polyethylene terephthalate, PP=Polypropylene, PS=Polystyrene, UPL=Undefined plastic. 6 of 30 official codes observed here; not retyped enum since 30 exceeds the seed's VOCAB_CODE_LIMIT of 20. Very sparse: only 162 of 79,451 rows populated. Verified 2026-07-29 against the full LT archive."),
  list(table = "LT", field = "LTPRP",
       examples = list("AO", "CL1", "CL5", "CL2", "CL4"),
       details = "Litter property code, no description present. icesVocab's LTPRP list confirms all five as BASE codes (checked 2026-07-29): AO=Attached organisms, CL1=Colour-None(clear), CL2=Colour-Black, CL4=Colour-Blue, CL5=Colour-White -- only 22 official base codes, but composite codes like 'CL1~AO' also appear in real data (a colour code plus an attached-organisms flag, tilde-joined), which is why 79 distinct values are observed here despite only 22 base codes existing -- a combinable/multi-value scheme, not a flat single-select list, confirming the earlier guess. Not retyped enum: even the 22-code base list is past the seed's VOCAB_CODE_LIMIT of 20, and the combinable form isn't a plain enum shape regardless. 58,349 of 79,451 rows unpopulated. Verified 2026-07-29 against the full LT archive."),
  list(table = "LT", field = "EEZ",
       examples = list("United Kingdom Exclusive Economic Zone", "Danish Exclusive Economic Zone", "French Exclusive Economic Zone", "Spanish Exclusive Economic Zone", "Swedish Exclusive Economic Zone"),
       details = "Exclusive Economic Zone name, no description present. 20 distinct values, 162 of 79,451 rows unpopulated. Not treated as a closed set -- EEZ coverage in a wider archive could plausibly include zones absent from this one. Verified 2026-07-29 against the full LT archive."),
  list(table = "LT", field = "NMArea",
       examples = list("United Kingdom 12 NM", "Swedish 12 NM", "Spanish 12 NM", "French 12 NM", "Danish 12 NM"),
       details = "National 12-nautical-mile zone name (sibling concept to EEZ above), no description present. 18 distinct values, 53,303 of 79,451 rows unpopulated. Not treated as a closed set, same reasoning as EEZ. Found 2026-07-29 only after fixing the Y/N-enum crash above -- validate-spec had never actually reached this field before, since it's the table's last column and everything upstream of it kept dying first (ThermoCline, then the flag enums). Verified 2026-07-29 against the full LT archive."),

  list(table = "LT", field = "Depth", type = "number(quantity)", units = "m", range = c(1, 3098),
       details = "Confirmed 2026-07-29: byte-for-byte identical to this table's own BottomDepth across all 79,288 populated rows (0 differences, 0 one-sided nulls) -- a known ICES-side redundancy (also documented in obus's own download-stage comments), not an opus/obus naming quirk. Given the same type/units/range as BottomDepth here rather than re-derived independently, since it is BottomDepth."),
  list(table = "LT", field = "LT_Weight", type = "number(quantity)", range = c(0, 1600000),
       details = "Unit varies by the sibling UnitWeight field (kg/haul for 46,673 rows, g/haul for 24,383, unspecified for 276), so no fixed units here. Two exclusions, 2026-07-29: -99 (3 rows, kg/haul) as an isolated sentinel-like anomaly, and 46,318,000 (1 row, g/haul) as a lone outlier roughly 29x the next-highest real value (1,600,000) -- an implausible ~46 tonnes of litter in one haul, almost certainly a data-entry error. The rest of the g/haul group's own large values (up to 1,600,000g = 1.6 tonnes) are kept: rare, but large litter catches (e.g. old fishing gear, major debris items) are plausible."),
  list(table = "LT", field = "LT_Items", type = "number(quantity)", range = c(0, 2323),
       details = "UnitItem is 'items/haul' for all but 36 of 76,882 populated rows -- effectively a fixed count, no exclusions needed: no isolated outlier or repeating marker pattern, just a smooth decline from the max.")
)

apply_field_spec <- function(dict, spec) {
  apply_col_update(dict, spec$table, spec$field, spec[setdiff(names(spec), c("table", "field"))])
}

curated <- reduce(field_specs, apply_field_spec, .init = curated)

# Fields whose spec is identical across every Tier 1 table they appear in
# (Working principles, rule 12): the same haul's own metadata (its sweep
# length, its own haul number, the year it was towed, its geometry/
# environment readings) is literally the same fact whether read from that
# haul's HH, HL, CA, or LT record, not four independently-measured
# quantities that happen to coincide. HH is the reference source (Tier 1's
# own primary table) -- these values were established during HH's own
# curation pass (data-raw/tier1_field_stats.R) and are reproduced verbatim
# to every other table that has a column of the same name, not
# independently re-derived per table.
#
# 24 of these 27 entries were promoted here 2026-07-29 while curating LT:
# comparing LT's remaining bare `number` fields against HH's own found only
# three genuinely LT-specific fields (Depth -- itself a confirmed duplicate
# of LT's own BottomDepth, see field_specs above -- plus LT_Weight/LT_Items,
# which have no HH counterpart at all); everything else LT still had bare
# was already an HH field, re-deriving it from LT's own subset alone would
# have repeated the exact mistake this rule exists to prevent.
#
# NOT every field shared by name gets this treatment -- two exceptions found
# 2026-07-29 while curating HL, both left as per-table field_specs entries
# instead:
#   - A field can describe a genuinely different POPULATION per table even
#     under the same name -- e.g. LengthClass/NumberAtLength mean "the whole
#     catch's length-frequency distribution" in HL but "the aged subsample
#     only" in CA (a much smaller, differently-scaled set of values).
#   - DateofCalculation recurs everywhere but its own minimum can genuinely
#     differ per table (LT's reporting began years later) -- see its own
#     block in field_specs above.
#
# data-dict.yaml's own spec has no mechanism for defining a column once and
# reusing it across tables (confirmed 2026-07-29 against site/spec.md --
# every table's `columns` list is fully independent); this list is how
# opus's OWN generation script enforces the consistency the shipped YAML
# itself cannot.

# Helper: Get Gear codes from icesVocab as enum values
get_gear_enum_values <- function() {
  library(icesVocab)
  gear_list <- getCodeList('Gear')
  # Filter out deprecated codes
  active_gears <- gear_list[gear_list$Deprecated == FALSE, ]
  # Create named list: code -> description
  setNames(as.list(active_gears$Description), active_gears$Key)
}

shared_field_specs <- list(
  # ---- string-typed fields: `examples` fill, 2026-07-29 ---------------------
  # The type-measure/range/examples pass above (and its own tier1_field_stats.R
  # verification) only ever covered bare `number` fields -- these `string`
  # columns were never in scope for either pass, seed-only until now (found
  # 2026-07-29 while investigating why validate-spec's S07 "missing examples"
  # kept flagging them). Filled the same way as the number fields: real
  # distinct values queried from obus's HH archive (rule 12's reference
  # source), not invented. Values are open code lists (new countries/gears/
  # platforms/surveys can appear over time), so `examples` only -- never
  # `type: enum`, which would wrongly closed-list them (unlike RecordHeader
  # above, which really is a fixed, closed, one-value-per-table tag).
  list(field = "Survey", examples = list("NS-IBTS", "BTS", "BITS", "DYFS", "Can-Mar"),
       details = "29 distinct values in HH's archive (verified 2026-07-29); ICES DATRAS survey acronym, an open list, not a fixed enum. icesVocab DOES resolve a 'Survey' key by name (checked 2026-07-29, data-raw/datras_vocabulary.R) but it's a false lead, not this field's source: its 133 codes are ICES's own cross-domain internal survey IDs (e.g. 'A1012'), a completely different scheme from DATRAS's own short acronyms -- confirmed by checking real codes against it directly, not assumed. Not used."),
  list(field = "Country", examples = list("NL", "DE", "GB", "DK", "GB-SCT"),
       details = "22 distinct values in HH's archive (verified 2026-07-29); 'GB-SCT' illustrates that this is ISO 3166 codes PLUS ICES's own sub-national region codes (per the field's own description), not plain ISO 3166 alone. icesVocab DOES resolve a 'TS_Country' key by name (checked 2026-07-29) but it's a false lead too, same as Survey above: its 25 codes are 3-letter (e.g. 'BEL', 'DEN', 'ENG'), a different scheme entirely from this field's own 2-letter-plus-region codes -- confirmed by checking real codes against it directly. Not used."),
  list(field = "Gear", type = "enum", values = get_gear_enum_values(),
       details = "All 99 active icesVocab Gear Type codes (deprecated code OTG excluded, 2026-08-02). 55 confirmed used in DATRAS archive; 44 additional codes are valid ICES definitions (may be used in future submissions or by other surveys). Each code has a full description in icesVocab. Validation: enum restricts submissions to these codes."),
  list(field = "Platform", examples = list("74E9", "26D4", "748S", "64SS", "18NE"),
       details = "110 distinct values in HH's archive (verified 2026-07-29); SeaDataNet ship/platform codes, an open list, not a fixed enum."),
  list(field = "StationName", examples = list("1", "2", "22", "9", "17"),
       details = "Field's own description says this is a national coding system, not defined by ICES -- examples show the common shape (short numeric-looking strings), not an exhaustive domain. 24,130 distinct values in HH's archive (verified 2026-07-29), the highest cardinality of any Tier 1 string field; 6,899 of 150,262 rows unpopulated."),
  list(field = "StatisticalRectangle", examples = list("37F8", "35F5", "36F7", "32F3", "36F6"),
       details = "701 distinct values in HH's archive (verified 2026-07-29); real ICES statistical rectangle codes (0.5 deg lat x 1 deg lon grid), not a fixed enum given the size of the grid. 12,235 of 150,262 HH rows unpopulated. Only present in HH and LT (confirmed 2026-07-29) -- consistent with the Open items note that LT's assessment output joins in a set of HH-style columns."),
  list(field = "StartTime", examples = list("730", "715", "1300", "900", "700"),
       details = "1,440 distinct values in HH's archive (verified 2026-07-29), always populated (150,262/150,262). Field's own description implies a fixed 4-digit HHMM ('E.g. 10:15=1015'), but real values are NOT zero-padded (e.g. '730', not '0730') -- documented here rather than silently assumed. Only present in HH and LT (confirmed 2026-07-29), same as StatisticalRectangle above."),

  list(field = "SweepLength", type = "number(quantity)", units = "m", range = c(0, 850)),
  list(field = "HaulNumber", type = "number(ordinal)", range = c(0, 82483),
       constraints = list("required"),
       details = "Sequential per-cruise numbering, but countries vary in whether it resets each cruise or runs continuously -- the archive-wide range spans many cruises' own counts pooled together, not one cruise's own haul tally."),
  list(field = "Year", type = "number(ordinal)", range = c(1965, 2026),
       constraints = list("required")),
  list(field = "Day", type = "number(ordinal)", range = c(1, 31),
       constraints = list("required")),
  list(field = "HaulDuration", type = "number(quantity)", units = "min", range = c(1, 120),
       details = "A haul cannot take zero or negative time; 217 rows recorded as exactly 0 and 2 as negative (-514, -238) are excluded, most likely unrecorded/placeholder rather than a genuine instantaneous haul. Upper bound set at 2 hours: DATRAS carries no passive/soak gear, so a longer tow is highly suspect -- observed values run as high as 1470 min with no repeating marker pattern (i.e. not a clean sentinel, just unreliable). Verified 2026-07-29 against the full archive."),
  list(field = "ShootLatitude", type = "number(quantity)", units = "decimal degrees", range = c(36.0013, 76.2117)),
  list(field = "ShootLongitude", type = "number(quantity)", units = "decimal degrees", range = c(-67.7115, 24.4333),
       details = "A genuine value of exactly -9.0000 degrees (9 deg W, an ordinary DATRAS longitude off Ireland/Iberia) would be indistinguishable from missing here: icesDatras's fetch pipeline scrubs literal -9 to NA for every numeric column, not just where -9 is a documented sentinel -- see data-raw/tier1_field_stats.R's header."),
  list(field = "HaulLatitude", type = "number(quantity)", units = "decimal degrees", range = c(36.0013, 65),
       details = "3 rows record exactly 0 degrees (the equator), categorically outside any DATRAS survey area -- excluded; the lower bound instead matches ShootLatitude's own clean minimum for the same archive."),
  list(field = "HaulLongitude", type = "number(quantity)", units = "decimal degrees", range = c(-67.6762, 45.8753),
       details = "Same -9-as-missing caveat as ShootLongitude above (0 degrees, the Prime Meridian, is a genuine North Sea value here and is kept)."),
  list(field = "BottomDepth", type = "number(quantity)", units = "m", range = c(1, 3098)),
  list(field = "NetOpening", type = "number(quantity)", units = "m", range = c(0, 76)),
  list(field = "Tickler", type = "number(quantity)", range = c(0, 27)),
  list(field = "Distance", type = "number(quantity)", units = "m", range = c(0, 59995)),
  list(field = "WarpLength", type = "number(quantity)", units = "m", range = c(0, 4065)),
  list(field = "WarpDiameter", type = "number(quantity)", units = "mm", range = c(16, 30),
       details = "A dense, well-populated cluster runs 16-21mm and 27-30mm; isolated single-occurrence values below (1mm x2, 5mm x10, 12mm) and above (39, 56, 85, 88mm) sit apart from it with no comparable support and are treated as data-entry errors, excluded here."),
  list(field = "WarpDensity", type = "number(quantity)", units = "kg/m", range = c(0, 26)),
  list(field = "DoorSurface", type = "number(quantity)", units = "m2", range = c(0, 20.2)),
  list(field = "DoorWeight", type = "number(quantity)", units = "kg", range = c(0, 1720)),
  list(field = "DoorSpread", type = "number(quantity)", units = "m", range = c(1, 250),
       details = "0m (9 rows) is excluded as a placeholder -- a rigged, towing trawl cannot have zero door spread. Three single-occurrence values (762, 767, 778m) sit far above everything else in the archive (next highest is 250m) and are treated as data-entry errors, excluded; a real, well-populated value at 3.6m (1128 rows, likely a fixed beam-trawl spread) is kept."),
  list(field = "WingSpread", type = "number(quantity)", units = "m", range = c(4, 50),
       details = "0m (9 rows), 1.8m and 2m (1 row each) are excluded as below any value with real support -- a well-populated cluster starts at 4m (1074 rows, likely a fixed beam-trawl spread). 142m (1 row) sits far above the next-highest real value (50m) and is treated as a data-entry error, excluded."),
  list(field = "TowDirection", type = "number(quantity)", units = "degrees", range = c(0, 360),
       details = "999 (3 rows) reads as an undocumented out-of-domain 'not recorded' marker, the same pattern confirmed for WindDirection below. A further cluster -- 450 deg (62 rows), 520(5), 460(5), 540(3), 510, 564, 702 (1 each) -- divided by 10 becomes ordinary bearings (45.0, 52.0, 46.0, 54.0, 51.0, 56.4, 70.2 deg); plausible but not investigated further (would need correlating with Country/Survey). Both groups are outside the documented 0-360 domain and excluded here."),
  list(field = "SpeedGround", type = "number(quantity)", units = "knots", range = c(0, 10),
       details = "Ceiling is a domain judgment (real trawling ground speed), not an observed cluster boundary -- observed values run 10.8 up to a 99.9 marker with no clean gap, all excluded."),
  list(field = "SpeedWater", type = "number(quantity)", units = "knots", range = c(0, 22)),
  list(field = "WindDirection", type = "number(quantity)", units = "degrees", range = c(-1, 360),
       details = "-1 is documented ('varying direction'). 999 (57 rows) reads as an undocumented out-of-domain 'not recorded' marker; a handful of further single-occurrence values just above 360 (711, 504, 420, 365, 361) are also excluded."),
  list(field = "WindSpeed", type = "number(quantity)", units = "m/s", range = c(0, 28),
       details = "Ceiling follows the Beaufort 10 upper bound (28.4 m/s, storm force) -- no vessel would be actively trawling above this. 1,641 of 109,012 populated rows (~1.5%) exceed it, tailing off smoothly with no clean gap up to 342 m/s; the count jumps from a thin 1-7-row-per-value tail above 28 to 357 rows right at 28, consistent with a real distribution below and noise above."),
  list(field = "SwellDirection", type = "number(quantity)", units = "degrees", range = c(0, 360)),
  list(field = "CodendMesh", type = "number(quantity)", units = "mm", range = c(9, 100),
       details = "0mm (202 rows) excluded as a placeholder -- a codend by definition has some mesh size. 250mm (1 row) sits far above the next-highest real value (100mm, 644 rows) and is treated as a data-entry error, excluded.")
)

apply_shared_field_spec <- function(dict, spec) {
  updates <- spec[setdiff(names(spec), "field")]
  for (ti in seq_along(dict$tables)) {
    ci <- which(map_chr(dict$tables[[ti]]$columns, "name") == spec$field)
    if (length(ci) == 0) next
    dict <- apply_col_update(dict, dict$tables[[ti]]$name, spec$field, updates)
  }
  dict
}

curated <- reduce(shared_field_specs, apply_shared_field_spec, .init = curated)

# Table-level labels and descriptions (grain and population for each table)
table_specs <- list(
  list(table = "HH",
       label = "Haul Information",
       description = "Each row is one haul (trawl deployment). Contains haul-level metadata: geography, timing, gear deployment, environmental conditions, and performance flags.",
       origin = "data-raw/DATASET_curate_dict.R",
       details = "Grain: each row represents one discrete haul deployment (one trawl operation). Population: all hauls submitted to ICES DATRAS within the covered survey/region/timeframe. Join key: HL, CA, and LT tables reference haul-level data via a composite identifier constructed from eight fields: Survey, Year, Quarter, Country, {Platform or Ship}, Gear, {StationName or StNo}, and HaulNumber. The naming convention differs by era: newer submissions use Platform/StationName/HaulNumber (new style); older submissions use Ship/StNo/HaulNo (old style). Note: HaulNumber alone is NOT a valid join key — it is nullable (305,276 nulls found in CA, ~5.12% of data) and must be paired with all seven other fields to uniquely identify a haul across the full dataset. See obus::dr_add_id for the composite ID construction logic."),
  list(table = "HL",
       label = "Length Frequency Distribution",
       description = "Each row is a length class within a haul's catch. Contains the count of fish in each length bin, without individual-level age/sex data; the length-aggregated summary layer of Tier 1.",
       origin = "data-raw/DATASET_curate_dict.R",
       details = "Grain: each row is a (haul, species, length class) combination with a count of fish in that length bin. Population: length-frequency summaries for all species caught in surveyed hauls, aggregated by length class. Linked to HH via the composite haul identifier (Survey + Year + Quarter + Country + Platform/Ship + Gear + StationName/StNo + HaulNumber). Note: HaulNumber is nullable in the CA table (see HH table details); the full 8-field composite key is required for correct joins."),
  list(table = "CA",
       label = "Age Composition (Individual)",
       description = "Each row is one aged fish specimen from a haul. Contains individual-level biological measurements (length, weight, age, sex, maturity) on a subsample of the catch; linked to HH via the composite haul identifier.",
       origin = "data-raw/DATASET_curate_dict.R",
       details = "Grain: each row is one biological specimen (a single aged fish) from a haul. Population: individual organisms sampled and measured from hauls within covered surveys, not the full catch — a subsample. Linked to HH via the composite haul identifier (Survey + Year + Quarter + Country + Platform/Ship + Gear + StationName/StNo + HaulNumber). Critical note: HaulNumber contains 305,276 null values (5.12% of 5.97M rows), violating the constraint marked in DATRAS-data-dict.yaml. This nullability breaks assumptions about HaulNumber as a join key; the composite 8-field identifier is required instead. See DATRAS-known-issues.yaml (issue: ca_haul_number_nullable) for full details on the constraint violation and preprocessing caveat (icesDatras converts literal -9 to NA)."),
  list(table = "LT",
       label = "Litter Assessment",
       description = "Each row is one litter observation from a haul. Contains types and counts of marine debris (plastics, fishing gear, natural/organic material) recorded during the catch review; a separate thematic addition to the HH/HL/CA exchange.",
       origin = "data-raw/DATASET_curate_dict.R",
       details = "Grain: each row is one litter assessment/observation recorded during a haul's catch review. Population: litter records from hauls in covered surveys; a thematic addition to the HH/HL/CA core exchange tables with a separate collection protocol and scope. Linked to HH via the composite haul identifier (Survey + Year + Quarter + Country + Platform/Ship + Gear + StationName/StNo + HaulNumber). Note: like CA, LT's own HaulNumber may be nullable; the full 8-field composite key is required for correct joins.")
)

for (spec in table_specs) {
  curated <- apply_table_update(curated, spec$table, spec)
}

# Column labels (short human-readable titles for user-facing display)
# Only adding labels where the column name is technical/terse and benefits from a label
col_labels <- list(
  list(table = "HH", field = "RecordHeader", label = "Record Type"),
  list(table = "HH", field = "HaulDuration", label = "Haul Duration (minutes)"),
  list(table = "HH", field = "DepthStratum", label = "Depth Stratum"),
  list(table = "HL", field = "RecordHeader", label = "Record Type"),
  list(table = "HL", field = "SpeciesCode", label = "Species (WoRMS AphiaID)"),
  list(table = "HL", field = "SpeciesCategory", label = "Species Category"),
  list(table = "HL", field = "LengthClass", label = "Length Class (cm)"),
  list(table = "HL", field = "NumberAtLength", label = "Count at Length"),
  list(table = "CA", field = "RecordHeader", label = "Record Type"),
  list(table = "CA", field = "SpeciesCode", label = "Species (WoRMS AphiaID)"),
  list(table = "CA", field = "LengthClass", label = "Length Class (cm)"),
  list(table = "CA", field = "AgeSource", label = "Age Determination Method"),
  list(table = "CA", field = "AgePreparationMethod", label = "Specimen Preparation for Aging"),
  list(table = "LT", field = "LT_Weight", label = "Total Litter Weight (kg)"),
  list(table = "LT", field = "LT_Items", label = "Total Item Count")
)

for (spec in col_labels) {
  curated <- apply_col_update(curated, spec$table, spec$field, list(label = spec$label))
}

# Add sources to each table (pointers to parquet test data)
for (ti in seq_along(curated$tables)) {
  table_name <- curated$tables[[ti]]$name
  curated$tables[[ti]]$source <- list(parquet = paste0(table_name, ".parquet"))
}

# Glossary: domain-specific DATRAS/survey terminology
glossary <- list(
  "Haul" = "A single deployment of a trawl net. The primary unit of observation in DATRAS: one haul's catch (HH record) is subsampled and analyzed into length frequencies (HL) and aged individuals (CA).",
  "Length-stratified subsample" = "A subset of fish taken from a haul's catch, selected across the full range of observed length classes. Used in CA for cost-efficient age sampling without exhaustively aging every fish.",
  "Valid_Aphia" = "The ICES Datacenter's server-inserted, validated WoRMS AphiaID for each species. May differ from SpeciesCode (submitted value) due to ICES corrections or updates to the WoRMS taxonomy.",
  "DateofCalculation" = "The timestamp (YYYYMMDD) when the ICES Datacenter last recalculated and reprocessed this record. Not submitted by data providers; inserted and updated server-side as part of ICES's QC workflow.",
  "Litter Assessment" = "A qualitative and quantitative survey of marine debris (plastics, metal, rubber, natural materials, fishing gear) observed in the trawl catch. LT records are a thematic extension beyond HH/HL/CA's focus on fishery target species.",
  "Tier 1" = "The raw, per-haul exchange layer of ICES DATRAS: HH (haul), HL (length frequency), CA (aged individuals), and LT (litter). The primary submission format from national institutes to ICES.",
  "Survey" = "A coordinated research program that conducts regular sampling (e.g., NS-IBTS: North Sea International Bottom Trawl Survey). DATRAS is the archive of submissions from many regional surveys with different spatial/temporal coverage."
)

# Top-level metadata: add $learn_more (spec-recommended, S09), drop the
# seed's "SEED ONLY / not yet curated" framing now that it's been curated,
# point at this script for what changed and why. Reconstructed explicitly
# (rather than just mutating `seed`) to keep key order matching the spec's
# suggested style ($version, $learn_more, name, label, description, version, tables).
curated <- list(
  `$version` = curated$`$version`,
  `$learn_more` = "http://data-dict.tidyverse.org/",
  name = curated$name,
  label = curated$label,
  description = paste(
    "Direct per-haul submissions to ICES DATRAS: HH (haul), HL (length),",
    "CA (age), LT (litter). Curated from",
    "data-raw/seed/DATRAS-exchange-dict-seed.yaml -- see",
    "data-raw/DATASET_curate_dict.R for the corrections and field-spec",
    "fills applied and why."
  ),
  origin = "data-raw/DATASET_seed_dict.R → data-raw/DATASET_curate_dict.R",
  version = list(date = as.character(Sys.Date())),
  tables = curated$tables,
  glossary = glossary
)

# Format long text fields with line breaks for YAML readability (80 chars/line)
format_long_text <- function(text, width = 80) {
  if (is.null(text) || !nchar(text) > width) return(text)
  # Break on word boundaries
  words <- strsplit(text, " ")[[1]]
  lines <- character()
  current_line <- ""
  for (word in words) {
    if (nchar(current_line) + nchar(word) + 1 <= width) {
      current_line <- if (nchar(current_line) == 0) word else paste(current_line, word)
    } else {
      if (nchar(current_line) > 0) lines <- c(lines, current_line)
      current_line <- word
    }
  }
  if (nchar(current_line) > 0) lines <- c(lines, current_line)
  paste(lines, collapse = "\n")
}

# Apply formatting to all text fields
format_yaml_text <- function(dict) {
  for (ti in seq_along(dict$tables)) {
    for (ci in seq_along(dict$tables[[ti]]$columns)) {
      col <- dict$tables[[ti]]$columns[[ci]]
      if (!is.null(col$description) && nchar(col$description) > 80) {
        col$description <- format_long_text(col$description)
      }
      if (!is.null(col$details) && nchar(col$details) > 80) {
        col$details <- format_long_text(col$details)
      }
      dict$tables[[ti]]$columns[[ci]] <- col
    }
  }
  dict
}

curated <- format_yaml_text(curated)

write_yaml(curated, "inst/DATRAS-data-dict.yaml")

# ============================================================================
# Create strict icesVocab-only version for validation testing
# ============================================================================
# The descriptive version above includes all observed enum values (including
# those NOT in icesVocab) to document what exists in the real data. The strict
# version below contains ONLY icesVocab-defined enums, allowing validation to
# detect undocumented values that appear in submissions.
#
# Violations detected in real archive:
#
# HH table:
#   - ThermoCline: archive has "y"/"Y" (case variants), spec only has "N"
#   - SwellHeight: numeric 0-60m (real quantities), spec defines as enum
#
# CA table:
#   - HaulNumber: 305,276 nulls (5.12%) despite required=true (D01 violation)
#   - AgeSource: 1.16M rows have "otolith" (lowercase), not in icesVocab codes
#   - AgePreparationMethod: 8 observed codes; only 3 in icesVocab (~250k non-null)
#
# LT table:
#   - PARAM: 50 distinct values; A2/A5/A7/A14/A3/A6 undocumented (~50k rows)

# Post-process YAML to quote number-looking string examples (new spec requirement)
# (R's yaml writer doesn't preserve quote style for strings like "74E9", but only
# for `string` columns -- `number(id)` examples should remain unquoted numbers)
for (outfile in c("inst/DATRAS-data-dict.yaml")) {
  lines <- readLines(outfile)
  i <- 1
  while (i <= length(lines)) {
    # Look for "type: string" followed (several lines later) by "examples:"
    if (grepl("^\\s+type: string\\s*$", lines[i])) {
      # Found a string column; now look for its examples section
      col_start <- i
      j <- i + 1
      examples_found <- FALSE
      while (j <= length(lines) && !grepl("^\\s+- name: ", lines[j])) {
        if (grepl("^\\s+examples:\\s*$", lines[j])) {
          examples_found <- TRUE
          # Quote examples on this string column
          j <- j + 1
          while (j <= length(lines) && grepl("^\\s+- ", lines[j])) {
            match <- regexpr("- (.+)$", lines[j])
            if (match > 0) {
              value <- regmatches(lines[j], match)
              value <- sub("^- ", "", value)
              # Quote if it looks like a number/hex code and isn't already quoted
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

# ============================================================================
# FINAL: Validate YAML structure against data-dict spec
# ============================================================================

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
  "Curated ", length(corrections), " WSDL-disagreement correction(s), ",
  length(field_specs), " per-table field-spec fill(s), and ",
  length(shared_field_specs), " cross-table shared-spec fill(s). Wrote ",
  "inst/DATRAS-data-dict.yaml (descriptive with observed data enums and legacy field names). ",
  "Post-processed to quote number-looking string examples for data-dict spec compliance.",
  "\n✓ Validated against data-dict spec."
)
