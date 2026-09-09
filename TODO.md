# opus — TODO

**Status:** Tier 1 (HH, HL, CA, LT) curated, validated and published. The
archive at `…/datras/raw/` is self-describing: each parquet carries its own
dictionary in its footer, read by `R/archive.R`'s `op_*` accessors. Forward
work is Tier 2 and imbus coordination.

*This file tracks outstanding work only. Dated development history — what was
done, when, and why — lives in `DEVLOG.md`; settled design lives in `AGENTS.md`.*

---

## Immediate

- [ ] **Two stale files are still served at the server root.** *(Corrected
      twice. 2026-09-02: this item used to end "and obus consumes the older
      one." It does not — `opus::op_archive()` returns `…/datras/raw`.
      **2026-09-09: the correction itself was wrong, and dangerously so.** It
      claimed obus's `dr_con()` whitelist "has no `HL`/`CA`/`LT` entry at
      all" and concluded "delete the four stale files". `obus/R/dr_con.R:32`
      has `DR_TABLES <- c("HH", "HL", "CA", …)`. Root `HL.parquet` and
      `CA.parquet` are **obus's own published record layer**, and deleting
      them destroys 20.4M rows that `dr_con("HL")` and `dr_con("CA")` read.
      Do not run the old recommendation.)*

      Measured live 2026-09-09, root against `raw/`:

      | root file | rows | cols | vs `raw/` | verdict |
      |---|---:|---:|---|---|
      | `HH.parquet` | 150,217 | 70 | raw + `.id` | **obus's, keep** |
      | `HL.parquet` | 14,423,771 | 30 | raw + `.id` | **obus's, keep** |
      | `CA.parquet` | 5,968,027 | 35 | raw + `.id` | **obus's, keep** |
      | `LT.parquet` | 79,451 | 58 | `GearEx` for raw's `GearExceptions`, no `Depth` | stale, delete |
      | `HL_standardised.parquet` | 15,483,270 | 19 | carries `aphia`/`type` | stale, delete |

      So HH, HL and CA at the root are each exactly `raw + .id` — that is
      obus's published contract, and its own `test-published-schema.R`
      asserts it online. The 2026-09-02 note already carved out `HH` on
      exactly those grounds; it simply failed to apply the same reasoning to
      `HL` and `CA`, whose row counts had moved since (HL was 14,400,747
      when that note was written and is 14,423,771 now — it was republished,
      not abandoned).

      Only two files are genuinely orphaned. Neither is produced by any
      current build script and nothing in obus reads either — `DR_TABLES`
      has no `LT` entry, so `dr_con_raw("LT")` reads `raw/LT.parquet`, the
      live one. obus's own TODO carries the same list and the command:

      ```
      ssh einarhj@heima.hafro.is 'rm ~/public_html/datras/{HL_standardised,LT}.parquet'
      ```

      `CPUEL.parquet` at the root is **not** in this list — it is ICES's own
      product, mirrored deliberately, and both obus's article and
      datrasdoodle2's Appendix A read it.

      The live problem is what a **reader** gets by guessing the obvious URL
      for those two: a superseded file with older names, silently. That is
      the decision `datrasdoodle2`'s Ch 3 ("Getting data") is blocked on —
      the chapter is gated on this, not on writing. Delete the two, or move
      them under a dated path, or document them as deliberate; any of the
      three unblocks the chapter.

- [ ] **One test file, fifty exports.** `tests/testthat/test_validation.R`
      is the whole suite, against obus's 10 files and 209 tests. opus is
      the spec authority for obus's builds *and* for every "what this field
      is supposed to mean" sentence in `datrasdoodle2`, so a regression in
      the dictionary, the enum tables or the registry propagates silently
      into both and nothing fails. Assessed 2026-09-02 as the largest
      structural fragility in the three-repo stack — and the least visible,
      because opus is the part that currently feels most finished.

      Cheapest first slice, if a full suite is too much at once: assert the
      registry and dictionary *load* and satisfy their own schema, that
      every `known_violations` id is unique, and that the accessors return
      the documented shapes. `data-raw/validate_issue_registry_sync.R`
      already does some of this outside the test suite — moving it inside
      `R CMD check` costs little and catches the loudest failures.

      **Progress 2026-09-09.** The suite now asserts values rather than
      shapes, and 41 assertions execute where 8 did. What it still does not
      have is a fixture, and that is parked on a real question rather than on
      effort — see the next item.

