# opus — ICES DATRAS data dictionary and known-issues registry

**Status:** active. Version 0.3.0. The published archive was last rebuilt on
2026-10-04. Open work is in `TODO.md`; dated history, measurements and how
things were found are in `DEVLOG.md`; earlier versions of this file are in git.

------------------------------------------------------------------------

## The YAML is the deliverable

opus produces three YAML specifications:

1. **`inst/DATRAS-imbus.yaml`** — the archive-side specification of Tier 1 (HH,
   HL, CA, LT): what the published archive actually contains, grounded in it.
   Enum values are restricted to codes observed in the archive (a new code in new
   data fails D04 and needs review: a data error or a genuinely new code);
   physical non-negativity is expressed as `assert:` constraints. Keyed by opus's
   current field names; each column's `details` carries the legacy on-the-wire
   name.
2. **`inst/DATRAS-ices.yaml`** — ICES's own documented view of the same format,
   consolidated faithfully from ICES's four metadata sources (WSDL,
   `getDatrasFieldList`, icesVocab, the field-description spreadsheet) with no
   corrections applied. Where ICES's sources disagree, the conflict is noted in
   `details`, not resolved. The difference between this file and
   `DATRAS-imbus.yaml` is the corrections story for the ICES Data Centre.
3. **`inst/DATRAS-known-issues.yaml`** — the registry of where ICES's
   specification and the submitted data part company: type mismatches,
   undocumented codes, incomplete vocabularies, systemic submission patterns a
   reader of the archive must know about, and their escalation status with ICES.

The R package provides thin tooling around these files: validation, generation
scripts, readers for the published archive. The YAML itself is the reference —
portable, language-agnostic, usable by any tool.

------------------------------------------------------------------------

## What the project does

opus is data-governance audit infrastructure, not a data-reformatting tool. It
exposes where ICES's own metadata sources diverge from each other and from the
data actually submitted. The registry is an accountability log — evidence,
impact, fix — and that reconciliation is the deliverable; the YAML specifications
are the vehicle.

1. **Consolidates scattered knowledge** — WSDL, icesVocab, the field
   descriptions, real submissions — into one machine-readable specification.
2. **Documents reality against the specification** — where the data diverges
   from the documentation, it is captured as a known issue, not as an error.
3. **Enables pre-submission validation** — submitters can validate locally before
   uploading to ICES.
4. **Escalates upstream** — the registry feeds the IMBUS and ICES dialogue.

------------------------------------------------------------------------

## Working principles

**1. Real data is ground truth for what the archive contains.** When the WSDL,
icesVocab or a specification conflicts with live submissions, trust the
submissions and file the divergence as a known issue.

**2. Consolidate scattered knowledge** into one machine-readable place.

**3. Metadata-centric, not domain logic.** opus ships the specifications and
tooling that works *on* them — validation, conversion, curation. No contextual QC
("door spread against depth"), no statistics, no derived products; that work
belongs in obus and imbus.

**4. Don't guess; document.** Every range, constraint and enum needs evidence:
real data, the WSDL or icesVocab. Borderline calls are flagged in `details:` for
expert review.

**5. Specifications are not QC.** The registry records what a reader of the
archive must know to read it correctly: schema and vocabulary gaps at ICES, and
systemic submission patterns (records that cannot be linked to a haul, a missing
raising factor). Whether a value is plausible in context is downstream, in obus
and imbus. opus surfaces whether data violate the *documented* specification;
imbus decides whether they are *valid* in context.

**6. Shared fields stay consistent.** HH, HL, CA and LT repeat field names for the
same facts; type, units and range match across tables.

**7. Principles are Magna Carta, not dogma** — revisable when practice demands.
Use them to explain surprising state before doubting the design.

**7b. No similar code in `data-raw/` and `R/`, ever.** `data-raw/` may *call*
`R/` and add orchestration — caching, looping, file layout — but never
re-implement it. A ported copy drifts silently the first time either side is
touched. The vocab helpers are the model: `get_codes_cached()` calls
`op_vocab_get_codes()` and adds only caching. Anything a downstream package or an
article needs belongs in `R/`, exported.

**8. Verify empirically.** A claim is checked only once confirmed against live,
primary data — the real archive, the real service response — not by re-reading a
document, a citation, or an earlier note.

