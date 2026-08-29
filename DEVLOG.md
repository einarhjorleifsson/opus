# opus development log

Dated development history: root causes, verification evidence, and the
reasoning behind non-obvious decisions. `AGENTS.md` documents opus's
*current* state (working principles, scope, architecture) and does not
carry this kind of narrative; `TODO.md` tracks only what's currently
open. Git commit messages remain the most granular record -- entries
here are a longer-form, human-browsable index of the same history.

Chronological, oldest first (new entries get appended at the bottom,
like a lab notebook).

---

## 2026-07-29 to 2026-08-01 -- initial build

Tier 1 (HH, HL, CA, LT) bootstrap workflow (WSDL seed -> parquet
enrich -> curate), R package scaffold, initial vignettes and test
data. Most field-level verification citations dated "2026-07-29"
throughout the shipped YAML trace back to this period, run against
obus's own icesDatras-fetched archive (see the 2026-08-16 entry below
for why several of those early "100% clean" claims later needed
correcting -- that archive silently scrubbed `-9` before opus ever saw
the data).

---

## 2026-08-02 -- what opus actually is; two systemic audits

**Critical architectural discovery: icesVocab code lookups are
dependent on field *names*, and DATRAS fields have two names (old/
legacy ICES names and new/current names) that sometimes point to
*different vocabularies*.** Example: `Sex` has `TS_Sex`/`AC_Sex`
(ambiguous between trawl and acoustic domains), but `IndividualSex`
does not; `GearEx` has `TS_GearEx` (13 codes) while `GearExceptions`
has `AC_GearExceptions` (1 code) -- both re-verified live 2026-08-08.
Solution adopted: document legacy field names in each column's
`details:` via a standardized `Legacy field name: {OldName}` prefix,
with dual-lookup wrappers in `R/vocab.R` + `R/field_names.R`. Full
discovery notes in `vignettes/articles/technical-notes.md`.

**Corollary, learned the hard way (2026-08-08):** knowing this
abstractly didn't prevent tripping over it. Checking `HH.HaulValidity`
and `HL.SpeciesValidity` against icesVocab using their *current* names
resolved to `AC_HaulValidity` (2 codes) and `AC_SpeciesValidity` (2
codes) -- producing a false "5 of 7 real values missing" / "8 of 10
missing" finding, reported as fact before being challenged.
Re-resolving against their *legacy* names (`HaulVal` -> `TS_HaulVal`,
`SpecVal` -> `TS_SpecVal`) showed a perfect match both directions --
no gap at all.