- [ ] **Six tests still skip for want of a fixture, and the fix needs a
      decision first: is this suite proving the wrappers work, or that the
      archive conforms?** Parked 2026-09-09, deliberately.

      **What it cost so far, measured not supposed.** `test_validation.R`
      opens with `hh_path <- system.file("HH.parquet", package = "opus")`,
      which returns `""`, so six tests carry
      `skip_if_not(file.exists(hh_path))` and skip. That is not an oversight:
      `a382b2c` (2026-07-31) added `inst/{HH,HL,CA,LT}.parquet` via Git LFS
      and `57b34c0` (2026-08-18) deleted them for sound reasons — they had
      drifted from real renames (CA `IndividualAge`/`Age`, LT
      `GearEx`/`GearExceptions`) and the resampling script had never been
      run. What that commit did not do was update the six dependent tests.

      Three defects were sitting behind those skips, all found 2026-09-09:
      `op_validate_full()` could never run at all (`cli_bin` passed
      positionally into `op_validate_spec()`'s `json`);
      `op_validation_problems()` returned 0 rows against a 20-problem report;
      and `op_inspect_parquet()`'s test asserts a `result$output` field the
      function does not return. The first two are fixed. **The third is
      not, and it is independent of everything below** — that test is wrong
      today and will fail the moment any fixture appears.

      **The three candidate fixtures, and what each actually buys.**

      | option | runs where | ships | can go stale |
      |---|---|---|---|
      | `inst/HH.parquet` (331 rows, 40.8 KB) | anywhere | 41 KB | yes — this is what bit `57b34c0` |
      | point tests at `.datras/` | this machine only | nothing | no |
      | synthetic, generated from `op_field_spec("HH")` | anywhere | nothing | no |

      `.datras/` is both gitignored and Rbuildignored, so option 2 restores
      today's skip on any fresh clone. Note there is no CI in this repo, so
      the machine option 1 exists for does not currently exist.

      Option 3 was measured and works: 69 columns, 1 row, 11.5 KB in a
      tempfile, and it produces results identical to the real 331-row
      subset — `op_validate_meta()` TRUE, `op_inspect_parquet()` 69 columns,
      `op_validate_full()` TRUE/TRUE/FALSE. It must be generated *from* the
      dictionary, never from a hand-written column list, or the test becomes
      a second source of truth for DATRAS field names. (Generating data to
      *satisfy* a declared `type` is legitimate; casting real data *from*
      one is the thing Working Principle 1 forbids.)

      **Why this is parked rather than done: half of it is a tautology.**

      - Synthetic fixture + "does this function run and return its
        documented shape" is **not** circular. It is plumbing, and it would
        have caught all three defects above, none of which involved data
        content.
      - Synthetic fixture + `expect_true(meta_valid)` **is** circular. A
        file built from the dictionary, checked against the dictionary,
        always passes. That assertion looks like conformance evidence and is
        not — which matters, because the current suite carries exactly that
        assertion and it was previously described here as the guard against
        fixture drift. On synthetic data it guards nothing.

      So the two purposes want different fixtures, and conflating them is
      what produced the original mess: `57b34c0` removed the real data and
      left behind assertions only real data could satisfy. The likely answer
      is both — a synthetic fixture for the plumbing, running everywhere,
      and a separate conformance test against `.datras/` that skips honestly
      elsewhere — but that is a decision about what this suite is for, not a
      task, so it waits for a human.

      **The conformance half is answered by the next item, and it is not a
      fixture at all.** A fixture is frozen by construction, so no fixture
      can ever test the dictionary; only data the dictionary has not seen
      can, and that arrives on every archive rebuild. So this item is only
      ever about plumbing, which shrinks it considerably.

- [ ] **The archive build validates the dictionary but never validates the
      data against it — so nothing checks the spec on the one input that can
      falsify it: new data.** Found 2026-09-09, from the question "on the
      tautology, is the real test not e.g. new data?", which is the right
      question and reframes the fixture item above.

      **What runs today.** Spec-level validation is wired in:
      `spec_02_curate_dict.R:1283` and `spec_03_translate_new_names.R:303`
      call `op_validate_spec()`, and `archive_06_metadata.R` notes that
      `export-spec` runs the same pass with the same `S##` diagnostics, so a
      dictionary that would not validate never reaches a file. That part is
      sound.

      **What does not run.** `op_validate_meta()` and `op_validate_data()` —
      the two that compare *data* against the dictionary — are invoked
      nowhere in the pipeline. `archive_06_consolidate.R:143` only prints a
      suggestion:

      ```r
      message("Verify with: opus::op_validate_meta('", OUT_DIR, "/HH.parquet', 'HH')")
      ```

      So every build asks the operator to check by hand and records nothing
      about whether they did. Measured 2026-09-09 on the staged HH:
      `meta_valid` TRUE, `data_valid` FALSE on 9 errors (8 x D01, a null in a
      `required` field; 1 x D04, a value outside an allowed set). Every one
      is a known ICES-side defect. The point is not that they exist — it is
      that a tenth would appear in silence.

      **Two things new data falsifies, needing different treatment.**

      1. *Hard constraints* — the D01/D04 codes. Mechanical, already
         implemented, simply never invoked on new data.
      2. *The measured prose* — the dictionary's `details` fields carry hard
         counts about the archive they describe. 614 lines contain a 3+ digit
         number, e.g. "1,894,960 rows", and `ThermoCline`'s breakdown is
         precise down to its 3 lower-case `y`s. Each is a claim a rebuild can
         silently falsify. This is the existing "re-verify the field prose"
         item, and it is the harder half: automating it means *generating*
         those statistics rather than writing them.

      **The shape of the fix is a ratchet, not a check.** An
      `archive_07_validate.R` after consolidate, over all four tables:

      ```r
      for (tbl in OP_TABLES) {
        f <- file.path(OUT_DIR, paste0(tbl, ".parquet"))
        m <- op_validate_meta(f, tbl)
        d <- op_validate_data(f, tbl)
        # per-code counts, not just the verdict -- the verdict is FALSE either way
        codes <- table(op_validation_problems(d)$code)
        ...
      }
      # write logs/validation_<built_utc>.json, then DIFF the previous one
      ```

      The diff is the whole value: "9 errors, same codes as last build" is a
      pass; "HH gained a D01 on `BottomDepth`" is a finding. Note
      `op_validation_problems()` only became usable for this on 2026-09-09 —
      before that it returned 0 rows against a report holding 20.

      **It should reach the provenance block too.** The footer records
      `dict_sha256`, `built_utc`, `opus_version`, `opus_git_sha`, `writer`
      and `pipeline`, so a published file says which dictionary it matched
      but not whether it *conformed*. A `validate-data` verdict there makes
      each build self-reporting, and is the missing half of the metadata work
      recorded at the end of this file.

      **Two honest limits.** The diff fires only when the archive is
      rebuilt, so it is exactly as frequent as downloads are — the newest log
      is `logs/download_2026-08-26_195940.log`. And it reports that a number
      moved, never whether the data or the spec is the thing that is wrong;
      that judgement is what the known-issues registry exists to record.

- [ ] **`archive_06_consolidate.R` still materialises the whole table in
      memory** (`arrow::open_dataset(part_dir) |> collect()`, 14.4M rows for
      HL) purely to write it out again. DuckDB's `COPY (SELECT * FROM
      read_parquet(...)) TO ... (FORMAT parquet, KV_METADATA {...})` would
      stream it and embed the metadata in the same statement. Not taken when the
      metadata work landed because DuckDB drops `DateofCalculation`'s DATE
      logical type, which nanoparquet preserves — so this needs either a fix for
      that or a deliberate trade. Worth revisiting on its own merits.

## Type contract — settled; residual is obus-side

- [ ] **Tell obus that `type` is not a casting instruction.** This was recorded
      here as an open decision for opus ("which type system is authoritative?").
      It is not one: data-dict already answers it, and opus already behaves
      correctly. Checked 2026-08-29, three independent ways:

      1. **The format says so.** `site/spec.md`: *"Types capture data types at a
         level that makes sense for analysis, which is typically coarser than
         the logical types of the underlying data"*, and `type` "should match
         (**approximately**) the underlying data type". The implementation
         enforces exactly that — `parquet_element_type()` collapses INT32,
         INT64, FLOAT and DOUBLE all to `number`, the measure qualifier
         (`(quantity)`/`(ordinal)`/`(id)`) is never read from a file because it
         is a semantic claim, and `validate_meta.rs` asserts
         `types_compatible("number(quantity)", "number")`. Which is why
         `op_validate_meta()` is clean on all four tables: the archive has been
         conformant throughout.
      2. **ICES sends integers.** All 31 fields where the YAML says
         `number(quantity)` and the archive stores integer are declared `int` by
         the WSDL, and a full scan of `.datras/xml/` — every one of the 29
         distinct tags, all 3,892 files, 19.8 GB — found **0 decimal values in
         100,280,647**. The archive's INT32 storage loses nothing.
      3. **opus never casts from the curated type.** `op_cast_wsdl_types()`
         casts from WSDL physical types; `op_cast_to_spec()` filters to
         `type %in% c("date","datetime")` and touches nothing else — the one
         semantic type the wire cannot express. There is no second type system
         in this package's conversion path.

      The one place a curated type is used as a casting rule is obus's
      `dr_settypes()` (`key_dbl <- ...type == "number(quantity)"` →
      `as.numeric()`), which turns a deliberately-coarse analysis label into a
      precise storage instruction. That is the whole of the divergence obus
      reported, and the fix belongs there: cast from the `r_type` /
      `parquet_type` now carried in each parquet footer, or from the WSDL, not
      from `type`.

      **opus's action is coordination only** — pass this on rather than change
      anything here. Recorded in `AGENTS.md` under Key Facts.

## ICES-side reporting and the known-issues registry

- [ ] **File the `-9` overloading with ICES** — a new `systemic`
      `known_violations` entry plus an `articles/issues.qmd` section for the
      `IMBUS_FISHMAP#29` batch. Worked example: `Tickler` (a documented real
      code, 78% of HH rows) against `Turbidity` (never recorded, 99.6%),
      indistinguishable by value or by frequency and separable only by
      consulting a vocabulary.

