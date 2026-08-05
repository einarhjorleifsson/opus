------------------------------------------------------------------------

# opus — ICES DATRAS Data Dictionary and Known-Issues Registry

**Status:** Active (2026–onward). **Version:** 0.2.0+

------------------------------------------------------------------------

## The YAML is the deliverable

opus produces **two YAML specifications**:

1. **`DATRAS-data-dict.yaml`** — Descriptive specification of Tier 1 (HH, HL, CA, LT). Documents what the archive **actually contains** — includes all observed enum values (both icesVocab codes and undocumented variants), with legacy field names for backward compatibility. Use as reference for understanding real-world patterns.

2. **`DATRAS-known-issues.yaml`** — Registry of metadata gaps between official ICES specs and real submission patterns. Tracks type mismatches, undocumented codes, incomplete vocabularies, and their escalation status with ICES.

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

**3. Data-only by design.** opus ships YAML + registry, no computational code. Portability, minimal maintenance, clear signal: this is a reference specification. obus ships thin wrapper functions (e.g., `validate_with_datadict()`) around the bundled data-dict CLI to remove friction for users who prefer not to shell out, but the wrappers are glue only — computation stays in the pipeline, not in package functions.

**4. Don't guess; document.** Every range/constraint/enum needs evidence: real data, WSDL, or icesVocab. Borderline calls get flagged in `details:` for expert review.

**5. Separate concerns: specs ≠ QC.** Known-issues registry documents schema gaps (upstream at ICES). Data-quality problems (wrong values) belong downstream in obus/imbus.

**6. Shared fields stay consistent.** HH/HL/CA/LT repeat field names (same facts). Type, units, range must match byte-for-byte across tables.

**7. Adapt when needed.** Principles are Magna Carta, not law. Revisable when practice demands.

------------------------------------------------------------------------

## Task

**opus feeds imbus WP2 (reference specification).** Deliver the most accurate DATRAS data-dict YAML, verified against real submissions. Documents the schema as actually submitted, flags upstream divergences (WSDL/icesVocab gaps), and escalates them to ICES. This is the work.