**Full systematic audit, same day (2026-08-08), all 52 Tier 1 enum
fields, both names checked for every one:** icesVocab is empirically
legacy-name-keyed, cleanly, no exceptions. Of the 21 renamed enum
fields where any vocab match exists at all, 100% (21/21) resolve via
the legacy name; 0/21 resolve via the current name. Overall: 46 fields
get a full bidirectional match on their best candidate, 6 have no
icesVocab entry under *either* name (`RecordHeader`/`RecordType` and
CA's three Sampling Flag fields -- legitimately no vocab exists), zero
genuine gaps once resolved correctly. This is the origin of Working
Principle 9 (audit exhaustively) -- each individual check on 2026-08-02
was genuinely empirical, yet the sweep still missed the answer because
it wasn't exhaustive; the two failures are independent, and both are
needed to actually verify something.

**Enum coverage audit:** Systematically audited all 52 enum fields in
Tier 1 against icesVocab. 35 fields (67%) full coverage; 17 (33%) no
icesVocab match (system/metadata fields); 4 incomplete (HaulValidity
29%, SpeciesValidity 20%, GearExceptions 8%, LengthCode 43%); 1 empty
vocab despite key existing (AgePreparationMethod); 12 exist under both
`TS_`/`AC_` prefixes with ambiguity. Outputs: `enum_field_inventory.csv`,
`enum_enrichment_analysis.md`. Key insight: incompleteness is systemic,
not random -- patterns suggesting domain-specific extensions not in
centralized icesVocab.

**Type source authority:** Three ICES metadata sources claim to define
field types and they diverge. WSDL is authoritative (auto-generated
from server code); getDatrasFieldList is secondary (hand-maintained).
Five confirmed divergences at the time: Year fields (WSDL=int, API=char;
real archive=int), Distance (WSDL=int, API=float; real archive=int).
opus seeds from WSDL only (documented in known-issues #10,
`datras_field_list_type_divergence`).

**What opus really is.** Not a data reformatting tool -- opus is
institutional data governance audit infrastructure. It systematically
exposes where ICES's three metadata sources (WSDL, getDatrasFieldList,
icesVocab) diverge from each other and from real data. The
known-issues registry is an accountability log: evidence, impact, fix.
This reconciliation work is the actual deliverable; the YAML specs are
the vehicle. (A trimmed version of this now lives in AGENTS.md's "What
the project does".)

---

## 2026-08-06 -- removed icesDatras/icesVocab R-package dependencies

Removed opus's R-package dependency on both `icesDatras` and
`icesVocab` (direct web-service calls instead, verified byte-identical
for icesVocab's two endpoints). Building the replacement
(`op_datras_field_list()`, `R/field_names.R`) required cross-verifying
ICES's live `getDatrasFieldList` metadata against each operation's own
ASMX response and the real archive, which surfaced 6 confirmed
ICES-side errors: LT coverage gap (only 22 of 58 real fields), 3 wrong
LT renames, a phantom LT `RecordHeader` field, CA's unverifiable
`IndividualAge`/`AgeRings` row, missing `DateofCalculation`/`Valid_Aphia`
entries, and LT's `Depth`/`BottomDepth` data duplication -- filed as
`data-raw/ICES_ISSUE_REPORT.md` (moved from `inst/` 2026-08-08), not
yet sent to ICES.

Corrected opus's own spec accordingly: `CA.IndividualAge` reverted to
`CA.Age` (the rename rested on an unverifiable metadata row), LT's ~23
shared fields renamed via verified cross-table inference.

Same-day session also produced several documents (`PHASE2_ISSUES_FOR_ICES.md`,
`PHASE3_ROADMAP.md`, `DATRAS_PHASE2_ORIGINAL_NAMES.yaml`,
`ICESVOCAB_MAPPING_AUDIT.md` and related CSVs) containing fabricated
row counts and misattributed sources, discovered when this session's
own rigor caught a specific bad claim. **Resolved 2026-08-07:** all
deleted; every one was untracked, so nothing was lost from git
history.

---

## 2026-08-08 -- data-raw/ reorganized; legacy/new parquet split; type-caster bug found and fixed

**data-raw/ audit and reorg.** Traced every `source()` call and
`Rscript data-raw/X` invocation across the whole repo (not
filenames/headers alone) to build the real dependency graph, confirming
two independent pipelines by actual git history: **spec-building**
(`spec_00_operation_types.R` -> `spec_01_seed_dict.R` ->
`spec_02_curate_dict.R` -> `spec_03_dict_to_qmd.R`, first committed
2026-07-31, builds `inst/DATRAS-data-dict.yaml`) and **data-archival**
(`archive_01_download_config.R`/`archive_02_download.R`/
`archive_03_catalog.R` -> `archive_04_parse_phase2.R` ->
`archive_05_backfill_lt_partitions.R` -> `archive_06_split_legacy_new.R`,
first committed 2026-08-05, downloads the real archive and consumes
the spec pipeline's yaml). Both renamed to a scoped `_0N_` prefix per
pipeline (deliberately two separate sequences, since the pipelines
don't run in one order).

Removed 6 confirmed-dead scripts, each verified individually rather
than assumed from naming: `datras_phase2_stage1.R` (read a spec file
that doesn't exist -- couldn't have run), `xml_to_parquet.R`/`.py` and
`xml_to_csv.py` (standalone converters from an earlier iteration, zero
callers, superseded by the inline parser in `archive_04_parse_phase2.R`),
`ices_api.R` (`op_fetch_datras_field_list()`/`op_fetch_vocab_codes()`,
zero callers, superseded by the exported `op_datras_field_list()`/
`op_vocab_get_codes()`), and `datras_vocabulary.R` (self-declared
deprecated, confirmed zero functional callers). Found but did **not**
remove a real duplicate: `archive_03_catalog.R::datras_get_field_list()`
is a second live implementation, actually called by
`archive_02_download.R` for manifest provenance hashing -- a different
purpose from the package's own `op_datras_field_list()`.

Every rename's cross-references were fixed by exhaustive repo-wide
grep before and after: `source()` calls, usage/help text, man pages
(regenerated via `devtools::document()`), vignettes, TODO.md, and
AGENTS.md. Moved the 9 untracked `*_retired.*` files into
`data-raw/retired/`; deleted the untracked, stray
`data-raw/DATRAS-data-dict_files/`.

**Legacy/new parquet split + full ground-truthing.** `.datras/parquet/LT`
had no partitioned directory (unlike HH/HL/CA) because LT's XML
predates the manifest-tracked downloader; backfilled via
`data-raw/archive_05_backfill_lt_partitions.R` (204 files, 75,310 rows
-- matches the pre-existing consolidated total exactly). That backfill
surfaced two latent bugs in `archive_04_parse_phase2.R` (LT wrongly
required a `RecordType` field it doesn't have; an all-empty XML file
crashed instead of being recorded as `EMPTY_RECORDS`), fixed in both
scripts. Then split the consolidated legacy archive from the curated
spec: `.datras/{HH,HL,CA,LT}_legacy.parquet` (current ICES field
names, full archive) alongside new `.datras/{HH,HL,CA,LT}.parquet`
(opus-curated names -- rename is the only difference) and
`.datras/DATRAS-data-dict-legacy.yaml`, all built by
`archive_06_split_legacy_new.R`. Crosswalk derived from the yaml's own
`Legacy field name:` annotations via the real `op_legacy_field_name()`
(not a second copy of its regex). Found and fixed a bad annotation:
LT's `BottomDepth` details wrongly said `Legacy field name: Depth`
(BottomDepth is its own legacy field, not a rename -- Issue 6).
Independently re-verified the full crosswalk for all four tables
directly against raw XML (at least one non-empty sample per survey,
all 28 surveys per table) -- zero discrepancies.

**Second-look review, same day:** re-verified column *values* (not
just names) survived the rename correctly -- sampled 50 random rows
per table, every column, legacy value equals the renamed column's
value, all four tables. Found the BottomDepth fix above had only
patched the symptom: `spec_02_curate_dict.R`'s `add_legacy_field_names()`
independently rebuilds its own old-name lookup and never inherited the
LT `Depth`/`BottomDepth` exception already applied a few dozen lines
above it -- so the cross-table inference kept wrongly tagging LT's
real, separate `BottomDepth` column. Fixed by excluding it from
`add_legacy_field_names()`'s lookup the same way the other step
already did.

**XML->parquet type casting was silently broken; fixed by moving to
WSDL-only, no yaml, no validation gates (2026-08-08/09).** User found
this by actually using the data: `open_dataset(".datras/parquet/CA")`
then a `str_detect(GenSamp, ...)` filter crashed with a DuckDB
schema-merge error. Root cause: `archive_04_parse_phase2.R`'s
yaml-based `apply_rigid_types(df, rt, spec)` checked `rt %in%
names(spec)`, but `spec` was the *whole* yaml object -- top-level
names are `tables`/`glossary`/`version`, never a table name. Always
true, so the function silently no-opped for every call, every column.
Confirmed via a real per-file schema scan: 16 CA columns and 8 HL
columns end up typed inconsistently across different files for the
same column (e.g. `GenSamp`: `int32` in all-`-9` files, `string` in
files with a real `Y`/`N`, though the yaml already documented GenSamp
as clean `Y`/`N` since 2026-07-29). HH and LT tested clean by luck of
their data, not correctness of the pipeline.

Fix, per two points from the same conversation: (1) this stage should
rely solely on live WSDL for types, never the curated yaml, and
shouldn't even know the word "enum" exists -- WSDL is keyed by the raw
XML's own legacy tag names, exactly what this stage parses, and
enum-ness is a curation conclusion reached by analyzing real data,
downstream of this stage (circular to depend on it here); (2) a
"required fields" completeness gate (reject a record for a missing
expected column) also doesn't belong at this stage -- a validation
judgment, not a type-casting one, removed from both scripts. Built
`data-raw/archive_00_wsdl_types.R`: `apply_wsdl_types(df, rt)`, casting
straight from live WSDL, fetched once per table and cached. Validated
against the two real files that exposed the bug, both now produce
`character` consistently.

Session paused mid-reprocessing (`TaskStop`) partway through the first
full-archive rerun, resumed cleanly after the required-fields fix
landed (unconditional overwrite self-heals a mixed starting state).
Full run, all four tables: 2,968 records written, 813 correctly
classified as genuinely empty ICES submissions (`EMPTY_RECORDS`, zero
`PARSE_ERROR`). Re-ran the schema-inconsistency scan: zero
inconsistent columns, all four tables (was 16 + 8). Reproduced the
user's original failing query: no error.

Simplified `archive_06_split_legacy_new.R`'s Step 1 while rebuilding
on top of the corrected data: instead of migrating a pre-existing file
of undocumented provenance via one-time rename, it now consolidates
directly from the partitioned directory every run -- fully known
provenance, self-heals on reprocessing. Row counts unchanged (145,958
/ 13,754,042 / 5,865,076 / 75,310), now consistently typed.

---

## 2026-08-09 -- legacy-name-primary restructure; icesDatras attribution corrected

**Curation pipeline restructured to be legacy-name-primary; icesVocab
audit extended to all 190 fields, not just the 52 enum ones.** Dated
proof the pipeline's file structure had it backwards: the yaml's own
"verified 2026-07-29" citations predate the very concept of new-named
parquet (invented 2026-08-08/09) by 10 days -- every check necessarily
ran against legacy-named data, yet the yaml stored the *new* name as
primary, the reverse of how data actually flows (raw XML ->
legacy-named parquet -> opus's own rename). Also, `build_vocab_correction.R`
only ever checked the 52 fields already curated as `type: enum` -- the
same blind spot Principle 9 exists to catch, one level up.

Rewrote `spec_01_seed_dict.R`/`spec_02_curate_dict.R` to key every
seed field, correction, and spec entry by legacy (real, on-the-wire)
name throughout (~140 individual substitutions, all 1:1 via the real
crosswalk). Cross-referenced all 40 `shared_field_specs` entries
against real per-table legacy names first; found exactly one case
where a table's legacy name for a shared concept diverges
(`BottomDepth`/`Depth`, Issue 6). `inst/DATRAS-data-dict.yaml` is no
longer hand-curated: a new final step, `spec_03_translate_new_names.R`,
does a pure rename off the newly-primary legacy yaml via
`op_datras_rename_crosswalk()`.

Two real bugs caught by verification: (1) `yaml::read_yaml()` silently
collapses a single-element YAML sequence back into a bare scalar on
read, breaking write-back for length-1 array fields -- fixed by
re-wrapping length-1 unnamed values before translating. (2) A
structural diff of the regenerated yaml against the pre-restructure
version caught a genuine content loss: LT's `BottomDepth` lost its
description and duplication note once the two tables' legacy names for
this field diverged -- fixed with an explicit backfill.

**Full audit (`build_vocab_field_audit.R`), all 190 fields by legacy
name against live icesVocab**, two stages (name-match, then
value-match): 115/190 zero candidates (expected, mostly genuine
measurements); 75/190 with >=1 candidate, 46 already-known enum
fields; 29 fields never typed `enum` still got a name match -- 16
already documented, 6 never checked before this sweep. Of those 6:
`Ship`->`TS_Ship` a false lead (79% of real values not covered, same
shape as known `Survey`/`Country` false leads); five genuine exact
matches, zero gaps: `Year`->`Year`, CA's `Maturity`->`TS_Maturity`,
HH's `DepthStratum`->`TS_DepthStratum`, HH+LT's `Tickler`->`TS_Tickler`,
HL's `CatIdentifier`->`TS_CatIdentifier`. Filed as Issue 9 in
`data-raw/ICES_ISSUE_REPORT.md`.

**icesDatras attribution corrected.** Earlier documentation (including
this log's own prior entries, since superseded) described `icesDatras`
as silently hand-patching `getDatrasFieldList()` (a fabricated
`lt_extra` table for LT, explicit overrides). Checked directly against
the current official `ices-tools-prod/icesDatras` on GitHub: its
`getDatrasFieldList()` is four lines -- fetch, parse, return. No
patches, no overrides, no `data-raw/` directory at all. That
patch-narrative described a personal development fork
(`einarhjorleifsson/icesDatras`, branch `einar_dev/integration`)
installed locally at the time, not the official package. One specific
claim this fed was actively wrong, not just imprecisely attributed:
`getDatrasFieldList()`'s CA `IndividualAge`/`AgeRings` row (Issue 4)
was described as something the icesDatras patch "still trusts" -- but
the fork's own patch had already fixed that exact row three weeks
before the report text was written. Every citation across opus
(comments, roxygen docs, the ICES issue report, the -9-sentinel claim
in the yaml) was re-checked against the current official repo and
corrected: retracted where the citation only exists on the fork (the
hand-patch narrative, `build_datras_schema.R` and siblings -- none
exist upstream), left in place and re-pointed where the underlying
fact turned out genuinely true of the official package too (the -9
scrub, real and current in `parseDatras()`, mis-cited as
`applyDatrasTypeSchema()`, which doesn't do it).

---

## 2026-08-10 -- Tickler/CatIdentifier retyped enum; undeclared icesVocab dependency fixed

The two fields flagged 2026-08-09. Re-verified fresh directly against
the real legacy parquet: HH's Tickler (9 distinct values) and LT's
Tickler (3, a subset of HH's) both fully covered by `TS_Tickler`'s 32
codes; HL's CatIdentifier (13 distinct values) fully covered by
`TS_CatIdentifier`'s 56 codes. Both vocab keys turned out to be
genuine controlled code lists once actually read, not just
name-matches. Retyped `enum` with the full vocab code list as
`values`.

Left `Year`, `Maturity`, `DepthStratum` (the other three matches from
the same sweep) unchanged, each for a distinct reason: `Year` is a
continuously-advancing ordinal, not a fixed closed set; `Maturity`'s
coding depends on the sibling `MaturityScale` field, so `TS_Maturity`'s
63 codes are plausibly a union across several scales; `DepthStratum`
is survey-specific per its own description, in tension with one
universal vocab key.

Found and fixed a real, unrelated bug while building the generic
version of this: the pre-existing `Gear` enum called `library(icesVocab);
getCodeList('Gear')` directly -- the *real* external package, not
opus's own `op_vocab_get_codes()` -- despite `icesVocab` appearing in
neither `Imports` nor `Suggests`. Would have failed on any machine
without that package, quietly contradicting opus's "zero R-package
dependency" claim. Confirmed byte-identical output (99 codes) before
generalizing.

Verified: structural diff of the regenerated yaml against the
pre-change version showed exactly the 3 intended changes and nothing
else. `devtools::check()` clean.

---

## 2026-08-16 -- data-dict feature adoption; a major archive-integrity bug; documentation architecture change

Started as a review of new data-dict features (`relationships`,
`todo`, `definitions`, assertions, the JSON/HTML `report` format,
`render`) opus wasn't yet using; became the single most consequential
session since the 2026-08-08/09 type-casting fix.

**`relationships` implemented.** HH's 8-field composite key marked
`primary_key`; HL/CA/LT's matching columns `required, foreign_key`;
three joins declared. Collapses four copies of the same prose
(previously hand-written per table) into one structurally-checked
fact. Caveat, confirmed by testing: `validate-data`'s `D05` only
checks single-column foreign keys, so this composite key always
reports `unevaluated` -- spec-level correctness only, no automatic
cross-table orphan detection.

**A real, systemic archive-integrity bug, found via that test.**
Testing the relationships surfaced a contradiction: `known-issues.yaml`
said CA's `HaulNo` carries a `-9` sentinel with "0 true nulls," but
`.datras/CA.parquet` showed 288,581 true nulls, zero `-9`. Root cause:
`archive_04_parse_phase2.R`/`archive_05_backfill_lt_partitions.R` each
carried a `GLOBAL_SENTINELS` list (`-9, -99, -999, -1, -5, -95, -100,
-900, 88888888`) applying a blanket, unconditional sentinel-to-`NA`
conversion across every column, before type casting -- introduced
between the pipeline's 2026-08-05 commit and the 2026-08-08 reorg,
*after* the `-9` finding had already been verified as real, non-null
data on 2026-08-07. Confirmed against raw XML: `CA_BTS_2004_Q3` has
513 literal `<HaulNo>-9</HaulNo>` tags, all silently becoming `NA`.

Not confined to one field: a full re-scan for all 9 sentinel values
across every numeric column found 101 (table, column, sentinel)
combinations with real counts. Worst: `HH.Tickler` -- icesVocab's own
code for `-9` is "No ticklers are allowed," a real answer, not an
absence of one -- was `-9` for 113,645 of 145,958 rows (78%), the
modal value. This directly undermined the 2026-08-10 Tickler/CatIdentifier
"zero gaps" finding: that check ran against an already-silently-scrubbed
archive.

Fix: removed `GLOBAL_SENTINELS`/`replace_sentinels()` entirely from
both scripts (sentinel *meaning* is a curation conclusion, not a
type-casting one -- same reasoning as the enum-detection fix). Full
reprocess from raw XML, all four tables: identical Success/Error
counts to the 2026-08-08/09 baseline. `op_flag_violations()`
re-confirmed the original finding exactly, now correctly `-9` not
null. Full writeup, including the quantity/ordinal/id/enum triage
technique for telling "standard missing" apart from "field-specific
meaning," in `vignettes/articles/technical-notes.md` section 4.

**Six field-level spec fixes followed, each root-caused against the
rebuilt archive:**
- `HH.SwellHeight`/`LT.SwellHeight`: retyped `number(quantity)` (was
  wrongly `enum` on LT, matching vocab codes neither table's real data
  uses -- confirmed exhaustively across all 580 registered vocab
  keys). Range `[0, 13]` for HH, settled using `WindSpeed` at the same
  haul as an independent check (a real discontinuity, not an
  arbitrary cutoff). LT is a byte-for-byte copy of HH's value
  (55,914/55,914 matched) and inherits HH's range/reasoning.
- `CA.Age`: `-9` (1,995,814 rows, 34%) was entirely undocumented.
- `DateofCalculation` (HH/HL/CA): `-9` (5.76-7.93%) already excluded
  by the declared range, just never named.
- `Quarter`/`Tickler`/`CatIdentifier`: live WSDL declares all three
  `int`, not string -- an accepted, permanent divergence, same class
  as the already-accepted `Valid_Aphia` pattern.

**Checked whether other "shared" fields are also literal HH copies**
-- ~30 are (100% or near-100%). Three real exceptions documented
instead of forced to match: `CA.GearEx` (92.27% -- CA supplements
HH's generic `-9` with a real code the other 7.73%, never
contradicts), `LT.Rigging` (95.33% at the time -- see the 2026-08-17
entry below for why this needed rechecking), `LT.HaulVal` (99.97%,
negligible). Diagnosed the 2.7% LT-to-HH composite-key match residual:
2,010 of 2,026 rows are `Survey=BTS, Year=2025, Quarter=1`, where HH's
own submission is genuinely empty -- an ICES-side submission gap
(`known-issues.yaml`'s new `lt_bts_2025_q1_orphaned`); the remaining
16 (`NS-IBTS`) later diagnosed as a different, still-open cause since
HH has abundant real data for both exact cells.

**`todo`/`definitions` adopted for the first time.** Six `todo:`
entries convert "flagged for review, not investigated"-style prose
into structured, `validate-spec`-visible (S31) notes. One
`definitions` entry: `CA.linkable_to_hh` (`HaulNo != -9`).

**`op_flag_violations()` reconsidered, not deprecated.** Confirmed the
CLI's report row-cap (5 per problem) isn't configurable, so exhaustive
per-row marking still can't be replaced by the report format,
correcting the function's own (false) docstring justification. Added
`op_validate_spec(json = TRUE)` and `op_validation_problems()`. 21
exported functions total, not 17.

**Documentation architecture decided: `render`, not the hand-rolled
Quarto generator.** `spec_04_dict_to_qmd.R` and its three generated
`.qmd` files removed; data-dict's own `render` (`op_render_spec()`)
does everything the generator did plus a relationship diagram, search,
and live data profiling (and actually renders `relationships`, which
the generator never did). `known-issues.yaml` gets no replacement page
(confirmed `render` rejects it -- never a real data-dict.yaml
document). `render` stays an on-demand tool, nothing committed --
`.datras/`'s full local archive is continuously growing, so a profiled
page can't be a "kept in sync" repo artifact. `op_render_spec()`
gained a `data_dir` parameter for exactly that use case.

**Follow-through, same day: two real bugs fixed in `.validate_via_dict()`**
(`R/validation.R`) that had silently made `op_validate_meta()`/
`op_validate_data()` non-functional against the shipped dictionary.
(1) The table end-boundary scan looked only for the next `- name:`
line, so the *last* table (LT) ran off the end and swallowed
`relationships:`/`glossary:` -- fixed by stopping at any unindented
line. (2) Once fixed, a second bug surfaced: removing an existing
`source:` block dropped only that line, not its indented `parquet:`
child, producing invalid YAML for every table -- fixed by walking
forward while lines stay nested. Verified against all four tables:
both validate cleanly now, 3 `M01` type mismatches for HH (`Quarter`,
`Month`, `Tickler`), all documented divergences (closed one genuine
gap this surfaced: `Month` had the same divergence as `Quarter`/
`Tickler` with no `details:` note of its own -- added).

**Pre-staging review, same day:** a three-part review before staging
the day's work -- (1) compared opus's yaml against data-dict's own
canonical worked examples; (2) audited against the data-dict CLI's
`skill-read`/`skill-create` prompts as a rubric; (3) a from-scratch
structural review of the whole repo. Two fixes landed directly:

- **`AgeSource`/`AgePrepMet` were resolving to redirect-only icesVocab
  keys.** `TS_AgeSource`/`TS_AgePrepMet` turned out non-authoritative
  -- each one's own icesVocab `Description` is a bare "see X"
  cross-reference to a different domain, invisible to name-matching.
  Real CA data matches `SampleType`/`PreparationMethod` exactly,
  code-for-code. Fixed in `spec_02_curate_dict.R`; `ICES_ISSUE_REPORT.md`
  Issue 8 gained an addendum on the general redirect-without-structure
  problem.
- **A real bug caught mid-fix:** the first attempt silently did
  nothing. Root cause: the entries lived in `col_labels`, whose apply
  loop hardcodes the update to `label` alone, silently discarding
  every other field with no warning. Fixed by moving to `field_specs`.
  Whether `col_labels`'s loop should instead reject unexpected keys
  outright is tracked in TODO.md.
- **Three CA sampling-flag columns (`GenSamp`/`StomSamp`/`ParSamp`)**
  had the same stale "100% clean" claim already fixed for
  Tickler/CatIdentifier/Age/SwellHeight, just missed by that pass --
  each was documented 2026-07-29 as clean Y/N, but that check ran
  against the same pre-scrubbed archive. Re-verified: `-9` is now
  dominant (82.9-85.6%) in all three.

Found the real provenance of `inst/*.parquet` along the way:
`data-raw/GENERATE_test_data_ns_ibts_2026q1.R` (2026-07-31) -- a
narrow single-survey/quarter extract from **obus's** local files, not
a broad sample. `inst/*.parquet`'s staleness relative to corrections
made since (e.g. `DateofCalculation`) is deliberately unresolved (see
TODO.md's D1 item); a draft resampling script,
`data-raw/archive_07_build_test_samples.R`, exists on disk, untracked,
pending that decision.

**Session-close correction, same day:** a post-commit status check
found three things investigated and verbally reported but never
actually written into AGENTS.md/TODO.md: the `swell_height_type_mismatch`
stale cross-reference, the render-adoption process lesson (below), and
`archive_07_build_test_samples.R`'s own false provenance claim. All
three re-added. **Lesson:** a verbal "still open, tracked" claim isn't
reliable on its own -- verify against the actual backlog file, not
memory of having written something down.

**Process lesson, written up late (should have been recorded
2026-08-08):** `render` was adopted 2026-08-08 (commit `638c9ac`), but
that decision was never recorded in AGENTS.md at the time -- so a
brand-new hand-rolled Quarto generator got built anyway two days
later and survived 8 days until this session found and removed it.

---

## 2026-08-17 -- read.delim() T/F-to-logical bug; dead R/ files removed; docs restructured

**A second, independent archive-integrity bug, root-caused and fixed:
`read.delim()`'s T/F-to-logical auto-coercion.** The "new
archive-integrity bug" flagged at the end of 2026-08-16 (literal
`"TRUE"`/`"FALSE"` text in several enum columns) was root-caused.
Checked raw XML first: ICES's real submissions are clean
(`<SpecCodeType>T</SpecCodeType>`, one character) -- the corruption is
entirely opus's own pipeline, not an ICES-side problem, so (unlike the
sentinel-scrub bug, similarly opus's own fault) no `known-issues.yaml`
entry was warranted.

Root cause: `archive_04_parse_phase2.R` and
`archive_05_backfill_lt_partitions.R` each carry their own independent
copy of `parse_xml_to_dataframe()`, both calling `read.delim(con,
stringsAsFactors = FALSE, na.strings = "")` with no `colClasses`, so
R's own type-guessing runs. Confirmed directly: `read.table`'s guesser
coerces bare `T`/`F`/`TRUE`/`FALSE` to `logical` (not `True`/`False`/
lowercase). Any file where a column's real values happen to be a
subset of `{T, F}` -- e.g. an HL file with no `W`-coded rows for
`SpecCodeType` -- silently became a `logical` vector at parse time,
before `apply_wsdl_types()` ever ran; its later `as.character()` cast
can't recover the original text (`as.character(TRUE)` is `"TRUE"`,
not `"T"`). Same failure shape as both the 2026-08-08/09 type-caster
bug and the sentinel scrub -- an earlier, implicit, per-file-value-
dependent step silently destroying information before the later,
correct, explicit step ever sees it.

Exhaustive scope check (every string column, all four tables) found 7
`(table, column)` pairs, one more than the 6 previously listed --
`CA.SpeciesCodeType` (514,216 rows) had been missed by the earlier ad
hoc discovery. Total ~2.12M affected rows, confirmed zero in LT:
`HH.DoorType` (733), `HH.Rigging` (1,784), `HL.DoorType` (60,844),
`HL.SpeciesCodeType` (1,536,333), `CA.DoorType` (9,141),
`CA.SpeciesCodeType` (514,216), `CA.IndividualSex` (87).

Fix: added `colClasses = "character"` to both scripts' `read.delim()`
call. Validated against a known-bad file (`HL_SP-NORTH_2009_Q3`, real
value `T`) before touching the full archive. Full reprocess, all four
tables: Success 2968 | Error 813 (all `EMPTY_RECORDS`) -- identical to
the 2026-08-16 baseline. Re-split legacy/new: row counts unchanged.
Re-ran the exhaustive scan: zero rows anywhere still equal
`TRUE`/`FALSE`. Spot-checked: `HL.SpeciesCodeType`'s `T` count
(2,008,425) exactly equals the old `T` + `TRUE` counts combined -- no
rows lost, only correctly retyped.

**Checked whether this had contaminated an existing conclusion -- it
hadn't.** The 2026-08-16 HH-vs-LT `Rigging` "95.33% match" was a
plausible suspect, since LT had zero rows affected by this bug while
HH.Rigging had 1,784 -- a row-level `"TRUE"` (HH) vs `"T"` (LT)
comparison for the same real haul would have shown a false mismatch.
Recomputed post-fix: 69,064/72,483 = 95.28% match, mismatches 100%
`FB`/`FW` swaps (3,419 -- the exact count already cited in
`spec_02_curate_dict.R`'s own comment), zero residual `TRUE`/`T`-shaped
mismatches. The small shift is denominator noise, not contamination --
the original conclusion holds. Worth having checked regardless: the
mechanism was real and plausible, it simply didn't reach far enough
into this particular downstream comparison to change its answer.

**Removed the 6 dead three-phase-bootstrap `R/` files**
(`op_apply_curated_spec.R`, `op_audit_yaml_phase2_mismatch.R`,
`op_build_final_yaml.R`, `op_check_type_mismatch.R`,
`op_enrich_stage2_yaml.R`, `op_minimal_yaml.R`). Verified empirically
before deleting: grepped the whole repo for each function name, found
zero real callers. `NAMESPACE` (hand-frozen, not roxygen-managed) had
zero `export()` entries for any of the six -- despite `@export` tags,
they were never actually part of the shipped API; the six `man/*.Rd`
pages existed only because roxygen2 generates a page for any
`@export`-tagged function regardless of NAMESPACE.

Read all six fully before deciding remove-vs-repurpose. Each
implements one phase of an abandoned three-phase merge design (WSDL
seed -> icesVocab enrich -> apply curated spec -> build final), and
every one requires an already-existing "curated_yaml" as input -- the
exact catch-22 the current `spec_00`(crawl)->`01`(seed)->`02`(curate)->
`03`(translate) pipeline was built to avoid, using one single verified
crosswalk instead of each function's own ad hoc lookup.
`op_check_type_mismatch()` additionally has a dead tautological branch
(`is_renamed && !is_renamed`, always `FALSE`). Verdict: remove, not
repurpose. `devtools::document()` correctly left `NAMESPACE` untouched
and auto-deleted the six orphaned man pages. `devtools::check()` clean
throughout.

**AGENTS.md/TODO.md restructured; this file created.** User flagged
that AGENTS.md had grown from 89 to 371 lines since 2026-07-31, every
single commit adding net content, never once trimmed -- duplicating
detail that git commit messages already carry. Considered and
rejected `NEWS.md` as the name for a split-out history file: that's
the R-ecosystem convention for package *consumer* release notes
(`tools::news()`, pkgdown's Changelog page), and opus has exactly one
user who is also its maintainer and will likely never have others --
there's no consumer audience to serve with that convention. Settled on
`DEVLOG.md` instead (this file), added to `.Rbuildignore` alongside
AGENTS.md/TODO.md as an internal working doc, not a package artifact.
AGENTS.md trimmed to current-state-only (principles, scope,
architecture); TODO.md trimmed to current backlog only, with resolved
items deleted outright rather than kept as struck-through paragraphs
(their story lives here and in git log instead). All of the historical
narrative above this entry was migrated from AGENTS.md's "Open Items"
section and TODO.md's resolved-item explanations, not rewritten from
memory.

---

## 2026-08-17 (continued) -- a fourth ICES data source found; full icesVocab snapshot built; Issue 11 filed

Investigating why `CA.HaulNo` has no icesVocab entry (a side question
during the AGENTS.md/TODO.md restructure above) led to a real, unplanned
discovery. Checked all 580 registered icesVocab code-types for anything
containing "haul" -- zero, confirming `HaulNo`/`HaulNumber` genuinely has
no controlled vocabulary under any name, prefix, or key, consistent with
it being a plain sequential identifier rather than a categorical code
(same class as `RecordHeader`/`RecordType` and CA's Sampling Flag
fields, already known to have none).

**Found and fetched ICES's real field-description spreadsheet** --
`DATRAS_Field_descriptions_and_example_file_December2025.xlsx`, linked
from the DATRAS format-description page. This is the closest thing to
the "Technical Reference" AGENTS.md has cited as one of opus's three
consolidated sources since the project's earliest days, but which had
literally never been fetched or checked against anything before this.
Downloaded and cached (`data-raw/build_field_description_snapshot.R`,
matching the existing hash-stamped snapshot convention).

Key findings from its "General Notes" sheet: an ICES-wide documented
convention -- **"for the fields with no information but header, please
submit -9"** -- the first time opus has had an actual ICES citation for
this, rather than inferring it field-by-field from icesVocab code
descriptions. Applies even to `HaulNumber` despite it being marked
`Mandatory: Yes` in the HH/CA field sheets ("mandatory" means "must be
present," not "must be a known value"). `HaulNumber`'s own description
is just "Sequential numbering of hauls during cruise" -- no key/
uniqueness declaration, consistent with opus's own `relationships`
treatment (part of an 8-field composite key, never unique alone) but
silent on CA's specific row-grain question.

`StatisticalRectangle`'s spreadsheet entry independently corroborates a
decision opus already made on 2026-07-29 (`type: string`, not `enum`,
with a `details:` note reading "not a fixed enum given the size of the
grid") -- the spreadsheet describes it via a geometric rule (0.5°
latitude x 1° longitude grid), not a code list, matching that reasoning
exactly, from a completely independent source. Nothing to fix; good to
have confirmed twice.

**Two fields found that opus doesn't have at all:** `ReasonHaulDisruption`
(HH) and `PreservationMethod` (CA), both explicitly called out as new in
the spreadsheet's December-2025 version notes. Checked live WSDL
(`getHHdata`: 69 fields, `getCAdata`: 34 fields) -- neither field
present. Checked the real downloaded archive
(`.datras/HH_legacy.parquet`/`CA_legacy.parquet`, also 69/34 columns) --
zero occurrences anywhere. So the spreadsheet says these fields exist;
the other two authoritative sources (live WSDL, real submitted data)
both disagree. Per Working Principle 1 (real data is ground truth) and
Principle 4 (don't guess; document), there is nothing to add to opus's
production yaml yet -- no real data exists to characterize either field
against. Filed as Issue 11 in `data-raw/ICES_ISSUE_REPORT.md` instead.

**A genuinely better vocabulary-resolution mechanism, found by accident.**
The spreadsheet's `Vocab` column is populated in exactly 1 of 154 field
rows -- `CA.PreservationMethod`, with a direct icesVocab codetypeguid URL
(`2f5a5876-c572-42bc-9348-3526ce413c59`). Checked the raw icesVocab
`CodeType` API response directly: it carries `guid`/`id`/`modified`
fields that `op_vocab_get_types()` had always silently discarded. The
spreadsheet's GUID resolves to exactly one code-type
(`key = "PreservationMethod"`, bare, no prefix) -- an exact,
ICES-declared match, unlike every other vocab-key resolution in this
project's history, which is explicitly caveated as a name-based guess
(`op_vocab_resolve_datras_key()`'s own docs: "always a guess, never an
ICES-declared fact"). Added `op_vocab_resolve_guid()` (R/vocab.R) and
extended `op_vocab_get_types()` to retain the `Guid`/`Modified` columns
(22 exported functions now, not 21). Not yet useful for
`PreservationMethod` itself, since that field isn't live anywhere yet --
but a real, reusable improvement for the next external source that
hands opus a GUID instead of a name to guess from.

**Built opus's own full icesVocab catalog snapshot**, at the user's
suggestion: they'd been using a `library(icesVocab); map(types, getCodeList)`
pattern for exactly this, which uses the real `icesVocab` package opus
removed 2026-08-06. Same idea, opus's own direct-HTTP way instead
(`data-raw/build_icesvocab_snapshot.R`): loop `op_vocab_get_types()`'s
580 code-types through `op_vocab_get_codes()`, cache the result with the
same hash-stamped provenance as every other ICES-source snapshot. Full
run: 557/580 code-types have >=1 code, 147,271 total (type, code) rows,
~5 minutes (580 live HTTP calls). Makes future audits that need many
codes at once (like this session's own field-by-field checks) fast,
offline, and reproducible against a fixed point in time, instead of
hundreds of live round-trips per run. Doesn't replace
`op_vocab_get_codes()`/`op_vocab_resolve_key()` for one-off live
lookups -- those stay simple and correct for a single field.

**Data Sources section in AGENTS.md now documents four sources, not
three** -- the field-description spreadsheet added as source #4, with
an explicit note that its `Vocab` column is nearly always empty (1/154
rows), so it mostly doesn't double as an icesVocab cross-reference.
`devtools::check()` clean (0 errors, 0 warnings, 0 notes) throughout.

**`NAMESPACE` switched from hand-maintained to roxygen2-generated.**
Having to manually add `op_vocab_resolve_guid()`'s export line moments
after writing it (`devtools::document()` printed the same "Skipping
NAMESPACE... not generated by roxygen2" message it always has) prompted
fixing the root cause instead of continuing to patch around it -- this
exact hand-maintenance gap is what let the six dead bootstrap-workflow
functions carry a live `@export` tag with no real NAMESPACE entry for
who knows how long, caught only by this session's own audit.

Verified safety before touching anything, not assumed: cross-checked
every `@export`-tagged function in `R/*.R` (22) against every
`export()` line in the hand-written `NAMESPACE` (22) -- exact match,
both directions, so the switch changes zero functions' export status.
The two `importFrom(yaml, ...)`/`importFrom(jsonlite, ...)` lines had
no corresponding `@importFrom` roxygen tag anywhere and zero bare
(unprefixed) call sites in the actual code -- every real call is
already fully-qualified (`yaml::read_yaml()`, `jsonlite::fromJSON()`)
-- so they were dead NAMESPACE entries, safe to drop.

Replaced `NAMESPACE`'s content with the `# Generated by roxygen2: do
not edit by hand` header roxygen2 requires before it will touch a file,
then ran `devtools::document()`: regenerated exactly the same 22
exports (alphabetically sorted), zero `importFrom` lines, confirming
the safety check above. `devtools::check()` clean. Going forward, any
new `@export` tag becomes live automatically on the next
`devtools::document()` -- the whole class of bug this session hit
twice (dead files with orphaned tags, a new function needing a manual
NAMESPACE edit) can't recur.

---

## 2026-08-17 (continued) -- a full remediation plan, not just a priority order

User's own instinct, mid-triage of the field-gap audit's findings (81%
`-9` on `CA.FishID`, 32% on `AreaCode`, 41 spreadsheet-vs-opus
conflicts): "small issues have been known to become bigger issues
later on in our prior processing" -- don't just prioritize a fix list,
plan it properly first. Backed by this project's own history: the
sentinel-scrub bug and the `read.delim()` T/F coercion bug both started
as one small anomaly. Entered plan mode; used two Explore agents in
parallel (root cause of the 41 missing-`required` fields; what
`CA.FishID`/`CA.AreaCode` actually are) and one Plan agent to validate
the resulting tier structure before writing the final plan
(`~/.claude/plans/tender-napping-bee.md`) and getting explicit approval
-- see that file for the full investigation writeup this entry
summarizes the *execution* of.

**Tier 0 (exhaustive sweep) itself caught a mistake before acting on
it.** The first grep for "verified 2026-07-29" citations in
`spec_02_curate_dict.R` was case-sensitive and found 11 sites. A second,
case-insensitive pass -- run specifically because the whole point of
this tier was not repeating "fixed one instance, missed the pattern" --
found 17 more, including `UnitWgt`/`UnitItem`/`LTSZC` (whose citations
used capital "Verified"). Checked all 28 candidate sites against current
`.datras/*_legacy.parquet`: 6 (`OSPARArea`, `MSFDArea`, `PARAM`, `EEZ`,
`NMArea`, `Valid_Aphia`) turned out genuinely clean (true nulls, not
sentinels) -- ruled out empirically, not assumed clean because they were
already suspected innocent.

**Tier 1: 13 fields fixed, same root cause as the already-known
sentinel-scrub bug, just missed by its own fix's verification sweep.**
`CA.FishID`, `CA.AreaCode`, `HH.StNo`, `HH.StatRec`, `HH.DepthStratum`,
`HH.HydroStNo`, `CA.AreaType`, `CA.Maturity`, `LT.LTSZC`, `LT.UnitWgt`,
`LT.UnitItem`, `LT.TYPPL`, `LT.LTPRP` -- all had 0 true nulls in the
current archive but were documented (originally verified 2026-07-29,
against obus's own pre-fix icesDatras archive) as substantially
"unpopulated." `LT.TYPPL` was the most dramatic: cited as "very sparse,
only 162 of 79,451 rows populated" -- the 162 was exactly right, the
other 79,289 rows were never absent, they were `-9` (99.79% of the
table). Plus 16 shared HH/LT gear and environmental-measurement fields
(`CodendMesh`, `DoorSpread`, `WarpDen`, etc.) got the same "`-9` is the
ICES-wide sanctioned convention" footnote already established for
`HaulNo` -- HH's own rates often exceed LT's (`WarpDen`: HH 96.1%, LT
60.3%), the modal value in both tables for several fields, not the
exception. `known-issues.yaml`'s `ca_haulno_unlinkable_to_hh` updated
with the same citation, sharpening its open question from "is -9 valid
here" to "why are so many mandatory composite-key values missing at
all." Batched into one `spec_02`/`spec_03` run; verified via structural
diff (order-insensitive for enum value sets, having learned from an
earlier false alarm over `Gear`'s cosmetic key-reordering -- confirmed
content-identical, never root-caused, now in `TODO.md`): exactly 52
`details`-only changes, nothing else. Committed separately from Tier 2
(`c74d4a2`) at the user's request, specifically so each commit's diff
stays reviewable against one coherent root cause rather than several
bundled together.

**Tier 2: a general mechanism, not a hand list -- and it repaired a bug
already in production.** 35 fields marked `Mandatory: Yes` in the
field-description spreadsheet had no `required` constraint in opus's
own spec. Root cause (an Explore agent's finding): `constraints` is set
by exactly two mechanisms in `spec_02_curate_dict.R` -- the composite-key
loop (2026-08-16) and 4 unrelated one-off hand edits -- and there had
never been a general mandatory-ness mechanism, because there had never
been a *source* for ICES's Mandatory flag before this session. Built
one: read the spreadsheet's Mandatory column programmatically, translate
curated names to legacy via `op_datras_rename_crosswalk()`, apply
`required` to any field lacking a stronger constraint whose real current
null rate is under 0.5%. All 35 qualified automatically; zero needed the
review-holdback path.

Before writing this, a Plan agent's validation pass found a real risk:
`apply_col_update()`'s `constraints` handling was a plain overwrite, not
a merge -- the new mechanism could have silently dropped a
composite-key field's `foreign_key` constraint. Fixed to a
de-duplicated union first. Verifying the fix's effect afterward found it
wasn't just precautionary: `HH.HaulNo` and `HH.Year` had *already*
silently lost their original `field_specs`-declared `required`
constraint (down to `primary_key` alone) the moment the 2026-08-16
composite-key loop first ran, undetected until this fix organically
restored it. Confirmed all 32 composite-key `foreign_key` constraints
intact afterward -- none dropped by the new loop. Structural diff:
exactly 37 `constraints`-only changes (35 new + 2 restored). Committed
separately (`a5d31a7`).

**Tier 3: closed a 2026-08-02 gap that had sat unfiled for over two
weeks.** `Year`'s WSDL-vs-documentation type divergence was noted
2026-08-02 (WSDL says `int`, `getDatrasFieldList` says `char`) and this
file's own narrative described it as "documented in known-issues #10" --
but it was never actually written into `inst/DATRAS-known-issues.yaml`
or `data-raw/ICES_ISSUE_REPORT.md`, confirmed by grepping both directly.
Today's field-gap audit independently corroborated it from a third
source (the field-description spreadsheet also says `char`) and found
the identical pattern for `SpecCode` (HL, CA). Filed as
`datras_field_list_type_divergence` in `known-issues.yaml` and Issue 12
in `ICES_ISSUE_REPORT.md`, framed correctly: not a bug in opus's own
spec (which already sides with WSDL and real data, correctly), but two
independently-maintained ICES documentation sources landing on the same
wrong answer, years apart, never reconciled against the live contract
they both describe.

**Tier 4: promoted the audit script; restructured known-issues.yaml
using today's own findings as the design material.**
`build_field_gap_audit.R` documented in `AGENTS.md` alongside
`build_vocab_correction.R`/`build_vocab_field_audit.R` -- none of which
had a "standalone audit tooling" section to live in before this, an
incompleteness of its own worth fixing while adding the new one, not
just plugging in the new script next to a gap. `known-issues.yaml`
gained a `scope` field (`field-level` / `systemic` / `opus-internal`) on
all 8 entries: the mapping fell out cleanly from what already existed --
5 entries are single-field findings, `icesVocab_gaps` and today's new
`datras_field_list_type_divergence` are genuinely systemic (one root
cause, multiple otherwise-unrelated fields), `sentinel_replacement_data_loss`
was already distinctly opus's own fault. Closes a `TODO.md` item that
had been open since before this session, designed around real examples
instead of guessed at in the abstract, exactly as planned.

Every tier verified with `devtools::check()` (clean throughout) and,
where a yaml regeneration was involved, a structural diff confirming
the change touched exactly what was intended and nothing else -- the
same discipline this project has applied to every field-level fix since
2026-08-08.

---

## 2026-08-17 (continued) -- why-opus.qmd and using-opus.qmd dropped; stale shipped test data removed; four generator bugs fixed

Working through `TODO.md`'s backlog this session surfaced a live,
uncommitted edit in `vignettes/articles/why-opus.qmd`: the user had
started annotating its own flagship example ("EINAR: It is wrong to
claim HaulNumber is supposed to link individual fish records back to
the haul in which they were captured...") but the note cut off
mid-sentence. Rather than reconstruct the intended correction, the user
chose to drop the file outright. Re-reading the rest of the vignette
confirmed this was a reasonable call on its own terms, not just
deference to the interrupted edit: past that one example, the remaining
sections (`What opus does`/`doesn't`, `Scope`, `Why now`, `The format`)
restate `AGENTS.md`'s own "What the project does"/Working Principles
content more thinly, with no second concrete example to fall back on.
Deleted (`git rm -f`, discarding the uncommitted note along with it,
per the user's explicit instruction); removed the now-dead pointer at
`AGENTS.md`'s former line 30.

**`vignettes/articles/using-opus.qmd` dropped too**, closing the
`TODO.md` backlog item that had left its fate undecided. Reading the
full file (untracked since 2026-07-30, per its own mtime -- this was
long-standing debt, not something drafted this session) confirmed it
documents a project phase that no longer exists: a "descriptive vs.
strict icesVocab-only" two-YAML split (today's actual split is
legacy-name vs. curated-name, per `AGENTS.md`), and a
`known-issues$issues` list with `title`/`status`/`description` fields
(today's registry is `known_violations`, keyed by
`id`/`severity`/`scope`/`field`/`table`/`issue`/`extent`/`implication`).
Every `{r, eval=FALSE}` chunk in the file would error against the
current package. Deleted along with its Quarto render byproduct
(`using-opus_files/`, also untracked); fixed the one place this file
was still referenced -- `README.md`/`README.Rmd` both pointed at a
third, never-existent path (`vignettes/using-opus.Rmd`, `.Rmd` not
`.qmd`, no `articles/` segment) that had never matched the real file's
location or extension.

**`inst/*.parquet` (the four bundled test-data samples) removed, not
regenerated.** `TODO.md`'s own backlog item (D1) had left this as an
open decision, with a draft resampling script
(`data-raw/archive_07_build_test_samples.R`, untracked, drafted
2026-08-16) sitting unrun. Checked directly rather than assumed: a
fresh sample drawn from the current `.datras/*.parquet` archive using
that script's own logic (same seed, same `min(20000, n)` sizing) was
compared against the committed `inst/*.parquet` files. Row counts
matched the *original* pre-fix sample sizes exactly (331/48,070/30,068/291
for HH/HL/CA/LT) -- confirming the script had never actually been run,
despite its own header comment's confidence. Worse, the comparison
found real drift, not just staleness: `inst/CA.parquet` still carries a
column named `IndividualAge` where the current archive (and current
spec) has `Age` (see `ICES_ISSUE_REPORT.md` Issue 4 -- `IndividualAge`
was never confirmed as a real rename), and `inst/LT.parquet` still
carries `GearEx` where the current archive has the already-renamed
`GearExceptions`. Given the choice between regenerating (fixing the
draft script's own wrong header claim first) and dropping shipped test
data entirely, the user chose to drop it. `git rm`'d the four parquet
files; deleted the now-pointless draft script; removed the `source:`
stanza this decision leaves dangling from both YAML generators
(`spec_02_curate_dict.R`'s per-table loop,
`spec_03_translate_new_names.R`'s per-table loop) rather than leave it
pointing at files that no longer exist -- `source` is optional per the
data-dict.yaml spec, and every opus R function already takes an
explicit `data_path` argument rather than reading it.

**Four smaller, purely mechanical fixes, verified via structural diff:**
- `tests/testthat/test_validation.R`: `skip_if_not(file.exists("HH.parquet"), ...)`
  checked the current working directory, not the installed package --
  always false under `devtools::test()`/`R CMD check`, silently
  skipping 6 of the file's 14 tests regardless of whether test data
  existed. Replaced with a `system.file("HH.parquet", package = "opus")`-resolved
  path (computed once, used in both the skip condition and the actual
  `op_*` calls that followed it -- the bare `"HH.parquet"` string had
  been passed to those too, which would have failed differently even
  if the skip check had been fixed alone). Now that `inst/*.parquet` is
  gone (above), these 6 correctly and honestly skip -- confirmed via a
  direct `testthat::test_file()` run, not inferred from `R CMD check`'s
  pass/fail summary alone.
- `DESCRIPTION`'s `Description:` field claimed "Data-only package (no
  computational functions)" against the package's own 22 exported
  functions -- reworded to describe the actual thin-wrapper role.
- Both YAMLs' `origin:` field carried a literal `<U+2192>` (eight
  characters of Unicode-escape *text*, not a real arrow) instead of the
  arrow character the R source (`spec_02_curate_dict.R`,
  `spec_03_translate_new_names.R`) actually contains -- a
  `yaml::write_yaml()` plain-scalar encoding quirk with the unquoted,
  unbracketed style `origin:` uses. Rather than chase the writer's
  internal handling, replaced the Unicode arrow with plain ASCII `->`
  at the source -- simpler, portable, and avoids the bug entirely.
- `HH.StartTime`/`LT.StartTime`'s `details` ended "...same as StatRec
  above." -- wrong on both counts. Traced to one shared source line
  (`spec_02_curate_dict.R`, the `TimeShot` field spec): the referenced
  field is actually *below* in file order (line 459/3239 vs.
  342/3207), and "StatRec" is the *legacy* name -- correct in the
  legacy YAML (where the field really is `StatRec`) but a bare,
  unqualified legacy-name reference in the current/curated-name YAML
  (where the field is `StatisticalRectangle`), where `spec_03`'s "pure
  rename, prose stays literal" design means it's never automatically
  retranslated. Fixed to `"same as {StatisticalRectangle or StatRec}
  below"`, matching the `{new or old}` bracket convention this same
  file already uses for the composite-key fields (`{Platform or
  Ship}`, `{StationName or StNo}`), which reads correctly in both
  YAMLs without needing yaml-specific branching.

Re-ran `spec_02_curate_dict.R` then `spec_03_translate_new_names.R`;
`git diff` confirmed exactly the intended changes and nothing else (2
arrow fixes, 2 StatRec fixes, 4 `source:` stanzas removed, per file).
`devtools::check()`: 0 errors, 0 warnings, 0 notes; direct
`testthat::test_file()` run confirmed the 6 previously-miscounted tests
now skip cleanly with the correct reason ("HH.parquet not found").

---

## 2026-08-18 -- remaining TODO.md backlog cleared; folded scalars; a real TimeShot bug found by hand; a systemic stale-citation audit

Cleared the rest of `TODO.md`'s Backlog in one continued session (dates
turn over from 2026-08-17 to 2026-08-18 partway through -- see the
`version:` field's own date bump, harmless and expected).

**`conflicts:` added to all three `relationships` entries, empirically
checked, not guessed from the one example TODO.md gave.** Every non-key
column HH shares with HL/CA/LT was checked against the real archive:
`RecordType`/`RecordHeader` conflicts for HL and CA (LT has no such
field); `DateofCalculation` conflicts for **LT only** -- HL/CA's copies
match HH 100.00% (5.6M-13.8M joined rows each), but LT's matches only
37.34% of the time (45,421 of 72,483 joined rows differ). `SweepLngt`/
`DoorType`/`GearEx` all confirmed 100% duplicates, not conflicts. Adding
this surfaced a real, unrelated bug: `spec_03_translate_new_names.R`'s
legacy-to-current translation was silently collapsing a one-item
`conflicts` array into a bare scalar on the YAML read/write round-trip
(same class of quirk as `apply_col_update()`'s own `constraints`
handling, fixed 2026-08-17), and never translated the column name at
all -- the current-name YAML would have shipped `conflicts: RecordType`,
a name that doesn't exist in that file. Fixed both: `conflicts` now
translates legacy->current names (resolved via HH's own rename map,
since every conflicts column is one HH also has) and round-trips as a
proper array (`vapply(..., USE.NAMES = FALSE)` -- the naive form
silently produces a *named* vector, which `as.list()` then turns into a
YAML mapping instead of a sequence).

**Trailing `.0` on range values, fixed by real type, not blanket
formatting.** `range = c(0, 360)` produces an R double; `yaml::write_yaml()`
then renders whole-number doubles with a spurious `.0`. Audited all ~85
range values showing this pattern against each field's *real* archive
column class: 55 (32 distinct fields, some declared per-table rather
than shared -- `Depth`, `LngtClass`) are genuinely integer-typed and got
their R literals converted to explicit integers (`0L`); the other ~29
are genuinely double-typed columns whose bound happens to be a whole
number (e.g. a Salinity range starting at `0.0`) and were left alone,
per the user's own rule: fix only where the underlying variable's real
type is integer.

**`col_labels` now rejects unexpected keys instead of silently dropping
them** -- the exact 2026-08-16 incident (an entry's `label`-only apply
loop silently discarded every other field a misplaced correction
carried) now fails loudly if a future entry repeats it.

**Glossary gained 7 entries** (`icesVocab`, `WSDL`, `WoRMS`/`AphiaID`,
the `M01`/`S24`/`D01`/`D04` rule codes, `CPUE`, `OSPAR`, `SeaDataNet`),
grounded against the sibling `data-dict` repo's own rule-code fixtures
(`crates/data-dict/tests/snapshots/validate_spec__s24_*`) rather than
guessed -- `M01`/`S24` are that CLI's own metadata/spec-tier codes, not
opus's invention.

**`HH.ThermoCline`/`LT.LTSRC`'s "two tiny case mismatches"**, recovered
from git history (`92bb3cb`'s own `AGENTS.md` diff had the detail TODO.md's
later summary dropped: "`HH.ThermoCline` 3 rows, `LT.LTSRC` 1 row") and
confirmed against the real archive: 3 HH rows carry lowercase `y`
instead of `Y`; 1 LT row carries lowercase `sba` instead of the declared
`SBA` code. Documented via `details:`, not added to `values:` -- both
read as one-off submitter slips, not an established alternate spelling
worth enumerating permanently.

**Folded (`>-`) scalar style, done as option B (the user's explicit
call after seeing the trade-off): remove `format_long_text()`'s
hard-`\n` bug first, then convert everything to real folded style.**
`yaml::write_yaml()` has no option to emit `>`/`>-` directly -- it
always picks plain or single-quoted style depending on content -- so
this rewrites the already-written file's raw text, same approach as
the existing quote-number-examples post-process (`fold_long_scalars()`,
added to both `spec_02`/`spec_03`, right after their own `write_yaml()`
calls). Verified safe two ways before trusting it: an isolated test
comparing parsed values before/after (byte-identical, after switching
the chomping indicator from bare `>` to `>-` -- bare `>` keeps one
trailing newline a plain/quoted scalar never had), then, once wired into
the real pipeline, a full column-by-column comparison across every one
of 190 fields in both files confirming zero unintended value changes.
One field (`HL.NoMeas`/`SubsampledNumber`) correctly stayed in literal
`|-` style: its description has a genuine two-line structure straight
from ICES's own seed text (a formula on its own line), and folding would
have collapsed that into a run-on sentence -- the skip-guard's job,
working as intended, not a bug.

**A real bug found by the user's own spot-check, not by any tooling
here: `TimeShot` (`HH`/`LT.StartTime`)'s "NOT zero-padded" claim was
backwards.** `hh |> select(TimeShot) |> mutate(n_char = nchar(TimeShot)) |>
count(n_char)` (the user's own query) showed all 145,958 HH rows are
exactly 4 characters -- confirmed against LT too (75,310 rows, same).
Real values ARE zero-padded (`'0730'`, not `'730'`); the file's own
`examples:` list even showed the wrong 3-character shapes. The citation's
row-count denominator (150,262) was stale too. Fixed both `examples:`
and `details:`; the 2026-07-29 citation's original basis isn't
recoverable from here, so the correction says so rather than guessing why
it was wrong.

**That single catch prompted a systemic audit, at the user's explicit
request ("no trouble adding more changes within this process"): every
`description:`/`details:` row-count citation across all 190 fields,
checked against today's real archive, not sampled.** Extracted every
`N/M`- and `N of M`-shaped citation (93, later 100 once new fixes added
their own), cross-referenced each `M` against the four real current
table totals (HH 145,958; HL 13,754,042; CA 5,865,076; LT 75,310).
Distinguishing a genuine bug from a false positive took actually reading
each flagged field, not just trusting the mechanical match: `HH.StNo`/
`StatRec`/`HydroStNo` and `CA.AreaCode` all cite the same stale
`150,262`/`5,966,950` totals *on purpose*, inside an explicit "framed
then as X... re-verified 2026-08-17 as Y" narrative already in the
text -- correctly already-fixed, not bugs. Genuinely still wrong,
fixed this pass:
- `HH.Turbidity` -- same root cause as the 13 fields fixed 2026-08-17
  (`-9` silently scrubbed to NA before the original 2026-07-29 check
  ever saw it), just missed by that sweep. 145,756 of 145,958 rows
  carry `-9`, not a null; only 202 real (all exactly 0), not "202 of
  150,262 populated."
- `LT.OSPARArea`/`MSFDArea`/`EEZ` -- numerator and distinct-value counts
  were already right; only the denominator (`79,451`, not LT's real
  `75,310`) was stale.
- `LT.PARAM`/`EEZ` -- same denominator fix, plus their own distinct-value
  counts had each drifted by exactly one (50->49, 20->19) since 2026-07-29.
- `LT.NMArea` -- denominator *and* both other numbers were wrong
  (18->17 distinct, 53,303->49,581 unpopulated), not just the total.
- `HH`/`LT.WindSpeed` -- one shared, undated citation (`1,641 of
  109,012`) matched neither table's real non-sentinel count; replaced
  with a proper per-table breakdown (HH: 1,407 of 106,109, 1.33%; LT:
  1,149 of 64,985, 1.77%) and dropped an unreconcilable "357 rows at
  exactly 28" claim rather than guess at it.
- `LT.LT_Items` -- previously cited 76,882 "populated rows", exceeding
  LT's own real 75,310-row total outright; not just stale, impossible.
- `HL.SubFactor` -- the already-known-and-described fix (from earlier
  today's status update, never actually applied until now): of 144,395
  rows showing `SubFactor < 1`, 144,041 are the `-9` sentinel, leaving
  354 genuine anomalies against a real 13,754,042-row total, not the
  previously cited 356 of 14,256,091.
- `LT.HaulVal`/`Rigging`/`SwellHeight` (HH-LT matched-row comparisons,
  originally checked 2026-08-16) -- discovered along the way: **LT has
  44,255 duplicate composite keys** (`HH` has zero), so a proper
  `inner_join` on the 8-field key fans out to more matched rows than a
  naive per-table count would suggest. All three fields' *difference*
  counts were already correct (21, 3,419, 0); only the matched-row
  denominator had drifted (73,263/73,284/55,914 -> a consistent 72,483/
  72,483/55,113). Fixed in `spec_02_curate_dict.R`, `DATRAS-known-issues.yaml`,
  and `ICES_ISSUE_REPORT.md` (all three carried the same stale number).

**Not chased further, flagged instead:** `LT`'s 44,255 duplicate
composite keys is a real structural fact about the table not documented
anywhere before this, potentially the same root cause behind
`LT.DateofCalculation`'s own conflict above (if a haul's multiple LT
rows were processed at different times) -- left open at the user's
request pending a clearer idea of what `DateofCalculation` actually
means per-table. A handful of vocab-code-coverage citations (`CA.AreaType`
"17 of 27", `LT.TYPPL` "6 of 30", `LT.LTSZC` "23 of 41") compare against
a *fixed external vocab list size*, not an archive row count, so they're
out of this audit's scope entirely, not overlooked.

`devtools::check()`: 0 errors, 0 warnings, 0 notes throughout every
regeneration this session.

---

## 2026-08-18 (continued) -- the two remaining Backlog items closed: one false alarm, one defensive fix

**`LT`'s 44,255 duplicate composite keys: not a bug, LT's real grain is
finer than "one row per haul."** Pulled a real example: two LT rows
sharing the exact 8-field key (`BITS`/2011/Q1/`DK`/`26D4`/`TVL`/228/28)
are identical on every HH-copied field (position, gear geometry,
environment) but differ on `PARAM` (`E5` vs `D`) and `LT_Weight`
(1.000 vs 1.476) -- two separate litter-category observations for the
same haul, exactly the same relationship HL/CA already have to HH (many
rows per haul, disambiguated by fields beyond the shared key). Checked
how far LT's own classification fields (`PARAM`, `LTSZC`, `TYPPL`,
`LTPRP`, `LTSRC`, `LTREF`) get toward uniqueness: 31,055 distinct with
the 8-field key alone, 65,883 with all six added -- closer, not
complete. The remaining 9,427 duplicate groups (16,140 rows) share
every one of those fields too and differ only in `LT_Weight`/`LT_Items`,
consistent with multiple physical litter items of the identical full
classification recorded as separate rows rather than summed into one --
LT carries no sequence/replicate field to disambiguate those, and none
seems to exist. Nothing to fix: the table's own `details` already says
"each row is one litter assessment/observation," and `relationships`
already declares `many-to-one`, both already consistent with what this
confirmed. Left as institutional knowledge in `TODO.md`'s history
rather than restated in the spec, since it doesn't change anything
already documented there.

**`Gear`'s enum key-order noise: root cause not confirmed, fixed
defensively anyway.** `get_vocab_enum_values()` (`spec_02_curate_dict.R`)
builds the `values` map straight from whatever row order
`op_vocab_get_codes()`'s live icesVocab call returns, with no sort.
Tried to reproduce the reported "different order every re-run" directly:
two live `op_vocab_get_codes("Gear")` calls a second apart, and two full
`spec_02` re-runs diffed byte-for-byte -- both came back perfectly
stable. Couldn't confirm the symptom recurs on a short timescale, so
either it's real but tied to a longer-timescale drift in the live
service (e.g. server-side reindexing between sessions days apart) than
this session tested, or the original observation was a one-off. Added
`codes[order(codes$Key), ]` before building the map regardless -- key
order carries no meaning for a map-form enum (data-dict spec: map form
is for labels, not sequence), so sorting is purely stabilizing, zero
content risk, and removes the possibility outright whether or not the
original cause is ever pinned down. Regenerating showed only a 2-line
diff per YAML -- the live service's natural order was already very
close to alphabetical, just not exactly.

Both items closed out `TODO.md`'s Backlog entirely; moved the
`ICES_ISSUE_REPORT.md` filing item (the one Backlog item deliberately
not touched this round) down into the `imbus/ICES liaison` section at
the user's request, with a one-line note that it's held on purpose
(more issues may still surface to fold in), not merely stuck.

`devtools::check()`: 0 errors, 0 warnings, 0 notes.

---

## 2026-08-18 (continued) -- ICES Issue 13 filed: DateofCalculation, corroborated from obus (read with explicit user permission)

The user connected the LT duplicate-key finding above to the earlier
`LT.DateofCalculation` conflict and suggested obus might already
document related behavior -- explicitly authorizing read access to
obus's repo for this (a deliberate, scoped exception to this project's
own standing "stay out of obus internals" habit, not a change to it
generally).

**obus's own `vignettes/articles/issues.qmd` (main branch, not a
feature branch) turned out directly relevant.** Two entries:
"FlexFile returns superseded `DateofCalculation` revisions per haul" --
`getFlexFile()` returns duplicate rows per haul, identical except
`DateofCalculation`, confirmed reprocessing revisions (739 of 53,859
distinct FL haul keys, full 2000-2026 pull) -- and "`DateofCalculation`
is encoded differently in different tables" (`YYYYMMDD` in HH,
`YYYYDDMM` in FlexFile). Both marked "not yet filed" with ICES by obus
itself. (A tempting-looking hit in an exploratory obus branch,
mentioning "LT" near a `DateofCalculation`-adjacent formula, turned out
to be a false lead on inspection -- "LT" there is the Lithuania country
code inside a quoted `{DATRAS}` package comment, not the Litter table;
included here as a reminder to read the actual context, not just trust
a grep match.)

**Extended opus's own verification before writing anything.** Confirmed
LT's own `DateofCalculation` is internally consistent across a haul's
multiple LT rows (0 of 14,059 multi-row hauls disagree with themselves)
-- so the HH-vs-LT conflict is a per-table difference, not an
LT-internal one. Checked HH/LT for obus's own digit-order finding
directly rather than assuming it transfers: neither table's own digit
pattern exceeds 12 in the position that would expose a day-before-month
encoding, so that specific sub-finding is FL-specific and was reported
as such, not generalized. Recomputed the HH-vs-LT mismatch on distinct
hauls rather than the earlier raw joined-row count (which double-counts
hauls with more than one LT row, though harmlessly, since LT's own
value doesn't vary within a haul): 30,364 distinct hauls with a value on
both sides, 19,193 (63.21%) disagree, median gap 120 days, max 2,557
days (~7 years), both directions.

Filed as `data-raw/ICES_ISSUE_REPORT.md` Issue 13 (own evidence primary,
obus's finding cited explicitly as corroboration, not merged in as if
it were opus's own) and `known-issues.yaml`'s
`dateofcalculation_cross_product_inconsistency` (`scope: systemic`).
`TODO.md`'s filing-item count updated 12->13.

---

## 2026-08-18 (continued) -- known-issues registry refinement: three false leads closed, one real gap surfaced, escalation list prioritized

`TODO.md`'s two remaining "Known-issues registry refinement" items:
inventory the original 5 D-level fields from the 2026-07-29/08-02
sessions, and prioritize escalation candidates for imbus using the
`scope` tag added 2026-08-17. Re-verified every original finding
directly against the current archive (`.datras/*_legacy.parquet`) and
the 2026-08-17 full icesVocab snapshot, rather than trusting prior
session notes at face value.

**3 of the 5 original fields turned out to be false leads, not real
issues.** `AgeSource` and `AgePreparationMethod` (CA): confirmed
2026-08-16 (see that date's entry) that `TS_AgeSource`/`TS_AgePrepMet`
are bare redirects ("see SampleType", "see PreparationMethod"), and
that fix was never folded back into `known-issues.yaml` itself --
re-verified again here (`AgeSource` real values are exactly
`{-9, otolith}`, both present in `SampleType`; `AgePrepMet`'s 8 real
values all present in `PreparationMethod`). `LTSRC` (LT) is a third,
independent false lead with a different mechanism: no prefix collision,
no redirect -- all 16 real codes, including a lone lowercase `sba`
case variant, match the vocab's own un-prefixed `LTSRC` key exactly
(re-checked directly against `.datras/LT_legacy.parquet` and the vocab
snapshot). The original 2026-07-29 "SB* codes missing" claim was simply
wrong or stale; no specific later fix corrected it, so there's no
`known_violations` entry to write -- closure recorded here only.

**The registry's own `icesVocab_gaps` entry was itself stale.** Its
first example, "GearExceptions (only 'B' in vocab)", was the exact
AC_/TS_ prefix collision already fixed 2026-08-08 (`AC_GearExceptions`
has 1 code; `TS_GearEx`, the correct legacy-name key, has 13) --
re-verified directly this session: HH's 9 real `GearEx` values
(`-9/S/SB/B/I2/DB/R/S2/D`) all match `TS_GearEx` exactly. The entry had
never been corrected after the 2026-08-08 fix, so it was quietly
carrying a debunked finding as if still live. Retired it, replaced with
two entries: `icesvocab_key_resolution_hazard` (`scope: systemic`) folds
in both the prefix-collision and the redirect-only-key findings as one
named hazard (icesVocab has no machine-readable way to mark a key as
scoped to one collection or as an alias/redirect -- filed with ICES as
Issues 7-8), and `param_vocab_incomplete` (`scope: field-level`) keeps
the one example from the old entry that actually held up: LT's `PARAM`
has 6 real codes (`A2/A3/A5/A6/A7/A14`) genuinely absent from
icesVocab's 1,938-code list, checked directly rather than sampled. That
finding had been sitting as an unaddressed `todo` in
`spec_02_curate_dict.R` since curation, never given its own registry
entry or filed anywhere.

**Escalation-candidate prioritization**, cross-referenced against
`ICES_ISSUE_REPORT.md`'s already-filed issues:

- *Already filed, nothing further needed:* `swell_height_vocab_unused`
  (Issue 10), `datras_field_list_type_divergence` (Issue 12),
  `dateofcalculation_cross_product_inconsistency` (Issue 13),
  `icesvocab_key_resolution_hazard` (Issues 7-8, new today).
- *Ready to file, not yet in the report:* `ca_haulno_unlinkable_to_hh`
  -- highest priority, largest volume (4.92% of CA rows), currently
  only mentioned in passing under an unrelated design suggestion, never
  its own issue; `lt_bts_2025_q1_orphaned` -- not mentioned at all;
  `param_vocab_incomplete` -- the todo above.
- *Not ready:* `ca_haulno_tail_mismatch` (700-row residual, cause still
  undiagnosed since 2026-08-07; checked again for any incidental lead
  from later sessions, found none).
- *Excluded:* `sentinel_replacement_data_loss` (`scope: opus-internal`
  -- not ICES's issue).

Scoped today's edits to `known-issues.yaml` itself, at the user's
choice: drafting the three ready-to-file items into
`ICES_ISSUE_REPORT.md` as new numbered issues stays under the
separately-tracked "imbus/ICES liaison" `TODO.md` item, not done here.

`devtools::check()`: 0 errors, 0 warnings, 0 notes.

---

## 2026-08-18 (continued) -- ICES_ISSUE_REPORT.md: 3 issues filed, a stale "false lead" corrected, dates/history stripped

Continuation of the same session: filed the three gaps identified above
(`ca_haulno_unlinkable_to_hh`, `lt_bts_2025_q1_orphaned`,
`param_vocab_incomplete`) as Issues 14-16, and reviewed the full report
end to end for staleness rather than just appending.

**Issue 9's own table was wrong, by the same mechanism Issue 8 itself
already names.** Its `Ship` row called `Ship` a "false lead" using
`TS_Ship`'s own codes (88 of 111 real values missing) -- but Issue 8's own
text, a few hundred lines earlier in the same document, already flags
`TS_Ship` as a bare redirect ("see SHIPC"). Nobody had gone back and
followed it. Checked directly: across HH/HL/CA/LT combined, 112 distinct
real `Ship` values, 109 match `SHIPC` (97%), only `AA36`/`DCA`/`HOL` don't.
`Country` had the identical problem, referenced only in Issue 9's prose
("already-known Survey/Country false leads") -- `TS_Country` misses 20 of
23 real values, but the redirect target `ISO_3166` covers 22 of 23 exactly
(the lone exception, `DUM`, reads as a placeholder; the archive's `SUHH`
correctly matches `ISO_3166`'s own convention of suffixing defunct
countries, `SUHH`=USSR). `Survey` was checked the same way and remains a
genuine false lead -- no redirect exists for it, the bare `Survey` key's
133 codes are simply a different, unrelated list from DATRAS's own 28
survey acronyms. Rewrote Issue 9's table and surrounding prose to reflect
the corrected picture, and folded in evidence for both corrected fields.
Also relocated a "Tickler/CatIdentifier adopted as enum" addendum that had
been orphaned at the very end of the file (after the unrelated "Suggestion
for consideration" section) back into Issue 9, where it actually belongs.
Added Ship/Country as two more confirmed instances to `known-issues.yaml`'s
`icesvocab_key_resolution_hazard` entry -- no opus-side bug resulted (Ship/
Country are typed as open strings, not enums), but the same hazard applies.

**At the user's explicit request, stripped discovery dates and
session-history narrative from the whole report.** Every "found
2026-08-16", "re-checked 2026-08-17", "First noticed 2026-08-02"-style
phrase removed; the "How this was verified" section's dated
"(added 2026-08-08)"/"(added 2026-08-09)" annotations folded into plain
numbered method descriptions; the top-level "Date: 2026-08-06" dropped
outright, since the document has kept changing since and was never
actually sent. What stayed: the substantive verification methodology
(which live sources, checked how) and all evidence/numbers -- an
ICES-facing report should read as a current-state account of what's wrong
and why, not a lab notebook of opus's own session-by-session path to
finding it. That narrative belongs here, in `DEVLOG.md`, exclusively.

Cross-referenced the three new issues back into their `known-issues.yaml`
entries ("Filed as ... Issue N"), corrected `param_vocab_incomplete`'s own
implication text (previously said "never actually filed," no longer true),
and bumped `TODO.md`'s stale issue count (13 -> 16).

`devtools::check()`: 0 errors, 0 warnings, 0 notes.

---

## 2026-08-18 (continued) -- a structural consistency checker between the two issue documents, which immediately found a third stale reference

User asked, after the "why two files" explanation above, for a script that
keeps `inst/DATRAS-known-issues.yaml` and `data-raw/ICES_ISSUE_REPORT.md`
in sync going forward. Wrote `data-raw/validate_issue_registry_sync.R`:
checks that every "ICES_ISSUE_REPORT.md Issue N" cited inside the yaml
resolves to a real `## Issue N:` header, the reverse (every yaml `id`
cited near "known issue(s)" in the .md still exists), that no
`scope: opus-internal` entry ever cites an ICES issue, and that the .md's
own Issue headers are unique and contiguous. Explicitly a linter, not a
fact-checker -- documented in the script's own header that it cannot
catch a claim going stale (today's earlier `icesVocab_gaps`/Issue 9 bugs
were both factual errors, not broken cross-references; neither would have
tripped this script). Verified detection actually works, not just that it
runs clean: copied both files to a scratch dir, corrupted each of the four
checks in turn (a dangling yaml->md number, a renamed yaml id still cited
in the .md, an opus-internal entry given a fake filing, a duplicated
`## Issue` header), and confirmed each specific break was caught with the
right message before reverting.

**Running it clean surfaced a third stale reference no one had caught by
hand.** `swell_height_vocab_unused`'s own text still said "Candidate for
`data-raw/ICES_ISSUE_REPORT.md`" -- even though Issue 10 already exists
and covers exactly this finding. This one had been silently wrong since
Issue 10 was written, and the "escalation candidate" list given to the
user just one turn earlier had wrongly asserted it as already
cross-referenced (an inherited assumption, not independently re-checked
at the time). Fixed the yaml text to say "Filed as ... Issue 10" once the
checker flagged it; re-running confirmed the fix and produced the correct
7-filed / 2-not-yet-filed split (`ca_haulno_tail_mismatch`, genuinely
undiagnosed; `swell_height_type_mismatch`, resolved on opus's own side
with no remaining ICES-facing angle -- both correctly informational, not
errors).

`devtools::check()`: 0 errors, 0 warnings, 0 notes.

---

## 2026-08-19 -- considered and declined a shipped icesVocab full-catalog csv

Investigated whether to add a tidy `inst/*.csv` snapshot of the entire
icesVocab catalog (every code-type, every code, plus the prefix-stripped
join key Issues 7-9 already reason about) as a stable,
`system.file()`-accessible artifact, independent of the `icesVocab` R
package. `data-raw/build_icesvocab_snapshot.R` already does almost
exactly this, but writes to a gitignored cache under a hashed filename
and drops the join-key columns `op_vocab_get_types()` already computes --
so relocating it alone wouldn't have been enough. Decided not to pursue,
at least for now, once the shape was fully scoped; no changes made. The
live-vs-cached distinction stays as-is regardless of this csv's fate:
`op_vocab_get_types()`/`op_vocab_get_codes()`/`op_vocab_resolve_key()` and
the drift-catching validator (see below) never read a shipped snapshot.

## 2026-08-20 -- Quarto documentation site replaces pkgdown/vignettes; the ICES issue report becomes an article in it

opus isn't a package with an external R-user audience (single user,
feeds IMBUS/ICES directly) -- pkgdown conventions and a `vignettes/`
directory were solving a problem opus doesn't have. Replaced both with a
plain Quarto website at the repo root (`_quarto.yml`, `index.qmd`,
`articles/`), rendered to `docs/` and committed so GitHub Pages can serve
it from `main` with no build step. Removed `_pkgdown.yml` and the
`vignettes/` directory entirely.

`data-raw/ICES_ISSUE_REPORT.md` is now `articles/issues.qmd` -- confirmed
via a full diff that nothing was lost in the move before deleting the
original. `data-raw/build_field_gap_audit.R` and
`data-raw/validate_issue_registry_sync.R` were re-pointed at the new
location.

`articles/dictionary.qmd` embeds a rendered profile of the shipped yaml
against the full local archive (via the external `data-dict` CLI's own
`render` command, `op_render_spec()`) -- deliberately a dated,
regenerate-at-milestones snapshot rather than a live page, since the
archive it profiles against isn't part of this repository and keeps
growing.

RStudio's own "Render Website" button doesn't work here: `opus.Rproj`'s
`BuildType: Package` line conflicts with Quarto's website-project
detection, and RStudio re-adds that line on every project open regardless
of edits to the .Rproj file. Settled on `quarto preview` from the
terminal instead of fighting the IDE.

Separately, went through `articles/issues.qmd`'s prose in three passes at
the user's request: rephrased away from insider framing ("Tier 1", "not a
sample", process-narration like "at all before this sweep") to read as a
novice-facing account; reordered issues by generality/severity with LT
issues always last (display order only, verified content-preserving via
a scripted diff check); and corrected one factual overreach -- "The two
services do not cross-reference each other anywhere" overstated what a
live schema check of both APIs actually shows. A user-supplied
`icesVocab::getCodeTypeList()`/`getCodeList()` script is a *consumer's*
name-matching workaround, not evidence of a real cross-reference, so the
text now reads "Neither service's own metadata cross-references the
other, anywhere."

`devtools::check()`: 0 errors, 0 warnings, 0 notes.

## 2026-08-20 (continued) -- de-historicized the yaml's curation notes; the vocab-annotation validator no longer depends on a cached csv

User flagged the yaml's own `TimeShot` entry as an example of a broader
problem: its `details:` read like a lab notebook of opus's own discovery
process ("corrected 2026-08-18, found via the user's own spot-check...
traced back to a 2026-07-29 citation whose basis... isn't recoverable
from here") rather than a description of the field itself -- "something
that is of no interest to the user of the yaml." Went through every
shipped `details:`/`todo:`/`mechanism:` string in
`data-raw/spec_02_curate_dict.R` (the `corrections`, `field_specs`,
`shared_field_specs`, and `table_specs` lists -- roughly 50 field entries
plus the four table overviews) and stripped dates, "originally X /
re-verified Y", internal-process citations, and discovery narrative,
while keeping every quantitative fact and legitimate present-tense
caveat. R-comment provenance (why the script does something, dated for
future maintainers) was left alone -- that's workshop notes for this
repo's own contributors, not part of the shipped deliverable.

Two of the strings being touched were more than stylistic. `TimeShot`'s
zero-padding claim had the polarity backwards relative to the real
archive. `LTSRC` and `ThermoCline` each still said "not added to
`values:` given the tiny count" even though a later block in the same
pipeline does add `values:` to them -- a leftover from before that later
block existed. Also found three citations to
`data-raw/tier1_field_stats.R`, a file renamed to
`data-raw/retired/tier1_field_stats_retired.R` in an earlier cleanup;
dropped the dead pointer rather than redirect to a "retired" script,
since the underlying claim (icesDatras's fetch pipeline scrubbing `-9` to
NA) doesn't need one to stand on its own.

Regenerated both `inst/DATRAS-data-dict-legacy.yaml` and
`inst/DATRAS-data-dict.yaml` (`spec_02` -> `spec_03`); 0 mismatches in a
full legacy/curated parity check across all 190 fields. Re-rendered the
dictionary snapshot (`articles/dictionary-snapshot-2026-08-20.html`,
replacing 08-18's -- the render embeds the yaml's own prose, so the old
file was now visibly stale) and the full site.

Separately, rewrote `data-raw/validate_vocab_annotations_sync.R` to stop
reading `data-raw/DATRAS-vocab-field-audit.csv` -- that csv was found 8
days stale relative to the archive it was supposedly auditing, and
re-deriving everything live (`op_vocab_resolve_key()`/
`op_vocab_get_types()`/`op_vocab_get_codes()` plus direct
`.datras/*.parquet` reads) removes the staleness risk structurally rather
than needing a fresher re-run each time. Correctly separates a mechanical
check (enum fields missing `values:`/`details:` completeness) from an
informational "possible enum promotion" worklist (non-enum fields with a
live full data-fit, never auto-applied) -- an earlier version of this
script wrongly flagged `Year`/`DepthStratum`/`StatisticalRectangle`/
`Maturity` as errors before that distinction was added.

`devtools::check()`: 0 errors, 0 warnings, 0 notes. Vocab-annotation
validator: 0 structural errors.

## 2026-08-20 (continued) -- ICES distribution pitch: parquet +
catalog.duckdb as a SOAP alternative

Explored, verified hands-on, and implemented a possible pitch to ICES:
publish Tier 1 tables as parquet plus a small companion `.duckdb`
"catalog" file at a plain https URL, as an alternative to DATRAS's
SOAP/WSDL access. `obus::dr_con()` already does the remote-parquet half
in production (pointed at `https://heima.hafro.is/~einarhj/datras`, the
user's own institutional server, run as a demo -- not the eventual
host); this adds a metadata/semantic layer DuckDB supports natively:
`COMMENT ON TABLE/COLUMN` (durable, queryable via `duckdb_columns()`/
`duckdb_views()`) and lookup tables for enum labels and range
constraints (DuckDB's native `CREATE TYPE ... AS ENUM` doesn't carry
labels, and view `CHECK` constraints aren't implemented). A catalog-only
`.duckdb` file (views over external parquet plus comments, zero data
rows) is ~275KB regardless of data volume, and `ATTACH
'https://.../catalog.duckdb' AS cat (READ_ONLY)` works directly with no
local download step -- confirmed against a real loopback HTTP server.

Built `data-raw/spec_04_build_catalog.R`: reads both shipped yaml
dictionaries, mirrors `op_flag_violations()`'s (`R/validation.R`) exact
field-walking logic for `values`/`range`/`constraints` -- including its
`.inf`-maps-to-Inf-on-either-side quirk, kept verbatim rather than
silently "fixed" -- and emits `CREATE VIEW`/`COMMENT ON TABLE`/`COMMENT
ON COLUMN` plus three lookup tables (`enum_labels`,
`range_constraints`, `field_constraints`) into
`.datras/to_https/catalog.duckdb`. Retargeted
`archive_06_split_legacy_new.R`'s output there too (`{TABLE}_legacy.
parquet` / `{TABLE}_new.parquet`), so the parquet and its catalog stage
side by side for manual upload.

Real discovery during implementation: DuckDB's `COMMENT ON COLUMN`
eagerly resolves the view's *actual current remote schema*, so it
errored against a stale trial file already sitting at the demo URL from
before this session's yaml curation -- and `CREATE OR REPLACE VIEW`
(tried as a workaround) wipes all existing column comments, so that
doesn't work either. Net effect is a real ordering constraint for any
future run: parquet must already be live at the target URL *before* the
catalog is built, not after or alongside. Verified the full pipeline by
temporarily pointing `BASE_URL` at the local `.datras/to_https` path --
all 8 views (4 tables x curated/legacy) built cleanly, and
`range_constraints` came out to exactly 192 rows (96 yaml `range:`
fields x 2 name variants), an independent cross-check.

Open question, not resolved this session: where the *connector* half
(ATTACH + return a lazy tbl, `dr_con()`-equivalent) should live long
term -- it's data access, not spec curation, so by opus's own scope
rule it belongs with obus, not here. obus itself is expected to be
restructured rather than scrapped, so this is a live design question,
not a blocker.

## 2026-08-26/27 -- XML download pipeline: fixed duplicate-file bug,
full restart, LT tag + EVHOE fixes

`.datras/xml/` could end up with two files for the same (record_type,
survey, year, quarter) cell: `archive_02_download.R` generated a
timestamp-suffixed filename on every fetch instead of a stable one, so
any re-fetch -- deliberate, or from the manifest simply not yet knowing
about an already-downloaded cell -- wrote a second file instead of
overwriting the first. A comment in the code already described a
`Quarter={quarter}/` partition level that the path-building code right
below it never actually implemented. Found 5 cells (HL/CA, NS-IBTS,
2025-2026) where this had corrupted the manifest -- recorded
`status="empty"`/`n_rows=0` despite the real XML holding tens of
thousands of records; a sorted-line diff confirmed the duplicate pairs
were byte-identical, just reordered by ICES's server, so no real data
was ever at risk. A broader catalog-vs-manifest check also found 72% of
(cell x record_type) combinations ICES actually has had no manifest row
at all, root cause undiagnosed -- moot given the restart below.

Rather than surgically dedupe an already-corrupted ~20GB/4790-file
cache, wiped `.datras/xml/` and `.datras/manifest.tsv` entirely and
relaunched a fresh 1965-2026, all-surveys, all-record-types download
(`.datras/catalog.tsv` and all downstream derived output left
untouched). Fixed in code first: stable path
`.../Survey=X/Year=Y/Quarter=Q/{rt}_{survey}_{year}_Q{quarter}.xml`, a
stable-path check before hitting the network at all, a new
`OPUS_FORCE_REFRESH_YEARS` config for a deliberate re-fetch, and a log
warning when a response is classified "empty" but is implausibly large
(a real empty DATRAS response is ~200 bytes).

The ~5.5 hour restart surfaced two more real bugs, both fixed and fully
repaired -- final manifest is 0 errors, 0 corrupted rows, full
973x4=3892-cell coverage (HH 972/1, HL 971/2, CA 906/67, LT 215/758,
`ok`/`empty`):

- **LT tag-pattern bug**: every LT fetch counted zero rows regardless of
  content -- the row-counting logic assumed `Cls_DatrasExchange_{rt}`
  universally, but LT's real element name is
  `Cls_DatrasExchange_LitterAssessmentOutput` (matches its distinct
  `getLitterAssessmentOutput` endpoint, unlike HH/HL/CA's
  `get{RT}data`). All 973 LT cells came back "empty"; 204 actually had
  content, caught by the implausibly-large-empty-response warning added
  earlier in the same session (fired exactly 204 times). Fixed the
  tag-pattern computation in `archive_02_download.R`, then repaired the
  204 rows locally (re-read the already-downloaded XML, recompute with
  the right tag) rather than re-fetching.
- **EVHOE padding (Issue 17)**: confirmed live against ICES's own
  `getSurveyList` that `EVHOE` -- and only `EVHOE`, of 30 surveys --
  comes back as `"EVHOE     "`, 5 trailing spaces baked into ICES's XML.
  Filed as Issue 17 in `articles/issues.qmd`. Fixed at the source
  (`trimws()` in `archive_03_catalog.R`'s `datras_get_surveys()`) plus
  `URLencode()` on the survey param as defense in depth. All 116
  previously-`error` EVHOE cells (29 cells x 4 record types) were
  retried in a small standalone script bypassing the shared
  `catalog.tsv` cache -- 100% succeeded, confirming padding was the sole
  cause.
- Also cleaned up manifest corruption from a since-fixed bug: multi-line
  curl error messages, written with `quote = FALSE`, had split single
  logical rows across physical lines. Stripped the resulting phantom
  rows and collapsed remaining multi-line `error_msg` values to one
  line.

`.datras/xml/` and `.datras/manifest.tsv` are now a complete, clean,
ready-to-use raw archive. `.datras/` itself is gitignored, so none of
this shows in git history directly -- only the code fix does
(`archive_01_download_config.R`, `archive_02_download.R`,
`archive_03_catalog.R`, `archive_05_backfill_lt_partitions.R`).

## 2026-08-27 -- data-dict pull check: R package shipped, tidyverse/Posit
now, opus's CLI integration verified still compatible

User pulled a fresh `~/garbage/data-dict` (53 commits since the last
check-in around 2026-08-05/06) and asked for a check against opus. The
project has re-homed under tidyverse/Posit (authored by Gabor Csardi and
Hadley Wickham), moved to `github.com/tidyverse/data-dict` and
data-dict.tidyverse.org, and is on a CRAN submission track -- no longer
an independent side tool.

The headline item, a new `r/` R package (`datadict`, v0.1.0), turned out
to be thin and consumer-facing: `dd_install()` downloads a released
binary (no Rust toolchain needed), `dd_run()` is generic, and
`dd_validate_data()` is the only validation-specific function -- it runs
`validate-data` and writes+opens an HTML report. It doesn't expose
validate-spec/meta, export-spec/data, render, describe, or draft
separately, and it can't inject a `source: parquet:` path the way opus's
own `validate_against_dict()` (`data-raw/validate_against_datadict.R`)
already has to, since the shipped yaml deliberately omits
machine-specific paths. So it doesn't replace or reduce opus's own
22-function `R/validation.R` -- it's a pointer worth giving to *consumers*
of `DATRAS-data-dict.yaml` (WP3, ICES submitters) who want a
zero-setup self-check, not something opus itself depends on. Checked the
PyPI side too (`data-dict-yaml`): confirmed from `tools/pypi/
make_wheels.py`'s own docstring that it repacks the compiled binary into
wheels with "no Python code involved" -- CLI distribution parity, not a
Python API analogous to the R package.

opus's local CLI binary (`~/garbage/data-dict/target/release/data-dict`,
what `validate_against_dict()` and `R/validation.R`'s wrappers all shell
out to) was stale -- last built 2026-08-16, 11 days behind a source tree
that had since grown the entire assertions feature and the R package
itself. Rebuilt it (`cargo build --release -p data-dict-cli`, now tool
v0.0.3) and diffed every flag opus's own code passes (`--json`,
`--table`, `--html`, `-o`/`--output`, `--pretty`, every subcommand name)
against live `--help` output for each wrapped subcommand. All unchanged.
Spec format version is still `$version: 0.1.0`, matching opus's yaml.
No compatibility breaks, no code changes needed.

The one substantive new feature is Assertions: a full `assert`-expression
language (SQL-like, three-valued logic, row-level or aggregate),
`language: r`/`python` passthrough read into the same semantics rather
than executed as-is, a `translate` CLI command, and three new data-check
codes (D07 violated, D08 not evaluable, D09 integer-overflowed). Spec
checks grew from S01-S27 to S01-S36 plus a reorganized S60-S69
"structural checks" block; D01-D06 grew to D01-D09. None of this is
hardcoded anywhere in opus's wrappers, which pass the CLI's JSON through
generically. AGENTS.md's existing line -- "not yet assertions, for which
no evidence-backed candidate has been identified" -- is still accurate;
no candidate rule surfaced in this pass either, and none was invented to
match the newly-available feature (Working Principle 4).

Updated AGENTS.md's three passages that talked about the R-package in
future tense ("R-package (when available)", "if/when R-package
matures", "when their R-package ships") to reflect that it has shipped,
and to state its actual (narrower-than-implied) scope, so a future
session doesn't re-discover the same gap. Updated the corresponding
memory entries (`data_dict_current_status`, `data_dict_trajectory`,
`data_dict_spec_tidyverse`) to match.

---

## 2026-08-28 -- obus's consistency check finds the WSDL-vs-curated type seam

Raised from obus, not from opus's own testing. obus ran the
parquet-vs-xml class-consistency check its `AGENTS.md` prescribes
(fetch the same table both ways, compare `sapply(x, class)`) on
NS-IBTS 2022 Q1. Row counts matched exactly; **types did not** -- 7
mismatched columns in HL, 6 in CA, plus `.id` present only in the
parquet.

**Root cause: opus answers "what type is this field" two different
ways, and nothing says which is authoritative.**

1. `data-raw/archive_00_wsdl_types.R` types the parquet archive from
   ICES's **WSDL physical types** (string/int/decimal). This is
   deliberate and well-reasoned -- that file's own header explains why
   the curated spec must not be an input here (enum-ness is a curation
   conclusion drawn from archive data, so feeding it back in would be
   circular), and states plainly that the YAML "plays no role here and
   is never loaded by this file or its callers."
2. `op_field_spec()` reports the **curated semantic types**
   (`number(quantity)`, `number(ordinal)`, `enum`) from the YAML.

Both are internally consistent. The problem is only visible downstream,
where a consumer touches both: obus types its live-XML path from (2)
and reads an archive built from (1), so the same column arrives as a
different R class depending on which source the user asked for --
silently, with no error anywhere.

Traced to the physical parquet schema rather than inferred from R
classes, which is what made the three distinct mechanisms legible:

- `SweepLength`, `LengthClass`, `SubsampleWeight`,
  `SpeciesCategoryWeight`, `SubsampledNumber`, `NumberAtLength`, `Age`
  -- **INT32** in the archive (R integer); `number(quantity)` in the
  YAML (R numeric). The straightforward physical-vs-semantic case.
- `Year` -- **INT64** in the archive. R has no native 64-bit integer,
  so it renders as numeric; the YAML's `number(ordinal)` gives integer.
  Not a typing disagreement at all -- a representation artifact of a
  storage width that looks like overkill for a year.
- `DateofCalculation` -- INT32 carrying a parquet **DATE** logical type
  (R `Date`); `number(ordinal)` in the YAML. Here the archive made a
  real semantic choice the WSDL doesn't express.

Worth noting the WSDL reports a plain `int` for **all five** of the
fields checked, including `Year` and `DateofCalculation` -- so "the
archive follows the WSDL" is not a complete account either. Something
downstream of `archive_00_wsdl_types.R` widened `Year` to INT64 and
annotated `DateofCalculation` as DATE; worth locating if the
reconciliation item is taken up.

Nothing was changed in opus as a result. The finding is recorded in
`TODO.md` as three items -- the reconciliation decision itself, the
narrower `DateofCalculation` question (a date typed `number(ordinal)`
looks wrong regardless of how the larger question resolves), and a
missing R accessor for `inst/DATRAS-known-issues.yaml`, which turned
out to have no reader anywhere in `R/` and is blocking obus's
sentinel-to-`NA` work.

**Also surfaced, unrelated to types:** NS-IBTS 2022 Q1 HL is exactly
32767 rows (2^15 - 1) in *both* the live ICES response and the archive,
while neighbouring quarters of the same survey run 44k-52k (2021 Q1:
51151; 2023 Q1: 45752). A scan of the whole HL archive found it is the
only one of 971 survey/year/quarter groups on that value, and that 115
groups exceed it (max 54712) -- so there is no global cap, and a
signed-16-bit truncation specific to that submission is the most likely
reading. Unproven; logged in `TODO.md` as a candidate registry entry
pending a targeted check against ICES.

The general lesson matches the 2026-08-16 entry's: a divergence between
two internally-consistent sources is invisible to anyone reading either
one, and only shows up when something reads both and compares real
values. opus has no such consumer of its own -- obus is it.

---

## 2026-08-29 -- the XML->parquet conversion becomes an R API; archive rebuilt; sentinel policy written down

Driven by a question from obus: the same DATRAS column arrived as a
different R class depending on whether it came from the parquet archive or
a live XML fetch. Tracing it found not a bug but a seam -- opus answered
"what type is this field" two ways (WSDL physical types building the
archive, curated semantic types in the yaml) and nothing reconciled them.

**The fix was structural rather than a reconciliation.** The conversion
moved out of `data-raw/` and into `R/` as four exported functions --
`op_cast_wsdl_types()`, `op_rename_to_new()`, `op_strip_sentinels()`,
`op_cast_to_spec()` -- so the archive build and any downstream consumer run
the *same code* rather than two implementations that agree by luck. The
question of which type system wins is now answered once, inside those
functions, instead of per-consumer. Also promoted: the ASMX readers
(`op_datras_operations()`, `op_datras_operation_types()`,
`op_datras_field_metadata()`) and the sentinel accessors. 22 exports -> 34.

**All three data-raw/R duplications resolved**, two of which the code's own
comments admitted to. `spec_00_operation_types.R` was a port of
`R/field_names.R`'s ASMX crawler; `archive_03`'s `datras_get_field_list()`
independently re-implemented `.fetch_live_datras_field_list()` down to the
same malformed-namespace fix; `archive_00_wsdl_types.R` held the caster.
All deleted, callers repointed. Recorded as Working Principle 7b. The
vocab helpers were already correct (they call `op_vocab_get_codes()` and
add only caching) and are cited as the model. One remains:
`spec_04_build_catalog.R` still mirrors `op_flag_violations()` verbatim.

**Two real bugs found by doing this.** `apply_wsdl_types()`'s switch handled
`int`/`decimal`/`string` and silently passed anything else through: exactly
one field in the specification is declared `float` (LT's `BottomDepth`) and
it had been a text column throughout. And -- introduced during this work,
caught by the acceptance test -- caching the rename crosswalk *per table*
degraded it silently, because tier 2 borrows evidence between tables:
asked for `"LT"` alone it returned 1 rename instead of 23. Fixed at source
so no caller can ask the question in a way that quietly degrades, rather
than by documenting the hazard.

**The sentinel policy is now written down and machine-readable.** A sweep
found `-9` in 133 column-instances (an earlier count of 98 was wrong: it
compared `CAST(col AS VARCHAR) = '-9'`, which misses every double column
because DuckDB renders those as `"-9.0"`). Prevalence turned out to be
useless as a discriminator -- `Tickler` is 78% `-9` and real, `Turbidity`
99.6% and never recorded. What separates them is the label ICES publishes:
of 29 enum fields documenting a `-9` code, 24 label it as absence and 5 as
a real answer. `inst/DATRAS-known-issues.yaml` grew a `sentinels:
resolution` block -- a list of absence-meaning labels plus explicit keep
entries -- and an unrecognised label resolves to *keep*, so a documented
code can never be silently destroyed.

**Dictionary retypes.** `Quarter`/`Month` -> `number(ordinal)` with ranges;
`DateofCalculation` -> `date` (the format's `date` type, previously unused);
`Tickler`/`SpeciesCategory` stay `enum` but are now stored as text, because
`S07` forbids a `values:` map on a number column and their 32 and 56 code
labels are load-bearing. Applied to both dictionaries in lockstep.

**Archive rebuilt from `.datras/xml/`** -- verified beforehand that the
rebuild depends on nothing else in `.datras/` -- and consolidated to
`.datras/to_https/raw/{T}.parquet`, current names only.
`archive_06_split_legacy_new.R` became `archive_06_consolidate.R`: one step
instead of three, no legacy-named output, with the per-file crosswalk
assertion moved into `op_rename_to_new()`.

`op_validate_meta()` now passes on all four tables -- **194 checks, 0
failures, from 13**. Every column is all-or-nothing on sentinels; the only
five still holding `-9` are the documented keeps, at exactly their
pre-rebuild counts. `DateofCalculation` is a real `DATE` everywhere and no
column is `INT64`.

**Ordering note worth keeping.** Converting `DateofCalculation` to a date
while sentinels are present turns every `-9` into a null -- individually
correct, collectively destructive, and it reports nothing. The published
archive had done exactly that: its null count matched the sentinel count
exactly. Hence strip-then-cast, and `op_cast_to_spec()` refuses to convert
anything it cannot parse rather than producing `NA`.

**Site.** `articles/approach.qmd` written (it had been a stub outline).
`articles/reference.qmd` added, generated from `man/*.Rd` by
`data-raw/build_reference.R` -- which fails if an export belongs to no
group, so the curation cannot rot. The dictionary snapshot was regenerated
and now *actually profiles the data*: `op_render_spec()`'s `data_dir` only
rewrote existing `source:` lines, and the shipped dictionary declares none,
so every previous render was spec-only despite the page claiming otherwise.
It now injects one (395KB -> 923KB, with real row counts).

The `icesDatras` rationale in `approach.qmd` was corrected: the reason is
not a fork, it is that the official `ices-tools-prod/icesDatras` *corrects*
rather than merely fetches -- `fix_types` (on by default) and `new_names`
apply a bundled schema derived from `getDatrasFieldList`, so its
corrections carry that source's errors forward silently. Its bundled table
renames CA's `Age` to `IndividualAge`; the live operation returns `Age`.
Fine for most users, wrong for a project whose job is to document where
that metadata is wrong.

`.datras/` tidied: superseded artifacts moved to `.datras/retired/` with a
README, not deleted. `devtools::check()`: 0 errors, 0 warnings, 0 notes.

---

## 2026-08-29 (continued) -- archive published; catalog built; a date range that could not fit a DOUBLE

The rebuilt parquet went live at
`https://heima.hafro.is/~einarhj/datras/raw/{HH,HL,CA,LT}.parquet`,
byte-identical to the locally validated files (sizes match exactly, and a
remote read confirms the same row counts, `DATE`-typed `DateofCalculation`
and no `INT64` columns). `op_validate_meta()` takes a local path rather than
a URL, so it validated the staged copies; identical bytes make that the same
check.

With the parquet live, `spec_04_build_catalog.R` could run -- the ordering
constraint is real and it held. All four views resolve against the published
files, and `enum_labels` carries Tickler's 32 and SpeciesCategory's 56 codes,
which is the entire reason those two stayed enums stored as text. The five
`-9` labels a user needs to read the kept sentinels (`No ticklers are
allowed`, `Invalid hauls`, `No plus group`) are all present.

**The `date` retype surfaced a latent catalog bug.** `range_constraints` was
declared `min_value DOUBLE, max_value DOUBLE`, but `RANGE_TYPES` has always
included `date` and `datetime`. Once `DateofCalculation` became a `date`, its
bound `'2012-04-19'` hit `as.numeric()` and silently became `NULL` for all
four tables -- four "NAs introduced by coercion" warnings and a lost
constraint. Bounds are now `VARCHAR`, so numeric and date ranges both survive
and consumers cast per the column's declared type. Nothing consumed the
catalog yet (it had never been published), so the schema change costs
nothing.

**Two archives are now live, and obus reads the older one.** The root
`…/datras/{T}.parquet` files remain in place and are a genuinely different
artifact from `…/datras/raw/{T}.parquet`: HL is 14,400,747 rows against
14,423,771, 30 columns against 29, and it carries obus's Tier-3 `aphia`/`sex`
names plus an `.id` column the new archive has no equivalent for. Pointing
obus at `raw/` is therefore not a URL change -- it needs a decision on the
Tier-3 naming layer and on `.id`. Recorded in TODO.md rather than resolved
here.

One incidental confirmation: both archives report 1,050,496 nulls in HL's
`DateofCalculation`. The old file reached that by silently coercing `-9`
during an implicit date cast; the new one reaches it by a declared,
registered sentinel decision. Same number, opposite epistemic status -- and
the agreement is a useful cross-check that the strip removed exactly the set
the old cast had destroyed.

---

## 2026-08-29 (continued) -- catalog published and exercised; two things the rebuild had quietly changed

The catalog went live at `.../datras/raw/catalog.duckdb`, byte-identical to
the local build. It works remotely with no download: `ATTACH '<url>' AS cat
(READ_ONLY)` streams over HTTP range requests, all four views resolve
against the published parquet, and a filtered aggregate over HL's 14.4M rows
returned in 0.3s because the predicate pushes down to parquet row-group
statistics. `httpfs` auto-installs; there is nothing to set up. dplyr works
via `tbl(con, I("cat.HH"))` -- the `I()` is needed for the schema-qualified
name.

The join that makes the sentinel work legible from the outside:

    SELECT h.Tickler, e.label, COUNT(*)
    FROM cat.HH h LEFT JOIN cat.enum_labels e
      ON e.table_name='HH' AND e.column_name='Tickler' AND e.code=h.Tickler

returns `-9 | No ticklers are allowed | 117290`. A user who knows nothing
about any of this reads it correctly.

**Catalog placement settled, and the earlier reasoning was wrong.** It now
sits *inside* `raw/`, with the exchange tables it describes. The earlier
argument for the root assumed one catalog spanning every layer; the actual
intent is that `raw/` is the minimum faithful parquet rendering of the
exchange data and downstream products may get their own catalog. A catalog
per layer means each lives beside its own data. Nothing constrains this
mechanically -- the view URLs are absolute -- so it is a judgement about
what the file describes.

**Two things surfaced by questions rather than by testing.**

*The rebuild dropped embedded metadata.* The old archive carried `obus:file`
(1.2 KB) and `obus:fields` (140 KB) in the parquet footer, so a detached
file described itself and `duckdbfs::open_dataset()` alone could reach it.
`archive_06_consolidate.R` uses `arrow::write_parquet()` and embeds only
`ARROW:schema`. Not a decision -- an omission, found when asked whether the
metadata was reachable without the catalog. Logged in TODO.md.

*The duplication objection did not survive checking.* Against embedding
per-file dictionaries I argued four copies could drift. But the yaml already
duplicates shared fields per table, both artifacts are generated from it in
one run, and a check of all 50 multi-table field names found `type` and
`units` identical in every case; the 23 that differ do so only in
`constraints`, `range`, `label` and `values`, all legitimately per-table. The
argument was wrong and the correction is recorded in AGENTS.md, because it
matters for any future decision that would duplicate field definitions.

**`arrow` vs DuckDB.** Prompted by the question of why the writer is `arrow`
at all. `archive_06_consolidate.R:53` collects 14.4M rows into memory purely
to write them out again; DuckDB's `COPY (SELECT * FROM read_parquet(...)) TO
...` streams it and takes `KV_METADATA` in the same statement, so the
embedding above would come free. `arrow` is a hard `Imports` while `duckdb`
is not declared at all, despite the catalog, the validation wrappers and
every consumer already being DuckDB. Verified that `KV_METADATA` writes and
`decode(value)` reads back byte-identically (29 KB test blob). Deferred to a
fresh session rather than started at the end of a long one; the full
rationale, caveats and open question are in TODO.md.