**9. Audit exhaustively.** Cover every relevant variant before concluding that
something is missing — legacy name and current name, every prefix candidate —
not just the first that resolves. A null result means something only for the
complete set of things worth checking. Empirical (8) and exhaustive (9) are
independent failures, and both are needed.

------------------------------------------------------------------------

## Task and boundaries

**opus feeds IMBUS WP2 (the reference specification):** the most accurate DATRAS
dictionary, verified against real submissions, with upstream divergences flagged
and escalated to ICES.

**opus does not** build QC infrastructure (contextual validation is WP3's,
on-vessel tooling), compute or transform data, report on data quality
independently, or solve multivariate constraints beyond data-dict's scope.

**Thin wrappers only.** Glue around external tools is fine — `op_validate_spec()`,
`op_validate_meta()`, `op_validate_data()` and `op_validate_full()` wrap the
data-dict CLI for its three levels of validation. Computation is not.

**data-dict's role.** Its three levels (spec, metadata, data) catch schema
violations and basic constraints; operational QC (co-parameter rules, on-vessel
limits) is beyond it and belongs to WP3. data-dict's own R package (`datadict`,
CRAN-track) is consumer-facing — install, validate data, view a report — and does
not expose spec/meta validation, export, render, describe or draft, nor inject a
`source:` path the way opus's wrappers do, so it complements opus's tooling rather
than replacing it. Worth pointing WP3 or ICES submitters at for a zero-setup
self-check against opus's YAML. opus watches data-dict so as not to reinvent
specification validation, and so that WP3 does not expect it to solve their QC.

### Decision gate for new work

1. Does it improve the YAML specification (types, constraints, values, known
   issues)?
2. If it is code: does it work *on* the specification (validation, curation,
   metadata utilities — opus) or *with* it (domain QC, contextual constraints,
   transformation — obus or imbus)?
3. Will it help submitters validate locally, or maintainers curate?
4. If uncertain, flag it for an explicit decision first.

------------------------------------------------------------------------

## Scope

- **Tier 1, DATRAS exchange data:** HH (hauls), HL (length frequencies), CA
  (biological data), LT (litter; partly novel observations, partly lookups and
  joins to HH).
- **Tier 2, DATRAS products computed from Tier 1** (CPUEL, CPUEA, FL, IDX):
  not curated yet.
- **Tier 3, obus's derived products:** contracts and derivatives built on opus's
  specifications; not curated yet.

------------------------------------------------------------------------

## Format: data-dict.yaml v0.1.0

Uses relationships, constraints, definitions, glossary, `todo`, and `assert:`
(non-negativity on every physically non-negative `number(quantity)` field; the
archive holds negative haul durations and ages). One file per tier; the schema is
closed, so only standard keys are allowed.

------------------------------------------------------------------------

## Data sources

opus consolidates metadata from four ICES sources:

1. **WSDL** — `https://datras.ices.dk/WebServices/DATRASWebService.asmx`. Field
   types (string/int/decimal) per operation; primary, because it describes what
   the service actually returns. DATRAS operations only (HH, HL, CA, LT).