**opus does NOT:**
- Build QC infrastructure (imbus WPX handles complex contextual validation — e.g., door spread constraints vs depth)
- Compute or transform data
- Analyze or report on data quality independently
- Solve multivariate co-parameter constraints (beyond data-dict's scope)

**Thin wrappers only:** Functions are OK if they're glue around external tools (e.g., `validate_with_datadict()` wrapping the data-dict CLI for basic spec/metadata/data validation). Computation is not — that belongs downstream.

**Why we monitor data-dict:** data-dict's three-level validation (spec/metadata/data) covers the basic checks; R-package (when available) could remove friction for users who want that validation. But imbus's **real QC work** — complex contextual rules like "door spread limits depend on depth" — is beyond data-dict's scope and belongs to imbus's own QC workpackage. We track data-dict to prevent reinventing spec validation, but set realistic expectations about what it can deliver. See [[data_dict_trajectory]] for roadmap.

### Decision Gate: New Work

Before starting work on opus, ask:
1. Does this document DATRAS schema (YAML spec) or known issues?
2. If adding code: is it a thin wrapper (glue only)?
3. If neither: does it belong in obus/imbus instead?
4. If uncertain: flag for explicit decision before proceeding.

------------------------------------------------------------------------

## Scope

**Tier 1: DATRAS Exchange Data (raw submissions)**
- **HH** (Haul Information): Primary exchange table
- **HL** (Length Frequency): Primary exchange table
- **CA** (Catch at Age): Primary exchange table
- **LT** (Litter Assessment): Hybrid—some novel observations + lookup/join fields to HH. Attached to Tier 1 but not purely exchange data.

**Tier 2: DATRAS Derived Products (computed from Tier 1, future)**
- **CPUEL, CPUEA** (Catch Per Unit Effort): Computed from HH/HL with species name lookup
- **FL** (Fishing Effort): Derived from HH
- **IDX** (Survey Index): Derived product
- These are processed outputs, not raw submissions

**Tier 3: obus Derived Products (future)**
- Contracts, aggregations, and domain-specific derivatives built on top of opus specs

------------------------------------------------------------------------

## Format: data-dict.yaml v0.1.0

- Uses ALL features: relationships, constraints, assertions, glossary
- One file per tier
- Schema closed: only standard keys allowed

------------------------------------------------------------------------

## Known-Issues Registry

`inst/DATRAS-known-issues.yaml`: Escalation log for ICES Datacenter. Documents where official specs diverge from actual submissions. Schema/vocab problems only (not data-quality issues).

------------------------------------------------------------------------

## Data Sources

opus consolidates metadata from three ICES web services:

1. **WSDL (Web Services Definition Language)**
   - Source: `https://datras.ices.dk/WebServices/DATRASWebService.asmx`
   - Provides: Field types (string/int/decimal) for each operation
   - Authority: Primary—describes what the service actually returns
   - Scope: DATRAS-specific (HH, HL, CA, LT operations only)

2. **getDatrasFieldList API**
   - Source: `https://datras.ices.dk/WebServices/DATRASWebService.asmx/getDatrasFieldList`
   - Provides: Field name mappings (old → new), descriptions
   - Authority: Secondary—derived from WSDL and internal DATRAS schema
   - Scope: DATRAS-specific (no other ICES products)
   - Note: DataFormat field can diverge from WSDL; opus sources types from WSDL directly

3. **icesVocab (ICES Vocabularies)**
   - Source: `https://vocab.ices.dk/services/api/`
   - Provides: Code definitions and meanings (e.g., Gear codes, species validation)
   - Authority: Cross-domain reference—used by multiple ICES data systems
   - Scope: Not DATRAS-exclusive; opus filters to vocabularies applicable to DATRAS fields
   - Note: Provides code semantics only, not structural types

opus unifies these three sources into a single YAML specification, making inconsistencies visible and escalatable to ICES.

## Implementation

**Development workflow** (`R/validation.R`):
- `op_validate_spec(dict_path)` — Check YAML spec conformation (uses data-dict CLI)
- `op_validate_meta(data_path, table, dict_path)` — Validate column names/types
- `op_validate_data(data_path, table, dict_path)` — Validate values vs constraints
- `op_validate_full(data_path, table, dict_path)` — Run all three checks
- `op_inspect_parquet(parquet_path)` — See what data-dict CLI sees
- `op_flag_violations(data_path, table, dict_path)` — Flag rows with constraint violations (workaround until data-dict CLI v0.0.1 returns row numbers)

These wrappers enable the curation loop: build YAML → validate against real data → identify issues → refine YAML. Use the **descriptive YAML** as reference for what exists in practice, including both icesVocab-defined codes and undocumented variants observed in real submissions.

**obus wrapper** (`R/validate_with_datadict.R`):
- `validate_with_datadict(dict_path, verbose=FALSE)` — Validate data against opus's data-dict spec (thin wrapper around bundled data-dict CLI). Works in development and after install.

**Source scripts** (`data-raw/`):
- `DATASET_seed_dict.R` — pull specs from live WSDL + getDatrasFieldList + icesVocab (no corrections). Sources types directly from WSDL (not from getDatrasFieldList's DataFormat field) to avoid known bugs.
- `DATASET_curate_dict.R` — apply hand-written corrections with issue_id tags, enriches enums from icesVocab, documents legacy field names, includes intelligent post-processing to quote number-looking string examples per data-dict spec
- `yaml_to_formatted_md.R` — render YAML to Quarto markdown for pkgdown articles (human-readable reference)

**ICES API wrappers** (`data-raw/ices_api.R` — development tools, not shipped):
- `op_fetch_datras_field_list()` — Direct call to ICES getDatrasFieldList endpoint (bypasses icesDatras package). Returns field names, old→new mappings, descriptions. 24-hour caching.
- `op_fetch_vocab_codes()` — Direct call to icesVocab API for code lists (bypasses icesVocab package). Returns codes with descriptions, deprecation status, modification dates.
- Used by `DATASET_seed_dict.R` and `DATASET_curate_dict.R` for building the spec. Roxygen-documented for maintainability, but not exported (keeping opus "data-only" per Principle 3).

------------------------------------------------------------------------

## Open Items

**Scope clarity: opus is WP2 (reference spec); WP3 owns operational QC on vessels.** opus's task is the reference YAML specification and processed data products for imbus's WP2. imbus's **QC work** (on-vessel quality control, including domain violations like "door spread constraints depend on depth") lives in **WP3** (Marine Institute, Stokes) — a separate workpackage that requires operational QC tooling, not data-dictionary work.

**data-dict's realistic role:** data-dict covers three validation levels (spec/metadata/data) — sufficient for catching schema violations and basic constraint checking. But imbus's **operational QC** (multivariate co-parameter rules, on-vessel validation logic, domain-specific limits) is beyond data-dict's scope. opus **optionally** wraps data-dict for basic validation (if/when R-package matures); but the heavy QC lifting belongs to WP3's operational tools.

**Why we monitor data-dict:** Prevents reinventing spec validation; clarifies boundaries. When their R-package ships, opus can offer it as a user convenience (via thin wrappers). But WP3 should not expect data-dict to solve their operational QC problem — that's a separate engineering effort. Monitoring helps opus stay proportionate and avoid scope creep into work that's not ours. See [[data_dict_trajectory]] and [[imbus_structure]] for roadmaps.

**icesVocab field-name dependency:** A critical architectural discovery (2026-08-02): icesVocab code lookups are **dependent on field names**, and those field names are both old (legacy ICES names) and new (current names), sometimes pointing to **different vocabularies**. Example: `Sex` has `TS_Sex` (vocab), but `IndividualSex` does not; `GearEx` has `TS_GearEx` (1 code) while `GearExceptions` has `AC_GearExceptions` (14 codes). Solution: document legacy field names in YAML details field using standardized prefix (`Legacy field name: {OldName}`), and provide dual-lookup wrappers in R/vocab.R + R/field_names.R for downstream validation code. See `vignettes/articles/technical-notes.md` for full discovery notes and implementation details.

**Enum coverage audit (2026-08-02):** Systematically audited all 52 enum fields in Tier 1 against icesVocab. Findings: 35 fields (67%) have full coverage; 17 fields (33%) have no icesVocab match (system/metadata fields); 4 fields have incomplete coverage (HaulValidity 29%, SpeciesValidity 20%, GearExceptions 8%, LengthCode 43%); 1 field has empty vocab despite key existing (AgePreparationMethod); 12 fields exist under both TS_ and AC_ domain prefixes with ambiguity. Outputs: enum_field_inventory.csv, enum_enrichment_analysis.md. Key insight: incompleteness is **systemic** — not random gaps but patterns suggesting domain-specific extensions not in centralized icesVocab.

**Type source authority (2026-08-02):** Discovered three ICES metadata sources claim to define field types and **they diverge**. WSDL is authoritative (auto-generated from server code). getDatrasFieldList is secondary (hand-maintained table). Five confirmed divergences: Year fields (WSDL=int, API=char; real archive=int), Distance (WSDL=int, API=float; real archive=int). opus seeds from WSDL only. Documented in known-issues #10 (datras_field_list_type_divergence) as institutional accountability marker — ICES must align getDatrasFieldList with WSDL and real data behavior.

**What opus really is (2026-08-02 realization):** Not a data reformatting tool. **opus is institutional data governance audit infrastructure.** Systematically exposes where ICES's three metadata sources (WSDL, getDatrasFieldList, icesVocab) diverge from each other and from real data. Known-issues registry becomes accountability log: "Here's evidence this is broken, here's the impact, here's how to fix it." This reconciliation work is the actual deliverable — YAML specs are the vehicle, but exposure of governance gaps is the value.
