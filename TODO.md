# opus — TODO

**Status:** v0.2.0 complete. Tier 1 (HH, HL, CA, LT) fully curated and documented. Ready for forward work: Tier 2 + imbus coordination.

*Detailed dated development history lives in `DEVLOG.md`, not here. This file tracks only current backlog state.*

**Latest:** 2026-08-28 — obus's consistency check surfaced a
WSDL-vs-curated type divergence and two other opus-side items; see
below and `DEVLOG.md`.

---

## v0.2.0 — Complete

✓ **Bootstrap workflow** — Three-phase bootstrap (WSDL seed → parquet enrich → curate) with supporting R functions
✓ **Tier 1 (HH, HL, CA, LT)** — Curated YAML specs + descriptive/strict YAML variants + known-issues registry
✓ **R package** — 22 exported functions (validation, vocabulary, field name utilities)
✓ **Documentation** — standalone Quarto site (`_quarto.yml`, `index.qmd`, `articles/`) replacing pkgdown/vignettes entirely, rendered to `docs/` for GitHub Pages; ICES issue report is now `articles/issues.qmd` (see DEVLOG.md)
~~Test data — Parquet samples for each Tier 1 table~~ — dropped 2026-08-17, see DEVLOG.md
✓ **Git history** — Clean three-phase commits with milestone tags
✓ **Package build** — devtools::check() passing; .rbuildignore optimized
✓ **Zero R-package dependency on `icesDatras`/`icesVocab`** (2026-08-06) — direct, cross-verified web-service calls instead (`op_datras_field_list()` in `R/field_names.R`, direct HTTP in `R/vocab.R`)

---

## Immediate: Tier 1 Validation + Known-Issues Escalation

- [x] ~~**Known-issues registry refinement:**~~ — done 2026-08-18, see DEVLOG.md
  - [x] ~~Restructure for two-level escalation: field-level gaps vs. systemic patterns~~ — done 2026-08-17: added a `scope` field (`field-level`/`systemic`/`opus-internal`) to all 8 `known_violations` entries, designed around today's own findings (`icesVocab_gaps`/`datras_field_list_type_divergence` are the systemic examples) rather than guessed at in the abstract.
  - [x] ~~Inventory findings from 2026-07-29/08-02 sessions (5 original D-level fields)~~ — done 2026-08-18: 3 of 5 (AgeSource, AgePreparationMethod, LTSRC) turned out to be false leads on re-verification, not real issues; `icesVocab_gaps`'s own GearExceptions example was also stale (same name-key-resolution artifact). Corrected registry: replaced with `icesvocab_key_resolution_hazard` (systemic) + `param_vocab_incomplete` (the one real gap that held up). See DEVLOG.md.
  - [x] ~~Prioritize escalation candidates for imbus feedback~~ — done 2026-08-18: see DEVLOG.md for the full ready-to-file / already-filed / needs-diagnosis / excluded breakdown.

- [ ] **imbus/ICES liaison (WP2 handoff):**
  - [ ] Post opus's confirmed issues (16, in `articles/issues.qmd`) to ICES's own tracker, `ices-tools-dev/IMBUS_FISHMAP#29` — the venue question is resolved (see DEVLOG.md), but posting still needs the user's explicit go-ahead each time (it's a public ICES-side ticket, not opus's own repo), and format (one comment per issue vs. a consolidated summary) is still an open choice.
  - [ ] Clarify opus's role vs. imbus's data governance work
  - [ ] Establish timeline for ICES feedback loop (e.g., HaulValidity vocab completion)

- [ ] **QC workflow decision:**
  - [ ] Domain-expert review of borderline constraints (range calls, enum membership)
  - [ ] Spot-check Quarto renders for accuracy
  - [ ] Validate enum audit results (enum_field_inventory.csv from 2026-08-02)

## Done — 2026-08-29 conversion pipeline

✓ **Conversion is `R/` code, called by `data-raw/`** — `op_cast_wsdl_types()`,
  `op_rename_to_new()`, `op_strip_sentinels()`, `op_cast_to_spec()`, plus the
  service readers and sentinel accessors. 34 exports.
