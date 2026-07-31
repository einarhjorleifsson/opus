# Tier 1 (HH/HL/CA/LT) curation verification: empirical field statistics
# computed from obus's staged exchange archive (obus/data-raw/to_https/xml/),
# used to inform data-raw/DATASET_curate_dict.R's type-measure/units/
# constraints/range/examples decisions for inst/DATRAS-data-dict.yaml. Not
# part of the seed/curate/render pipeline itself (AGENTS.md's "Seeding,
# curation, and rendering") -- a verification pass, kept here rather than
# discarded so it's rerunnable and so curation decisions can point back to it
# (Working principles rule 4: "reference the analysis code").
#
# CAVEAT, load-bearing for every range/example below (found 2026-07-29):
# obus's xml/ archive was fetched via icesDatras's getDATRAS()/
# getLTassessment() with fix_types = TRUE (see obus's
# data-raw/DATASET_datras_download.R). icesDatras's own parseDatras()
# (R/utilities.R) unconditionally replaces literal -9 (numeric, or the string
# "-9") with NA for EVERY column of EVERY fetch, regardless of fix_types --
# it runs before fix_types is even consulted -- and applyDatrasTypeSchema()
# (fix_types = TRUE only) repeats this for int/decimal columns specifically,
# to also catch "-9.0"-shaped values. Neither step is field-aware: both
# apply whether or not -9 is that particular field's own documented "not
# known" sentinel. Harmless for most Tier 1 fields (weights/lengths/depths/
# speeds/etc. are never legitimately -9 in reality, sentinel or not), but it
# means a genuine measurement of exactly -9 in a field where that IS
# physically plausible is silently indistinguishable here from missing --
# confirmed candidates: TidePhase (a signed "minutes before high tide" could
# ordinarily read -9) and ShootLongitude/HaulLongitude (-9 degrees is an
# ordinary DATRAS longitude, west of Ireland/Iberia). Re-running this script
# against a fresh obus rebuild will not change this -- the scrub happens
# upstream of any obus/opus choice. Bypassing icesDatras entirely (raw HTTP
# against ICES's own web service) would be needed to see genuinely raw
# values; decided against for now given how long a full xml/ rebuild already
# takes (hours -- see obus's REBUILD_ALL.R).
#
# NOTE ON RANGE PHILOSOPHY: data-dict.yaml's `range` is used to validate real
# datasets against opus's spec, so it must describe the VALID domain, not
# just whatever the archive happens to contain -- a range built from raw
# literal min/max would let a validator wave through the same kind of
# already-known-implausible value (e.g. HaulDuration's -514, TowDirection's
# 999) that the field's own description already rules out. Section 4 below
# (extreme-value / sentinel gap check) exists specifically to tell "a
# recurring, suspiciously round out-of-domain value (probably an undocumented
# sentinel)" apart from "a smooth tail of genuinely large-but-real
# measurements" -- decided per field, not by one blanket rule.

suppressPackageStartupMessages({
  library(duckdbfs)
  library(dplyr)
  library(tidyr)
  library(yaml)
})

dict <- read_yaml("inst/DATRAS-data-dict.yaml")
xml_root <- path.expand("~/R/Pakkar/obus/data-raw/to_https/xml")
open_tbl <- function(t) open_dataset(file.path(xml_root, t))

bare_number_fields <- function(table_entry) {
  vapply(table_entry$columns, function(col) {
    if (!is.null(col$type) && identical(col$type, "number")) col$name else NA_character_
  }, character(1)) |> (\(x) x[!is.na(x)])()
}

## 1. Per-field summary stats for every bare `number` column, per table ------
## n (non-missing), n_distinct, min, max, counts of exact -9/-1/0 (sentinel/
## boundary candidates -- see caveat above for -9's limits), and a count of
## non-integer values (helps tell counts/ids from continuous measurements).
all_results <- list()
row_counts <- list()

for (tbl in dict$tables) {
  table_name <- tbl$name
  fields <- bare_number_fields(tbl)
  if (length(fields) == 0) next
  ds <- open_tbl(table_name)
  present <- intersect(fields, colnames(ds))
  missing <- setdiff(fields, present)
  if (length(missing) > 0) {
    message("NOTE: ", table_name, " -- not found as columns in xml/: ", paste(missing, collapse = ", "))
  }

  row_counts[[table_name]] <- ds |> summarise(n_rows = n()) |> collect() |> pull(n_rows)

  summ <- ds |>
    summarise(across(
      all_of(present),
      list(
        n        = ~sum(!is.na(.)),
        ndist    = ~n_distinct(.),
        min      = ~min(., na.rm = TRUE),
        max      = ~max(., na.rm = TRUE),
        n_neg9   = ~sum(. == -9, na.rm = TRUE),
        n_neg1   = ~sum(. == -1, na.rm = TRUE),
        n_zero   = ~sum(. == 0, na.rm = TRUE),
        n_nonint = ~sum(. != round(.), na.rm = TRUE)
      ),
      .names = "{.col}___{.fn}"
    )) |>
    collect()

  long <- summ |>
    pivot_longer(everything(), names_to = c("field", "stat"), names_sep = "___") |>
    pivot_wider(names_from = stat, values_from = value)

  all_results[[table_name]] <- long |> mutate(table = table_name, .before = 1)
}
field_stats <- bind_rows(all_results)
write.csv(field_stats, "data-raw/tier1_field_stats.csv", row.names = FALSE)

