------------------------------------------------------------------------

# opus — ICES DATRAS Data Dictionary and Known-Issues Registry

**Status:** Active (2026–onward). **Version:** 0.2.0+

------------------------------------------------------------------------

## The YAML is the deliverable

opus produces **three YAML specifications**:

1. **`DATRAS-data-dict.yaml`** — Descriptive specification of Tier 1 (HH, HL, CA, LT). Documents what the archive **actually contains** — includes all observed enum values (both icesVocab codes and undocumented variants). Use as reference for understanding real-world patterns.

2. **`DATRAS-data-dict-icesvocab.yaml`** — Strict specification for validation testing. Restricts enums to icesVocab-defined codes only. Use to detect submissions with undocumented values that violate the published standard.

3. **`DATRAS-known-issues.yaml`** — Registry of metadata gaps between official ICES specs and real submission patterns. Tracks type mismatches, undocumented codes, incomplete vocabularies, and their escalation status with ICES.

The R package (`opus`) provides **thin tooling** around these YAML files: validation functions, generation scripts, and documentation. The YAML itself is the reference — portable, language-agnostic, and suitable for any tool.

------------------------------------------------------------------------

## What the project does

1. **Consolidates scattered knowledge** — WSDL, icesVocab, Technical Reference, real submissions — into one authoritative YAML
2. **Documents reality vs. spec** — When real data diverges from official documentation, capture it (not as error, but as known issue)
3. **Enables pre-submission validation** — Submitters can validate locally before uploading to ICES
4. **Escalates problems upstream** — Known-issues registry feeds into imbus/ICES dialogue

See `vignettes/why-opus.qmd` for context and philosophy.

------------------------------------------------------------------------

## Working Principles

**1. Real data is ground truth.** When WSDL/icesVocab/specs conflict with live submissions, trust the submissions; file the divergence as a known issue.

**2. Consolidate scattered knowledge.** WSDL, icesVocab, Technical Reference, real submissions — bring together into one machine-readable place.

**3. Data-only by design.** opus ships YAML + registry, no computational code. Portability, minimal maintenance, clear signal: this is a reference specification.

**4. Don't guess; document.** Every range/constraint/enum needs evidence: real data, WSDL, or icesVocab. Borderline calls get flagged in `details:` for expert review.

**5. Separate concerns: specs ≠ QC.** Known-issues registry documents schema gaps (upstream at ICES). Data-quality problems (wrong values) belong downstream in obus/imbus.

**6. Shared fields stay consistent.** HH/HL/CA/LT repeat field names (same facts). Type, units, range must match byte-for-byte across tables.

**7. Adapt when needed.** Principles are Magna Carta, not law. Revisable when practice demands.

------------------------------------------------------------------------

## Scope

- **Tier 1:** HH, HL, CA, LT (raw exchange submissions)
- **Tier 2:** FL, CPUEL, CPUEA, IDX (ICES-computed, future)
- **Tier 3:** obus derived products (contracts, future)

------------------------------------------------------------------------

## Format: data-dict.yaml v0.1.0

- Uses ALL features: relationships, constraints, assertions, glossary
- One file per tier
- Schema closed: only standard keys allowed

------------------------------------------------------------------------

## Known-Issues Registry

`inst/DATRAS-known-issues.yaml`: Escalation log for ICES Datacenter. Documents where official specs diverge from actual submissions. Schema/vocab problems only (not data-quality issues).

------------------------------------------------------------------------

## Implementation

**Development workflow** (`R/validation.R`):
- `op_validate_spec(dict_path)` — Check YAML spec conformation (uses data-dict CLI)
- `op_validate_meta(data_path, table, dict_path)` — Validate column names/types
- `op_validate_data(data_path, table, dict_path)` — Validate values vs constraints
- `op_validate_full(data_path, table, dict_path)` — Run all three checks
- `op_inspect_parquet(parquet_path)` — See what data-dict CLI sees
- `op_flag_violations(data_path, table, dict_path)` — Flag rows with constraint violations (workaround until data-dict CLI v0.0.1 returns row numbers)

These wrappers enable the curation loop: build YAML → validate against real data → identify issues → refine YAML. Use the **strict icesvocab version** to detect specification violations; use the **descriptive version** as reference for what exists in practice.

**Source scripts** (`data-raw/`):
- `DATASET_seed_dict.R` — pull specs from live WSDL + icesVocab (no corrections)
- `DATASET_curate_dict.R` — apply hand-written corrections with issue_id tags
- `DATASET_dict_to_qmd.R` — render dictionaries to HTML/preview
