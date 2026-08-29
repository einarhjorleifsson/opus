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

------------------------------------------------------------------------

## Working Principles

**1. Real data is ground truth.** When WSDL/icesVocab/specs conflict with live submissions, trust the submissions; file the divergence as a known issue.

**2. Consolidate scattered knowledge.** WSDL, icesVocab, Technical Reference, real submissions — bring together into one machine-readable place.

**3. Metadata-centric, not domain logic.** opus ships YAML specs + metadata validation, conversion and curation tooling (34 R functions). These functions work *on* the specification and data patterns, not *on* domain questions. No contextual QC (e.g., "door spread constraints vs. depth"), no statistical analysis, no derived products. That computational work belongs in obus/imbus.

**4. Don't guess; document.** Every range/constraint/enum needs evidence: real data, WSDL, or icesVocab. Borderline calls get flagged in `details:` for expert review.

**5. Separate concerns: specs ≠ QC.** Known-issues registry documents schema gaps (upstream at ICES). Data-quality problems (wrong values) belong downstream in obus/imbus. opus surfaces whether data violates the *documented* spec; imbus solves whether it's *valid* in context.

**6. Shared fields stay consistent.** HH/HL/CA/LT repeat field names (same facts). Type, units, range must match byte-for-byte across tables.

**7. Adapt when needed.** Principles are Magna Carta, not law. Revisable when practice demands.

**7b. No similar code in `data-raw/` and `R/`, ever.** `data-raw/` may *call* `R/` and add orchestration on top -- caching, looping, file layout -- but never re-implement it. A ported copy is a duplicate, and a verbatim behavioural copy is the worst kind because it drifts silently the first time either side is touched. The vocab helpers are the model: `get_codes_cached()` and friends call `op_vocab_get_codes()` and add only caching. Anything a downstream package or an article would need to call belongs in `R/`, exported.

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

**Why we monitor data-dict:** data-dict's three-level validation (spec/metadata/data) covers the basic checks; its R-package (`datadict`, shipped 2026-08-27, CRAN-track — see Key Facts below) gives downstream users of opus's yaml a zero-setup way to run that validation themselves. But imbus's **real QC work** — complex contextual rules like "door spread limits depend on depth" — is beyond data-dict's scope and belongs to imbus's own QC workpackage. We track data-dict to prevent reinventing spec validation, but set realistic expectations about what it can deliver. See [[data_dict_trajectory]] for roadmap.

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

