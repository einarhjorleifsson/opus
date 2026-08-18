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