✓ **All three `data-raw`/`R` duplications resolved** —
  `spec_00_operation_types.R` and `archive_00_wsdl_types.R` deleted,
  `archive_03`'s `datras_get_field_list()` dropped; callers now use the
  exported functions (Working Principle 7b).
✓ **Both dictionaries retyped and validating** — `Quarter`/`Month` →
  `number(ordinal)` with ranges; `DateofCalculation` → `date`;
  `Tickler`/`SpeciesCategory` stay enums stored as text.
✓ **Sentinel policy encoded** in `inst/DATRAS-known-issues.yaml`
  (`sentinels: resolution`), label-driven with 3 documented keep entries.
✓ **Archive rebuilt from `.datras/xml/`**, consolidated to
  `.datras/to_https/raw/{T}.parquet` — current names only, no sentinels except
  the documented keeps, `DateofCalculation` a real `DATE`, no `INT64`.
✓ **`op_validate_meta()` clean on all four tables** (was HH 3, HL 3, CA 2, LT 5).
✓ **Site**: `articles/approach.qmd` written; `articles/reference.qmd` generated
  from `man/*.Rd` by `data-raw/build_reference.R`; dictionary snapshot
  regenerated — and it now actually profiles the data, which it never did
  before (`op_render_spec()`'s `data_dir` injects a `source:`).
✓ **`.datras/` tidied** — superseded artifacts moved to `.datras/retired/`
  (documented in its own README), not deleted.

## Immediate: next

- [ ] **Publish** `.datras/to_https/raw/*.parquet` + `catalog.duckdb` to the
      server. Note the ordering constraint from `spec_04_build_catalog.R`:
      the parquet must be live at the target URL *before* the catalog is
      built, because DuckDB's `COMMENT ON COLUMN` resolves the view's real
      remote schema eagerly.
- [ ] **`spec_04_build_catalog.R` still mirrors `op_flag_violations()`
      verbatim** — the third and last `data-raw`/`R` duplication, and the
      most dangerous kind (a behavioural copy carrying a known `.inf` quirk).
      Extract the shared yaml field-walk into `R/` and have both call it.
- [ ] **File the `-9` overloading with ICES** — a new `systemic`
      `known_violations` entry plus an `articles/issues.qmd` section for the
      `IMBUS_FISHMAP#29` batch. Worked example: `Tickler` (a real code)
      against `Turbidity` (never recorded), indistinguishable by value or by
      frequency and separable only by consulting a vocabulary.
- [ ] Two smaller ICES-side items, both handled locally for now by
      `op_wsdl_type_overrides()`: `Valid_Aphia` declared `string` while
      holding numeric AphiaIDs, and `DateofCalculation` declared `string` by
      LT's operation but `int` by HH/HL/CA. The latter is distinct from the
      existing `dateofcalculation_cross_product_inconsistency` entry, which
      is about *values* disagreeing between products, not types.
- [ ] `.datras/retired/` (656M) can be deleted once the rebuilt data is
      published — that is the last point where the old files are useful for a
      before/after comparison.

## Raised by obus, 2026-08-28 — resolved 2026-08-29

Found by running obus's parquet-vs-xml consistency check against real
data (NS-IBTS 2022 Q1). Kept here for the reasoning; the items below are
answered unless marked otherwise.

**Resolved.** The "two unreconciled type systems" question is settled by
making the conversion itself an `R/` API: the archive and any live-XML
consumer now call the *same four functions*, so the question of which type
system wins no longer arises per-consumer — it is answered once, in
`op_cast_wsdl_types()` (physical, from the WSDL) and `op_cast_to_spec()`
(semantic, only where the wire cannot express it). The missing sentinel
accessor is `op_sentinels()`. The `-9` truncation anomaly below is still
open and still worth reporting to ICES.

<details>
<summary>Original write-up, kept for the evidence</summary>


- [ ] **Two type systems, unreconciled — which one is the public
      contract?** opus produces two different, independently-maintained
      answers to "what type is this field":
        1. **WSDL physical types** (string/int/decimal), which
           `data-raw/archive_00_wsdl_types.R` applies when building the
           parquet archive — deliberately so, and documented as such:
           "The curated spec (`inst/DATRAS-data-dict.yaml`) plays no
           role here and is never loaded by this file or its callers."
        2. **Curated semantic types** (`number(quantity)`,
           `number(ordinal)`, `enum`) in the YAML, which
           `op_field_spec()` reports.
      Consumers hit both. obus types its live-XML path from (2) and
      reads the archive built from (1), so the same column arrives as a
      different R class depending on source: 7 mismatched columns in HL,
      6 in CA. Measured, not inferred — physical parquet schema vs.
      `op_field_spec()`:
        - `SweepLength`/`LengthClass`/`SubsampleWeight`/
          `SpeciesCategoryWeight`/`SubsampledNumber`/`NumberAtLength`/
          `Age` — **INT32** in the archive (R integer), but
          `number(quantity)` in the YAML (R numeric).
        - `Year` — **INT64** in the archive, so R renders it numeric
          (no native 64-bit int); `number(ordinal)` in the YAML → R
          integer. Arguably INT64 is overkill for a year.
        - `DateofCalculation` — INT32 carrying a parquet **DATE**
          logical type (R `Date`), but `number(ordinal)` in the YAML.
      The split is defensible in principle — physical vs. semantic
      answer different questions — but nothing currently states which
      one downstream packages should treat as authoritative, and the
      WSDL reports a plain `int` for all of the above, so it doesn't
      explain the `Year`/`DateofCalculation` choices on its own. A
      decision here unblocks obus; a documented statement of the split
      might be enough, without changing either pipeline.

- [ ] **`DateofCalculation` is typed `number(ordinal)` but is a date.**
      The archive already stores it as a real parquet DATE. opus's own
      `op_datras_field_list()` docs record it as a field ICES documents
      under no name at all (discrepancies #5 and #6), so there's no ICES
      type to defer to — this is opus's call. `number(ordinal)` looks
      like the wrong answer regardless of how the item above resolves.

- [ ] **No R accessor for the known-issues registry.** opus ships
      `inst/DATRAS-known-issues.yaml` (including the `sentinels:`
      entries) but exports no function that reads it — confirmed by
      grepping all of `R/`, zero references to the file. obus's
      sentinel-to-`NA` work is blocked on this: obus's own `AGENTS.md`
      forbids it from parsing opus's YAMLs directly ("reads opus's
      shipped YAMLs through this one function and never parses them
      itself"), so it needs an accessor here, the way `op_field_spec()`
      was added for the data dict. Same blocker applies to any
      downstream `flag_known_issues()`-style feature.

- [ ] **Candidate known-issues entry: NS-IBTS 2022 Q1 HL is exactly
      32767 rows (2^15 - 1).** Both the live ICES XML response and the
      parquet archive return that identical count, while neighbouring
      quarters of the same survey run 44k-52k (2021 Q1: 51151;
      2023 Q1: 45752). Scanned the whole HL archive: it is the only one
      of 971 survey/year/quarter groups on that value, and 115 groups
      exceed it (max 54712), so there is no global cap — which makes a
      signed-16-bit truncation specific to that submission the most
      likely reading, though unproven. Worth a targeted check against
      ICES; if it holds up it's a registry entry, and an ICES-side
      report rather than anything to work around.

</details>

## Forward: Tier 2 (FL, CPUEL, CPUEA, IDX)

- [ ] Assess WSDL coverage (complete vs. gaps)
- [ ] Decide: seed from WSDL or direct hand-author (depends on confidence in source)
- [ ] Follow Tier 1 workflow if seeding (bootstrap + curate + audit)
- [ ] Test parquet availability for validation data

## Future: Tier 3 (obus contracts)

- [ ] Hand-authored specs (no ICES source); deferred until Tier 1+2 stable
- [ ] Coordinate with obus team on contract-specific constraints and enums