**User-facing exported functions** (34 total; the rendered index is `articles/reference.qmd`, generated from `man/*.Rd` by `data-raw/build_reference.R`):

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
- `op_render_spec(dict_path, output, data_dir)` — Render a dictionary as a self-contained HTML page (wraps data-dict CLI's `render`); on-demand tool only, nothing shipped/committed. `data_dir` (e.g. `.datras/to_https/raw`) **injects a `source:` for any table that declares none**, which is what makes the page profile real data at all — data-dict renders spec-only unless at least one table's source file is present, and the shipped dictionary deliberately declares no source (the archive is not in the repository, so a committed path would dangle for everyone but whoever built it).

*Reading the DATRAS web service* (`R/datras_service.R` -- the single implementation of the ASMX crawl; nothing in `data-raw/` may re-implement it, see Working Principle 7b):
- `op_datras_operations()` — every operation the service currently exposes. Doubles as the migration tripwire: ICES converts tables to current field names one at a time, and each converted table appears as a new `…NewHeaders` operation.
- `op_datras_operation_types(operation)` — the fields *and WSDL types* one operation actually returns
- `op_datras_field_metadata()` — `getDatrasFieldList` as ICES publishes it, unverified. Not to be confused with `op_datras_field_list()`, which is what survives cross-checking; this one is what ICES *claims*.

*XML → parquet conversion* (`R/cast.R`, `R/rename.R`, `R/sentinels.R`) — four steps whose order is load-bearing, exported so a downstream package calling them on its own live fetch gets a result identical to the published archive rather than a near-miss:
- `op_cast_wsdl_types(df, table)` — physical types from the WSDL; **sentinels preserved exactly**. Deciding which sentinels mean "missing" is not a type-casting decision.
- `op_rename_to_new(df, table)` — legacy → current names, asserting the incoming columns against the crosswalk first. Self-retiring: applied to data already in current names it alters nothing, so an ICES-side flip breaks nothing.
- `op_strip_sentinels(df, table)` — `-9` → `NA` where it means absence, per the registry
- `op_cast_to_spec(df, table)` — the semantic types the wire cannot express (`date`). **Refuses** to convert a column holding anything it cannot parse rather than producing `NA`.
- `op_wsdl_type_overrides()` — the documented per-field exceptions where the WSDL is wrong, or where the dictionary's `enum` typing requires string-like storage

*Sentinel policy* (`R/sentinels.R`):
- `op_sentinels()` — the registry accessor (`inst/DATRAS-known-issues.yaml`'s `sentinels:` block)
- `op_sentinel_policy(table)` — the per-column verdict, with the reasoning attached
- `op_sentinel_audit(path, table)` — sentinel counts per column in a real parquet file; both the evidence behind each decision and the regression check afterwards

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

  Both resolve over the **full Tier 1 set regardless of `tables`**, and narrow only at the end. Tier 2 borrows a `confirmed` mapping from another table, so resolving a single table leaves nothing to borrow from — and the result degrades silently rather than erroring. Asked for `"LT"` alone the crosswalk returns 1 rename instead of 23, because ICES documents `Ship`/`StNo`/`HaulNo` and 34 more as renamed for HH/HL/CA but not for LT.

These wrappers enable the curation loop: build YAML → validate against real data → identify issues → refine YAML. The **descriptive YAML** (DATRAS-data-dict.yaml) is the reference for what exists in practice, including both icesVocab-defined codes and undocumented variants observed in submissions.

**Development-only functions:** none. The original three-phase bootstrap workflow's six functions were removed 2026-08-17, superseded by the `data-raw/spec_00`-`03` scripts since 2026-08-05/08 (see [[project_bootstrap_yaml_workflow]] for the original rationale, `DEVLOG.md` 2026-08-17 for the removal).

**`NAMESPACE` is roxygen2-generated** (since 2026-08-17 — see `DEVLOG.md`): every `@export`-tagged function is live automatically; `devtools::document()` regenerates the file completely, so it never needs hand-editing and can never again silently drift from what's actually tagged `@export` in the source (the exact failure mode behind the six dead functions above, and behind `op_vocab_resolve_guid()` needing a manual NAMESPACE edit just before this).

**Source scripts** (`data-raw/`, spec-building pipeline, keyed by legacy field names throughout except the final translate step):
- (the former `spec_00_operation_types.R` crawler is gone — it was a second copy of `R/field_names.R`'s ASMX parser; both are now `op_datras_operation_types()`, `R/datras_service.R`)
- `spec_01_seed_dict.R` — pull specs from live WSDL + getDatrasFieldList + icesVocab (no corrections); keyed by ICES's own legacy (real, on-the-wire) field names
- `spec_02_curate_dict.R` — apply hand-written corrections, enrich enums, keyed by legacy field names throughout; writes `inst/DATRAS-data-dict-legacy.yaml`
- `spec_03_translate_new_names.R` — pure rename, legacy → opus's curated names, via `op_datras_rename_crosswalk()` (`R/field_names.R`); writes `inst/DATRAS-data-dict.yaml`, the only step that introduces new names at all

Rendering (a hand-rolled Quarto generator's old job) is now handled by data-dict's own `render` command (`op_render_spec()`, `R/validation.R`) — a self-contained HTML page with a relationship diagram, searchable index, and live data profiling. `known-issues.yaml` has no `render` equivalent (it isn't a real data-dict.yaml document) and stays plain YAML.

There is a second, separate pipeline (`data-raw/archive_0N_*`) that downloads and converts the real DATRAS archive rather than building the spec:
- `archive_01_download_config.R` / `archive_02_download.R` / `archive_03_catalog.R` — download the raw XML and build a manifest
- `archive_04_parse_phase2.R` / `archive_05_backfill_lt_partitions.R` — parse XML → parquet, then chain the four `opus::` conversion calls in order (cast → rename → strip sentinels → cast to spec). These scripts hold **no conversion logic of their own**; the former `archive_00_wsdl_types.R` is gone, its `apply_wsdl_types()` now `op_cast_wsdl_types()` in `R/cast.R`. Phase A is still WSDL-only and still does not know the yaml or the word "enum": enum-ness is a curation conclusion drawn from archive data, so it cannot be an input to building that archive without circularity. Each script carries its own copy of the XML parser; see the source for why.
- `archive_06_consolidate.R` — consolidates the partitioned output into `.datras/to_https/raw/{TABLE}.parquet`, current names only, rebuilding from the partitioned directory every run so provenance is always known. Legacy-named output is no longer produced: opus publishes one name per table. Two whole-table assertions live here (no legacy column names survived; the sentinel policy held all-or-nothing per column); the per-file crosswalk ground-truth check moved into `op_rename_to_new()`, which now runs it on every file rather than once per consolidation.
- **Data-wise the rebuild depends only on `.datras/xml/`.** `archive_05` derives survey/year/quarter from the directory path and reads neither the manifest nor the catalog; the four conversion functions read no `.datras` file at all (types and crosswalk come from the live service, the registry and dictionary from the installed package's `inst/`).

Full construction history, reorg, and bug fixes for both pipelines are in `DEVLOG.md`.

**Standalone audit tooling** (`data-raw/`, not part of either pipeline above — each re-run independently, on demand, to verify or re-derive a specific cross-source fact rather than to build a shipped artifact):
- `build_vocab_correction.R` — for each of the ~55 Tier 1 enum fields, picks the best-fitting icesVocab key and reports the fit; writes `inst/DATRAS-vocab-correction.csv`, read at runtime by `op_vocab_resolve_datras_key()`
- `build_vocab_field_audit.R` — the same name-match/value-fit check extended to all 190 Tier 1 fields, not just the already-curated enums (`vocab_fit_helper.R`'s `pick_best_vocab_match()` is shared by both, factored out once rather than duplicated)
- `build_icesvocab_snapshot.R` — full-catalog bulk download of every icesVocab code-type's codes (opus's own direct HTTP, not the `icesVocab` package), cached under `.datras/ices-schemas/` with hash-stamped provenance; makes audits needing many codes at once fast and reproducible instead of hundreds of live calls per run
- `build_field_description_snapshot.R` — downloads and caches the DATRAS field-description spreadsheet (opus's 4th data source, above), same caching convention
- `build_reference.R` — regenerates `articles/reference.qmd` from `man/*.Rd`, so the site's function index cannot drift from the roxygen. Grouping is hand-maintained the way a pkgdown reference section would be, and the script **fails** if an exported function belongs to no group — adding an export forces a decision about where it belongs.
- `build_field_gap_audit.R` — cross-references real sentinel usage, icesVocab coverage, and the field-description spreadsheet's `Mandatory`/`DataType` columns against opus's own spec for all 190 fields at once; this is what surfaced the 2026-08-17 fixes above (13 stale-citation fields, 35 missing-`required` fields, `Year`/`SpecCode`'s type divergence) — none of which either of the two audits above, run independently, had ever caught, because they'd never been cross-referenced against each other. Worth re-running whenever the field-description spreadsheet gets a new dated version, not treated as a one-off.

------------------------------------------------------------------------

## Key Facts

**`raw/` is the minimum faithful rendering of the exchange data as parquet, and that is the test for what belongs in it.** `.datras/to_https/raw/{HH,HL,CA,LT}.parquet` are the ICES exchange tables, not products. Work belongs there only if parquet cannot represent the data honestly without it: current field names, WSDL-derived types, `-9` resolved to a real null where it means absence, and a date stored as a `DATE`. Anything computed -- derived quantities, joins, unit conversions, CPUE -- is a downstream product and belongs at the `datras/` root, not here.

**The catalog lives with what it describes: `raw/catalog.duckdb`.** It is built from `inst/DATRAS-data-dict.yaml`, which covers Tier 1 exchange tables only, so for now it describes exactly the four files beside it. Downstream products may get their own catalog rather than sharing this one; keeping each catalog next to its own layer is what makes that possible without renaming anything. Nothing constrains the placement mechanically -- the view URLs are absolute -- so moving it later is a one-line change and a re-upload.


**The published parquet carries no sentinel, except where `-9` is a documented answer.** Parquet has a native null; `-9` is an artifact of a fixed-width text format that cannot express missingness, and carrying it forward makes every naive `mean()` silently wrong. But it cannot be stripped blindly: ICES overloads the value. Of the 29 Tier 1 enum fields whose `values:` map documents a `-9` code, 24 label it as absence (`Not known`, `Not available`, `Unknown`, …) and 5 as a real answer (`No ticklers are allowed`, `No plus group`, `Invalid hauls`). **Neither the value nor its prevalence is the discriminator — the published label is.** `Tickler` is ~78% `-9` and real; `Turbidity` is ~99.6% `-9` and simply never recorded. The policy (registry `sentinels: resolution`) strips by default, keeps where the vocabulary documents a real answer, and resolves an unrecognised label to *keep* — never silently destroying a documented code. That `-9` means two things inside one vocabulary is an ICES-side defect and is recorded as such.

**Ordering in the conversion is load-bearing, and getting it wrong is silent.** Cast → rename → strip sentinels → cast to spec. The WSDL type map is keyed by each operation's own (legacy) field names, so casting must precede renaming. The sentinel registry is keyed by current names, so the strip must follow it. And a `Date` column cannot hold `-9`, so the semantic cast must come last — converting `DateofCalculation` while sentinels are present turns every one into a null, a conversion that is individually correct, collectively destructive, and reports nothing. `op_cast_to_spec()` refuses to convert anything it cannot parse rather than producing `NA`, as the backstop.

**An `enum`'s data must be string-like, and retyping to a number deletes its labels.** data-dict's own rule (`site/validation.md`, "Enum membership") makes an integer-stored `enum` a type mismatch (M01); `S07` separately forbids a `values:` map on a `number(*)` column. So each such field is a judgement, not a rule: `Quarter`/`Month` became `number(ordinal)` (their labels restate the number), while `Tickler`/`SpeciesCategory` stay enums stored as **text** — their 32 and 56 codes carry meaning, and the labels reach users through the catalog's `enum_labels` table. "Make the validator pass" is not the goal; which side moves is a question about what the specification is for.

**`op_validate_meta()` against the published archive is the gate.** All four tables validate clean (194 checks, 0 failures). Treat any regression there as a release blocker rather than a note — it is the only automated check that the dictionary and the data still describe each other.


**Scope clarity: opus is WP2 (reference spec); WP3 owns operational QC on vessels.** opus's task is the reference YAML specification and processed data products for imbus's WP2. imbus's **QC work** (on-vessel quality control, including domain violations like "door spread constraints depend on depth") lives in **WP3** (Marine Institute, Stokes) — a separate workpackage that requires operational QC tooling, not data-dictionary work.

**data-dict's realistic role:** data-dict covers three validation levels (spec/metadata/data) — sufficient for catching schema violations and basic constraint checking. But imbus's **operational QC** (multivariate co-parameter rules, on-vessel validation logic, domain-specific limits) is beyond data-dict's scope. opus wraps data-dict for basic validation via its own `R/validation.R` (thin wrappers around the CLI); the heavy QC lifting belongs to WP3's operational tools.

**data-dict's own R-package (`datadict`, shipped, CRAN-track) is a separate, narrower thing:** it's consumer-facing — `dd_install()` + `dd_validate_data()` — for someone with data and a dictionary who wants a zero-setup validate-and-view-HTML-report flow. It doesn't expose validate-spec/meta, export, render, describe, or draft separately, and it can't inject a `source:` path the way opus's own `validate_against_dict()` does, so it doesn't replace opus's tooling. Worth pointing WP3 or ICES submitters at, if they want to self-check data against opus's yaml without building anything.

**Why we monitor data-dict:** Prevents reinventing spec validation; clarifies boundaries. WP3 should not expect data-dict to solve their operational QC problem — that's a separate engineering effort. Monitoring helps opus stay proportionate and avoid scope creep into work that's not ours. See [[data_dict_trajectory]] and [[imbus_structure]] for roadmaps.

**icesVocab is keyed by each field's legacy (on-the-wire) name, not its current opus name — resolve the legacy name first, always check both.** DATRAS fields have two names (legacy ICES names and opus's current names), and icesVocab code lookups depend on which one is used — sometimes pointing to entirely different vocabularies. Example: `Sex` has `TS_Sex`/`AC_Sex` (ambiguous between trawl/acoustic domains), but `IndividualSex` does not; `GearEx` has `TS_GearEx` (13 codes) while `GearExceptions` has `AC_GearExceptions` (1 code). A full audit of all 190 Tier 1 fields found this is the rule, not an occasional pitfall: of the 21 renamed enum fields with any vocab match, 100% resolve via the legacy name, 0% via the current name. Document legacy names in each column's `details:` via `Legacy field name: {OldName}`; use the dual-lookup wrappers in `R/vocab.R` + `R/field_names.R` for anything new. Full discovery story — including a case where resolving only the current name produced a false "missing from vocab" finding — is in `DEVLOG.md` (2026-08-02, 2026-08-08).
