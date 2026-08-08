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

**3. Metadata-centric, not domain logic.** opus ships YAML specs + metadata validation and curation tooling (20 R functions). These functions work *on* the specification and data patterns, not *on* domain questions. No contextual QC (e.g., "door spread constraints vs. depth"), no statistical analysis, no derived products. That computational work belongs in obus/imbus.

**4. Don't guess; document.** Every range/constraint/enum needs evidence: real data, WSDL, or icesVocab. Borderline calls get flagged in `details:` for expert review.

**5. Separate concerns: specs ≠ QC.** Known-issues registry documents schema gaps (upstream at ICES). Data-quality problems (wrong values) belong downstream in obus/imbus. opus surfaces whether data violates the *documented* spec; imbus solves whether it's *valid* in context.

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
1. Does this improve the YAML specification (types, constraints, values, known issues)?
2. If adding code: does it work *on* the specification (validation, curation, metadata utilities) or work *with* the specification (domain QC, contextual constraints, data transformation)?
   - *On* the spec → belongs in opus (metadata-centric per Principle 3)
   - *With* the spec → belongs in obus/imbus (domain logic)
3. Will this function help data submitters validate locally or help opus maintainers curate specs?
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
   - Authority: Secondary—derived from WSDL and internal DATRAS schema, and
     **confirmed unreliable** (2026-08-06): covers only 22 of LT's 58 real
     fields, wrongly claims 3 LT fields were never renamed, documents a
     `RecordHeader` field LT doesn't have, and pairs CA's `IndividualAge`
     with an old-name (`AgeRings`) that doesn't exist. Filed with ICES —
     see `data-raw/ICES_ISSUE_REPORT.md`.
   - Scope: DATRAS-specific (no other ICES products)
   - Note: DataFormat field can diverge from WSDL; opus sources types from WSDL directly

3. **icesVocab (ICES Vocabularies)**
   - Source: `https://vocab.ices.dk/services/api/`
   - Provides: Code definitions and meanings (e.g., Gear codes, species validation)
   - Authority: Cross-domain reference—used by multiple ICES data systems
   - Scope: Not DATRAS-exclusive; opus filters to vocabularies applicable to DATRAS fields
   - Note: Provides code semantics only, not structural types

opus unifies these three sources into a single YAML specification, making inconsistencies visible and escalatable to ICES.

