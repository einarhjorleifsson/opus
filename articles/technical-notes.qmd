---
title: "Technical Notes: Implementation Decisions & Discoveries"
description: "In-depth technical documentation of key implementation decisions, design tradeoffs, and discoveries during opus development."
date: 2026-08-02
---

This page collects detailed technical notes on implementation decisions, tradeoffs, and discoveries that don't fit neatly into other documentation. These notes are kept here for future maintainers and for transparency about how design decisions were made.

## 1. Field Name Mapping: Old → New and icesVocab Dependency

**Date:** 2026-08-02  
**Status:** Superseded 2026-08-09 (see note below) — kept for historical design rationale, not current behavior.

> **2026-08-09 update:** Sections 1 and 2 below describe recording a column's legacy name as a `Legacy field name: X` annotation inside its `details:` text, extracted via `op_legacy_field_name()`/`op_field_name_map()` (still live, exported functions — this isn't removed). As of 2026-08-09 the curation pipeline (`data-raw/spec_01_seed_dict.R`/`spec_02_curate_dict.R`) no longer uses that mechanism: legacy names are the *primary* key throughout seeding and curation, and opus's curated names are introduced exactly once, as a pure rename, by `data-raw/spec_03_translate_new_names.R` (crosswalk via the new `op_datras_rename_crosswalk()`, `R/field_names.R`). Both the legacy-named (`inst/DATRAS-data-dict-legacy.yaml`) and curated (`inst/DATRAS-data-dict.yaml`) dictionaries now exist as real, complete files side by side, so annotating one name inside the other's `details:` text is redundant. The design-tradeoff discussion below (why a `details:` prefix over a non-standard key, etc.) is still accurate history for *why that approach was chosen at the time* — just not what the pipeline does today.


### The Discovery

icesVocab code lookups are **dependent on field names** — and those field names are both old and new, sometimes pointing to **different vocabularies**.

### Pattern Analysis

From a 20-field sample of renamed fields across HH/HL/CA/LT:

- **NEITHER** (55%): No vocab under either old or new name (e.g., SweepLength, HaulNumber)
- **OLD ONLY** (30%): Vocab exists ONLY under old name (e.g., Sex → TS_Sex, but no TS_IndividualSex)
- **BOTH (different)** (15%): Same field has vocabs under both names pointing to different keys (e.g., GearEx → TS_GearEx vs GearExceptions → AC_GearExceptions)

### The Risk: Silent Validation Failure

If opus's YAML documents field names using NEW names only:

```
Example: Sex → IndividualSex
- icesVocab has vocab: TS_Sex (under OLD name only)
- icesDatras::getDatrasFieldList() uses: IndividualSex (new name)
- When op_vocab_first_usable("IndividualSex") is called
  → NOT FOUND (no TS_IndividualSex exists)
  → enum validation silently skipped
```

For "BOTH (different)" fields, downstream code may pick different vocabs depending on which name is used:

```
Example: GearEx → GearExceptions
- TS_GearEx: 1 code
- AC_GearExceptions: 14 codes
→ Validation rules differ depending on lookup method
```

### Implementation Approach

**1. Dual-name vocabulary lookup in R**

Add to `R/vocab.R`:
```r
op_vocab_get_codes_with_fallback <- function(field_name, field_name_old = NULL, types) {
  # Try new name first
  vocab <- op_vocab_first_usable(field_name, types)
  
  # If not found AND old name provided, fallback to old name
  if (is.na(vocab$key) && !is.null(field_name_old)) {
    vocab <- op_vocab_first_usable(field_name_old, types)
    if (!is.na(vocab$key)) {
      warning(sprintf(
        "Field '%s' (legacy: '%s'): vocab found under legacy name only (%s)",
        field_name, field_name_old, vocab$key
      ))
    }
  }
  
  vocab
}
```

**2. Document legacy names in YAML details**

In each column with a legacy name:

```yaml
- name: IndividualSex
  type: enum
  details: |
    Legacy field name: Sex (icesVocab: TS_Sex).
    Gender of the described species category. In CA-records should be
    defined by dissection. If no determination was performed, report '-9'.
```

**3. Curation script enhancements**

Flag patterns during YAML generation:

```r
# In spec_02_curate_dict.R:
vocab_coverage <- data.frame(
  field = ...,
  vocab_via_old = ...,
  vocab_via_new = ...,
  pattern = ... # NEITHER, OLD_ONLY, NEW_ONLY, BOTH_SAME, BOTH_DIFF
)

# Emit warnings for risky patterns
```

**4. Document conflicts explicitly**

For "BOTH (different)" fields, add clarification to details:

```yaml
- name: GearExceptions
  type: enum
  details: |
    Legacy field name: GearEx.
    NOTE: icesVocab maintains separate vocabs for this field:
    - TS_GearEx (legacy, 1 code)
    - AC_GearExceptions (current, 14 codes)
    This YAML uses AC_GearExceptions (current standard).
    See DATRAS-known-issues.yaml for details on the discrepancy.
```

### References

- Source of truth (updated 2026-08-06): `op_datras_field_list()` (`R/field_names.R`), which replaced a direct call to `getDatrasFieldList()`. Correction, 2026-08-09: the "hand-patch layered on top of the same live endpoint" this bullet used to describe was traced to a personal development fork of `icesDatras`, not the official `ices-tools-prod/icesDatras` (whose own `getDatrasFieldList()` has no patch of any kind). `op_datras_field_list()` cross-verifies ICES's live metadata against each operation's own ASMX response before trusting a rename regardless -- that cross-verification is the actual reason it's more reliable, not a claim about what any version of the `icesDatras` package does.
- icesVocab: https://vocab.ices.dk/
- Related working principle: AGENTS.md principle 1 ("Real data is ground truth") and principle 4 ("Don't guess; document")

---

## 2. Enum Value Descriptions: Storage Without Violating data-dict Spec

**Date:** 2026-08-02  
**Status:** Implemented (see inst/DATRAS-data-dict.yaml)

### The Challenge

Enum value descriptions need to be:
1. Stored in the YAML persistently
2. Machine-readable for downstream code
3. Fully compliant with data-dict v0.1.0 spec (no non-standard keys)

### Options Evaluated

| Option | Format | Viable? | Notes |
|--------|--------|---------|-------|
| YAML comments | `# Old name: X` | ✗ | Lost in round-trip (write_yaml → read_yaml) |
| Non-standard keys | `old_name: X` | ✗ | Violates data-dict's closed schema |
| JSON in details | Mixed prose + JSON struct | ✓ | Verbose, mixes formats |
| **Standardized prefix** | `Legacy field name: X` | ✓ | **CHOSEN** |

### Chosen Approach: Standardized Prefix

Store legacy names using a fixed prefix in the `details` field:

```yaml
- name: SweepLength
  type: number(quantity)
  details: |
    Legacy field name: SweepLngt (verified via op_datras_field_list()).
    Length of sweep in metres. Recommended values depend on survey and quarter,
    see survey manuals for further details.
```

**Regex extraction:** `/Legacy field name: (\w+)/`

**Advantages:**
- ✓ Fully spec-compliant (details is free-text, unlimited length)
- ✓ Human-readable AND machine-readable
- ✓ No additional YAML keys needed
- ✓ Easy to scan visually
- ✓ Survives YAML round-trips

### Implementation

Add to `R/field_names.R` (new file):

