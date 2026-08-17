# opus — TODO

**Status:** v0.2.0 complete. Tier 1 (HH, HL, CA, LT) fully curated and documented. Ready for forward work: Tier 2 + imbus coordination.

*Detailed dated development history lives in `DEVLOG.md`, not here. This file tracks only current backlog state.*

**Latest:** 2026-08-17 — Full day: fixed the `read.delim()` T/F-to-logical bug and the 4th-data-source/`NAMESPACE` work (see prior entries below), then a field-gap audit (`data-raw/build_field_gap_audit.R`, now permanent tooling) cross-referencing real sentinel usage, icesVocab coverage, and the field-description spreadsheet against opus's own spec — cross-referencing two individually-thorough prior audits that had never been checked against each other. Found and fixed: 13 fields where `-9` was mis-framed as "unpopulated" (one, `LT.TYPPL`, was 99.8% sentinel); a general Mandatory→`required` mechanism covering 35 previously-undeclared fields, which along the way caught and repaired an already-live silent-constraint-loss bug (`HH.HaulNo`/`HH.Year`); `Year`/`SpecCode`'s type divergence, filed as Issue 12 after sitting unfiled since 2026-08-02; and `known-issues.yaml`'s two-level (`field-level`/`systemic`/`opus-internal`) restructure, designed around today's own findings rather than guessed at abstractly. See `DEVLOG.md`'s 2026-08-17 entries for full detail.

---

## v0.2.0 — Complete

✓ **Bootstrap workflow** — Three-phase bootstrap (WSDL seed → parquet enrich → curate) with supporting R functions
✓ **Tier 1 (HH, HL, CA, LT)** — Curated YAML specs + descriptive/strict YAML variants + known-issues registry
✓ **R package** — 22 exported functions (validation, vocabulary, field name utilities) + 5 vignettes
✓ **Documentation** — why-opus, using-opus, technical-notes articles + Quarto reference site
✓ **Test data** — Parquet samples for each Tier 1 table
✓ **Git history** — Clean three-phase commits with milestone tags
✓ **Package build** — devtools::check() passing; .rbuildignore optimized
✓ **Zero R-package dependency on `icesDatras`/`icesVocab`** (2026-08-06) — direct, cross-verified web-service calls instead (`op_datras_field_list()` in `R/field_names.R`, direct HTTP in `R/vocab.R`)

---

## Backlog