## 2. DateofCalculation: YYYYMMDD vs YYYYDDMM format check, all 4 tables -----
## Prompted by LT's DateofCalculation being typed `string` while HH/HL/CA
## type the same field `number` -- real data shows the identical 8-digit
## stamp (e.g. LT's "20260625"), so before curating it as one consistent
## number(ordinal) type across all four tables, check whether the digit
## ORDER also agrees. Test: for an 8-digit YYYYxxyy value, if the middle two
## digits (positions 5-6) ever exceed 12, they can't be a month -- proves
## that table isn't YYYYMMDD (must be YYYYDDMM or something else). Also
## reconfirms DateofCalculation >= the record's own Year in every table (per
## obus's own download-script comment: it's an ICES-side "last calculated"
## stamp, so it should never predate the survey year).
##
## RESULT (verified 2026-07-29, full archive): all four tables show
## n_mid2_gt12 = 0 and n_last2_gt12 > 0, max_mid2 = 12, max_last2 = 31,
## n_calc_before_year = 0 -- format is uniformly YYYYMMDD, no cross-table
## day/month order inconsistency.
message("\n--- DateofCalculation format check (all 4 tables) ---")
for (table_name in c("HH", "HL", "CA", "LT")) {
  ds <- open_tbl(table_name)
  chk <- ds |>
    filter(!is.na(DateofCalculation)) |>
    mutate(doc_num = as.numeric(DateofCalculation)) |>
    mutate(
      mid2  = floor((doc_num %% 10000) / 100),  # digits 5-6
      last2 = doc_num %% 100                     # digits 7-8
    ) |>
    summarise(
      n                   = n(),
      n_mid2_gt12         = sum(mid2 > 12, na.rm = TRUE),
      n_last2_gt12        = sum(last2 > 12, na.rm = TRUE),
      max_mid2            = max(mid2, na.rm = TRUE),
      max_last2           = max(last2, na.rm = TRUE),
      n_calc_before_year  = sum(floor(doc_num / 10000) < Year, na.rm = TRUE)
    ) |>
    collect()
  message(table_name, ":")
  print(chk)
}

## 3. Evenly-spaced examples for number(id) candidates -----------------------
## Per data-dict.yaml spec guidance ("5 evenly spaced values along the sorted
## unique values"): SpeciesCode (HL, CA) and SpeciesCategory (HL) will be
## curated as number(id) (see conversation: SpeciesCode is the same WoRMS
## AphiaID nature as Valid_Aphia; SpeciesCategory's real values
## {1-5,11-14,21-23,31} read as a coded scheme with gaps, not a sequence).
## Valid_Aphia (HL, CA) already shipped as number(id) but is missing its
## required representative-value field entirely -- filled in here too.
evenly_spaced <- function(ds, col, k = 5) {
  vals <- ds |> filter(!is.na(.data[[col]])) |> distinct(.data[[col]]) |>
    arrange(.data[[col]]) |> collect() |> pull(1)
  n <- length(vals)
  list(n_distinct = n, examples = vals[unique(round(seq(1, n, length.out = k)))])
}

hl <- open_tbl("HL")
ca <- open_tbl("CA")
message("\n--- number(id) candidate examples ---")
message("HL$SpeciesCode: ");     print(evenly_spaced(hl, "SpeciesCode"))
message("CA$SpeciesCode: ");     print(evenly_spaced(ca, "SpeciesCode"))
message("HL$SpeciesCategory: "); print(evenly_spaced(hl, "SpeciesCategory"))
message("HL$Valid_Aphia: ");     print(evenly_spaced(hl, "Valid_Aphia"))
message("CA$Valid_Aphia: ");     print(evenly_spaced(ca, "Valid_Aphia"))

## 4. Extreme-value / sentinel-gap check -------------------------------------
## For fields whose empirical max (section 1) looks physically implausible
## against the field's own ICES description, show the top-N distinct values
## with counts: a recurring, suspiciously round value with a big gap below it
## reads as an undocumented out-of-domain sentinel (like TowDirection's 999);
## a smooth tail with no gap reads as genuine, if extreme, real measurements.
## HH only for this pass.
hh <- open_tbl("HH")
top_n <- function(ds, col, n = 8) {
  ds |> filter(!is.na(.data[[col]])) |> count(.data[[col]], sort = TRUE) |>
    arrange(desc(.data[[col]])) |> head(n) |> collect()
}
suspicious_hh_fields <- c(
  "HaulDuration", "Distance", "WarpDiameter", "DoorSpread", "WingSpread",
  "NetOpening", "TowDirection", "SpeedGround", "SpeedWater",
  "SurfaceCurrentSpeed", "BottomCurrentSpeed", "SurfaceCurrentDirection",
  "BottomCurrentDirection", "WindDirection", "WindSpeed", "SwellDirection",
  "TidePhase", "TideSpeed"
)
message("\n--- HH: top distinct values for fields with a suspicious empirical max ---")
for (f in suspicious_hh_fields) {
  message(f, ":")
  print(top_n(hh, f))
}

message("\nRow counts per table:")
print(row_counts)
message("Wrote ", nrow(field_stats), " field-stat rows to data-raw/tier1_field_stats.csv")
