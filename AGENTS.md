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

opus is **institutional data governance audit infrastructure**, not a data reformatting tool. It systematically exposes where ICES's own metadata sources (WSDL, getDatrasFieldList, icesVocab) diverge from each other and from real submitted data. The known-issues registry is an accountability log — evidence, impact, fix — and this reconciliation work is the actual deliverable; the YAML specs are the vehicle.

1. **Consolidates scattered knowledge** — WSDL, icesVocab, Technical Reference, real submissions — into one authoritative YAML
2. **Documents reality vs. spec** — When real data diverges from official documentation, capture it (not as error, but as known issue)
3. **Enables pre-submission validation** — Submitters can validate locally before uploading to ICES
4. **Escalates problems upstream** — Known-issues registry feeds into imbus/ICES dialogue

See `vignettes/why-opus.qmd` for context and philosophy.

------------------------------------------------------------------------

## Working Principles

**1. Real data is ground truth.** When WSDL/icesVocab/specs conflict with live submissions, trust the submissions; file the divergence as a known issue.

**2. Consolidate scattered knowledge.** WSDL, icesVocab, Technical Reference, real submissions — bring together into one machine-readable place.

**3. Metadata-centric, not domain logic.** opus ships YAML specs + metadata validation and curation tooling (22 R functions). These functions work *on* the specification and data patterns, not *on* domain questions. No contextual QC (e.g., "door spread constraints vs. depth"), no statistical analysis, no derived products. That computational work belongs in obus/imbus.

**4. Don't guess; document.** Every range/constraint/enum needs evidence: real data, WSDL, or icesVocab. Borderline calls get flagged in `details:` for expert review.

**5. Separate concerns: specs ≠ QC.** Known-issues registry documents schema gaps (upstream at ICES). Data-quality problems (wrong values) belong downstream in obus/imbus. opus surfaces whether data violates the *documented* spec; imbus solves whether it's *valid* in context.

**6. Shared fields stay consistent.** HH/HL/CA/LT repeat field names (same facts). Type, units, range must match byte-for-byte across tables.

**7. Adapt when needed.** Principles are Magna Carta, not law. Revisable when practice demands.

**8. Verify empirically.** A claim only counts as checked once confirmed against live, primary data — the real archive, the real service response — not by re-reading a document, a citation, or your own earlier note.

**9. Audit exhaustively.** Cover every relevant variant before concluding something is missing or absent — legacy name and current name, every prefix candidate — not just the first one that resolves. A confirmed null result is only meaningful if it's a null result for the complete set of things worth checking, not a partial one. See the icesVocab field-name dependency note below for the concrete case that forced this rule into existence: each individual check was genuinely empirical (principle 8) yet a sweep still missed the answer because it wasn't exhaustive (principle 9) — the two failures are independent, and both are needed to actually verify something. Full discovery story in `DEVLOG.md` (2026-08-02, 2026-08-08).

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

- Uses relationships, constraints, definitions, glossary, todo (added 2026-08-16, see `DEVLOG.md`); not yet assertions, for which no evidence-backed candidate has been identified (Working Principle 4 — not guessed into existence just because the feature exists)
- One file per tier
- Schema closed: only standard keys allowed

------------------------------------------------------------------------

## Known-Issues Registry

`inst/DATRAS-known-issues.yaml`: Escalation log for ICES Datacenter. Documents where official specs diverge from actual submissions. Schema/vocab problems only (not data-quality issues).

------------------------------------------------------------------------

## Data Sources

opus consolidates metadata from four ICES sources:

1. **WSDL (Web Services Definition Language)**
   - Source: `https://datras.ices.dk/WebServices/DATRASWebService.asmx`
   - Provides: Field types (string/int/decimal) for each operation
   - Authority: Primary—describes what the service actually returns
   - Scope: DATRAS-specific (HH, HL, CA, LT operations only)

