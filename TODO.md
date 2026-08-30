# opus — TODO

**Status:** Tier 1 (HH, HL, CA, LT) curated, validated and published. The
archive at `…/datras/raw/` is self-describing: each parquet carries its own
dictionary in its footer, read by `R/archive.R`'s `op_*` accessors. Forward
work is Tier 2 and imbus coordination.

*This file tracks outstanding work only. Dated development history — what was
done, when, and why — lives in `DEVLOG.md`; settled design lives in `AGENTS.md`.*

---

## Immediate

- [ ] **The old archive is still live at the server root, and obus reads it.**
      `…/datras/{T}.parquet` is a different artifact from
      `…/datras/raw/{T}.parquet`: HL is 14,400,747 rows against 14,423,771,
      30 columns against 29, and it carries obus's Tier-3 `aphia`/`sex` names
      plus an `.id` column the current archive has no equivalent for. Switching
      obus over is not just a URL change — it needs a decision on those Tier-3
      names and on `.id`, and that decision is obus's. Until then the two
      archives coexist and obus consumes the older one.

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

- [ ] **Candidate registry entry: NS-IBTS 2022 Q1 HL is exactly 32767 rows
      (2^15 − 1).** Both the live ICES XML response and the archive return that
      identical count, while neighbouring quarters of the same survey run
      44k–52k (2021 Q1: 51,151; 2023 Q1: 45,752). Scanned the whole HL archive:
      it is the only one of 971 survey/year/quarter groups on that value, and
      115 groups exceed it (max 54,712), so there is no global cap — which makes
      a signed-16-bit truncation specific to that submission the likeliest
      reading, though unproven. Worth a targeted check against ICES; if it holds
      up it is a registry entry and an ICES-side report, not something to work
      around.

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

## Future: Tier 3 (obus contracts)

- [ ] Hand-authored specs, no ICES source; deferred until Tier 1 + 2 are stable.
- [ ] Coordinate with obus on contract-specific constraints and enums. The
      `aphia`/`sex`/`age` layer in obus's `.dr_obus_rename` is the candidate
      seed, and the `.id` composite key is already authored here as the
      HL/CA/LT → HH relationships.
