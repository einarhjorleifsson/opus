# Curates the Tier 1 (raw exchange) data-dict.yaml from the seed, applying
# known domain-knowledge corrections. Deliberately diffable against the
# seed, so the two together show the whole workflow at a glance:
#
#   diff data-raw/seed/DATRAS-exchange-dict-seed.yaml inst/DATRAS-data-dict-legacy.yaml
#
# This is a separate script from spec_01_seed_dict.R on purpose (AGENTS.md's
# Working principles, rule 11 / seed-vs-curate split): the seed reports
# ICES's sources literally, unfixed; corrections happen only here, and each
# one is written down explicitly below, not silently applied while seeding.
#
# Restructured 2026-08-09 to key every correction/spec by legacy (real,
# on-the-wire) field name, not ICES's suggested new name -- matches the
# seed's own restructure (see spec_01_seed_dict.R's header for why). This
# script's own output is now `inst/DATRAS-data-dict-legacy.yaml`; the
# curated/new-named version opus actually ships is produced from it by
# data-raw/spec_03_translate_new_names.R, a pure rename, nothing else.
#
# Each correction is a stand-in for a future DATRAS-known-issues.yaml row --
# that registry doesn't exist yet (filing/tracking issues formally is a
# later step, see AGENTS.md). The `issue_id`s used here are kept consistent
# with the illustrative examples already used in AGENTS.md, so they resolve
# cleanly once the registry exists instead of needing renaming.

library(yaml)
library(purrr)
library(opus)  # op_vocab_get_codes(), via get_vocab_enum_values()

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
  if (!is.null(updates$todo))        col$todo <- updates$todo
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
  if (!is.null(updates$todo))        tbl$todo <- updates$todo
  if (!is.null(updates$definitions)) tbl$definitions <- updates$definitions
  dict$tables[[ti]] <- tbl
  dict
}

# Helper: fetch a vocab key's active codes as an enum values map
# (code -> description), via opus's own op_vocab_get_codes() (R/vocab.R,
# already excludes deprecated codes -- no icesVocab package dependency).
# Generalized 2026-08-10 from a Gear-only version that called
# `library(icesVocab); getCodeList('Gear')` directly -- a real, undeclared
# dependency (icesVocab is in neither Imports nor Suggests in DESCRIPTION)
# that would have failed on any machine without it installed. Confirmed
# byte-identical output for Gear before switching (99 codes, both sources).
# Defined here, ahead of field_specs below, because CatIdentifier's entry
# calls it eagerly (a plain list() literal evaluates its arguments
# immediately, not lazily).
get_vocab_enum_values <- function(key) {
  codes <- op_vocab_get_codes(key)
  setNames(as.list(codes$Description), codes$Key)
}