2. **`getDatrasFieldList`** —
   `https://datras.ices.dk/WebServices/DATRASWebService.asmx/getDatrasFieldList`.
   Old-to-new name mappings, descriptions and a `DataFormat` per record type and
   field. Secondary, and unreliable in specific, documented ways (filed with ICES;
   `articles/issues.qmd`). Its `DataFormat` diverges from the WSDL (for example
   `Year` is `char`, `Distance` is `float`), so opus sources types from the WSDL.
   It also documents fields the WSDL does not serve, and some of its descriptions
   are misplaced (the FA record's are shifted by one row). Its XML namespace is
   `ices.dk.local/DATRAS`; opus parses it by regex (`op_datras_field_metadata()`).
3. **icesVocab** — `https://vocab.ices.dk/services/api/`. Code definitions and
   meanings, cross-domain (opus filters to vocabularies that apply to DATRAS
   fields). Code semantics only, not types, and keyed by each field's **legacy**
   name (Key facts). Each code type carries a `Guid`; a GUID match is exact and
   ICES-declared, unlike every name-based match, which is a guess
   (`op_vocab_resolve_guid()`).
4. **The DATRAS field-description spreadsheet**, linked from
   `https://www.ices.dk/data/data-portals/Pages/DATRAS_format_description.aspx`
   and fetched by `data-raw/audit/build_field_description_snapshot.R`.
   Per-field `Mandatory`, `DataType` and `Description`, an ICES-wide convention
   ("submit -9 for a field with no information"), and occasionally a vocabulary
   GUID. The nearest thing to a technical reference — but hand-maintained, dated
   in its filename, not an API, not kept in sync with the other three (its
   `Vocab` column is rarely filled). Re-run the build script when a new dated
   version appears.

The disparity between the four (four formats, no single owner keeping them in
sync) is itself part of what the registry exists to surface.

**No R-package dependency on `icesDatras` or `icesVocab`.** opus calls both web
services directly (`R/vocab.R`, `R/datras_service.R`, `R/field_names.R`) and
checks every claim against at least two independent live sources.

------------------------------------------------------------------------

## Implementation

The exported surface is `NAMESPACE` (roxygen2-generated; never hand-edit it) and
the rendered index `articles/reference.qmd`, generated from `man/*.Rd` by
`data-raw/audit/build_reference.R`, which fails if an export belongs to no group.

- **Reading the published archive** (`R/archive.R`) — every function here reads a
  parquet footer, so against the hosted archive each costs one range request,
  not a download: `op_archive()` (the archive root: a directory named `raw`
  holding the four tables, which is what lets every reader assume the `datras:`
  keys exist), `op_con()`, `op_dict()` (one row per column with three type views
  — the curated `type`, the stored `parquet_type`/`logical_type`, the `r_type` a
  reader gets — allowed to disagree), `op_crosswalk()`/`op_rename()` (legacy ↔
  current names from the footer itself, asserted 1:1 and total),
  `op_enums()`, `op_definitions()`/`op_define()` (named filters and metrics with
  code for R and DuckDB), `op_relationships()` (the eight-field composite haul
  key), `op_coverage()`/`op_surveys()`, `op_sentinel_meta()`,
  `op_provenance()`/`op_known_issues()` (including `dict_sha256`, which tells a
  consumer whether its installed opus built the file), `op_keys()`, and
  `op_catalog()` (an in-memory DuckDB of views, comments and lookups rebuilt from
  the footers).
- **Specification validation, parquet exploration, drafting**
  (`R/validation.R`): the four `op_validate_*()` wrappers; `op_inspect_parquet()`;
  `op_flag_violations()`, which flags every violating row, because the CLI's
  report stops at the first few rows per problem; `op_validation_problems()`;
  `op_describe_parquet()`; `op_draft_from_parquet()`; `op_export_spec()`,
  `op_export_data()`, `op_render_spec()` (data-dict's `render`, on demand only;
  `data_dir` injects a `source:` so the page profiles real data, because the
  shipped dictionary declares none).
- **The DATRAS web service** (`R/datras_service.R`, the single implementation of
  the ASMX crawl): `op_datras_operations()` (doubles as the migration tripwire:
  each table ICES converts to current names appears as a new `…NewHeaders`
  operation), `op_datras_operation_types()`, `op_datras_field_metadata()` (the
  field list as ICES publishes it, unverified).
- **XML to parquet conversion** (`R/cast.R`, `R/rename.R`, `R/sentinels.R`),
  exported so a downstream package converting its own fetch gets exactly the
  published archive: `op_cast_wsdl_types()` (sentinels preserved),
  `op_rename_to_new()` (asserts the incoming columns against the crosswalk first;
  harmless on data already in current names), `op_strip_sentinels()`,
  `op_cast_to_spec()` (refuses to convert what it cannot parse), and
  `op_wsdl_type_overrides()`.
- **Sentinel policy** (`R/sentinels.R`): `op_sentinels()`, `op_sentinel_policy()`,
  `op_sentinel_audit()`.
- **icesVocab** (`R/vocab.R`): `op_vocab_get_types()`, `op_vocab_resolve_key()`,
  `op_vocab_resolve_guid()`, `op_vocab_get_codes()`, `op_vocab_first_usable()`,
  `op_vocab_resolve_datras_key()` (reads `inst/DATRAS-vocab-correction.csv`).
- **Field names** (`R/field_names.R`): `op_legacy_field_name()`,
  `op_field_name_map()`, `op_field_spec()` (old name, new name and type for every
  Tier 1 column from the shipped `DATRAS-imbus.yaml` alone), 
  `op_translate_dict_names()` (the one legacy-to-current rename the pipeline
  applies, ground-truthing the crosswalk first), `op_datras_field_list()` (verified
  mappings from the live services, tiered `confirmed` / `cross_table_confirmed` /
  `no_evidence`), `op_datras_rename_crosswalk()`. Both of the last two resolve over
  the full Tier 1 set whatever `tables` is, and narrow only at the end: a mapping
  confirmed for one table is borrowed for another, so resolving one table alone
  would degrade silently (LT inherits most of its renames from HH, HL and CA).
- **Dictionary writing** (`R/dict_write.R`): `op_write_dict_yaml()`, the canonical
  writer every dictionary goes through.

**`data-raw/`** is grouped by concern: `spec/` (the dictionary pipeline, run in
numeric order), `archive/` (download, parse, consolidate), `audit/` (on-demand
cross-source checks), `assets/` (generated files), plus `seed/`, `issue-drafts/`,
`mock/`, `retired/`. Basenames are stable because the shipped YAML cites script
paths and those citations reach the published footers.

**The specification pipeline** (`data-raw/spec/`, keyed by legacy names until the
final rename). **The generator is the source of truth:** YAML changes arrive only
through `spec_02` → `spec_03` (and `spec_04`) regeneration, never by hand.
- `spec_01_seed_dict.R` — specifications from the live WSDL, field list and
  icesVocab, uncorrected, keyed by legacy names.
- `spec_02_curate_dict.R` — hand-written corrections and enriched enums, then two
  archive-grounded passes: non-negativity `assert:` on every physically
  non-negative quantity (an undecided quantity field fails the build), and enum
  `values:` trimmed to codes observed in the archive. Writes the internal
  `data-raw/seed/DATRAS-curated-legacy.yaml`.
- `spec_03_translate_new_names.R` — the pure rename via
  `op_translate_dict_names()`; writes `inst/DATRAS-imbus.yaml`.
- `spec_04_build_ices_yaml.R` — renames the seed the same way and merges the
  field-description spreadsheet (its descriptions preferred; `Mandatory` →
  `required`; conflicts and coverage gaps noted in `details`; examples from its
  own example records, with an archive fallback that says so); writes
  `inst/DATRAS-ices.yaml`.

Rendering is data-dict's `render` (`op_render_spec()`); the registry is not a
data-dict document and stays plain YAML.

**The archive pipeline** (`data-raw/archive/`):
- `archive_01_download_config.R`, `archive_02_download.R`, `archive_03_catalog.R`
  — download the XML and build a manifest.
- `archive_04_parse_phase2.R`, `archive_05_backfill_lt_partitions.R` — parse XML
  to parquet and chain the four conversion calls in order. No conversion logic of
  their own. Phase A is WSDL-only and does not know the YAML: enum-ness is a
  curation conclusion drawn from the archive, so it cannot be an input to
  building it.
- `archive_06_consolidate.R` — to `.datras/to_https/raw/{TABLE}.parquet`,
  current names only, rebuilt from the partitions every run; asserts no legacy
  names survived and that the sentinel policy held per column.
  `archive_06_metadata.R` writes the footers.
- The rebuild depends only on `.datras/xml/`: survey, year and quarter come from
  the directory path; types and the crosswalk from the live service; the registry
  and the dictionary from the installed package.

**Standalone audits** (`data-raw/audit/`, each re-run on demand):
`build_vocab_correction.R` (best-fitting icesVocab key per enum field, writes
`inst/DATRAS-vocab-correction.csv`), `build_vocab_field_audit.R` (the same check
over every Tier 1 field), `build_icesvocab_snapshot.R` and
`build_field_description_snapshot.R` (cached, hash-stamped snapshots under
`.datras/ices-schemas/`), `build_reference.R`, `build_field_gap_audit.R`
(sentinel usage, icesVocab coverage and the spreadsheet's `Mandatory`/`DataType`
cross-referenced against opus's specification for every field at once — re-run
whenever the spreadsheet gets a new dated version), `validate_against_datadict.R`,
`validate_issue_registry_sync.R` (keeps the registry and `articles/issues.qmd`
consistent), `validate_vocab_annotations_sync.R`.

------------------------------------------------------------------------

## Key facts

**Shared fields are consistent where it matters.** Across every field name that
appears in more than one table, `type` and `units` never diverge; other keys
differ only where they legitimately vary by table (a primary key in HH is not one
in HL, LT's date range starts later, `RecordHeader` names its own table).

**A curated `type` is an analysis-level claim, not a storage instruction — and
that is data-dict's rule.** data-dict's specification says types "capture data
types at a level that makes sense for analysis, which is typically coarser than
the logical types of the underlying data", and its implementation collapses all
numeric physical types to `number` and never reads the measure qualifier
(`(quantity)`, `(ordinal)`, `(id)`) from a file. So a `number(quantity)` stored as
INT32 is conformant. opus casts from WSDL physical types, and `op_cast_to_spec()`
overrides only `date`/`datetime`; nothing casts from a curated `type`, and
nothing should. A downstream package that did would manufacture a divergence the
archive does not have; cast from the `r_type`/`parquet_type` each footer carries.
ICES both declares and sends integers for every affected field.

**The published parquet is self-describing.** Each file in `raw/` carries five
`datras:` keys in its footer: `dict` (the table's slice of the dictionary, plus
`legacy_name`, `parquet_type`, `r_type` per column), `provenance`, `sentinels`,
`coverage`, `known_issues`. A detached file carries its own descriptions,
crosswalk and record of which sentinels were stripped. The writer is
`nanoparquet` with `write_arrow_metadata = FALSE`, because arrow would serialise
the custom metadata a second time inside `ARROW:schema`, which DuckDB never reads.

**`raw/` is the minimum faithful rendering of the exchange data as parquet.**
Work belongs there only if parquet cannot represent the data honestly without it:
current names, WSDL types, `-9` resolved to null where it means absence, dates as
`DATE`. Anything computed is a product and belongs at the `datras/` root. The one
other file is `raw/datras-data-dict.html`, the rendered dictionary, which
describes exactly these files.

**The catalog is a function, not a published file.** `op_catalog()` rebuilds the
views, comments and lookups in an in-memory DuckDB from the footers on demand, so
it cannot describe a different vintage from the data beside it, and a consumer
who downloads one table still gets its dictionary.

**The published parquet carries no sentinel, except where `-9` is a documented
answer.** A `-9` makes every naive mean wrong, but ICES overloads the value: most
`-9` codes in the vocabularies mean absence (`Not known`, `Not available`), a few
are real answers (`No ticklers are allowed`, `No plus group`, `Invalid hauls`).
Neither the value nor its prevalence is the discriminator — the published label
is: `Tickler` is mostly `-9` and real, `Turbidity` mostly `-9` and never
recorded. The policy (registry `sentinels: resolution`) strips by default, keeps
where the vocabulary documents a real answer, and keeps any unrecognised label,
never silently destroying a documented code. That one value means two things in
one vocabulary is an ICES-side defect, recorded as such.

**The order of conversion is load-bearing, and getting it wrong is silent.** Cast
→ rename → strip sentinels → cast to spec. The WSDL type map is keyed by legacy
names, so casting precedes renaming; the sentinel registry is keyed by current
names, so the strip follows; a `Date` cannot hold `-9`, so the semantic cast
comes last. `op_cast_to_spec()` refuses to convert what it cannot parse, as the
backstop.

**An `enum`'s data must be string-like, and retyping it to a number deletes its
labels.** data-dict makes an integer-stored `enum` a type mismatch and forbids a
`values:` map on a `number(*)` column. So each such field is a judgement:
`Quarter` and `Month` became `number(ordinal)` (their labels restate the number);
`Tickler` and `SpeciesCategory` stay enums stored as text, because their codes
carry meaning that reaches users through `op_enums()`. Which side moves is a
question about what the specification is for, not about making the validator
pass.

**Two dictionaries ship, one naming scheme.** `DATRAS-imbus.yaml` and
`DATRAS-ices.yaml` both use current names; the legacy-named YAMLs are internal
intermediates under `data-raw/seed/`. Names stay self-contained through the
`Legacy field name: {old}.` stamp in `details`. ICES's own sources diverge: the
spreadsheet documents fields the WSDL does not serve (HH `SurveyIndexArea`,
`EDMO`, `ReasonHaulDisruption`; CA `LiverWeight`, `PreservationMethod`; LT
`RecordHeader`, `Reserved1`, `Reserved2`, `DatrasSurvey`), the field list
documents most of them too (not `PreservationMethod` or `DatrasSurvey`), and both
call CA's `Age` `IndividualAge`, while the WSDL and the archive call it `Age`.
Some `FieldName` values in the field list carry an embedded line break, so trim
before matching.

**`op_validate_meta()` against the published archive is the gate.** All four
tables validate clean; treat any regression as a release blocker. It is the only
automated check that the dictionary and the data still describe each other.

**`op_validate_data()` against the published archive.** The dictionary describes
the published archive, where `-9` has been stripped, so a field ICES calls
Mandatory but which is null-heavy in the archive carries a `todo` recording
ICES's claim and the null rate, not a `required` constraint; declaring `required`
on a stripped column would fail by construction. Enum `values:` are the codes
observed in the archive, and observed-but-undocumented codes are carried pending
ICES's disposition. The non-negativity `assert:` constraints fire on a handful of
real negative values (haul durations, category weights, ages, litter weights),
none of them standard sentinels — candidates for the registry. Validation is
cheap enough to run on every rebuild. The data-dict binary and the `datadict`
package read different environment variables for the CLI path (`OPUS_DATA_DICT`
and `DATA_DICT`).

**icesVocab is keyed by each field's legacy name, not its current one — resolve
the legacy name first, and always check both.** The two can point to different
vocabularies (`Sex` has `TS_Sex`/`AC_Sex`, `IndividualSex` has neither; `GearEx`
has `TS_GearEx`, `GearExceptions` has `AC_GearExceptions`). For renamed enum
fields this is the rule, not the exception: they resolve through the legacy name.
Record legacy names in `details:` and use the dual-lookup wrappers in
`R/vocab.R` and `R/field_names.R`.

**Scope against WP3.** opus is WP2's reference specification. On-vessel quality
control, including contextual rules ("door spread depends on depth"), is WP3's
(Marine Institute) and needs operational tooling, not dictionary work.

------------------------------------------------------------------------

## Working with Einar

Standing collaboration rules; the opus project memory
(`~/.claude/projects/-Users-einarhj-R-Pakkar-opus/memory/`) is the fuller source.

1. **Confer before git stage or commit.** Explicit confirmation per commit; work
   on `main`, no branches.
2. **No discovery narrative in deliverables.** Dates and "how we found it" belong
   in `DEVLOG.md` only — not in the YAML prose, `TODO.md`, this file, or
   ICES-facing reports.
3. **Pace before planning.** Check in with findings after a bounded round; do not
   chain long autonomous sweeps.
4. **Plan, don't just prioritise, when findings may share a root cause.**
   Investigate connections and sequence by dependency before proposing fixes.
5. **Verify, don't inherit.** Trace claims to the literal source, re-check
   inherited numbers (opus's own included), and fix the generator, not the
   generated file.
6. **Write deliverables for biologists, in ICES terms.** Issue reports lead with
   ICES's legacy field names.
7. **Check for a vocabulary mix-up before blaming ICES.** A `TS_` key can be a bare
   "see X" redirect; resolve legacy and current names before filing a gap.
8. **Stay out of obus internals.** Read obus's published data and public
   contract, not its R or QC internals; never mine `obus_retired` for facts.
9. **The YAML is the source; no code shortcuts.** Fix the dictionary and re-run
   the pipeline; never drop real rows to make a join work.
10. **Keep process proportionate.** opus is one narrow slice of IMBUS; default to
    the lowest-ceremony option.
11. **Postings to IMBUS_FISHMAP#29 need a go-ahead each time** — it is a public
    ICES-side ticket, not opus's own repository.
12. **Einar wants a recommendation, not a survey of options.**