2. **getDatrasFieldList API**
   - Source: `https://datras.ices.dk/WebServices/DATRASWebService.asmx/getDatrasFieldList`
   - Provides: Field name mappings (old → new), descriptions
   - Authority: Secondary — derived from WSDL and internal DATRAS schema, and confirmed unreliable (6 confirmed errors: LT coverage gap, wrong LT renames, a phantom field, an unverifiable CA rename, missing entries, a data-duplication miss — filed with ICES, see `data-raw/ICES_ISSUE_REPORT.md`; full findings in `DEVLOG.md` 2026-08-06)
   - Scope: DATRAS-specific (no other ICES products)
   - Note: DataFormat field can diverge from WSDL; opus sources types from WSDL directly

3. **icesVocab (ICES Vocabularies)**
   - Source: `https://vocab.ices.dk/services/api/`
   - Provides: Code definitions and meanings (e.g., Gear codes, species validation)
   - Authority: Cross-domain reference—used by multiple ICES data systems
   - Scope: Not DATRAS-exclusive; opus filters to vocabularies applicable to DATRAS fields
   - Note: Provides code semantics only, not structural types. Keyed by each field's **legacy** (on-the-wire) name, not its current opus name — see the icesVocab field-name dependency note under Key Facts below. Each code-type also carries a `Guid` (`op_vocab_get_types()`); a GUID match is exact and ICES-declared, unlike every name-based match in this package, which is always a guess (`op_vocab_resolve_guid()`, added 2026-08-17 — see `DEVLOG.md`).

4. **DATRAS field-description spreadsheet** (found 2026-08-17 — see `DEVLOG.md`)
   - Source: linked from `https://www.ices.dk/data/data-portals/Pages/DATRAS_format_description.aspx`, currently `DATRAS_Field_descriptions_and_example_file_December2025.xlsx`; fetched by `data-raw/build_field_description_snapshot.R`
   - Provides: per-field `Mandatory`/`DataType`/`Description`, an ICES-wide general convention ("submit -9 for a field with no information"), and occasionally a direct icesVocab GUID
   - Authority: Closest thing to a real Technical Reference opus has — but hand-maintained (dated filename, prose version notes), not an API, and not kept in sync with the other three sources (its `Vocab` column is populated in only 1 of 154 field rows)
   - Scope: DATRAS-specific
   - Note: A versioned document, not a stable endpoint — re-run the build script periodically rather than treating one snapshot as permanently current

opus unifies these four sources into a single YAML specification, making inconsistencies visible and escalatable to ICES — the disparity between them (four sources, four formats, no single owner keeping them in sync) is itself part of what opus's known-issues registry exists to surface.