**No R-package dependency on either `icesDatras` or `icesVocab`** (removed
2026-08-06): opus calls these two web services directly (`R/vocab.R`,
`R/field_names.R`'s `op_datras_field_list()`), verifying every claim against
at least two independent live sources rather than trusting either service's
metadata blindly — this is how the getDatrasFieldList errors above were
caught. `icesDatras`'s own `getDatrasFieldList()` papers over some of the
same errors with an undocumented, ICES-unsourced hand-patch; opus does not
rely on it.

## Implementation

**User-facing exported functions** (17 total):

*Specification validation* (`R/validation.R`):
- `op_validate_spec(dict_path)` — Check YAML spec conformation (uses data-dict CLI)
- `op_validate_meta(data_path, table, dict_path)` — Validate column names/types
- `op_validate_data(data_path, table, dict_path)` — Validate values vs constraints
- `op_validate_full(data_path, table, dict_path)` — Run all three checks
- `op_inspect_parquet(parquet_path)` — See what data-dict CLI sees
- `op_flag_violations(data_path, table, dict_path)` — Flag rows with constraint violations
- `op_export_spec(dict_path)` — Export a fully-resolved dictionary as JSON (wraps data-dict CLI's `export-spec`)
- `op_export_data(dict_path)` — Export a dictionary with per-column data profiles as JSON (wraps data-dict CLI's `export-data`)

*Parquet exploration and drafting* (`R/op_draft_from_parquet.R`):
- `op_describe_parquet(parquet_path)` — Describe parquet structure and statistics
- `op_draft_from_parquet(parquet_paths, output_path)` — Generate skeleton YAML from parquet data

*ICES Vocabulary utilities* (`R/vocab.R`):
- `op_vocab_get_types()` — Get all ICES vocabulary code-types with prefix metadata
- `op_vocab_resolve_key(field_name, table_name)` — Find candidate vocabulary keys for a field
- `op_vocab_get_codes(vocab_key)` — Fetch code:description pairs for a vocabulary
- `op_vocab_first_usable(vocab_keys)` — Select first non-empty vocabulary from candidates

*Field name utilities* (`R/field_names.R`):
- `op_legacy_field_name(details)` — Extract legacy (old ICES) field name from YAML details
- `op_field_name_map(dict, table_name=NULL)` — Build legacy→new field name mapping table
- `op_datras_field_list(tables)` — Derive verified Tier 1 old-name→new-name mappings directly from ICES's live services (replaces `icesDatras::getDatrasFieldList()`); tiers each mapping as `confirmed` / `cross_table_confirmed` / `no_evidence` rather than trusting ICES's field-list metadata blindly. See its own roxygen docs for the six confirmed ICES-side errors this caught.

These wrappers enable the curation loop: build YAML → validate against real data → identify issues → refine YAML. The **descriptive YAML** (DATRAS-data-dict.yaml) is the reference for what exists in practice, including both icesVocab-defined codes and undocumented variants observed in submissions.

**Development-only functions** (`R/` — not exported):
- `op_minimal_yaml()` — Generate minimal type-only YAML from WSDL (Phase 1 seed)
- `op_enrich_stage2_yaml()` — Enrich with icesVocab codes (Phase 2)
- `op_apply_curated_spec()` — Apply field renames and type refinements (Phase 3)
- `op_build_final_yaml()` — Merge curated + enriched YAML
- `op_check_type_mismatch()` — Audit types across WSDL/curated/real data
- `op_audit_yaml_phase2_mismatch()` — Compare versions during curation

These are internal to the three-phase bootstrap workflow; see [[project_bootstrap_yaml_workflow]] for rationale.

**Source scripts** (`data-raw/`, spec-building pipeline; renamed to a scoped `spec_0N_` prefix 2026-08-08, see that date's data-raw reorg entry below):
- `spec_00_operation_types.R` — WSDL operation-page crawler (`.fetch_datras_operation_fields()`'s data source); sourced by `spec_01_seed_dict.R`
- `spec_01_seed_dict.R` — pull specs from live WSDL + getDatrasFieldList + icesVocab (no corrections)
- `spec_02_curate_dict.R` — apply hand-written corrections, enrich enums, document legacy names
- `spec_03_dict_to_qmd.R` — render `inst/*.yaml` to Quarto markdown for `vignettes/articles/`

There is a second, separate pipeline (`data-raw/archive_0N_*`) that downloads and converts the real DATRAS archive rather than building the spec; see the 2026-08-08 data-raw reorg entry below for both pipelines and what else was removed.

Historical note: `data-raw/ices_api.R` (`op_fetch_datras_field_list()`/`op_fetch_vocab_codes()`, direct ICES API dev wrappers) was removed 2026-08-08 — dead code with zero callers, properly superseded by the exported `op_datras_field_list()` (`R/field_names.R`) and `op_vocab_get_codes()` (`R/vocab.R`).

------------------------------------------------------------------------

## Open Items

**Scope clarity: opus is WP2 (reference spec); WP3 owns operational QC on vessels.** opus's task is the reference YAML specification and processed data products for imbus's WP2. imbus's **QC work** (on-vessel quality control, including domain violations like "door spread constraints depend on depth") lives in **WP3** (Marine Institute, Stokes) — a separate workpackage that requires operational QC tooling, not data-dictionary work.

**data-dict's realistic role:** data-dict covers three validation levels (spec/metadata/data) — sufficient for catching schema violations and basic constraint checking. But imbus's **operational QC** (multivariate co-parameter rules, on-vessel validation logic, domain-specific limits) is beyond data-dict's scope. opus **optionally** wraps data-dict for basic validation (if/when R-package matures); but the heavy QC lifting belongs to WP3's operational tools.

**Why we monitor data-dict:** Prevents reinventing spec validation; clarifies boundaries. When their R-package ships, opus can offer it as a user convenience (via thin wrappers). But WP3 should not expect data-dict to solve their operational QC problem — that's a separate engineering effort. Monitoring helps opus stay proportionate and avoid scope creep into work that's not ours. See [[data_dict_trajectory]] and [[imbus_structure]] for roadmaps.

**icesVocab field-name dependency:** A critical architectural discovery (2026-08-02): icesVocab code lookups are **dependent on field names**, and those field names are both old (legacy ICES names) and new (current names), sometimes pointing to **different vocabularies**. Example: `Sex` has `TS_Sex` (vocab), but `IndividualSex` does not; `GearEx` has `TS_GearEx` (1 code) while `GearExceptions` has `AC_GearExceptions` (14 codes). Solution: document legacy field names in YAML details field using standardized prefix (`Legacy field name: {OldName}`), and provide dual-lookup wrappers in R/vocab.R + R/field_names.R for downstream validation code. See `vignettes/articles/technical-notes.md` for full discovery notes and implementation details.

**Enum coverage audit (2026-08-02):** Systematically audited all 52 enum fields in Tier 1 against icesVocab. Findings: 35 fields (67%) have full coverage; 17 fields (33%) have no icesVocab match (system/metadata fields); 4 fields have incomplete coverage (HaulValidity 29%, SpeciesValidity 20%, GearExceptions 8%, LengthCode 43%); 1 field has empty vocab despite key existing (AgePreparationMethod); 12 fields exist under both TS_ and AC_ domain prefixes with ambiguity. Outputs: enum_field_inventory.csv, enum_enrichment_analysis.md. Key insight: incompleteness is **systemic** — not random gaps but patterns suggesting domain-specific extensions not in centralized icesVocab.

**Type source authority (2026-08-02):** Discovered three ICES metadata sources claim to define field types and **they diverge**. WSDL is authoritative (auto-generated from server code). getDatrasFieldList is secondary (hand-maintained table). Five confirmed divergences: Year fields (WSDL=int, API=char; real archive=int), Distance (WSDL=int, API=float; real archive=int). opus seeds from WSDL only. Documented in known-issues #10 (datras_field_list_type_divergence) as institutional accountability marker — ICES must align getDatrasFieldList with WSDL and real data behavior.

**What opus really is (2026-08-02 realization):** Not a data reformatting tool. **opus is institutional data governance audit infrastructure.** Systematically exposes where ICES's three metadata sources (WSDL, getDatrasFieldList, icesVocab) diverge from each other and from real data. Known-issues registry becomes accountability log: "Here's evidence this is broken, here's the impact, here's how to fix it." This reconciliation work is the actual deliverable — YAML specs are the vehicle, but exposure of governance gaps is the value.

**Dependency removal + getDatrasFieldList audit (2026-08-06):** Removed opus's R-package dependency on both `icesDatras` and `icesVocab` (direct web-service calls instead, verified byte-identical for icesVocab's two endpoints). Building the replacement (`op_datras_field_list()`, see `R/field_names.R`) required cross-verifying ICES's live `getDatrasFieldList` metadata against each operation's own ASMX response and the real archive, which surfaced 6 confirmed ICES-side errors (LT coverage gap, 3 wrong LT renames, a phantom LT `RecordHeader` field, CA's unverifiable `IndividualAge`/`AgeRings` row, missing `DateofCalculation`/`Valid_Aphia` entries, and LT's `Depth`/`BottomDepth` data duplication) — filed as `data-raw/ICES_ISSUE_REPORT.md` (moved from `inst/` 2026-08-08), not yet sent to ICES. Corrected opus's own spec accordingly: `CA.IndividualAge` reverted to `CA.Age` (the rename rested on an unverifiable metadata row), LT's ~23 shared fields renamed via verified cross-table inference (matching what `icesDatras`'s own unsourced patch did, but sourced and documented this time). **Still open:** the earlier same-day session (before this dependency work) produced several documents (`PHASE2_ISSUES_FOR_ICES.md`, `PHASE3_ROADMAP.md`, `DATRAS_PHASE2_ORIGINAL_NAMES.yaml`, `ICESVOCAB_MAPPING_AUDIT.md` and related CSVs) containing fabricated row counts and misattributed sources, discovered when this session's rigor caught a specific bad claim — their fate (delete vs. mark superseded) is undecided; do not treat their contents as reliable.

**Legacy/new parquet split + full ground-truthing (2026-08-08):** `.datras/parquet/LT` had no partitioned directory (unlike HH/HL/CA) because LT's XML predates the manifest-tracked downloader; backfilled via `data-raw/archive_05_backfill_lt_partitions.R` (204 files, 75,310 rows — matches the pre-existing consolidated total exactly). That backfill surfaced two latent bugs in `data-raw/archive_04_parse_phase2.R` itself (LT wrongly required a `RecordType` field it doesn't have; an all-empty XML file crashed instead of being recorded as `EMPTY_RECORDS`), fixed in both scripts. Then split the consolidated legacy archive from the curated spec: `.datras/{HH,HL,CA,LT}_legacy.parquet` (moved from `.datras/parquet/{table}.parquet`, current ICES field names, full archive) sit alongside new `.datras/{HH,HL,CA,LT}.parquet` (same data, opus-curated names — column rename is the *only* difference) and `.datras/DATRAS-data-dict-legacy.yaml` (pure name-swap of `inst/DATRAS-data-dict.yaml`, nothing else touched), all built by `data-raw/archive_06_split_legacy_new.R`. Along the way, found `data-raw/seed/DATRAS-exchange-name-history-seed.csv` is stale for LT (missing the ~23-field cross-table-inference correction above — confirmed by running it, not assumed), so the crosswalk is derived from the yaml's own `Legacy field name:` annotations instead — via the real `op_legacy_field_name()` (`R/field_names.R`, `source()`d directly, matching the precedent in `data-raw/spec_02_curate_dict.R`), not a second copy of its regex; a second-look review caught that the script had initially duplicated the regex inline, confirmed it agreed with the real function on all 190 columns, then switched to calling the real one to remove the drift risk — asserted against the real legacy parquet's actual columns before anything is written. Also fixed a bad annotation this surfaced: LT's `BottomDepth` details wrongly said `Legacy field name: Depth`; corrected at the source in `inst/DATRAS-data-dict.yaml` (BottomDepth is its own legacy field, not a rename — see Issue 6). Final step: independently re-verified the full crosswalk for all four tables directly against raw XML (not the parquet, not this file, not memory) — at least one non-empty sample per survey, all 28 surveys per table — zero discrepancies. See the 2026-08-08 addendum in `data-raw/ICES_ISSUE_REPORT.md` for the LT-specific re-confirmation, and its Issues 2–3 (reformatted 2026-08-08 to lead with legacy names, per house style: issue reports to ICES are framed in ICES's own current vocabulary; opus's own legacy→new mapping decisions are a separate entity, recorded in the yaml, not in the issue report). **Second-look review, same day:** re-verified column *values* (not just names) survived the rename correctly — sampled 50 random rows per table, every column, legacy value equals the value under its renamed column, all four tables — and confirmed the legacy yaml's 13-line-shorter line count against the source is pure `yaml::write_yaml()` re-wrapping, not lost content (every non-`name` field across every column compared programmatically, zero diffs, glossary and top-level metadata included). **The BottomDepth fix above only patched the symptom, not the cause — found and fixed properly during this same review.** `data-raw/spec_02_curate_dict.R`'s `add_legacy_field_names()` independently rebuilds its own old-name lookup from `op_datras_field_list()` and never inherited the LT `Depth`/`BottomDepth` exception already applied to the separate `lt_renames` step a few dozen lines above it (~line 166) — so `op_datras_field_list()`'s cross-table inference (correctly: "HH confirms Depth→BottomDepth, LT also has a Depth column, so infer the same rename for LT") wrongly tags LT's real, separate `BottomDepth` column with that inference, with nothing downstream aware of the LT-specific duplication. Confirmed by calling the live function directly: exactly one row matches (`LT, Depth, BottomDepth, cross_table_confirmed`), and the fix (excluding it from `add_legacy_field_names()`'s lookup the same way `lt_renames` already excludes it) removes only that row, leaving all other real LT renames (`Ship`→`Platform` etc.) untouched. Without this, the next full regeneration of `inst/DATRAS-data-dict.yaml` via this script would have silently reintroduced the exact bug just fixed. Also regenerated `vignettes/articles/DATRAS-data-dict.qmd` from the corrected yaml (2-line diff, exactly the BottomDepth/Depth text) and fixed the same stale `inst/ICES_ISSUE_REPORT_20260806.md` path in two more places inside `spec_02_curate_dict.R` itself and one live TODO.md checklist item (left the file's own "Latest" historical narration line untouched, since it's an accurate statement of what was true on 2026-08-06).

**data-raw/ audit and reorg (2026-08-08, same day):** User asked for a deep review of every `data-raw/` script for orphans, duplication, and naming. Traced every `source()` call and `Rscript data-raw/X` invocation across the whole repo (not filenames/headers alone) to build the real dependency graph, confirming two independent pipelines by actual git history: **spec-building** (`spec_00_operation_types.R` → `spec_01_seed_dict.R` → `spec_02_curate_dict.R` → `spec_03_dict_to_qmd.R`, first committed 2026-07-31, builds `inst/DATRAS-data-dict.yaml`) and **data-archival** (`archive_01_download_config.R`/`archive_02_download.R`/`archive_03_catalog.R` → `archive_04_parse_phase2.R` → `archive_05_backfill_lt_partitions.R` → `archive_06_split_legacy_new.R`, first committed 2026-08-05, downloads the real archive and consumes the spec pipeline's yaml). Both renamed from their original flat names (`DATASET_*`, `datras_*`) to this scoped `_0N_` prefix per pipeline — deliberately not one global sequence, since the two pipelines don't actually run in one order.

Removed 6 confirmed-dead scripts, each verified individually rather than assumed from naming: `datras_phase2_stage1.R` (read a spec file, `inst/DATRAS-types-minimal.R`, that doesn't exist — couldn't have run), `xml_to_parquet.R`/`.py` and `xml_to_csv.py` (standalone converters from an earlier iteration, zero callers anywhere, superseded by the inline parser now in `archive_04_parse_phase2.R`), `ices_api.R` (`op_fetch_datras_field_list()`/`op_fetch_vocab_codes()`, zero callers, superseded by the exported `op_datras_field_list()`/`op_vocab_get_codes()`), and `datras_vocabulary.R` (self-declared deprecated in its own header, confirmed zero functional callers — the handful of remaining mentions in `spec_02_curate_dict.R`'s `details:` text are accurate historical citations of what tool verified a specific field on 2026-07-29, deliberately left as-is rather than scrubbed). Found but did **not** remove a third, real duplicate: `archive_03_catalog.R::datras_get_field_list()` is a second live implementation of "fetch getDatrasFieldList," actually called by `archive_02_download.R` to hash the raw response for manifest provenance — a different purpose from the package's own verified `op_datras_field_list()`, not simply redundant.

Also found: `spec_00_operation_types.R`'s own comments reference `data-raw/build_datras_schema.R` and `data-raw/DATASET_RAW.R`, files that don't exist anywhere in opus — leftover narrative from wherever this file was originally written (its header says "built from the obus side"), even though its two functions are genuinely live (sourced by `spec_01_seed_dict.R`). Left as-is (out of scope to rewrite the historical narrative in a file already mid-rename), but worth knowing before trusting those specific comments. Moved the 9 untracked `*_retired.*` files (already `.gitignore`'d by pattern, confirmed via `git check-ignore` — never lost git history since they never had any) into `data-raw/retired/`, and deleted the untracked `data-raw/DATRAS-data-dict_files/` (a stray Quarto render-support directory, no content of value).

Every rename's cross-references were fixed by exhaustive repo-wide grep before and after, not assumed complete after the obvious spots: `source()` calls between the renamed scripts, each renamed file's own usage/help text, `R/field_names.R` + `R/op_minimal_yaml.R` (one of which had a live, executable `source("data-raw/datras_operation_types.R")` call that would have broken `op_minimal_yaml()` if missed) plus the man page that generates from it (regenerated via `devtools::document()`, not hand-edited), `vignettes/articles/technical-notes.md`, `TODO.md`, and this file — including a whole stale "ICES API wrappers" section here describing the just-deleted `ices_api.R` as if still current, and a "Source scripts" entry for `yaml_to_formatted_md.R`, a file already deleted in the *previous* (2026-08-07/08) session and never updated here. One gap the first sweep missed and a second pass caught: a comment inside `spec_02_curate_dict.R`, added earlier this same session, cited `split_legacy_and_new.R` by its pre-rename name — missed because the archive-pipeline and spec-pipeline rename passes were done separately without cross-checking each other's files. `inst/DATRAS-data-dict.yaml`'s own filename citations (an `origin:` field plus a couple of `details:` citations) were hand-patched to match what the corrected generator now produces, rather than re-running the full live-network curate pipeline for a pure filename-string change — then `vignettes/articles/DATRAS-data-dict.qmd`/`DATRAS-known-issues.qmd` regenerated from the corrected yaml and the diff confirmed to be exactly the expected strings, nothing else.