- [ ] **File `data-raw/ICES_ISSUE_REPORT.md` with ICES** — 12 confirmed issues, drafted but not yet sent (longest-standing open item in this project). Venue undecided (informal imbus discussion first, per existing strategy, or direct GitHub/DIG submission?) — and per the imbus/ICES liaison item below, the venue doesn't actually exist yet either.
- [ ] **Decide `inst/*.parquet`'s fate (D1)** — stale relative to corrections made since its 2026-07-31 generation (e.g. `DateofCalculation`), provenance was unclear until traced to `data-raw/GENERATE_test_data_ns_ibts_2026q1.R` (a narrow single-survey/quarter extract from obus's own local files, not a broad sample). A draft resampling script, `data-raw/archive_07_build_test_samples.R`, exists on disk untracked, pending this decision — its own header comment is also wrong ("no script anywhere in this repo previously built these files") and needs fixing regardless of what else happens to it. Until resolved, treat `.datras/*.parquet` (not `inst/*.parquet`) as the only reliable source for yaml/issue-report/documentation work.
- [ ] Decide `vignettes/articles/using-opus.qmd`'s fate (untracked, severely stale — rewrite from scratch or drop; `why-opus.qmd`/`technical-notes.md` may already cover the ground).
- [ ] Fix `inst/DATRAS-data-dict-legacy.yaml`'s `source:` stanzas (point to nonexistent `{TABLE}_legacy.parquet`).
- [ ] Stop baking hard `\n` line breaks into `description`/`details` string values (`format_long_text()` in `spec_02_curate_dict.R`) — use a folded (`>`) scalar instead, matching data-dict's own canonical examples.
- [ ] Add `conflicts` to the three `relationships` entries where real overlapping non-key columns exist (e.g. `RecordHeader`'s meaning differs HH vs. HL).
- [ ] Fix the literal `<U+2192>` text (not a real arrow) in both YAMLs' `origin:` field (line 10).
- [ ] Fix `tests/testthat/test_validation.R`'s file-existence check (`file.exists("HH.parquet")` → `system.file(...)`) — 6 of 14 tests always silently skip right now.
- [ ] Fix `DESCRIPTION`'s "Data-only package (no computational functions)" claim against its own 22 exported functions.
- [ ] Fix `HH.StartTime`'s details ("same as StatRec above" — wrong name, wrong direction; same bug in the legacy YAML).
- [ ] Glossary: add `icesVocab`, `WSDL`, `WoRMS`/`AphiaID`, the internal rule codes (`M01`/`S24`/`D01`/`D04`), `CPUE`, `OSPAR`, `SeaDataNet` — all used repeatedly, never defined.
- [ ] Minor cleanup pass: trailing `.0` on range values, flow-scalar vs. block-scalar inconsistency at the table/dataset level, `HL.SubsamplingFactor`'s stale row-count citation (and spot-check others for the same drift), two tiny case mismatches (`HH.ThermoCline`, `LT.LTSRC`), delete the now-fully-dead `scripts/build-dictionary.sh`; `Gear`'s enum `values` map re-serializes in a different (but content-identical) key order on every `spec_02`/`spec_03` re-run -- cosmetically noisy diffs, confirmed harmless (2026-08-17) but never root-caused.
- [ ] Consider making `col_labels`'s apply loop (`spec_02_curate_dict.R`) reject unexpected keys instead of silently dropping them — this exact silent-drop hid a real fix on its first attempt (`DEVLOG.md`, 2026-08-16).

Full evidence/detail behind every item above is in `DEVLOG.md`.

---

## Immediate: Tier 1 Validation + Known-Issues Escalation

- [ ] **Known-issues registry refinement:**
  - [x] ~~Restructure for two-level escalation: field-level gaps vs. systemic patterns~~ — done 2026-08-17: added a `scope` field (`field-level`/`systemic`/`opus-internal`) to all 8 `known_violations` entries, designed around today's own findings (`icesVocab_gaps`/`datras_field_list_type_divergence` are the systemic examples) rather than guessed at in the abstract.
  - [ ] Inventory findings from 2026-08-02 session (7 D-level issues across HH/HL/CA/LT)
  - [ ] Prioritize escalation candidates for imbus feedback — now filterable by the new `scope: systemic` tag, not yet actually done

- [ ] **imbus/ICES liaison (WP2 handoff):**
  - [ ] Define escalation format: memo, GitHub Issues, or direct registry submission? -- checked 2026-08-17: `vignettes/imbus-interim-note-mockup.qmd` is explicitly a mockup, "not live yet". The escalation channel itself doesn't exist yet, not just an undecided choice among existing ones -- a bigger decision than opus can resolve unilaterally (imbus liaison structure, per this file's own WP2/WP3 scope boundary), so `ICES_ISSUE_REPORT.md` (now 12 issues) stays unsent regardless of anything else in this backlog.
  - [ ] Clarify opus's role vs. imbus's data governance work
  - [ ] Establish timeline for ICES feedback loop (e.g., HaulValidity vocab completion)

- [ ] **QC workflow decision:**
  - [ ] Domain-expert review of borderline constraints (range calls, enum membership)
  - [ ] Spot-check Quarto renders for accuracy
  - [ ] Validate enum audit results (enum_field_inventory.csv from 2026-08-02)

## Forward: Tier 2 (FL, CPUEL, CPUEA, IDX)

- [ ] Assess WSDL coverage (complete vs. gaps)
- [ ] Decide: seed from WSDL or direct hand-author (depends on confidence in source)
- [ ] Follow Tier 1 workflow if seeding (bootstrap + curate + audit)
- [ ] Test parquet availability for validation data

## Future: Tier 3 (obus contracts)

- [ ] Hand-authored specs (no ICES source); deferred until Tier 1+2 stable
- [ ] Coordinate with obus team on contract-specific constraints and enums