- [ ] **File the inconsistent encoding of absent values** — registry entry
      `absent_value_encoding_inconsistency` (added 2026-08-29), for the same
      `IMBUS_FISHMAP#29` batch as the `-9` overloading above. HH/CA/HL always
      use the documented `-9`; LT also returns an empty XML element for the
      same meaning, and `GearEx` uses both inside LT (19,296 empty vs 26,856
      `-9`). Nothing in ICES's documentation says which to expect where.

- [ ] **The CSV download route is paused — revisit only if ICES catches up.**
      `DATRASDownloadAPI.aspx` is dramatically faster (all of NS-IBTS in 86s
      against hours by XML, ~128x smaller on the wire for CA) and
      `data-raw/archive_02b_download_csv.R` is written and verified — on DWS the
      CSV-derived and XML-derived partitions matched exactly, 72 x 69, same
      names, order, classes and values. It is paused anyway, and not because it
      fails: **the endpoint is in flux and on the evidence is a step backwards
      from the ASMX service.** Its HH export is malformed (#63); it names one
      concept four ways where the XML is consistent (#64); it serves no LT or FL
      and misses CODS-Q4; it ships no metadata at all; its type source is wrong
      about `Year`/`SpecCode` and silent about eight of its own columns; and it
      reports failure as HTTP 200. Building a second archive on that buys
      download speed at the cost of correctness that already holds. The archive
      stays XML-derived. Revisit when #63 and #64 close and LT is served.

- [ ] **Track the two filed icesDatras issues** —
      [#63](https://github.com/ices-tools-prod/icesDatras/issues/63) (HH CSV has
      a 72-field header over 70-field rows, so `DateofCalculation` is lost and
      its values surface under `EDOM`) and
      [#64](https://github.com/ices-tools-prod/icesDatras/issues/64) (`AphiaID`
      and the WoRMS name are called four different things across HL and CA, and
      `getDatrasFieldList()` covers none of them). Both were found while
      evaluating `DATRASDownloadAPI.aspx` as a faster ingest route; source text
      and evidence in `data-raw/issue-drafts/`. #63 has a verified local
      workaround (`icesDatras-hh-workaround.R`) that `archive_02b` already uses,
      so opus is unblocked either way — this is watch-and-close, not a
      dependency.

- [ ] **Two smaller ICES-side items**, both handled locally for now by
      `op_wsdl_type_overrides()`: `Valid_Aphia` declared `string` while holding
      numeric AphiaIDs, and `DateofCalculation` declared `string` by LT's
      operation but `int` by HH/HL/CA. The latter is distinct from the existing
      `dateofcalculation_cross_product_inconsistency` entry, which is about
      *values* disagreeing between products, not types.

- [x] **WITHDRAWN — NS-IBTS 2022 Q1 HL's 32767 rows is a coincidence, not a
      truncation. Do not report this to ICES.** obus investigated and resolved
      it 2026-08-31 (see `obus/TODO.md`); independently re-verified here
      2026-09-02 while writing `datrasdoodle2`'s HH chapter.

      **The row count is exactly what the haul count predicts.** NS-IBTS Q1
      2022 ran **249 hauls**, against 325–387 in every other year 2014–2026 —
      a real drop in survey effort, concentrated in two countries (DE 67 → 10,
      GB-SCT 61 → 15 between 2021 and 2022). Rows per haul is **131.6**, sitting
      mid-range against neighbouring years (117.2–145.2). A truncated file would
      leave HH untouched and rows-per-haul anomalously low; neither holds.

      **The original reasoning contains a base-rate error worth remembering.**
      "It is the only one of 971 survey/year/quarter groups sitting on exactly
      that value" is not evidence — nearly every specific row count is hit at
      most once, so uniqueness at a value carries no information. The question
      that settles it is whether the count is anomalous *given the haul count*,
      and it is not.

      Original text kept for the record: both the live ICES XML response and the
      archive return that identical count, while neighbouring quarters run
      44k–52k (2021 Q1: 51,151; 2023 Q1: 45,752); 115 groups exceed it (max
      54,712), so there is no global cap.

      Filing this would have sent ICES a defect report for ordinary reduced
      survey effort.

- [ ] **Amend the filed `dateofcalculation_cross_product_inconsistency`
      entry: a second product pair, HH vs CPUEL — and it is the stronger
      evidence.** The entry currently rests on HH vs LT (30,364 hauls on both
      sides, 63.21% disagreeing). The same behaviour reproduces against a
      third product, measured 2026-09-02 on the published `HH` and the CPUEL
      snapshot at `…/datras/CPUEL.parquet` (11,774,468 rows, 8 surveys):

      **49,275 hauls carry a `DateofCalculation` on both sides; 22,538
      (45.74%) disagree.** CPUEL is the later side in 17,678 and HH in 4,860,
      so it runs both directions here too. Median gap when disagreeing 1,036
      days; max 2,539 days (~7 years) — the same order as the LT-side max.
      CPUEL is internally consistent: all 60,542 distinct `.id` values carry
      exactly one date. (The only multi-date group is the null-`.id` bucket —
      1,059,736 rows, 9.0% of CPUEL, carrying no haul key at all. Separate
      issue, noted here only so the 60,542 is not misread.)

      Per survey, share of shared hauls disagreeing: ROCKALL 364/364
      (100%), SWC-IBTS 2,327/2,327 (100%), IE-IGFS 93.4%, SCOROC 87.1%,
      EVHOE 73.3%, NS-IBTS 44.3%, BITS 25.2%, SCOWCGFS 14.2%.

      **Why this pair is worth adding rather than merely corroborating.** The
      LT evidence establishes that the dates differ. The CPUEL pair
      establishes that the difference *carries no information about the
      data*: ROCKALL and SWC-IBTS both disagree on 100% of hauls, with CPUEL
      roughly three years later in each case, and their catch data agree
      **99.6%** and **0.4%** respectively. Same date signature, opposite
      outcome. So `DateofCalculation` cannot be used to rank two products by
      freshness — which is the use a reader will most naturally reach for.

      Not a download artifact on our side: ICES's exchange copy of SWC-IBTS
      reports 2016-06-08, and a full re-download on 2026-08-26
      (`logs/download_2026-08-26_195940.log`, 188 SWC-IBTS requests)
      returned the same date, on an archive whose newest calculation
      anywhere is 2026-08-24.

      **Caveat, and it matters for filing:** CPUEL is Tier 2 and opus has
      not curated it — its field names are the older style and were taken
      as-is, and the join uses CPUEL's own `.id` column. Not verified
      against ICES's production code. Safe as `extent` evidence for a
      behaviour already filed; *not* safe as a standalone claim about
      CPUEL's correctness.

      Drafted amendment (needs a human to approve touching an entry already
      filed as Issue 13):

      - `table:` → `HH, LT, CPUEL`
      - `extent:` append — *"The same behaviour reproduces against CPUEL
        (Tier 2, uncurated): of 49,275 hauls carrying a date in both HH and
        CPUEL, 22,538 (45.74%) disagree; CPUEL later in 17,678, HH later in
        4,860; median gap when disagreeing 1,036 days, max 2,539. Two
        surveys disagree on every shared haul (ROCKALL 364/364, SWC-IBTS
        2,327/2,327). Verified 2026-09-02."*
      - `implication:` append — *"The CPUEL pair additionally shows the gap
        is not a freshness ordering: ROCKALL and SWC-IBTS share the same
        100%-disagreement signature, with CPUEL ~3 years later in both
        cases, yet their catch data agree 99.6% and 0.4% respectively."*

      Found via `datrasdoodle2`'s CPUEL appendix, which had read the same
      dates as a staleness ordering and concluded a fresh download would
      close the SWC-IBTS gap. It does not; the appendix has been corrected.

- [ ] **Candidate registry entry: `HaulDuration` violates its own declared
      range in published data.** `inst/DATRAS-data-dict.yaml` declares HH
      `HaulDuration` as `constraints: [required]` with `range_min: 1`,
      `range_max: 120` (minutes). Measured on the published archive
      2026-09-02, over 150,217 HH rows: **219 rows below 1** (including two
      negatives, −514 and −238 minutes, both Can-Mar 2017), **178 above 120**
      (max 1470), and **51 NULL** despite `required`.

      The sub-1 tail is mostly self-declaring — the two negatives and 18 of
      the zeros are already `HaulValidity == "I"`, and the remaining 199
      zeros are all `HaulValidity == "N"` ("No oxygen", BITS), i.e. hauls
      that were never fished. Those are arguably correct as submitted.

      **The upper tail is not.** 167 of the 178 over-120 hauls are flagged
      `HaulValidity == "V"`: NL-BSAS 156, BITS 4, DWS 3, NS-IDPS 3, EVHOE 1.
      So one survey routinely submits, and marks valid, durations the format
      says are out of range. Either the 1–120 bound is wrong (NL-BSAS
      genuinely tows longer than the format anticipates) or the values are,
      and nothing in the data settles which — it needs someone who knows the
      survey. Worth a targeted check before it becomes either a registry
      entry or a dictionary correction.

      Distinct from the existing "re-verify the field prose" item below:
      that is about stale `details` statistics, this is a declared
      *constraint* contradicted by the data it describes. Found while
      writing `datrasdoodle2`'s HH chapter.

- [ ] **Candidate registry entry: `StationName` is a `required` `primary_key`
      component that is NULL on 4.59% of HH.** Declared
      `constraints: [primary_key, unique, required]`; measured 2026-09-02,
      **6,899 of 150,217 HH rows have no `StationName`** — BTS 4,048,
      NS-IBTS 1,543, BITS 979, SP-NORTH 325, NSSS 4. A required primary-key
      component with nulls is an internal contradiction in the dictionary's
      own terms, so one of the two sides is wrong.

      Note the field is documented as *"Station number. National coding
      system, not defined by ICES"* — which is a reason to doubt the
      `required`/`primary_key` claim rather than the data. Nothing downstream
      is blocked (obus's `dr_add_id()` skips NA fields when building `.id`,
      and `.id` is still exactly unique over all 150,217 hauls, verified), so
      this is a spec-accuracy question, not an outage. Found the same way.

- [ ] **Candidate registry entry: HL's taxonomic scope expands over time, so
      an absent row is not evidence of absence for non-fish taxa.** Found
      while writing `datrasdoodle2`'s HL chapter, measured on NS-IBTS Q1
      (321,750 `HL_summary` rows, all of which resolve against the species
      lookup — zero unmatched aphia).

      Distinct taxa reported per decade, split by group:

      | decade | fish | arthropods | molluscs | echinoderms | other | total |
      |---|---:|---:|---:|---:|---:|---:|
      | 1960s | 97 | 0 | 0 | 0 | 0 | 97 |
      | 1970s | 150 | 0 | 0 | 0 | 1 | 151 |
      | 1980s | 145 | 1 | 2 | 0 | 1 | 149 |
      | 1990s | 164 | 6 | 9 | 0 | 1 | 180 |
      | 2000s | 168 | 15 | 32 | 0 | 0 | 215 |
      | 2010s | 181 | 65 | 56 | **37** | 27 | 366 |
      | 2020s | 163 | 60 | 70 | 14 | 47 | 354 |

      Fish grow 1.4x from an already-broad base (93 taxa/year in 1984 to 126
      in 2026, Spearman +0.90 — real, but gradual). Everything else starts at
      nothing: molluscs 0 -> 70, arthropods 0 -> 65, and **no echinoderm is
      recorded anywhere in the series before 2011**, after which 37 taxa
      appear at once. NS-IBTS is a groundfish survey; the invertebrates were
      in the net all along and only became reportable later.

      **Why this belongs in the registry rather than in a consumer's head.**
      The standard operation on this table is to complete haul x species and
      set the missing combinations to zero — which is *required* for an
      unbiased CPUE (dropping the absences inflates the mean by exactly
      `1 / occupancy`). But applied across a period when a taxon was not
      being recorded, that same step manufactures confident zeros, and it
      manufactures them at the start of the series, which is the shape of a
      textbook colonisation curve. Worked example: *Alloteuthis subulata*
      goes from 0 of 2,877 hauls in the 1980s to 41.6% in the 2010s, which
      is uninterpretable as ecology because cephalopod reporting went from 2
      taxa to 40 over the same window.

      Note the asymmetry, which is what makes the entry actionable rather
      than merely discouraging: rising reporting effort can fabricate an
      apparent increase but **cannot** fabricate a decline. So declines are
      safe to read and increases are not, and the guidance can say exactly
      that.

      Suggested shape: `systemic` scope, field/table-level note on HL (and CA,
      which is presumably the same story — **not checked**), with the
      per-decade taxa counts as evidence and an explicit "safe for fish;
      suspect for molluscs and arthropods before ~2000; meaningless for
      echinoderms before 2011" for NS-IBTS. **Per-survey generality is not
      established** — only NS-IBTS Q1 was measured, and the onset year will
      differ by survey.

- [ ] **Candidate registry entry: CA `Age` carries out-of-range values and a
      sentinel sitting on its own range ceiling.** `Age` is declared
      `number(quantity)` with `range_min: 0`, `range_max: 99`, and the sentinel
      policy for it is `strip` ("no documented code for this sentinel").
      Measured on the published archive 2026-09-02 over 5,968,027 CA rows
      (3,918,845 with an age):

      - **2,324 rows are below the declared floor** — `-1` on 2,322, plus a
        single `-5` and a single `-95`. Only `-9` is stripped, so these
        survive. They will drag down any unguarded `mean(Age)`.
      - **54 rows are aged exactly 99**, which is the declared *maximum* and
        therefore legal by the spec and stripped by nothing. The real tail
        thins smoothly and stops at 57; a gap from 57 to 99 followed by a
        spike precisely at the range ceiling is the signature of a sentinel
        that `range_max: 99` has accidentally legitimised.

      Worth deciding whether `range_max` should be lowered to something
      biologically defensible (the observed real maximum is 57) so that 99
      becomes a detectable violation, or whether 99 should join the sentinel
      list for this field. Either way the sub-zero values are a
      straightforward unstripped-sentinel violation. Found while writing
      `datrasdoodle2`'s CA chapter.

      Note in passing that `AgePlusGroup`'s `keep` policy is **correct and
      should not be touched** — `-9` there is the documented real answer "no
      plus group" (5,963,393 rows, against 4,634 `"+"`), and the registry's
      own reason field says so. This was checked before being written up as a
      leak; it is not one.

- [ ] **Candidate registry entry: implausible waterbird records in DYFS.**
      Four `Mergellus albellus` (smew, a freshwater diving duck) and one
      `Calidris bairdii` (Baird's sandpiper, a Nearctic vagrant wader) in
      `HL_summary`, all DYFS, 2021-2023. **One 2021 haul records
      `n_totalnumber = 320` smew.** Three hundred and twenty diving ducks in
      one beam-trawl tow is not a bycatch event. None of the five records
      carries a weight, so nothing internal settles whether the number, the
      species code, or the record itself is wrong.

      DYFS is shallow coastal beam trawl, so a waterbird is at least
      physically possible there — the seal and porpoise records elsewhere in
      the archive (one each) look like genuine, if grim, bycatch. It is the
      *count* that fails here, which is the point worth recording: a taxon
      plausibility rule keyed only on "is this marine?" passes all five of
      these, and would also wrongly flag the 1,900-odd legitimate algae
      records (`Ulva` 945, `Rhodophyta` 775). A usable check has to combine
      taxon, gear, place and **number**.

      Historical note: `datrasdoodle` recorded mosquitoes (`Culex`) in NS-IBTS
      in 2018. There is no `Insecta` anywhere in the archive today, so that
      one has been resolved upstream at some point — evidence this class of
      record does get cleaned, and worth reporting rather than working around.

- [ ] **No accessor for the registry's `known_violations` section.**
      `R/sentinels.R` reads the `sentinels:` half (`op_sentinels()`,
      `op_sentinel_policy()`, `op_sentinel_audit()`), and `op_known_issues()`
      returns the per-table slice embedded in each parquet footer — but nothing
      reads `known_violations` from the shipped YAML directly. That is the gap
      for any consumer working outside the archive: a `flag_known_issues()`-style
      feature, or validating a submission before it reaches ICES.

## Dictionary curation

- [ ] **Re-verify the field prose against the archive whenever it is rebuilt.**
      All ~100 statistics in the field `details` were recomputed on 2026-08-29
      after being found stale against an older, smaller archive; they now
      distinguish the submitted view (`-9` present) from the published one
      (stripped to null). They will drift again on the next rebuild. The audit
      that catches it: check every `A/B rows (P%)` figure for internal
      consistency, and every denominator against the real row counts.
      `articles/archive.qmd` carries captured outputs from the same archive
      (row counts, coverage, the CA worked example) and drifts with it.

- [ ] **`LengthClass`'s `label` says `(cm)`, and the field is mm about half the
      time.** Both copies -- HL `inst/DATRAS-data-dict.yaml:1713` and CA
      `:2289` -- carry `label: Length Class (cm)`, which contradicts the
      `description` and `details` sitting directly above it: the unit varies by
      the sibling `LengthCode` (`.`/`0` are mm, `1`/`2`/`5` are cm). Measured on
      the published archive 2026-09-02: **HL 39.65% mm / 57.73% cm** (2.62%
      sentinel or missing), **CA 48.23% mm / 51.77% cm**. So the label is wrong
      for roughly half the rows in each table, and it is not inert -- `label`
      lands in the archive catalog (`R/archive.R:145`) and is the fallback
      column comment when a `description` is absent (`:397`). Only these two
      labels and `Total Litter Weight (kg)` assert a unit at all; the fix is
      probably to drop the parenthetical rather than to add a conditional the
      label field cannot express. Found while obus was building its
      length-weight cascade, which has to know the unit and the bin geometry to
      predict weight at all.

      The `description` itself is correct and needs no change: *"Lower length
      boundary of the Length class. In cm or mm depending on the LngtCode. E.g.
      10-11 cm=10"*, verbatim from ICES. Worth recording that this is the one
      place the lower-boundary semantics is written down for downstream
      consumers -- obus had been predicting weight from the bin's lower bound,
      which under-estimates by 5.1% at 30 cm with 1 cm bins, until this was
      checked against the dictionary.

- [ ] **`contract.md` §4's AreaType guard cannot be authored as written.** It
      says to filter CA to `AreaType == "H"` before joining to HH, but AreaType
      is ICES `TS_AreaType` (`'0'` statistical rectangles, `'2'` NS roundfish
      areas, `'13'` ICES divisions …) and has **no `'H'` code** — the filter
      would match zero rows. The underlying concern is real (CA rows attributed
      to an area rather than a haul are a coarser grain than HH), and CA's
      `linkable_to_hh` definition now names that set correctly. Decide whether
      §4 gets rewritten against the real code set, or retired.

- [ ] **Eleven citations of the dead path `data-raw/ICES_ISSUE_REPORT.md`
      remain in shipped files.** That document became `articles/issues.qmd` on
      2026-08-18; the "Issue N" numbering carried over, so only the path is
      wrong. Nine are in `inst/DATRAS-known-issues.yaml`, one in each of
      `inst/DATRAS-data-dict.yaml` and `inst/DATRAS-data-dict-legacy.yaml`.
      AGENTS.md's was fixed on 2026-08-29; these were deliberately left, because
      the known-issues file is embedded in the published parquet footers and
      propagating the fix means rebuilding and re-uploading the archive. Worth
      folding into the next rebuild rather than doing on its own.

## imbus / ICES liaison (WP2 handoff)

- [ ] Post opus's confirmed issues (17, in `articles/issues.qmd`) to ICES's own
      tracker, `ices-tools-dev/IMBUS_FISHMAP#29`. The venue question is settled
      (see `DEVLOG.md`), but posting needs explicit go-ahead each time — it is a
      public ICES-side ticket, not opus's own repo — and the format (one comment
      per issue vs. a consolidated summary) is still an open choice.
- [ ] Clarify opus's role vs. imbus's data governance work.
- [ ] Establish a timeline for the ICES feedback loop (e.g. HaulValidity vocab
      completion).

## QC workflow

- [ ] Domain-expert review of borderline constraints (range calls, enum
      membership).
- [ ] Spot-check Quarto renders for accuracy.
- [ ] Validate the enum audit results (`data-raw/enum_field_inventory.csv`).

## Forward: Tier 2 (FL, CPUEL, CPUEA, IDX)

- [ ] Assess WSDL coverage (complete vs. gaps).
- [ ] Decide: seed from WSDL, or hand-author directly — depends on confidence in
      the source.
- [ ] Follow the Tier 1 workflow if seeding (bootstrap → curate → audit).
- [ ] Test parquet availability for validation data.

## Metadata for downstream products (2026-09-04)

obus publishes eight derived tables to `…/datras/` and **none of them carry
any parquet key-value metadata** (measured 2026-09-04: all four `raw/*.parquet`
carry the five `datras:*` blocks, all eight published files carry zero). The
agreed split is that the *format and writer* are opus's, the *content for
obus's own derived columns* is obus's, and the source `dict_sha256` must travel
with every derived table. Full reasoning lives in `../obus/TODO.md`
("Metadata on the derived tables"); the outstanding opus work is:

- [ ] **Export a writer**, or at minimum the block schema, so a downstream
      package can emit the same five-block footer. It must be expressible as
      `COPY … (FORMAT PARQUET, KV_METADATA {…})` rather than assuming an
      in-memory data frame and `nanoparquet`, because obus streams from DuckDB
      and never materialises in R. *(Feasibility confirmed 2026-09-04: obus's
      `duckdbfs::write_dataset()` forwards a multi-element `options` vector
      straight into the `COPY` parens, verified on a lazy input with JSON
      payloads and multiple keys. The one trap is that these are single-quoted
      SQL literals, so any prose payload — `known_issues` especially — must go
      through `DBI::dbQuoteString()`; a bare apostrophe is a parser error. If
      opus exports a helper that assembles the clause, it should own that
      escaping.)*
- [ ] **Decide how the accessors reach a non-Tier-1 file.** `.op_path()` does
      `match.arg(table, OP_TABLES)` with `OP_TABLES <- c("HH","HL","CA","LT")`
      (`R/archive.R:14`, `:47`), so `op_dict("HL_length", path)` errors today
      even if the file carried a dictionary — and `op_archive()` additionally
      insists the directory be named `raw`. Either relax both, or add
      path-based accessors alongside the table-name wrappers. Note
      `op_describe_parquet()` and `op_inspect_parquet()` already take a
      `parquet_path`, so the precedent exists.
- [ ] **Decide which blocks are meaningful for a derived table.** `dict` and
      `provenance` clearly are. `sentinels` arguably is not — obus scrubs
      nothing, so the block would restate opus's policy rather than record an
      action. `coverage` and `known_issues` need a call.
- [ ] **Provenance contract:** a derived table's receipt must name the source
      archive's `dict_sha256`, `opus_version` and `opus_git_sha`, so a
      published product can be tied to the archive build it came from. This is
      the item obus most needs — it has already been bitten by stale
      published files that looked current.
- [ ] Consider a `datras:grain` block, or a grain field in `dict`. obus
      documents both catch tables' grain in prose that has twice been wrong;
      machine-readable grain is testable.

## Future: Tier 3 (obus contracts)

- [ ] Hand-authored specs, no ICES source; deferred until Tier 1 + 2 are stable.
- [ ] Coordinate with obus on contract-specific constraints and enums. The
      `.id` composite key is already authored here as the HL/CA/LT → HH
      relationships. *(Corrected 2026-09-04: this item used to name the
      `aphia`/`sex`/`age` layer in obus's `.dr_obus_rename` as the candidate
      seed. That layer no longer exists — obus dropped its own field names on
      2026-09-01 and the derived tables now carry opus's names verbatim;
      `.dr_obus_rename` greps to nothing in obus. The candidate seed is now
      obus's genuinely new columns: `n_haul`, `n_hour`, `n_measured`,
      `length_mm`, `length_cm`, `length_cm_mid`, `accuracy`, `w_haul`.)*