**No R-package dependency on either `icesDatras` or `icesVocab`** (removed 2026-08-06): opus calls these two web services directly (`R/vocab.R`, `R/field_names.R`'s `op_datras_field_list()`), verifying every claim against at least two independent live sources rather than trusting either service's metadata blindly. Full history of this removal, and of a since-corrected attribution error that had described the real `icesDatras` package as hand-patching data it doesn't actually patch, in `DEVLOG.md` (2026-08-06, 2026-08-09).

------------------------------------------------------------------------

## Implementation

**User-facing exported functions** (22 total):

*Specification validation, parquet exploration, and drafting* (`R/validation.R` -- all of them; despite the name, `op_describe_parquet()`/`op_draft_from_parquet()` live here too, not in a separate file):
- `op_validate_spec(dict_path, json)` — Check YAML spec conformation (uses data-dict CLI); `json=TRUE` also returns the structured report (`$report`)
- `op_validate_meta(data_path, table, dict_path)` — Validate column names/types
- `op_validate_data(data_path, table, dict_path)` — Validate values vs constraints
- `op_validate_full(data_path, table, dict_path)` — Run all three checks
- `op_inspect_parquet(parquet_path)` — See what data-dict CLI sees
- `op_flag_violations(data_path, table, dict_path)` — Flag EVERY row violating required/enum/range constraints, exhaustively. Complements, not superseded by, the CLI's own report (`op_validate_meta()`/`op_validate_data()`'s `$result`, `op_validate_spec(json=TRUE)`'s `$report`): the report is capped at the first 5 rows/problem (no CLI flag raises this — see `site/report.md#counting-and-capping` in the data-dict repo), so this function still exists specifically for exhaustive marking.
- `op_validation_problems(report)` — Flatten any of the above reports' `problems` into a data frame (pure reshaping, no new checks)
- `op_describe_parquet(parquet_path)` — Describe parquet structure and statistics
- `op_draft_from_parquet(parquet_paths, output_path)` — Generate skeleton YAML from parquet data
- `op_export_spec(dict_path)` — Export a fully-resolved dictionary as JSON (wraps data-dict CLI's `export-spec`)
- `op_export_data(dict_path)` — Export a dictionary with per-column data profiles as JSON (wraps data-dict CLI's `export-data`)
- `op_render_spec(dict_path, output, data_dir)` — Render a dictionary as a self-contained HTML page (wraps data-dict CLI's `render`); on-demand tool only, nothing shipped/committed. `data_dir` (e.g. `.datras/`) profiles against a full local archive instead of the shipped `inst/*.parquet` samples.

*ICES Vocabulary utilities* (`R/vocab.R`):
- `op_vocab_get_types()` — Get all ICES vocabulary code-types with prefix metadata
- `op_vocab_resolve_key(field_name, types)` — Find candidate vocabulary keys for a field, given the full domain table from `op_vocab_get_types()`
- `op_vocab_resolve_guid(guid, types)` — Resolve an ICES Vocabulary GUID to its key. Exact and ICES-declared, unlike every name-based match in this package — use whenever an external source (e.g. the field-description spreadsheet's `Vocab` column) hands you one.
- `op_vocab_get_codes(vocab_key)` — Fetch code:description pairs for a vocabulary
- `op_vocab_first_usable(vocab_keys)` — Select first non-empty vocabulary from candidates
- `op_vocab_resolve_datras_key(table, field)` — Look up opus's own audited vocab-key proposal for a Tier 1 field from the pre-computed correction table (`inst/DATRAS-vocab-correction.csv`)

*Field name utilities* (`R/field_names.R`):
- `op_legacy_field_name(details)` — Extract legacy (old ICES) field name from YAML details
- `op_field_name_map(dict, table_name=NULL)` — Build legacy→new field name mapping table
- `op_datras_field_list(tables)` — Derive verified Tier 1 old-name→new-name mappings directly from ICES's live services (replaces `icesDatras::getDatrasFieldList()`); tiers each mapping as `confirmed` / `cross_table_confirmed` / `no_evidence` rather than trusting ICES's field-list metadata blindly. See its own roxygen docs for the six confirmed ICES-side errors this caught.
- `op_datras_rename_crosswalk()` — The legacy→curated rename table `spec_03_translate_new_names.R` actually applies (wraps `op_datras_field_list()`, with the one known correction and a general collision guard, not a hardcoded special case)

These wrappers enable the curation loop: build YAML → validate against real data → identify issues → refine YAML. The **descriptive YAML** (DATRAS-data-dict.yaml) is the reference for what exists in practice, including both icesVocab-defined codes and undocumented variants observed in submissions.

**Development-only functions:** none. The original three-phase bootstrap workflow's six functions were removed 2026-08-17, superseded by the `data-raw/spec_00`-`03` scripts since 2026-08-05/08 (see [[project_bootstrap_yaml_workflow]] for the original rationale, `DEVLOG.md` 2026-08-17 for the removal).

**`NAMESPACE` is roxygen2-generated** (since 2026-08-17 — see `DEVLOG.md`): every `@export`-tagged function is live automatically; `devtools::document()` regenerates the file completely, so it never needs hand-editing and can never again silently drift from what's actually tagged `@export` in the source (the exact failure mode behind the six dead functions above, and behind `op_vocab_resolve_guid()` needing a manual NAMESPACE edit just before this).

**Source scripts** (`data-raw/`, spec-building pipeline, keyed by legacy field names throughout except the final translate step):
- `spec_00_operation_types.R` — WSDL operation-page crawler (`.fetch_datras_operation_fields()`'s data source); sourced by `spec_01_seed_dict.R`
- `spec_01_seed_dict.R` — pull specs from live WSDL + getDatrasFieldList + icesVocab (no corrections); keyed by ICES's own legacy (real, on-the-wire) field names
- `spec_02_curate_dict.R` — apply hand-written corrections, enrich enums, keyed by legacy field names throughout; writes `inst/DATRAS-data-dict-legacy.yaml`
- `spec_03_translate_new_names.R` — pure rename, legacy → opus's curated names, via `op_datras_rename_crosswalk()` (`R/field_names.R`); writes `inst/DATRAS-data-dict.yaml`, the only step that introduces new names at all

Rendering (a hand-rolled Quarto generator's old job) is now handled by data-dict's own `render` command (`op_render_spec()`, `R/validation.R`) — a self-contained HTML page with a relationship diagram, searchable index, and live data profiling. `known-issues.yaml` has no `render` equivalent (it isn't a real data-dict.yaml document) and stays plain YAML.

There is a second, separate pipeline (`data-raw/archive_0N_*`) that downloads and converts the real DATRAS archive rather than building the spec:
- `archive_01_download_config.R` / `archive_02_download.R` / `archive_03_catalog.R` — download the raw XML and build a manifest
- `archive_04_parse_phase2.R` / `archive_05_backfill_lt_partitions.R` — parse XML → parquet with rigid, WSDL-only type casting (`archive_00_wsdl_types.R`, `apply_wsdl_types()`). Deliberately does *not* know the yaml, "enum," a completeness/required-fields gate, or sentinel scrubbing exist — those are all curation-stage judgments made downstream from real (unscrubbed) data, not type-casting decisions. Each script carries its own copy of the XML parser; see the source for why.
- `archive_06_split_legacy_new.R` — consolidates into `.datras/{TABLE}_legacy.parquet` (legacy names, full archive) and `.datras/{TABLE}.parquet` (opus-curated names — rename is the only difference), rebuilding from the partitioned directory every run so provenance is always known

Full construction history, reorg, and bug fixes for both pipelines are in `DEVLOG.md`.

------------------------------------------------------------------------

## Key Facts

**Scope clarity: opus is WP2 (reference spec); WP3 owns operational QC on vessels.** opus's task is the reference YAML specification and processed data products for imbus's WP2. imbus's **QC work** (on-vessel quality control, including domain violations like "door spread constraints depend on depth") lives in **WP3** (Marine Institute, Stokes) — a separate workpackage that requires operational QC tooling, not data-dictionary work.

**data-dict's realistic role:** data-dict covers three validation levels (spec/metadata/data) — sufficient for catching schema violations and basic constraint checking. But imbus's **operational QC** (multivariate co-parameter rules, on-vessel validation logic, domain-specific limits) is beyond data-dict's scope. opus **optionally** wraps data-dict for basic validation (if/when R-package matures); but the heavy QC lifting belongs to WP3's operational tools.

**Why we monitor data-dict:** Prevents reinventing spec validation; clarifies boundaries. When their R-package ships, opus can offer it as a user convenience (via thin wrappers). But WP3 should not expect data-dict to solve their operational QC problem — that's a separate engineering effort. Monitoring helps opus stay proportionate and avoid scope creep into work that's not ours. See [[data_dict_trajectory]] and [[imbus_structure]] for roadmaps.

**icesVocab is keyed by each field's legacy (on-the-wire) name, not its current opus name — resolve the legacy name first, always check both.** DATRAS fields have two names (legacy ICES names and opus's current names), and icesVocab code lookups depend on which one is used — sometimes pointing to entirely different vocabularies. Example: `Sex` has `TS_Sex`/`AC_Sex` (ambiguous between trawl/acoustic domains), but `IndividualSex` does not; `GearEx` has `TS_GearEx` (13 codes) while `GearExceptions` has `AC_GearExceptions` (1 code). A full audit of all 190 Tier 1 fields found this is the rule, not an occasional pitfall: of the 21 renamed enum fields with any vocab match, 100% resolve via the legacy name, 0% via the current name. Document legacy names in each column's `details:` via `Legacy field name: {OldName}`; use the dual-lookup wrappers in `R/vocab.R` + `R/field_names.R` for anything new. Full discovery story — including a case where resolving only the current name produced a false "missing from vocab" finding — is in `DEVLOG.md` (2026-08-02, 2026-08-08).