# One row per correction. Add to this list as curation finds more; nothing
# here is inferred or guessed -- each entry traces to a specific, verified
# disagreement between what ICES's WSDL declares and what the field
# actually is/contains (see `mechanism`). All five of these fields happen
# to be unrenamed (legacy name == curated name), so no key changed here
# during the 2026-08-09 legacy-keying restructure.
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
    range = list(0.0, 13.0),
    values = NULL,
    issue_id = "swell_height_type_mismatch",
    mechanism = paste(
      "icesVocab declares this an enum (codes H/L/M/N/NR/VH for height classes),",
      "but real HH archive data shows this is a measured quantity, not a",
      "categorized class. Full picture (rechecked 2026-08-16 after removing an",
      "unrelated archive-pipeline bug that had been silently converting this",
      "field's own -9 sentinel to NA): 0 true nulls; 108,698 rows (74.47% of all",
      "145,958) carry the standard DATRAS -9 'not recorded' sentinel; the",
      "remaining 37,260 are real, continuous numeric measurements (0-60m).",
      "Range set to 0-13m using WindSpeed as an independent co-parameter check:",
      "median WindSpeed rises smoothly with SwellHeight through 13m (8m/24,",
      "9m/26, 10m/22, 12m/28, 13m/24 m/s), consistent with genuine rough-weather",
      "readings, but breaks down sharply above it (15m/5, 16m/8, 20m/4, 25m/13,",
      "30m/7, 60m/16 m/s -- implausibly calm for the claimed swell height, and",
      "matching the wind speeds already seen at 1.5m/1.6m/2.0m/2.5m/3.0m/6.0m,",
      "the values these look like decimal-shifted versions of). The 23 rows",
      "above 13m are excluded as data-entry errors on this evidence, not",
      "genuine extreme swells. Candidate for DATRAS-known-issues.yaml formal",
      "escalation to imbus/ICES -- both the type mismatch and the fact that",
      "neither table's real data uses icesVocab's own declared code scheme at all."
    )
  ),
  list(
    table = "LT", field = "SwellHeight", type = "number(quantity)",
    units = "m",
    range = list(0.0, 13.0),
    values = NULL,
    issue_id = "swell_height_type_mismatch",
    mechanism = paste(
      "Same known issue as HH's own SwellHeight above (icesVocab declares a single",
      "unprefixed 'SwellHeight' key, an enum of H/L/M/N/NR/VH height classes -- the",
      "seed stage applies it here too since the key resolves the same way for LT).",
      "This field is not independently observed by LT: it is HH's own SwellHeight,",
      "recorded again on the LT record for the same haul (confirmed 2026-08-16 by",
      "joining LT to HH on the full 8-field composite key -- 55,914 of 55,914",
      "rows where both are non-null carry an identical value, zero exceptions).",
      "Range, exclusion boundary, and evidence (including the WindSpeed",
      "co-parameter check) are therefore HH's, not independently re-derived here --",
      "see HH's own SwellHeight entry above for the full reasoning."
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

# Fills type MEASURE (id/ordinal/quantity -- the seed deliberately leaves
# these bare, see spec_01_seed_dict.R's own header), `units` (quantity
# columns only, per spec), `range`/`examples`, and `constraints` where
# directly verified. Kept as its own step, distinct from `corrections`
# above: these are gap-fills the seed always intended for hand curation, not
# fixes for something ICES's WSDL got wrong, so none of them carry an
# issue_id.
#
# Keyed by legacy (real, on-the-wire) field name throughout -- e.g. CA's
# GeneticSamplingFlag is `field = "GenSamp"` here, matching what these
# `details` notes actually verified against (the real archive column is
# called GenSamp; "GeneticSamplingFlag" is opus's own curated name, applied
# only at translate time by data-raw/spec_03_translate_new_names.R). This
# also means the field key here now directly matches what a reader would
# see querying the real archive, no legacy/new cross-reference needed to
# confirm which column a `details` note is actually about.
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
# parseDatras() (R/utilities.R) scrubs literal -9 to NA for every numeric
# column regardless of whether -9 is that field's own documented sentinel,
# upstream of any obus/opus choice and not fixable by re-fetching. Checked
# directly against the current official `ices-tools-prod/icesDatras`
# (2026-08-09, unlike some other icesDatras citations that were traced back
# to a personal fork -- see AGENTS.md): this specific behavior is real and
# current in the official package (`x[x == -9] <- NA`, unconditional,
# inside `parseDatras()`), not something `applyDatrasTypeSchema()` does --
# that function only casts types, so it's dropped from this citation.
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
# CAVEAT on this whole "verified 2026-07-29" era (added 2026-08-17): these
# checks ran against obus's own icesDatras-fetched archive, whose
# parseDatras(fix_types=TRUE) unconditionally scrubs literal -9 to NA for
# every numeric-looking column -- a "sentinel is present but reads as
# unpopulated/absent" misread, not a wrong distinct-value count. Confirmed
# affected and already corrected: CA.GenSamp/StomSamp/ParSamp/AgeSource/
# AgePrepMet (2026-08-16), HH.StNo/StatRec and CA.FishID/AreaCode
# (2026-08-17). Confirmed NOT affected (real, current zero-sentinel fields,
# checked directly): Survey, Country, Ship, TimeShot. Any *other* field in
# this file still citing bare "2026-07-29" with no later re-verification
# note has not been individually re-checked for this specific failure mode
# -- don't assume clean without checking, per Working Principle 9.
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
  # columns -- not seeded there at all, checked 2026-07-29). Legacy name is
  # RecordType on the wire for all three. ------------------------------------
  # NOT a shared_field_specs entry despite recurring across three tables:
  # unlike SweepLngt/HaulNo/Year (rule 12's main case -- one haul's own
  # fact reproduced verbatim), RecordType's valid value differs BY TABLE --
  # it's the record-type tag itself (which exchange file this row came from),
  # not a haul-level measurement, so "shared" would be wrong here (found
  # 2026-07-29). Verified against the full archive: 100% constant per table
  # (HH: 150,262/150,262 rows = "HH"; HL: 14,400,747/14,400,747 = "HL"; CA:
  # 5,966,950/5,966,950 = "CA"), matching the seed's own RecordType
  # description ("HH=Haul Information", "HL=Length Frequency Distribution",
  # "CA=individual fish recordings with biological information") exactly --
  # retyped enum accordingly, one single-key values map per table. The
  # description itself is left as-is (still useful general context covering
  # all four record types), `values` adds this table's own specific code.
  list(table = "HH", field = "RecordType", type = "enum",
       values = list(HH = "Haul Information")),
  list(table = "HL", field = "RecordType", type = "enum",
       values = list(HL = "Length Frequency Distribution")),
  list(table = "CA", field = "RecordType", type = "enum",
       values = list(CA = "individual fish recordings with biological information")),

  # ---- HH-only fields (no LT/HL/CA counterpart) ---------------------------
  list(table = "HH", field = "DepthStratum",
       examples = list("D2", "10", "9", "11", "D1"),
       details = "Field's own description says depth strata are survey-specific, not an ICES-wide vocabulary -- examples illustrate the shape seen in practice (mix of letter-prefixed and bare-number codes), not an exhaustive domain. Originally verified 2026-07-29 against obus's own pre-fix icesDatras archive (same sentinel-scrubbing caveat as GenSamp/StomSamp/ParSamp/AgeSource below) -- framed then as 'only half of surveys report it'. Re-verified 2026-08-17 directly against .datras/HH.parquet (145,958 rows): -9 is present and dominant (74,509 rows, 51.05%), not a null -- 0 true nulls in the current archive."),
  list(table = "HH", field = "HydroStNo",
       examples = list("74SC0000", "88888888", "1", "0", "3"),
       details = "National station numbering (field's own description), so examples are illustrative only, not an exhaustive domain. '88888888' recurs and reads like an undocumented all-8s placeholder/sentinel (the same kind of pattern seen elsewhere in HH, e.g. HaulDuration's zeros) rather than a real station ID, but is kept in `examples` (unlike a `range` exclusion, `examples` isn't a validity gate) since a reader should know it's a real recurring value. Originally verified 2026-07-29 against obus's own pre-fix icesDatras archive (same sentinel-scrubbing caveat as GenSamp below) -- framed then as 'only 79,371 of 150,262 rows populated'. Re-verified 2026-08-17 directly against .datras/HH.parquet (145,958 rows): 0 true nulls -- 69,762 rows (47.79%) carry either -9 or the 88888888 placeholder, the rest a real station ID."),
  list(table = "HH", field = "Buoyancy", type = "number(quantity)", units = "kg", range = c(0, 398)),
  list(table = "HH", field = "KiteDim", type = "number(quantity)", units = "m2", range = c(0, 1),
       details = "Coarse, equipment-spec values (0, 0.5, 0.7, 0.72, 0.8, 1) rather than a continuously measured quantity -- only 6 distinct values across 30,116 rows."),
  list(table = "HH", field = "WgtGroundRope", type = "number(quantity)", units = "kg", range = c(0, 2212)),
  list(table = "HH", field = "SurCurDir", type = "number(quantity)", units = "degrees", range = c(0, 360),
       details = "Two single-occurrence values just above 360 (392, 390) excluded; the rest of the archive is densely populated right up to 360."),
  list(table = "HH", field = "SurCurSpeed", type = "number(quantity)", units = "m/s", range = c(0, 9.3),
       details = "99 (marker) and 46.3 and 16 (each a single, isolated occurrence with no support nearby) excluded; a smoother, better-populated tail resumes at 9.3 (3 rows) and below."),
  list(table = "HH", field = "BotCurDir", type = "number(quantity)", units = "degrees", range = c(0, 359)),
  list(table = "HH", field = "BotCurSpeed", type = "number(quantity)", units = "m/s", range = c(0, 9.9),
       details = "9.9 (1 row) is unusually high for a bottom current and resembles the '9-family' marker pattern seen elsewhere in HH, but a genuinely fast tidal-race reading can't be ruled out -- kept in range rather than excluded, unlike the more clear-cut cases above."),
  list(table = "HH", field = "SurTemp", type = "number(quantity)", units = "degC", range = c(-1.5, 36)),
  list(table = "HH", field = "BotTemp", type = "number(quantity)", units = "degC", range = c(-1, 35.4)),
  list(table = "HH", field = "SurSal", type = "number(quantity)", units = "PSU", range = c(0, 38.52)),
  list(table = "HH", field = "BotSal", type = "number(quantity)", units = "PSU", range = c(3.13, 39.93)),
  list(table = "HH", field = "ThClineDepth", type = "number(quantity)", units = "m", range = c(0, 90)),
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

  list(table = "LT", field = "Rigging",
       details = paste(
         "Mostly a copy of HH's own Rigging for the same haul, but 3,419 of",
         "73,284 matched non-null rows (4.67%, checked 2026-08-16) diverge --",
         "almost entirely a near-symmetric swap between just two codes",
         "(FB<->FW: 1,978 and 1,441 rows respectively), consistent with",
         "independent recording variance between HH's haul-time entry and",
         "LT's own litter-assessment-time entry, not a one-directional error."
       )),
  list(table = "LT", field = "HaulVal",
       details = "Near-total copy of HH's own HaulVal for the same haul: only 21 of 73,263 matched non-null rows differ (0.03%, checked 2026-08-16), a small A<->I swap, negligible."),

  # ---- HH's BottomDepth concept / LT's own BottomDepth (see below) --------
  # The only one of 40 shared-concept fields whose LEGACY name diverges by
  # table (checked exhaustively 2026-08-09, all 40 shared_field_specs
  # entries cross-referenced against op_datras_field_list()): HH's real,
  # on-the-wire column is called "Depth"; LT genuinely has BOTH its own
  # separate "Depth" AND its own separate "BottomDepth" as real, distinct
  # legacy columns (byte-for-byte duplicates of each other -- ICES-side
  # redundancy, Issue 6, data-raw/ICES_ISSUE_REPORT.md). Under new-name
  # keying this was invisible (both HH's and LT's own "BottomDepth" curated
  # column shared one shared_field_specs entry, since they'd both been
  # renamed/kept as "BottomDepth") -- under legacy keying it can't be a
  # single shared entry, since "Depth" would otherwise ambiguously mean two
  # different things depending on table. Split into two explicit per-table
  # entries instead, table-scoped so there's no actual key collision (LT's
  # own separate "Depth" entry, further below, is a third, genuinely
  # different real column). All three get the identical range/units,
  # confirmed byte-identical real values.
  list(table = "HH", field = "Depth", type = "number(quantity)", units = "m", range = c(1, 3098)),
  list(table = "LT", field = "BottomDepth", type = "number(quantity)", units = "m", range = c(1, 3098),
       details = "-9 is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: 139 of 75,310 rows (0.18%), 0 true nulls."),

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
  # Unrenamed on every table (legacy name == curated name), so this key is
  # unchanged by the 2026-08-09 restructure.
  list(table = "HH", field = "DateofCalculation", type = "number(ordinal)", range = list(20120419L, Inf),
       details = "8-digit YYYYMMDD stamp, digit order (month before day) verified consistent across all four Tier 1 tables. Upper bound deliberately left open: a live, continuously-advancing ICES Datacenter 'last recalculated' stamp, not submitted by data providers, so a fixed max would go stale immediately. Lower bound is this table's own verified minimum -- NOT forced identical across tables the way SweepLngt/HaulNo/Year are, since a genuine table-specific difference is plausible here (confirmed: LT's own minimum is years later). A -9 sentinel (11,574 rows, 7.93% of non-null; already excluded by the lower bound above) reads as the standard DATRAS 'not recorded' convention for this server-computed field -- not yet (re)calculated for this record."),
  list(table = "HL", field = "DateofCalculation", type = "number(ordinal)", range = list(20120419L, Inf),
       details = "8-digit YYYYMMDD stamp, digit order (month before day) verified consistent across all four Tier 1 tables. Upper bound deliberately left open: a live, continuously-advancing ICES Datacenter 'last recalculated' stamp, not submitted by data providers, so a fixed max would go stale immediately. Lower bound is this table's own verified minimum -- NOT forced identical across tables the way SweepLngt/HaulNo/Year are, since a genuine table-specific difference is plausible here (confirmed: LT's own minimum is years later). A -9 sentinel (1,050,496 rows, 7.64% of non-null; already excluded by the lower bound above) reads as the standard DATRAS 'not recorded' convention for this server-computed field -- not yet (re)calculated for this record."),
  list(table = "CA", field = "DateofCalculation", type = "number(ordinal)", range = list(20120419L, Inf),
       details = "8-digit YYYYMMDD stamp, digit order (month before day) verified consistent across all four Tier 1 tables. Upper bound deliberately left open: a live, continuously-advancing ICES Datacenter 'last recalculated' stamp, not submitted by data providers, so a fixed max would go stale immediately. Lower bound is this table's own verified minimum -- NOT forced identical across tables the way SweepLngt/HaulNo/Year are, since a genuine table-specific difference is plausible here (confirmed: LT's own minimum is years later). A -9 sentinel (337,562 rows, 5.76% of non-null; already excluded by the lower bound above) reads as the standard DATRAS 'not recorded' convention for this server-computed field -- not yet (re)calculated for this record."),
  list(table = "LT", field = "DateofCalculation", type = "number(ordinal)", range = list(20151127L, Inf),
       details = "Same open-upper-bound, ICES-Datacenter-inserted basis as HH/HL/CA's DateofCalculation, but this table's OWN verified minimum (2015-11-27) is genuinely years later than theirs (2012-04-19) -- consistent with LT/litter reporting being a newer addition to DATRAS than the main haul/length/age exchange."),

  # ---- HL (remaining fields) ----------------------------------------------
  list(table = "HL", field = "SpecCode", type = "number(id)",
       examples = c(55L, 122388L, 127196L, 159048L, 1789435L),
       constraints = list("required"),
       details = "Official WoRMS AphiaID as submitted by the data provider -- contrast with Valid_Aphia, the ICES Datacenter's own validated/corrected version of the same concept, inserted server-side (see Valid_Aphia's own details below)."),
  list(table = "HL", field = "CatIdentifier", type = "enum",
       values = get_vocab_enum_values("TS_CatIdentifier"),
       details = paste(
         "icesVocab's TS_CatIdentifier resolves this as a controlled, leveled code",
         "list (56 active codes: '1. Level' through '55. Level', plus a",
         "'-9'/'Unknown' sentinel) -- not an open numeric ID, confirming this",
         "field's own already-documented shape (a coded scheme, not a sequence,",
         "verified 2026-07-29 against the full archive; not this field's own",
         "values map until the full-field vocab sweep found it,",
         "data-raw/build_vocab_field_audit.R, Issue 9). Re-checked 2026-08-10 --",
         "but against data an archive-pipeline bug (known-issues.yaml's",
         "sentinel_replacement_data_loss) had already silently scrubbed -9 out of:",
         "at the time, 13 real distinct values were found, not including -9.",
         "Re-verified 2026-08-16 after that bug's fix: 14 real distinct values",
         "(-9, 1-5, 11-14, 21-23, 31), still zero gaps against the vocab's 56",
         "codes either direction; 42 of the 56 are valid ICES definitions not yet",
         "observed in this archive. Live WSDL (getHLdata) declares this field int,",
         "not string -- an accepted, permanent M01 divergence between the",
         "WSDL-driven archive and this curated enum spec (see Valid_Aphia's own",
         "note for the general pattern), not a bug to fix by changing either side."
       )),
  list(table = "HL", field = "TotalNo", type = "number(quantity)", range = c(0, 3581592),
       details = "Per the field's own description, TotalNo=SUM(HLNoAtLngt); values in the hundreds of thousands and non-integer values (7.7% of populated rows) both trace to the same documented mechanism -- DataType C records are standardised to 60 minutes, which can inflate very abundant small-bodied catches to large, non-integer counts. Top values all have real support (9-30 occurrences each, a smooth tail), not isolated errors."),
  list(table = "HL", field = "NoMeas", type = "number(quantity)", range = c(0, 578731),
       details = "Same DataType C standardisation basis as TotalNo above; top values are all well-supported (4-10 occurrences each), not isolated errors."),
  list(table = "HL", field = "SubFactor", type = "number(quantity)", range = c(1, 10997.1834),
       details = "356 of 14,256,091 rows (0.0025%) show values below 1, contradicting the field's own description (documented as always >=1, for every DataType) -- excluded. The high end is genuine, not an error: top values cluster at power-of-2-like numbers (4096 recurs 133 times; 8192, 5120, 6144 also recur with real support), consistent with repeatedly halving a very abundant catch to reach a manageable subsample."),
  list(table = "HL", field = "SubWgt", type = "number(quantity)", units = "g", range = c(0, 3519200)),
  list(table = "HL", field = "CatCatchWgt", type = "number(quantity)", units = "g", range = c(0, 35568000),
       details = "-900 (2562 rows) and -100 (1 row) are excluded as a 'not weighed' placeholder, the same pattern seen in several HH fields. The high end is genuine: top values all have real support (3-18 occurrences each)."),
  list(table = "HL", field = "LngtClass", type = "number(quantity)", range = c(0, 4500),
       details = "Unit varies by the sibling LngtCode field (mm or cm; see LngtCode's own values map), so no fixed units here. Two isolated outliers excluded, 2026-07-29: 11930 (LngtCode '.', i.e. 11.93m) and 900 (LngtCode '1', i.e. 9m) -- each a lone occurrence far above the next-highest real value. Everything else, including a cluster around 420-460 under LngtCode '1' (4.2-4.6m -- large but not implausible for occasional large elasmobranch/tuna bycatch), is kept as-is: this is a first curation pass from data patterns alone, not a domain-expert review, and a tighter bound wasn't asserted without one. CA's own LngtClass is curated separately (a different sampling population, not assumed identical -- see CA's own pass).",
       todo = "Confirm with a domain expert whether the 420-460 (4.2-4.6m) cluster is genuinely plausible occasional large elasmobranch/tuna bycatch, or should be excluded like the two isolated outliers above it."),
  list(table = "HL", field = "HLNoAtLngt", type = "number(quantity)", range = c(0, 940339.35),
       details = "Same DataType C standardisation basis as TotalNo above. Top values are each a unique one-off but decline smoothly with no marker/gap pattern, consistent with genuine (if rare) very large hauls of abundant small-bodied species. CA's own NumberAtLength (CANoAtLngt) is curated separately (a different sampling population -- aged individuals only, not the whole catch -- so not assumed identical)."),
  list(table = "HL", field = "Valid_Aphia",
       examples = c(55L, 117258L, 126757L, 140474L, 1895010L)),

  # ---- CA (remaining fields) -----------------------------------------------
  # `examples` fill for CA's own remaining S07 findings, 2026-07-29 (TODO.md's
  # "remaining ~18" item) -- same real-archive-verified approach as the
  # string-field pass above. GenSamp/StomSamp/ParSamp are retyped enum: each
  # is a 100%-clean two-value split (Y/N, zero exceptions across 800k+
  # non-null rows) AND the seed's own description ("Flag whether X was
  # taken/performed") independently confirms boolean intent -- same
  # evidentiary bar as RecordType. `values` is the ARRAY form (`["Y", "N"]`),
  # not a labelled map (`{Y: Yes, N: No}`): the map form hits
  # tidyverse/data-dict#144 too, just via a different trigger than
  # ThermoCline's -- confirmed 2026-07-29 by testing both forms directly
  # against the CLI. quarto-yaml discards quote style the same way for
  # boolean-looking words as for numeric-looking ones, so a quoted 'N' gets
  # re-read as YAML 1.1's boolean false, not the string "N"; the array form
  # sidesteps it exactly like #144's own writeup predicted for the
  # array/map asymmetry. The rest
  # stay `string` + `examples` even where the observed set looks small
  # (AreaType: 17 values; IndividualMaturity/Maturity: 48) because, unlike
  # the flags, nothing here rules out a wider true domain than this one
  # archive happens to show, and none of these fields carry an ICES-sourced
  # description confirming a complete code list the way Quarter/DayNight's
  # icesVocab-backed enums do -- inventing closure would risk the same
  # mistake the numeric `range` philosophy above already warns against
  # (describing "what was observed" as if it were "the full valid domain").
  list(table = "CA", field = "AreaType",
       examples = list("0", "13", "2", "12", "6"),
       details = "Field's own description ('Age sampling aggregation level') doesn't explain what the codes themselves mean, but icesVocab's TS_AreaType resolves them (checked 2026-07-29, data-raw/datras_vocabulary.R): '0'=ICES Statistical Rectangles, '2'=Standard NS Roundfish Areas, '6'=EVHOE areas, '12'=Spanish North Areas, '13'=ICES Divisions. Not retyped enum because TS_AreaType has 27 official codes total, over the seed's own VOCAB_CODE_LIMIT (20, data-raw/spec_01_seed_dict.R) for a usable `values` map -- and confirms the true domain genuinely is wider than what's observed here (17 of 27 codes appear in this archive). The name-match check above never tested real-data sentinel coverage: checked 2026-08-17 directly against .datras/CA.parquet (5,865,076 rows), -9 is present and substantial (1,968,019 rows, 33.55%), 0 true nulls -- not previously documented either way."),
  list(table = "CA", field = "AreaCode",
       examples = list("VIa", "38G3", "43G1", "37G1", "44G0"),
       details = "Field's own description says coding is 'according to AreaType' (its sibling field) -- meaning depends on that field's own value, same pattern as LngtClass/LngtCode. Codes mix ICES-area style (VIIg) and rectangle-like style (38G3). Originally verified 2026-07-29 against obus's own icesDatras-fetched archive, whose parseDatras(fix_types=TRUE) scrubs literal -9 to NA before opus ever sees it (same caveat as GenSamp/StomSamp/ParSamp/AgeSource below) -- framed then as '1,898,151 of 5,966,950 rows unpopulated', which undercounted the true picture: re-verified 2026-08-17 directly against .datras/CA.parquet (5,865,076 rows), -9 is present and dominant (1,891,107 rows, 32.24%), not a null. No icesVocab entry exists for this field under any name (checked against all 580 registered keys)."),
  list(table = "CA", field = "Maturity",
       examples = list("61", "62", "1", "2", "B"),
       details = "Field's own description says the scheme depends on the sibling MaturityScale field ('MaturityScale should be filled in when...') -- explains the observed mix of numeric (61, 62, 1, 2) and letter (B, A) codes, different maturity scales using different code sets, not an inconsistency. Originally verified 2026-07-29 against obus's own pre-fix icesDatras archive (same sentinel-scrubbing caveat as GenSamp below) -- framed then as '3,173,580 rows unpopulated'. Re-verified 2026-08-17 directly against .datras/CA.parquet (5,865,076 rows): -9 is present and dominant (3,100,723 rows, 52.87%), not a null -- 0 true nulls in the current archive."),
  list(table = "CA", field = "FishID",
       examples = list("1", "2", "3", "4", "5"),
       details = "Field's own description ('Fish identification number - running sampling number of the specimen') confirms a real per-specimen sequence, open-ended and illustrative only, not an exhaustive domain. Originally verified 2026-07-29 against obus's own icesDatras-fetched archive, whose parseDatras(fix_types=TRUE) scrubs literal -9 to NA before opus ever sees it (same caveat as GenSamp/StomSamp/ParSamp/AgeSource below) -- framed then as 'only ~18.7% of rows populated', which was really the same sentinel misread: re-verified 2026-08-17 directly against .datras/CA.parquet (5,865,076 rows), -9 is present and dominant (4,747,074 rows, 80.94%), not a null; real per-specimen IDs make up the remaining ~19%. No icesVocab entry exists for this field under any name (checked against all 580 registered keys) -- expected for a plain sequential identifier, not a coded field."),
  list(table = "CA", field = "GenSamp", type = "enum",
       values = list("-9", "Y", "N"),
       details = "Field's own description ('Flag whether genetic sample was taken') confirms boolean intent. Originally verified 2026-07-29 as a clean two-value Y/N split with zero -9 -- but that check ran against obus's own icesDatras-fetched archive, whose parseDatras(fix_types=TRUE) unconditionally scrubs literal -9 to NA for every numeric-looking column regardless of whether -9 is that field's own documented sentinel (see this file's own header, and known-issues.yaml's sentinel_replacement_data_loss for the analogous bug in opus's own now-fixed pipeline). Re-verified 2026-08-16 directly against the independently-built .datras/CA.parquet (5,865,076 rows): -9 is present and dominant (5,021,736 rows, 85.6%), not absent; N: 829,547 (14.1%); Y: 13,793 (0.24%); zero other values. No icesVocab entry exists for this field under either name (ICES_ISSUE_REPORT.md Issue 8's own table already records this as 'no vocab exists') -- -9 reads as the standard generic-missing sentinel, the only meaning a simple boolean flag has room for."),
  list(table = "CA", field = "StomSamp", type = "enum",
       values = list("-9", "Y", "N"),
       details = "Field's own description ('Flag whether stomach sampling was performed') confirms boolean intent. Originally verified 2026-07-29 as a clean two-value Y/N split with zero -9 -- same obus/icesDatras fix_types=TRUE scrubbing caveat as GenSamp above. Re-verified 2026-08-16 directly against .datras/CA.parquet: -9 is present and dominant (4,861,583 rows, 82.9%); N: 964,090 (16.4%); Y: 39,403 (0.67%); zero other values. Same 'no vocab exists' / generic-missing reasoning as GenSamp above."),
  list(table = "CA", field = "ParSamp", type = "enum",
       values = list("-9", "Y", "N"),
       details = "Field's own description ('Flag whether parasites sampling was performed') confirms boolean intent. Originally verified 2026-07-29 as a clean two-value Y/N split with zero -9 -- same obus/icesDatras fix_types=TRUE scrubbing caveat as GenSamp above. Re-verified 2026-08-16 directly against .datras/CA.parquet: -9 is present and dominant (4,948,612 rows, 84.4%); N: 839,844 (14.3%); Y: 76,620 (1.31%); zero other values. Same 'no vocab exists' / generic-missing reasoning as GenSamp above."),
  list(table = "CA", field = "AgeSource", type = "enum",
       values = get_vocab_enum_values("SampleType"),
       details = "Seeded from TS_AgeSource (name-match to the field, per ICES_ISSUE_REPORT.md Issue 8's own table -- '-9, LB, OT, SC, VR'), but that key's OWN icesVocab description is a redirect: 'see SampleType', not an authoritative code list in its own right. Real CA archive data (verified 2026-08-16): only -9 (4,757,200 rows) and the literal word 'otolith' (1,107,876 rows, lowercase) appear -- zero overlap with TS_AgeSource's LB/OT/SC/VR codes, contradicting Issue 8's 'full match' verdict for this field (that check evidently name-matched TS_AgeSource without testing per-code archive coverage). SampleType (bare prefix, the redirect target) resolves the discrepancy exactly: its own code list includes 'otolith' verbatim, lowercase, as the code itself (not just the description) -- an exact match, not a coincidence. Candidate for correcting Issue 8's table and inst/DATRAS-vocab-correction.csv; not an ICES-reportable gap in the vocab's actual coverage, since icesVocab does have the right codes once the redirect is followed."),
  list(table = "CA", field = "AgePrepMet", type = "enum",
       values = get_vocab_enum_values("PreparationMethod"),
       details = "Same redirect pattern as AgeSource above: seeded from TS_AgePrepMet (name-match, Issue 8's table -- '-9, BK, BR, CP, NO, WA, WO'), but that key's own icesVocab description says 'see PreparationMethod', not an authoritative list itself. Real CA archive data (verified 2026-08-16): -9, AL, ALEt, ALR, BB, Br, SS, Se -- zero overlap with TS_AgePrepMet's codes, contradicting Issue 8's 'full match' verdict here too. PreparationMethod (bare prefix, the redirect target, 48 codes) contains every one of these real values exactly. Same candidate-for-correction note as AgeSource above -- an opus-side vocab-key resolution fix, not an ICES-reportable gap."),
  list(table = "CA", field = "SpecCode", type = "number(id)",
       examples = c(213L, 126326L, 127118L, 158513L, 1667212L),
       constraints = list("required"),
       details = "Official WoRMS AphiaID as submitted by the data provider -- contrast with Valid_Aphia, the ICES Datacenter's own validated/corrected version of the same concept, inserted server-side (see Valid_Aphia's own details below)."),
  list(table = "CA", field = "Valid_Aphia",
       examples = c(213L, 105872L, 126412L, 141452L, 1667212L),
       details = "CA's own instance was missed when HL's Valid_Aphia was originally filled (found 2026-07-29 via validate-spec's S07 check) -- same concept as HL's Valid_Aphia (ICES Datacenter's validated AphiaID) but a different sampling population (aged individuals only), so queried independently rather than assumed identical (Working principles, rule 12). 667 distinct values, 0 unpopulated (always present). Verified 2026-07-29 against the full CA archive."),
  list(table = "CA", field = "LngtClass", type = "number(quantity)", range = c(0, 5630),
       details = "Unit varies by the sibling LngtCode field (mm or cm; see LngtCode's own values map), so no fixed units here. One isolated outlier excluded, 2026-07-29: 932 (LngtCode '1', i.e. 9.32m) -- a lone occurrence with a 2.3x gap to the next-highest value (405). Curated separately from HL's own LngtClass: CA's population is aged individuals only, a different (and differently distributed) subset from HL's whole-catch length-frequency tally, so the two are not assumed identical (Working principles, rule 12)."),
  list(table = "CA", field = "GearEx",
       details = paste(
         "Mostly a copy of HH's own GearExceptions for the same haul (92.27% of",
         "5,563,036 matched non-null rows identical, checked 2026-08-16), but in",
         "430,289 rows (7.73%) CA carries a real code (S, SB, B, D, MY, R, or",
         "MN) where HH has only the generic '-9' placeholder for the same",
         "haul -- CA never contradicts a real HH code, only supplements HH's",
         "own '-9' with something more specific. Not forced identical to HH's",
         "spec as a result (contrast SwellHeight above, a genuine byte-for-byte",
         "copy): this field carries real information HH's own copy doesn't have."
       )),
  list(table = "CA", field = "Age", type = "number(quantity)", units = "years", range = c(0, 99),
       details = paste(
         "-9 (1,995,814 rows, 34.03% of all 5,865,076 CA rows -- not visible until an unrelated",
         "archive-pipeline bug that had been silently converting it to NA was fixed 2026-08-16) reads as",
         "the standard DATRAS 'not recorded' convention and is excluded on the same basis as the -1/-5/-95",
         "cluster below, just far larger. -1 (1757 rows) reads as a systematic, undocumented 'not",
         "determined' sentinel; -5 and -95 (1 row",
         "each) are isolated anomalies -- all three excluded. 99 (54 rows) is kept: real, repeated support,",
         "not a fluke -- reads like a plus-group/max-age reporting convention, though that mechanism isn't",
         "confirmed here, just noted as an observation.",
         "ICES's getDatrasFieldList documents a field 'IndividualAge' for CA, paired with old-name",
         "'AgeRings' -- but 'AgeRings' is not a real CA field (verified 2026-08-06 against both the archive",
         "and getCAdata's own live ASMX response; the real field is 'Age', used here). Since that row's",
         "old-name half is already wrong, its proposed new name isn't trusted either. Filed with ICES;",
         "not yet resolved upstream."
       ),
       todo = "Confirm with a domain expert whether Age=99 (54 rows) is a genuine plus-group/max-age reporting convention, or should be treated as a placeholder like the -1/-5/-9/-95 sentinels above."),
  list(table = "CA", field = "CANoAtLngt", type = "number(quantity)", range = c(1, 218),
       details = "Distinct population from HL's own NumberAtLength (HLNoAtLngt): this counts aged individuals only, not the whole catch, hence the much smaller scale -- not assumed identical (Working principles, rule 12)."),
  list(table = "CA", field = "IndWgt", type = "number(quantity)", units = "g", range = c(0, 97000)),

  # ---- LT (remaining fields not shared with HH) ---------------------------
  # 24 of LT's 27 bare `number` fields turned out to be exact HH duplicates
  # (found 2026-07-29 comparing field lists) and are handled once, in
  # shared_field_specs below. Depth and BottomDepth (LT's own two separate,
  # byte-duplicate real columns, see the dedicated block above) plus
  # LT_Weight/LT_Items are the genuinely LT-specific entries here.
  #
  # The 9 `examples` fills directly below (OSPARArea through EEZ) are
  # LT-specific litter/area classification fields, TODO.md's "remaining ~18"
  # item, 2026-07-29 -- none carry an ICES-sourced description (confirmed:
  # all nine are bare `string` with no `description` at all in the seed), so
  # none are retyped enum even where the observed set is small (MSFDArea: 2
  # values; UnitItem: 1) -- same reasoning as CA's AreaType/Maturity
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
       details = "Litter parameter/category code, no description present. icesVocab resolves a PARAM list (checked 2026-07-29, data-raw/datras_vocabulary.R) -- 'LT-TOT'='Litter - total' confirmed there among 1,938 total codes -- but 'A2'/'A3'/'A5'/'A6'/'A7'/'A14' do NOT appear in it under any description, despite being common real values here (checked directly, not just absent from a sample). A real discrepancy between this archive's own PARAM usage and icesVocab's published list. Not retyped enum regardless: 1,938 codes is far past the seed's VOCAB_CODE_LIMIT of 20. 50 distinct values, 2 of 79,451 rows unpopulated. Verified 2026-07-29 against the full LT archive.",
       todo = "File A2/A3/A5/A6/A7/A14 (undocumented in icesVocab's 1,938-code PARAM list despite being common real values) as a DATRAS-known-issues.yaml entry and ICES_ISSUE_REPORT.md candidate."),
  list(table = "LT", field = "LTSZC",
       examples = list("A", "B", "C", "D", "13"),
       details = "Litter size class code (mix of letter and numeric codes), no description present. icesVocab's LTSZC list confirms all five (checked 2026-07-29): 'A'='squared centimetre <5*5cm=25cm2' through 'D'='<50*50cm=2500cm2' (area-based classes), '13'='centimetre 15-49.99cm' (a length-based class) -- two different measurement bases coexisting under one code list. 23 of 41 official codes observed here; not retyped enum since 41 exceeds the seed's VOCAB_CODE_LIMIT of 20. Originally verified 2026-07-29 against obus's own pre-fix icesDatras archive (same sentinel-scrubbing caveat as GenSamp below) -- framed then as '16,508 rows unpopulated'. Re-verified 2026-08-17 directly against .datras/LT.parquet (75,310 rows): -9 is present (14,736 rows, 19.57%), not a null -- 0 true nulls in the current archive."),
  list(table = "LT", field = "UnitWgt",
       examples = list("kg/haul", "g/haul"),
       details = "Unit of the sibling LT_Weight field (see LT_Weight's own details below); exactly 2 real values observed (kg/haul, g/haul). No description present to confirm this is the complete valid unit set. Originally verified 2026-07-29 against obus's own pre-fix icesDatras archive (same sentinel-scrubbing caveat as GenSamp below) -- framed then as '4,256 rows unpopulated'. Re-verified 2026-08-17 directly against .datras/LT.parquet (75,310 rows): -9 is present (4,144 rows, 5.50%), not a null -- 0 true nulls in the current archive."),
  list(table = "LT", field = "UnitItem",
       examples = list("items/haul"),
       details = "Unit of the sibling LT_Items field (see LT_Items's own details below); only one real value ever observed -- a single example, not five, because no second real value exists in the archive to show. Originally verified 2026-07-29 against obus's own pre-fix icesDatras archive (same sentinel-scrubbing caveat as GenSamp below) -- framed then as '36 rows unpopulated'. Re-verified 2026-08-17 directly against .datras/LT.parquet: -9 accounts for exactly those 36 rows, not a null -- 0 true nulls in the current archive."),
  list(table = "LT", field = "TYPPL",
       examples = list("PE", "PP", "PET", "PS", "UPL"),
       details = "Litter (plastic) type code, no description present. icesVocab's TYPPL list confirms all five (checked 2026-07-29): PE=Polyethylene, PET=Polyethylene terephthalate, PP=Polypropylene, PS=Polystyrene, UPL=Undefined plastic. 6 of 30 official codes observed here; not retyped enum since 30 exceeds the seed's VOCAB_CODE_LIMIT of 20. Originally verified 2026-07-29 against obus's own pre-fix icesDatras archive (same sentinel-scrubbing caveat as GenSamp below) -- framed then as 'very sparse: only 162 of 79,451 rows populated', which badly understated the true picture: the other 79,289 rows weren't absent, they were the -9 sentinel, scrubbed to NA before that check ever saw them. Re-verified 2026-08-17 directly against .datras/LT.parquet (75,310 rows): -9 is present and overwhelmingly dominant (75,148 rows, 99.79%), 0 true nulls -- the 162 real plastic-type codes are the rare case, not the norm."),
  list(table = "LT", field = "LTPRP",
       examples = list("AO", "CL1", "CL5", "CL2", "CL4"),
       details = "Litter property code, no description present. icesVocab's LTPRP list confirms all five as BASE codes (checked 2026-07-29): AO=Attached organisms, CL1=Colour-None(clear), CL2=Colour-Black, CL4=Colour-Blue, CL5=Colour-White -- only 22 official base codes, but composite codes like 'CL1~AO' also appear in real data (a colour code plus an attached-organisms flag, tilde-joined), which is why 79 distinct values are observed here despite only 22 base codes existing -- a combinable/multi-value scheme, not a flat single-select list, confirming the earlier guess. Not retyped enum: even the 22-code base list is past the seed's VOCAB_CODE_LIMIT of 20, and the combinable form isn't a plain enum shape regardless. Originally verified 2026-07-29 against obus's own pre-fix icesDatras archive (same sentinel-scrubbing caveat as GenSamp below) -- framed then as '58,349 rows unpopulated'. Re-verified 2026-08-17 directly against .datras/LT.parquet (75,310 rows): -9 is present and dominant (54,208 rows, 71.97%), not a null -- 0 true nulls in the current archive."),
  list(table = "LT", field = "EEZ",
       examples = list("United Kingdom Exclusive Economic Zone", "Danish Exclusive Economic Zone", "French Exclusive Economic Zone", "Spanish Exclusive Economic Zone", "Swedish Exclusive Economic Zone"),
       details = "Exclusive Economic Zone name, no description present. 20 distinct values, 162 of 79,451 rows unpopulated. Not treated as a closed set -- EEZ coverage in a wider archive could plausibly include zones absent from this one. Verified 2026-07-29 against the full LT archive."),
  list(table = "LT", field = "NMArea",
       examples = list("United Kingdom 12 NM", "Swedish 12 NM", "Spanish 12 NM", "French 12 NM", "Danish 12 NM"),
       details = "National 12-nautical-mile zone name (sibling concept to EEZ above), no description present. 18 distinct values, 53,303 of 79,451 rows unpopulated. Not treated as a closed set, same reasoning as EEZ. Found 2026-07-29 only after fixing the Y/N-enum crash above -- validate-spec had never actually reached this field before, since it's the table's last column and everything upstream of it kept dying first (ThermoCline, then the flag enums). Verified 2026-07-29 against the full LT archive."),

  list(table = "LT", field = "Depth", type = "number(quantity)", units = "m", range = c(1, 3098),
       details = "Re-verified 2026-08-06 (originally 2026-07-29, against an older LT archive snapshot whose row count differs from the current one -- re-checked here to avoid repeating a stale figure): byte-for-byte identical to this table's own BottomDepth across all 75,310 rows (100% populated in both, 0 differences, 0 one-sided nulls) -- a known ICES-side redundancy (also documented in obus's own download-stage comments), not an opus/obus naming quirk. Filed with ICES 2026-08-06 (see data-raw/ICES_ISSUE_REPORT.md, Issue 6). Given the same type/units/range as BottomDepth here rather than re-derived independently, since it is BottomDepth."),
  list(table = "LT", field = "LT_Weight", type = "number(quantity)", range = c(0, 1600000),
       details = "Unit varies by the sibling UnitWgt field (kg/haul for 46,673 rows, g/haul for 24,383, unspecified for 276), so no fixed units here. Two exclusions, 2026-07-29: -99 (3 rows, kg/haul) as an isolated sentinel-like anomaly, and 46,318,000 (1 row, g/haul) as a lone outlier roughly 29x the next-highest real value (1,600,000) -- an implausible ~46 tonnes of litter in one haul, almost certainly a data-entry error. The rest of the g/haul group's own large values (up to 1,600,000g = 1.6 tonnes) are kept: rare, but large litter catches (e.g. old fishing gear, major debris items) are plausible."),
  list(table = "LT", field = "LT_Items", type = "number(quantity)", range = c(0, 2323),
       details = "UnitItem is 'items/haul' for all but 36 of 76,882 populated rows -- effectively a fixed count, no exclusions needed: no isolated outlier or repeating marker pattern, just a smooth decline from the max."),

  # Four fields whose seed-stage `values` already include -9, at high real
  # prevalence (70-99.9%), but where a live icesVocab check (2026-08-16,
  # via each field's own resolved key) finds either no vocab key at all or
  # a resolved key with no -9 code -- unlike the ~20 other enum fields
  # checked the same day, where -9 resolves to a real, if generic,
  # "missing/unknown"-style label. -9 has never been externally confirmed
  # as a genuine code for these four; it may simply be the raw archive's
  # standard sentinel, swept into the seed's observed-values list without
  # anyone distinguishing "real code" from "generic missing value" -- see
  # vignettes/articles/technical-notes.md's own note on this sweep.
  list(table = "HL", field = "DevStage",
       todo = "Confirm whether -9 (99.80% of non-null rows) is a genuine DevelopmentStage code or just the generic missing-value sentinel -- no icesVocab key resolves for this field under either name, so nothing external confirms it either way."),
  list(table = "HL", field = "LenMeasType",
       todo = "Confirm whether -9 (71.59% of non-null rows) is a genuine LengthType code or just the generic missing-value sentinel -- no icesVocab key resolves for this field under either name, so nothing external confirms it either way."),
  list(table = "CA", field = "PlusGr",
       todo = "Confirm whether -9 (99.92% of non-null rows) is a genuine AgePlusGroup code or just the generic missing-value sentinel -- the resolved vocab key (AC_AgePlusGroup) has no -9 code at all, so nothing external confirms it either way."),
  list(table = "HL", field = "LngtCode",
       todo = "Confirm whether -9 (2.69% of non-null rows) is a genuine LengthCode code or just the generic missing-value sentinel -- no icesVocab key resolves for this field under either name, so nothing external confirms it either way."),
  list(table = "CA", field = "LngtCode",
       todo = "Confirm whether -9 is a genuine LengthCode code or just the generic missing-value sentinel -- no icesVocab key resolves for this field under either name, so nothing external confirms it either way.")
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
# Keyed by legacy field name -- checked exhaustively 2026-08-09 (all 40
# entries below cross-referenced against op_datras_field_list()'s per-table
# old_name): 39/40 have exactly one legacy name shared by every table that
# has the field, so the "apply to whichever table has a column with this
# name" mechanism carries over unchanged. The one exception (BottomDepth,
# HH's own legacy name "Depth" vs LT's own genuinely separate "BottomDepth"
# column) is handled as two explicit per-table field_specs entries above,
# not here.
#
# 24 of these entries were promoted here 2026-07-29 while curating LT:
# comparing LT's remaining bare `number` fields against HH's own found only
# three genuinely LT-specific fields (Depth/BottomDepth -- see the dedicated
# block in field_specs above -- plus LT_Weight/LT_Items, which have no HH
# counterpart at all); everything else LT still had bare was already an HH
# field, re-deriving it from LT's own subset alone would have repeated the
# exact mistake this rule exists to prevent.
#
# NOT every field shared by name gets this treatment -- two exceptions found
# 2026-07-29 while curating HL, both left as per-table field_specs entries
# instead:
#   - A field can describe a genuinely different POPULATION per table even
#     under the same name -- e.g. LngtClass/NumberAtLength mean "the whole
#     catch's length-frequency distribution" in HL (HLNoAtLngt) but "the
#     aged subsample only" in CA (CANoAtLngt) -- a much smaller, differently-
#     scaled set of values, and not even the same legacy name across tables.
#   - DateofCalculation recurs everywhere but its own minimum can genuinely
#     differ per table (LT's reporting began years later) -- see its own
#     block in field_specs above.
#
# data-dict.yaml's own spec has no mechanism for defining a column once and
# reusing it across tables (confirmed 2026-07-29 against site/spec.md --
# every table's `columns` list is fully independent); this list is how
# opus's OWN generation script enforces the consistency the shipped YAML
# itself cannot.

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
  # `type: enum`, which would wrongly closed-list them (unlike RecordType
  # above, which really is a fixed, closed, one-value-per-table tag).
  list(field = "Survey", examples = list("NS-IBTS", "BTS", "BITS", "DYFS", "Can-Mar"),
       details = "29 distinct values in HH's archive (verified 2026-07-29); ICES DATRAS survey acronym, an open list, not a fixed enum. icesVocab DOES resolve a 'Survey' key by name (checked 2026-07-29, data-raw/datras_vocabulary.R) but it's a false lead, not this field's source: its 133 codes are ICES's own cross-domain internal survey IDs (e.g. 'A1012'), a completely different scheme from DATRAS's own short acronyms -- confirmed by checking real codes against it directly, not assumed. Not used."),
  list(field = "Country", examples = list("NL", "DE", "GB", "DK", "GB-SCT"),
       details = "22 distinct values in HH's archive (verified 2026-07-29); 'GB-SCT' illustrates that this is ISO 3166 codes PLUS ICES's own sub-national region codes (per the field's own description), not plain ISO 3166 alone. icesVocab DOES resolve a 'TS_Country' key by name (checked 2026-07-29) but it's a false lead too, same as Survey above: its 25 codes are 3-letter (e.g. 'BEL', 'DEN', 'ENG'), a different scheme entirely from this field's own 2-letter-plus-region codes -- confirmed by checking real codes against it directly. Not used."),
  list(field = "Gear", type = "enum", values = get_vocab_enum_values("Gear"),
       details = "All 99 active icesVocab Gear Type codes (deprecated code OTG excluded, 2026-08-02). 55 confirmed used in DATRAS archive; 44 additional codes are valid ICES definitions (may be used in future submissions or by other surveys). Each code has a full description in icesVocab. Validation: enum restricts submissions to these codes."),
  list(field = "Ship", examples = list("74E9", "26D4", "748S", "64SS", "18NE"),
       details = "110 distinct values in HH's archive (verified 2026-07-29); SeaDataNet ship/platform codes, an open list, not a fixed enum."),
  list(field = "StNo", examples = list("1", "2", "22", "9", "17"),
       details = "Field's own description says this is a national coding system, not defined by ICES -- examples show the common shape (short numeric-looking strings), not an exhaustive domain; not a coded field, so no icesVocab entry is expected (confirmed 2026-08-17 against all 580 registered keys). Originally verified 2026-07-29 against obus's own icesDatras-fetched archive, whose parseDatras(fix_types=TRUE) scrubs literal -9 to NA before opus ever sees it (same caveat as GenSamp/StomSamp/ParSamp/AgeSource below) -- framed then as '6,899 of 150,262 rows unpopulated', which was really the same sentinel misread: re-verified 2026-08-17 directly against .datras/HH.parquet (145,958 rows, 20,319 distinct values), -9 accounts for exactly those 6,899 rows, not a null. ICES's own field-description spreadsheet (data-raw/build_field_description_snapshot.R) confirms the ICES-wide '-9 = no information' convention applies here, same as HaulNo above. Unlike HaulNo's own -9 sentinel, this isn't an orphaning problem: CA's own matching StNo=-9 rows for these same hauls (191,893 rows, verified 2026-08-17) join HH successfully via the other 7 composite-key fields, since both sides consistently carry -9 for the same haul rather than disagreeing."),
  list(field = "StatRec", examples = list("37F8", "35F5", "36F7", "32F3", "36F6"),
       details = "Real ICES statistical rectangle codes (0.5 deg lat x 1 deg lon grid), not a fixed enum given the size of the grid -- independently corroborated 2026-08-17 by ICES's own field-description spreadsheet, which describes this field via the same geometric grid rule rather than a code list (data-raw/build_field_description_snapshot.R). Only present in HH and LT (confirmed 2026-07-29) -- consistent with LT's assessment output joining in a set of HH-style columns. Originally verified 2026-07-29 against obus's own icesDatras-fetched archive, whose parseDatras(fix_types=TRUE) scrubs literal -9 to NA before opus ever sees it (same caveat as GenSamp/StomSamp/ParSamp/AgeSource below) -- framed then as '12,235 of 150,262 HH rows unpopulated', which was really the same sentinel misread: re-verified 2026-08-17 directly against .datras/HH.parquet (145,958 rows, 685 distinct values), -9 accounts for exactly those 12,235 rows, not a null."),
  list(field = "TimeShot", examples = list("730", "715", "1300", "900", "700"),
       details = "1,440 distinct values in HH's archive (verified 2026-07-29), always populated (150,262/150,262). Field's own description implies a fixed 4-digit HHMM ('E.g. 10:15=1015'), but real values are NOT zero-padded (e.g. '730', not '0730') -- documented here rather than silently assumed. Only present in HH and LT (confirmed 2026-07-29), same as StatRec above."),

  list(field = "SweepLngt", type = "number(quantity)", units = "m", range = c(0, 850)),
  list(field = "HaulNo", type = "number(ordinal)", range = c(0, 82483),
       constraints = list("required"),
       details = "Sequential per-cruise numbering, but countries vary in whether it resets each cruise or runs continuously -- the archive-wide range spans many cruises' own counts pooled together, not one cruise's own haul tally. No icesVocab entry exists under any name or prefix (confirmed 2026-08-17 against all 580 registered keys) -- expected for a plain sequential identifier, not a coded field. ICES's own field-description spreadsheet (data-raw/build_field_description_snapshot.R) confirms Mandatory: Yes and documents an ICES-wide convention applicable to any field with a header: submit -9 for 'no information' -- so the -9 sentinel seen in CA (DATRAS-known-issues.yaml: ca_haulno_unlinkable_to_hh) is a sanctioned value, not an undocumented one."),
  list(field = "Year", type = "number(ordinal)", range = c(1965, 2026),
       constraints = list("required")),
  list(field = "Day", type = "number(ordinal)", range = c(1, 31),
       constraints = list("required")),
  list(field = "HaulDur", type = "number(quantity)", units = "min", range = c(1, 120),
       details = "A haul cannot take zero or negative time; 217 rows recorded as exactly 0 and 2 as negative (-514, -238) are excluded, most likely unrecorded/placeholder rather than a genuine instantaneous haul. Upper bound set at 2 hours: DATRAS carries no passive/soak gear, so a longer tow is highly suspect -- observed values run as high as 1470 min with no repeating marker pattern (i.e. not a clean sentinel, just unreliable). Verified 2026-07-29 against the full archive."),
  list(field = "ShootLat", type = "number(quantity)", units = "decimal degrees", range = c(36.0013, 76.2117)),
  list(field = "ShootLong", type = "number(quantity)", units = "decimal degrees", range = c(-67.7115, 24.4333),
       details = "A genuine value of exactly -9.0000 degrees (9 deg W, an ordinary DATRAS longitude off Ireland/Iberia) would be indistinguishable from missing here: icesDatras's fetch pipeline scrubs literal -9 to NA for every numeric column, not just where -9 is a documented sentinel -- see data-raw/tier1_field_stats.R's header."),
  list(field = "HaulLat", type = "number(quantity)", units = "decimal degrees", range = c(36.0013, 65),
       details = "3 rows record exactly 0 degrees (the equator), categorically outside any DATRAS survey area -- excluded; the lower bound instead matches ShootLat's own clean minimum for the same archive."),
  list(field = "HaulLong", type = "number(quantity)", units = "decimal degrees", range = c(-67.6762, 45.8753),
       details = "Same -9-as-missing caveat as ShootLong above (0 degrees, the Prime Meridian, is a genuine North Sea value here and is kept)."),
  list(field = "Netopening", type = "number(quantity)", units = "m", range = c(0, 76),
       details = "-9 is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: HH 75,609/145,958 rows (51.80%), LT 24,717/75,310 rows (32.82%), 0 true nulls in either table -- the modal value in both tables, not the exception."),
  list(field = "Tickler", type = "enum", values = get_vocab_enum_values("TS_Tickler"),
       details = paste(
         "icesVocab's TS_Tickler resolves this as a controlled tickler-chain count",
         "code list (32 active codes: 0-30, plus a '-9'/'no ticklers allowed'",
         "sentinel) -- not an open numeric quantity, found via the full-field vocab",
         "sweep (data-raw/build_vocab_field_audit.R, Issue 9). Checked 2026-08-10",
         "directly against the real archive -- but against data an archive-pipeline",
         "bug (known-issues.yaml's sentinel_replacement_data_loss) had already",
         "silently scrubbed -9 out of: at the time HH showed 9 distinct values and",
         "LT 3, neither including -9. Re-verified 2026-08-16 after that bug's fix:",
         "HH now shows 10 distinct values (-9, 0, 1, 4, 5, 8, 10, 20, 21, 27) and",
         "LT 4 (-9, 0, 5, 8, a subset of HH's own); -9 turns out to be the",
         "DOMINANT value in both (78% of HH, 41% of LT), not absent -- still zero",
         "gaps against the vocab's 32 codes, either direction. Live WSDL",
         "(getHHdata) declares this field int, not string -- an accepted,",
         "permanent M01 divergence between the WSDL-driven archive and this",
         "curated enum spec (see Valid_Aphia's own note for the general pattern),",
         "not a bug to fix by changing either side."
       )),
  list(field = "Distance", type = "number(quantity)", units = "m", range = c(0, 59995),
       details = "-9 is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: HH 23,929/145,958 rows (16.39%), LT 996/75,310 rows (1.32%), 0 true nulls in either table."),
  list(field = "Warplngt", type = "number(quantity)", units = "m", range = c(0, 4065),
       details = "-9 is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: HH 53,727/145,958 rows (36.81%), LT 759/75,310 rows (1.01%), 0 true nulls in either table."),
  list(field = "Warpdia", type = "number(quantity)", units = "mm", range = c(16, 30),
       details = "A dense, well-populated cluster runs 16-21mm and 27-30mm; isolated single-occurrence values below (1mm x2, 5mm x10, 12mm) and above (39, 56, 85, 88mm) sit apart from it with no comparable support and are treated as data-entry errors, excluded here. -9 is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: HH 85,420/145,958 rows (58.52%), LT 28,755/75,310 rows (38.18%), 0 true nulls in either table -- the modal value in both tables, not the exception (already excluded by the range above, [16,30])."),
  list(field = "WarpDen", type = "number(quantity)", units = "kg/m", range = c(0, 26),
       details = "-9 is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: HH 140,298/145,958 rows (96.12%), LT 45,440/75,310 rows (60.34%), 0 true nulls in either table -- the modal value in both tables, not the exception."),
  list(field = "DoorSurface", type = "number(quantity)", units = "m2", range = c(0, 20.2),
       details = "-9 is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: HH 78,096/145,958 rows (53.51%), LT 27,021/75,310 rows (35.88%), 0 true nulls in either table."),
  list(field = "DoorWgt", type = "number(quantity)", units = "kg", range = c(0, 1720),
       details = "-9 is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: HH 77,794/145,958 rows (53.30%), LT 26,904/75,310 rows (35.72%), 0 true nulls in either table."),
  list(field = "DoorSpread", type = "number(quantity)", units = "m", range = c(1, 250),
       details = "0m (9 rows) is excluded as a placeholder -- a rigged, towing trawl cannot have zero door spread. Three single-occurrence values (762, 767, 778m) sit far above everything else in the archive (next highest is 250m) and are treated as data-entry errors, excluded; a real, well-populated value at 3.6m (1128 rows, likely a fixed beam-trawl spread) is kept. -9 is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: HH 83,779/145,958 rows (57.40%), LT 25,658/75,310 rows (34.07%), 0 true nulls in either table -- already excluded by the range above."),
  list(field = "WingSpread", type = "number(quantity)", units = "m", range = c(4, 50),
       details = "0m (9 rows), 1.8m and 2m (1 row each) are excluded as below any value with real support -- a well-populated cluster starts at 4m (1074 rows, likely a fixed beam-trawl spread). 142m (1 row) sits far above the next-highest real value (50m) and is treated as a data-entry error, excluded. -9 is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: HH 102,696/145,958 rows (70.36%), LT 31,038/75,310 rows (41.21%), 0 true nulls in either table -- already excluded by the range above."),
  list(field = "TowDir", type = "number(quantity)", units = "degrees", range = c(0, 360),
       details = "999 (3 rows) reads as an undocumented out-of-domain 'not recorded' marker, the same pattern confirmed for WindDir below. A further cluster -- 450 deg (62 rows), 520(5), 460(5), 540(3), 510, 564, 702 (1 each) -- divided by 10 becomes ordinary bearings (45.0, 52.0, 46.0, 54.0, 51.0, 56.4, 70.2 deg). Both groups are outside the documented 0-360 domain and excluded here. -9 is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: HH 50,625/145,958 rows (34.68%), LT 2,384/75,310 rows (3.17%), 0 true nulls in either table -- already excluded by the range above.",
       todo = "Confirm the divide-by-10 cluster (450/520/460/540/510/564/702) is a genuine data-entry pattern by correlating with Country/Survey -- same class of check already confirmed for SwellHeight via its WindSpeed co-parameter."),
  list(field = "GroundSpeed", type = "number(quantity)", units = "knots", range = c(0, 10),
       details = "Ceiling is a domain judgment (real trawling ground speed), not an observed cluster boundary -- observed values run 10.8 up to a 99.9 marker with no clean gap, all excluded. -9 is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: HH 56,805/145,958 rows (38.92%), LT 10,224/75,310 rows (13.58%), 0 true nulls in either table -- already excluded by the range above."),
  list(field = "SpeedWater", type = "number(quantity)", units = "knots", range = c(0, 22),
       details = "-9 is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: HH 131,220/145,958 rows (89.90%), LT 41,502/75,310 rows (55.11%), 0 true nulls in either table -- the modal value in both tables, not the exception."),
  list(field = "WindDir", type = "number(quantity)", units = "degrees", range = c(-1, 360),
       details = "-1 is documented ('varying direction'). 999 (57 rows) reads as an undocumented out-of-domain 'not recorded' marker; a handful of further single-occurrence values just above 360 (711, 504, 420, 365, 361) are also excluded. -9 is ALSO present and is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: HH 40,431/145,958 rows (27.70%), LT 5,111/75,310 rows (6.79%), 0 true nulls in either table -- already excluded by the range above (unlike -1, which the range explicitly keeps)."),
  list(field = "WindSpeed", type = "number(quantity)", units = "m/s", range = c(0, 28),
       details = "Ceiling follows the Beaufort 10 upper bound (28.4 m/s, storm force) -- no vessel would be actively trawling above this. 1,641 of 109,012 populated rows (~1.5%) exceed it, tailing off smoothly with no clean gap up to 342 m/s; the count jumps from a thin 1-7-row-per-value tail above 28 to 357 rows right at 28, consistent with a real distribution below and noise above."),
  list(field = "SwellDir", type = "number(quantity)", units = "degrees", range = c(0, 360),
       details = "-9 is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: HH 120,204/145,958 rows (82.35%), LT 28,459/75,310 rows (37.79%), 0 true nulls in either table -- the modal value in both tables, not the exception."),
  list(field = "CodendMesh", type = "number(quantity)", units = "mm", range = c(9, 100),
       details = "0mm (202 rows) excluded as a placeholder -- a codend by definition has some mesh size. 250mm (1 row) sits far above the next-highest real value (100mm, 644 rows) and is treated as a data-entry error, excluded. -9 is the ICES-wide sanctioned 'no information' convention (data-raw/build_field_description_snapshot.R), confirmed 2026-08-17: HH 104,918/145,958 rows (71.88%), LT 22,672/75,310 rows (30.11%), 0 true nulls in either table -- the modal value in both tables, already excluded by the range above."),
  list(field = "Quarter",
       details = paste(
         "Live WSDL (getHHdata and getCAdata, checked 2026-08-16) declares this",
         "field int, not string. An accepted, permanent M01 divergence between",
         "the WSDL-driven archive (which stays int, per",
         "archive_00_wsdl_types.R's own WSDL-only design) and this curated enum",
         "spec (whose values must be quoted strings per the data-dict spec's own",
         "S24 rule) -- the same class of divergence already accepted for",
         "Valid_Aphia (number(id) vs WSDL's own 'character') and",
         "Tickler/CatIdentifier above (enum vs WSDL's own 'int'), not a bug to",
         "fix by changing either side."
       )),

  # ---- Confirmed shared (WSDL-verified 2026-08-07), needing no correction --
  # DoorType/Month/HaulVal/DataType/Rigging/SwellHeight: HH's and LT's
  # own WSDL operations (getHHdata vs getLitterAssessmentOutput) declare an
  # identical type for each -- same evidence basis as every field above --
  # they just never needed a type/range/units/details fix, so were never
  # added here until add_shared_field_descriptions() (below) needed a
  # complete shared-field list to reproduce HH's description onto LT.
  list(field = "DoorType"),
  list(field = "Month",
       details = paste(
         "Live WSDL (getHHdata, checked 2026-08-16) declares this field int,",
         "not string -- the same accepted, permanent M01 divergence as",
         "Quarter above (curated enum vs WSDL's own 'int'), not a bug to fix",
         "by changing either side."
       )),
  list(field = "HaulVal"),
  list(field = "DataType",
       details = paste(
         "icesVocab's TS_DataType gives -9 its own specific meaning: 'Invalid",
         "hauls' -- not a generic missing-value placeholder like most of this",
         "field's sibling enums (checked 2026-08-16, part of a full sweep of",
         "every enum field with -9 as a declared code; see",
         "vignettes/articles/technical-notes.md). Low prevalence in both",
         "tables that carry it (HH: 39/145,958 rows, 0.03%; LT: 20/75,310,",
         "0.03%)."
       )),
  list(field = "Rigging"),
  list(field = "SwellHeight")
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

# --- Reproduce HH's own description onto shared fields missing one --------
#
# apply_col_update() (above) deliberately never touches `description` --
# unlike type/units/range/details/constraints, it's sourced per-table from
# ICES's own getDatrasFieldList() service (spec_01_seed_dict.R), which has
# a confirmed, documented coverage gap for LT (22 of 58 real fields; see
# op_datras_field_list()'s own docs / data-raw/ICES_ISSUE_REPORT.md).
# Before 2026-08-06 this went unnoticed because a direct call to
# getDatrasFieldList() -- via a personal icesDatras development fork
# installed at the time, not the official package (confirmed 2026-08-09;
# see AGENTS.md) -- silently patched around the gap with its own
# undocumented lt_extra table, which, it turns out, included description
# text copied from HH (verified: byte-identical wording in the last
# committed YAML). Replacing that call correctly stopped inheriting an
# unofficial, ICES-unsourced patch, but also correctly re-exposed the gap
# as a missing `description` on ~35 LT columns (found 2026-08-07,
# regenerating for an unrelated fix).
#
# Verified directly against ICES's own WSDL (2026-08-07, not just inferred):
# every shared_field_specs field but one (DateofCalculation, already excluded
# from this list for its own documented reasons -- see field_specs above)
# declares an IDENTICAL type across HH/HL/CA/LT's own live operations --
# strong, primary-source evidence these really are one fact per haul
# (Working principles, rule 12), not independently-documented per table.
# So: reproduce HH's own description onto any sibling table's same-named
# column that's missing one, scoped exactly to shared_field_specs's own
# (already curated, already exception-filtered) field list -- deliberately
# NOT a blanket same-name-anywhere rule, since fields with genuine per-table
# differences (LngtClass/NumberAtLength, RecordType, LT's own Depth/
# BottomDepth duplication) were already kept out of shared_field_specs for
# independently-verified reasons and so are automatically excluded here too.
add_shared_field_descriptions <- function(dict, shared_fields) {
  hh <- dict$tables[[which(map_chr(dict$tables, "name") == "HH")]]
  hh_desc <- list()
  for (col in hh$columns) if (!is.null(col$description)) hh_desc[[col$name]] <- col$description

  for (ti in seq_along(dict$tables)) {
    if (dict$tables[[ti]]$name == "HH") next
    for (ci in seq_along(dict$tables[[ti]]$columns)) {
      col <- dict$tables[[ti]]$columns[[ci]]
      if (is.null(col$description) && col$name %in% shared_fields && col$name %in% names(hh_desc)) {
        col$description <- hh_desc[[col$name]]
        dict$tables[[ti]]$columns[[ci]] <- col
      }
    }
  }
  dict
}

curated <- add_shared_field_descriptions(curated, map_chr(shared_field_specs, "field"))

# BottomDepth's HH<->LT description backfill and duplication cross-reference
# can't use add_shared_field_descriptions() above -- that mechanism matches
# siblings by IDENTICAL col$name, but HH's own legacy name for this concept
# is "Depth" while LT's is "BottomDepth" itself (the one shared-concept field
# whose legacy name diverges by table, see the dedicated field_specs block
# above). Handled explicitly instead: description backfilled programmatically
# from HH's own "Depth" column (same evidentiary basis as every other
# shared_field_specs description backfill, not hardcoded text), and a details
# note added cross-referencing LT's own separate "Depth" field, which already
# carries the full Issue 6 duplication finding.
hh_ti <- which(map_chr(curated$tables, "name") == "HH")
hh_ci <- which(map_chr(curated$tables[[hh_ti]]$columns, "name") == "Depth")
hh_depth_desc <- curated$tables[[hh_ti]]$columns[[hh_ci]]$description

lt_ti <- which(map_chr(curated$tables, "name") == "LT")
lt_ci <- which(map_chr(curated$tables[[lt_ti]]$columns, "name") == "BottomDepth")
if (is.null(curated$tables[[lt_ti]]$columns[[lt_ci]]$description) && !is.null(hh_depth_desc)) {
  curated$tables[[lt_ti]]$columns[[lt_ci]]$description <- hh_depth_desc
}

curated <- apply_col_update(curated, "LT", "BottomDepth", list(
  details = paste(
    "Not a rename -- BottomDepth is already the raw ICES field name in LT's",
    "archive. It sits alongside this table's own separate Depth field,",
    "byte-for-byte identical to it (see Depth's own details): a known",
    "ICES-side redundancy, not a rename relationship, filed with ICES",
    "2026-08-06 (data-raw/ICES_ISSUE_REPORT.md, Issue 6)."
  )
))

# Table-level labels and descriptions (grain and population for each table).
# Prose here deliberately describes BOTH real-world naming conventions
# (Platform/StationName/HaulNumber vs Ship/StNo/HaulNo) since the archive
# itself genuinely contains both eras of submission -- unaffected by which
# name this script's own columns are keyed by.
table_specs <- list(
  list(table = "HH",
       label = "Haul Information",
       description = "Each row is one haul (trawl deployment). Contains haul-level metadata: geography, timing, gear deployment, environmental conditions, and performance flags.",
       origin = "data-raw/spec_02_curate_dict.R",
       details = "Grain: each row represents one discrete haul deployment (one trawl operation). Population: all hauls submitted to ICES DATRAS within the covered survey/region/timeframe. Join key: HL, CA, and LT tables reference haul-level data via a composite identifier constructed from eight fields: Survey, Year, Quarter, Country, {Platform or Ship}, Gear, {StationName or StNo}, and HaulNumber. The naming convention differs by era: newer submissions use Platform/StationName/HaulNumber (new style); older submissions use Ship/StNo/HaulNo (old style). Note: HaulNumber alone is NOT a valid join key and must be paired with all seven other fields -- but even the full composite key doesn't recover everything: 288,581 CA rows (4.92%) carry a -9 sentinel (not a null; verified 2026-08-07) in HaulNumber/HaulNo and match no HH haul on any subset of the 8 fields. See DATRAS-known-issues.yaml (ca_haulno_unlinkable_to_hh) and obus::dr_add_id for the composite ID construction logic."),
  list(table = "HL",
       label = "Length Frequency Distribution",
       description = "Each row is a length class within a haul's catch. Contains the count of fish in each length bin, without individual-level age/sex data; the length-aggregated summary layer of Tier 1.",
       origin = "data-raw/spec_02_curate_dict.R",
       details = "Grain: each row is a (haul, species, length class) combination with a count of fish in that length bin. Population: length-frequency summaries for all species caught in surveyed hauls, aggregated by length class. Linked to HH via the composite haul identifier (Survey + Year + Quarter + Country + Platform/Ship + Gear + StationName/StNo + HaulNumber). Note: CA (not HL) has a verified HaulNumber/HaulNo linkage gap -- 4.92% of CA rows carry a -9 sentinel and match no HH haul even via the full composite key (see HH table details). The full 8-field composite key is required for correct joins regardless."),
  list(table = "CA",
       label = "Age Composition (Individual)",
       description = "Each row is one aged fish specimen from a haul. Contains individual-level biological measurements (length, weight, age, sex, maturity) on a subsample of the catch; linked to HH via the composite haul identifier.",
       origin = "data-raw/spec_02_curate_dict.R",
       details = "Grain: each row is one biological specimen (a single aged fish) from a haul. Population: individual organisms sampled and measured from hauls within covered surveys, not the full catch — a subsample. Linked to HH via the composite haul identifier (Survey + Year + Quarter + Country + Platform/Ship + Gear + StationName/StNo + HaulNumber). Critical note (corrected 2026-08-07; see DATRAS-known-issues.yaml issue ca_haulno_unlinkable_to_hh): HaulNumber/HaulNo contains 0 true nulls -- 288,581 rows (4.92% of 5,865,076) instead carry a -9 sentinel, which violates the column's declared range ([0, 82483]; a D04_range violation, confirmed via op_flag_violations()), not the required constraint (D01 never fires here). These rows match no HH haul on the full 8-field composite key, or on the 7 non-HaulNumber fields alone -- not a join-key problem, but genuinely orphaned CA records. A separate, much smaller residual (700 rows, 0.01%) with a plausible HaulNumber also fails to match HH.",
       todo = "Diagnose the 700-row (0.01%) HaulNumber tail-mismatch residual (known-issues.yaml: ca_haulno_tail_mismatch) -- distinct from the -9 sentinel issue above, cause not yet found.",
       definitions = list(
         list(
           name = "linkable_to_hh",
           description = "Rows whose HaulNo is a real value, not the -9 'unlinkable' sentinel (known-issues.yaml: ca_haulno_unlinkable_to_hh) -- i.e. rows that can actually be joined back to HH via the composite key.",
           expr = "HaulNo != -9"
         )
       )),
  list(table = "LT",
       label = "Litter Assessment",
       description = "Each row is one litter observation from a haul. Contains types and counts of marine debris (plastics, fishing gear, natural/organic material) recorded during the catch review; a separate thematic addition to the HH/HL/CA exchange.",
       origin = "data-raw/spec_02_curate_dict.R",
       details = "Grain: each row is one litter assessment/observation recorded during a haul's catch review. Population: litter records from hauls in covered surveys; a thematic addition to the HH/HL/CA core exchange tables with a separate collection protocol and scope. Linked to HH via the composite haul identifier (Survey + Year + Quarter + Country + Platform/Ship + Gear + StationName/StNo + HaulNumber). Note: CA has a verified HaulNumber/HaulNo linkage gap via a -9 sentinel (see CA table details); LT's own HaulNumber has no equivalent gap -- checked 2026-08-16, zero nulls and zero -9 values. The full 8-field composite key is required for correct joins regardless: 2,026 of 75,310 LT rows (2.7%) don't match any HH haul on it, but for an unrelated, diagnosed reason (known-issues.yaml: lt_bts_2025_q1_orphaned) -- HH's own submission is genuinely missing for that survey/year/quarter, not an LT-side data-quality problem.")
)

for (spec in table_specs) {
  curated <- apply_table_update(curated, spec$table, spec)
}

# Column labels (short human-readable titles for user-facing display)
# Only adding labels where the column name is technical/terse and benefits from a label
col_labels <- list(
  list(table = "HH", field = "RecordType", label = "Record Type"),
  list(table = "HH", field = "HaulDur", label = "Haul Duration (minutes)"),
  list(table = "HH", field = "DepthStratum", label = "Depth Stratum"),
  list(table = "HL", field = "RecordType", label = "Record Type"),
  list(table = "HL", field = "SpecCode", label = "Species (WoRMS AphiaID)"),
  list(table = "HL", field = "CatIdentifier", label = "Species Category"),
  list(table = "HL", field = "LngtClass", label = "Length Class (cm)"),
  list(table = "HL", field = "HLNoAtLngt", label = "Count at Length"),
  list(table = "CA", field = "RecordType", label = "Record Type"),
  list(table = "CA", field = "SpecCode", label = "Species (WoRMS AphiaID)"),
  list(table = "CA", field = "LngtClass", label = "Length Class (cm)"),
  list(table = "CA", field = "AgeSource", label = "Age Determination Method"),
  list(table = "CA", field = "AgePrepMet", label = "Specimen Preparation for Aging"),
  list(table = "LT", field = "LT_Weight", label = "Total Litter Weight (kg)"),
  list(table = "LT", field = "LT_Items", label = "Total Item Count")
)

for (spec in col_labels) {
  curated <- apply_col_update(curated, spec$table, spec$field, list(label = spec$label))
}

# Composite haul-identifier key: HL/CA/LT all reference haul-level data in
# HH via the same 8-field composite identifier (see each table's own
# `details` above, previously the only place this was recorded). HH's own
# 8 columns become `primary_key` (implies required+unique, satisfying the
# `many-to-one` cardinality below); HL/CA/LT's matching columns become
# `required, foreign_key` -- still required, since a haul-linking record is
# not meaningful without them (matching what these columns already had
# before this step, for Year/HaulNo; the other six had no constraint
# declared at all until now). Legacy names throughout, matching this
# script's own keying convention; data-raw/spec_03_translate_new_names.R
# translates the relationships' join expressions to new names the same way
# it already translates every column's `name`.
composite_key_fields <- c("Survey", "Year", "Quarter", "Country", "Ship", "Gear", "StNo", "HaulNo")
for (f in composite_key_fields) {
  curated <- apply_col_update(curated, "HH", f, list(constraints = list("primary_key")))
  for (t in c("HL", "CA", "LT")) {
    curated <- apply_col_update(curated, t, f, list(constraints = list("required", "foreign_key")))
  }
}

# `relationships`: formalizes the composite-key join above as the spec's
# own structural feature, so it's checked by validate-spec (typos in any
# of the 24 column references across the 3 joins become S01-S06 errors,
# not silent) and machine-resolvable via export-spec/export-data (`pairs`)
# instead of only readable as prose. Table-level `details` above are left
# as-is rather than trimmed -- this is additive, not a replacement.
relationship_join <- function(child_table) {
  paste(
    sprintf("%s.%s = HH.%s", child_table, composite_key_fields, composite_key_fields),
    collapse = " AND "
  )
}
relationships <- list(
  list(join = relationship_join("HL"), cardinality = "many-to-one"),
  list(
    join = relationship_join("CA"), cardinality = "many-to-one",
    description = paste(
      "Known gap (see CA table's own details and DATRAS-known-issues.yaml's",
      "ca_haulno_unlinkable_to_hh): 4.92% of CA rows (288,581 of 5,865,076)",
      "carry a -9 sentinel in HaulNo and match no HH row on this key --",
      "genuinely orphaned CA records, not a join-key problem."
    )
  ),
  list(join = relationship_join("LT"), cardinality = "many-to-one")
)

# Add sources to each table (pointers to parquet test data) -- points at the
# LEGACY-named parquet, matching this yaml's own (legacy) column names.
for (ti in seq_along(curated$tables)) {
  table_name <- curated$tables[[ti]]$name
  curated$tables[[ti]]$source <- list(parquet = paste0(table_name, "_legacy.parquet"))
}

# Glossary: domain-specific DATRAS/survey terminology
glossary <- list(
  "Haul" = "A single deployment of a trawl net. The primary unit of observation in DATRAS: one haul's catch (HH record) is subsampled and analyzed into length frequencies (HL) and aged individuals (CA).",
  "Length-stratified subsample" = "A subset of fish taken from a haul's catch, selected across the full range of observed length classes. Used in CA for cost-efficient age sampling without exhaustively aging every fish.",
  "Valid_Aphia" = "The ICES Datacenter's server-inserted, validated WoRMS AphiaID for each species. May differ from SpecCode (submitted value) due to ICES corrections or updates to the WoRMS taxonomy.",
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
    "data-raw/spec_02_curate_dict.R for the corrections and field-spec",
    "fills applied and why. Keyed by ICES's own legacy (real, on-the-wire)",
    "field names -- see data-raw/spec_03_translate_new_names.R for the",
    "curated/new-named version this package actually ships."
  ),
  origin = "data-raw/spec_01_seed_dict.R → data-raw/spec_02_curate_dict.R",
  version = list(date = as.character(Sys.Date())),
  tables = curated$tables,
  relationships = relationships,
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

write_yaml(curated, "inst/DATRAS-data-dict-legacy.yaml")

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
#   - HaulNumber/HaulNo: 288,581 rows (4.92%) carry a -9 sentinel, not a null (0
#     true NAs) -- violates the declared range [0,82483] (D04_range, confirmed
#     via op_flag_violations()), not required (D01 never fires). These rows
#     match no HH haul via the full 8-field composite key. Corrected 2026-08-07;
#     see DATRAS-known-issues.yaml (ca_haulno_unlinkable_to_hh).
#   - AgeSource: 1.16M rows have "otolith" (lowercase), not in icesVocab codes
#   - AgePrepMet: 8 observed codes; only 3 in icesVocab (~250k non-null)
#
# LT table:
#   - PARAM: 50 distinct values; A2/A5/A7/A14/A3/A6 undocumented (~50k rows)

# Post-process YAML to quote number-looking string examples (new spec requirement)
# (R's yaml writer doesn't preserve quote style for strings like "74E9", but only
# for `string` columns -- `number(id)` examples should remain unquoted numbers)
for (outfile in c("inst/DATRAS-data-dict-legacy.yaml")) {
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

validation_result <- op_validate_spec("inst/DATRAS-data-dict-legacy.yaml")

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
  "inst/DATRAS-data-dict-legacy.yaml (descriptive with observed data enums, ",
  "keyed by ICES's own legacy field names). ",
  "Post-processed to quote number-looking string examples for data-dict spec compliance.",
  "\n✓ Validated against data-dict spec.",
  "\nRun data-raw/spec_03_translate_new_names.R next to produce the curated/new-named inst/DATRAS-data-dict.yaml."
)
