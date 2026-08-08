---
title: "Technical Notes: Implementation Decisions & Discoveries"
description: "In-depth technical documentation of key implementation decisions, design tradeoffs, and discoveries during opus development."
date: 2026-08-02
---

This page collects detailed technical notes on implementation decisions, tradeoffs, and discoveries that don't fit neatly into other documentation. These notes are kept here for future maintainers and for transparency about how design decisions were made.

## 1. Field Name Mapping: Old → New and icesVocab Dependency

**Date:** 2026-08-02  
**Status:** Under implementation

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

- Source of truth (updated 2026-08-06): `op_datras_field_list()` (`R/field_names.R`), which replaced `icesDatras::getDatrasFieldList()` after tracing that function to an undocumented, ICES-unsourced hand-patch layered on top of the same live endpoint. `op_datras_field_list()` cross-verifies ICES's live metadata against each operation's own ASMX response before trusting a rename.
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