```r
#' Extract legacy field name from column details
#' 
#' @param details Character string from column$details field
#' @return Character: legacy field name, or NA if not found
#' @examples
#'   op_legacy_field_name("Legacy field name: SweepLngt (see ...)")
#'   # Returns "SweepLngt"
#'
#' @export
op_legacy_field_name <- function(details) {
  if (is.null(details) || is.na(details)) return(NA_character_)
  
  m <- regexec("Legacy field name: (\\w+)", details)
  match <- regmatches(details, m)
  
  if (length(match) > 0 && length(match[[1]]) > 1) {
    match[[1]][2]
  } else {
    NA_character_
  }
}

#' Build field name mapping from data-dict
#'
#' @param dict List: parsed DATRAS-data-dict.yaml
#' @param table_name Character: HH, HL, CA, LT (optional, defaults to all)
#' @return Data frame: columns = (RecordHeader, new_name, old_name, has_legacy)
#'
#' @export
op_field_name_map <- function(dict, table_name = NULL) {
  rows <- list()
  
  for (table in dict$tables) {
    if (!is.null(table_name) && table$name != table_name) next
    
    for (col in table$columns) {
      old <- op_legacy_field_name(col$details)
      rows[[length(rows) + 1]] <- data.frame(
        RecordHeader = table$name,
        new_name = col$name,
        old_name = old,
        has_legacy = !is.na(old),
        stringsAsFactors = FALSE
      )
    }
  }
  
  do.call(rbind, rows)
}
```

### References

- data-dict spec: http://data-dict.tidyverse.org/
- AGENTS.md principle 4: "Don't guess; document"

---

## 3. Enum Value Descriptions: Source and Coverage

**Date:** 2026-08-02  
**Status:** Implemented (see inst/DATRAS-data-dict.yaml)

### Coverage Summary

| Metric | Count |
|--------|-------|
| Total enum fields across HH/HL/CA/LT | 48 |
| Fields with value descriptions | 31 (65%) |
| Fields without vocab matches | 17 (35%) |

### Fields Not Enriched (Why)

- **Synthetic numeric codes** (StandardSpeciesCode, BycatchSpeciesCode) — no vocab in icesVocab
- **Context-specific codes** (SpeciesCodeType, LengthType) — no matching vocab
- **Partial matches** (LengthCode: codes '.' and '0' not in icesVocab)
- **Boolean flags** (Y/N, T/F) — not formally defined in icesVocab

### Design Decision: VOCAB_CODE_LIMIT = 20

Fields with >20 enum codes are stored as `examples` instead of full value maps. This is a deliberate constraint:

- **Why:** Enums are for small, fixed, meaningful sets (e.g., DayNight: 2 codes)
- **Threshold:** 20 codes is the pragmatic boundary for "human-readable enum"
- **Above threshold:** Use `examples` + `details` instead (e.g., Gear: 99 codes)

### References

- icesVocab: https://vocab.ices.dk/
- AGENTS.md principle 4: "Don't guess; document"

---

## 4. Global Sentinel Replacement: A Silent Data-Destruction Bug, and Why -9 Doesn't Mean the Same Thing Everywhere

**Date:** 2026-08-16  
**Status:** Implemented

### The Discovery

Investigating a `SwellHeight` type mismatch (icesVocab declares it an enum; opus's curated spec had HH correctly typed as a numeric quantity, but LT was still wrongly typed `enum`) led to checking `LT.SwellHeight`'s real archive values directly. They were continuous numbers, not the vocab's six codes — consistent with HH. But cross-checking `CA.HaulNo`, a field with an *already-documented* known issue (`ca_haulno_unlinkable_to_hh`: 288,581 rows carry a `-9` sentinel, explicitly "not null"), the real archive showed the opposite: 288,581 **true nulls**, zero literal `-9` values. Same count, contradictory representation.

### Root Cause

`data-raw/archive_04_parse_phase2.R` and `archive_05_backfill_lt_partitions.R` each carried a `GLOBAL_SENTINELS` list (`-9, -99, -999, -1, -5, -95, -100, -900, 88888888`) and a `replace_sentinels()` function applying it **unconditionally, across every column**, before type casting. Git history confirms this did not exist in the pipeline's original 2026-08-05 commit; it appears by the 2026-08-08 reorg commit — i.e. it was introduced *after* the `-9` sentinel had already been verified as real, non-null data on 2026-08-07. Nobody connected the two changes until this investigation.

Checking raw XML directly confirmed the mechanism: `CA_BTS_2004_Q3`'s own file has 513 literal `<HaulNo>-9</HaulNo>` tags. The archive-building pipeline was silently converting every one of them to `NA`.

### The Scale

Not confined to one field. A full re-scan of the archive for all 9 sentinel values across every numeric column, once the values were recoverable, found **101 (table, column, sentinel) combinations with real, non-zero counts**. Most dramatically: `HH.Tickler` — `-9` is icesVocab's own documented code for *"No ticklers are allowed"*, a real, meaningful answer, not a missing value — was `-9` for **113,645 of 145,958 rows (78%)**. Not a rare edge case; it was the modal value for the entire column, and the bug had been silently erasing it.

### Why This Was Architecturally Wrong

`archive_00_wsdl_types.R`'s own design already establishes the relevant principle, just applied to a different question: type-casting relies solely on live WSDL and *deliberately doesn't know the word "enum" exists*, because enum-ness is a curation conclusion reached by analyzing real data — depending on it at the parsing stage is circular (you can't discover a field is a clean enum before you can reliably read it at all).

Sentinel *meaning* is the same kind of curation conclusion. Whether `-9` means "genuinely absent" or a real, specific code is something you decide by looking at real data (or icesVocab) — not something the raw XML→parquet stage should decide for you. Worse: if that stage erases the value before anyone can look, curation can never discover it was meaningful later, no matter how carefully it's done. That's exactly what happened to `Tickler`: a 2026-08-10 vocab-coverage check concluded "zero gaps" for its enum — correctly, given what it could see — but it was checking an archive that had already lost every `-9` row. The conclusion wasn't wrong; the data it was drawn from was incomplete in a way nobody knew about.

### The Fix

Removed `GLOBAL_SENTINELS`/`replace_sentinels()` entirely from both scripts. Validated on a single known file first (`HaulNo` in `CA_BTS_2004_Q3` now shows all 513 real `-9` values, correctly typed `integer`, not silently `NA`). Then rebuilt the full archive from raw XML for all four tables (`Success: 2968 | Error: 813`, identical to the already-documented 2026-08-08/09 run; all 813 "errors" confirmed still the known-benign `EMPTY_RECORDS` case — no new failure mode introduced).

### Telling "Standard Missing" Apart from "Field-Specific Meaning"

Not every field needs the same scrutiny. There's a principled shortcut:

- **`number(quantity)` fields** (continuous physical measurements — temperatures, depths, speeds, directions, weights, distances) **can only plausibly mean "not recorded"** for a sentinel value. A continuous quantity has no way to encode a specific *meaning* the way a discrete code can — there's no such thing as "`-9` degrees means something specific" the way "`-9` ticklers means none were used." This matches the global sentinel convention already documented in `DATRAS-known-issues.yaml`'s `sentinels: global`.
- **`number(ordinal)`/`number(id)`/`enum` fields are where a real, field-specific meaning is actually possible**, because these are code-like by nature. A much shorter list to check individually.

Verified so far, each against real archive data (not assumed): `Tickler` (HH, LT) — `-9` = "No ticklers are allowed", a real code, not missing. `SpeciesCategory` (HL) — `-9` = "Unknown", already correctly declared. `Age` (CA) — `-9` (1,995,814 rows, 34%) reads as standard "not recorded", same basis as the smaller, already-documented `-1`/`-5`/`-95` cluster. `DateofCalculation` (HH/HL/CA) — `-9` reads as "not yet (re)calculated", a server-side processing fact, standard "not recorded" in spirit. `SwellHeight` (HH, LT) — see `swell_height_type_mismatch`/`swell_height_vocab_unused` in `DATRAS-known-issues.yaml`.

**Not yet individually verified:** roughly 26 more enum fields declare `-9` as one of their own curated codes (`GearExceptions`, `DoorType`, `DataType`, `Rigging`, `ThermoCline`, `PelagicSamplingType`, `SpeciesSex`, `LengthCode`, `DevelopmentStage`, `LengthType`, `IndividualSex`, `AgePlusGroup`, `AgeSource`, `AgePreparationMethod`, `OtolithGrading`, `MaturityScale`, `LTSRC`, and others) — structurally similar to `Tickler`, but only `Tickler` has had the raw-XML/icesVocab cross-check actually done.

### A Useful Cross-Check: Co-Parameters

Where a value's plausibility is ambiguous (e.g., deciding whether an extreme `SwellHeight` reading is real or a decimal-point entry error), a physically-related co-parameter can corroborate or refute it independently. `WindSpeed` at the same haul turned out to be exactly this for `SwellHeight`: median `WindSpeed` rises smoothly with `SwellHeight` for values later confirmed genuine (8m→24 m/s, 9m→26, 12m→28, 13m→24), and drops implausibly low for values later excluded as errors (15m→5 m/s, 20m→4) — a real discontinuity, not an arbitrary cutoff. Worth remembering as a technique, not just a one-off fix.

### Shared Fields Are Sometimes Literal Copies, Not Independent Observations

A related discovery along the way: `LT.SwellHeight` isn't independently measured at all — it's HH's own value, recorded again on the LT record for the same haul (confirmed by joining on the full composite key: 55,914 of 55,914 matched non-null rows identical, zero exceptions). The same check across ~35 other "shared-name" fields in HL/CA/LT found the same pattern holds almost everywhere (gear geometry, positions, environmental readings — all 100% or near-100% identical to HH), with a few real exceptions worth their own look: `RecordHeader` (0% match — a record-type discriminator, correctly different by design), `CA.GearExceptions` (92.27%), and `LT.Rigging`/`HaulValidity` (95.33%/99.97%). Where a field is confirmed a literal copy, its spec (type/range/units) should be forced identical to HH's rather than independently re-derived per table — that divergence is exactly what had gone unnoticed for `SwellHeight` before this investigation.

### Practical Guidance for Anyone Reading `.datras/*.parquet` Directly

Before computing statistics on this archive without going through the curated spec: `-9` (and the other 8 sentinel values) are now **real, literal values**, not silently removed. A naive `mean(Turbidity)` today would be badly wrong — 99.86% of that column's "measurements" are the sentinel, not real turbidity. Always check the field's declared `range`/`values` in `inst/DATRAS-data-dict.yaml` first, or use `op_flag_violations()`, which already treats declared out-of-range/non-enum values as violations.

### References

- `data-raw/archive_04_parse_phase2.R`, `data-raw/archive_05_backfill_lt_partitions.R` — the fix and its own header commentary
- `data-raw/archive_00_wsdl_types.R` — the earlier enum-detection precedent this fix mirrors
- `inst/DATRAS-known-issues.yaml` — `sentinel_replacement_data_loss`, `ca_haulno_unlinkable_to_hh`, `swell_height_type_mismatch`, `swell_height_vocab_unused`, and the `sentinels: field_specific` entries for `Tickler`/`Age`
- AGENTS.md Working Principle 8 ("Verify empirically") and Principle 9 ("Audit exhaustively")

---

## How to Contribute Technical Notes

When you discover something worth documenting that doesn't fit other docs:

1. **Add a new section** to this file with:
   - Clear title
   - Date discovered
   - Status (Discovery, Under implementation, Implemented)
   - Problem statement
   - Solution/approach
   - Implementation details (if applicable)
   - References to related code/docs

2. **Keep it technical** — this is for developers, not users

3. **Include code examples** when they illustrate the point

4. **Cross-reference AGENTS.md principles** when a decision relates to them

5. **Update this TOC** when adding new sections
