# opus — TODO

**Status:** v0.2.0 complete. Tier 1 (HH, HL, CA, LT) fully curated and documented. Ready for forward work: Tier 2 + imbus coordination.

*Detailed dated development history lives in `DEVLOG.md`, not here. This file tracks only current backlog state.*

**Latest:** 2026-08-17 — Fixed the `read.delim()` T/F-to-logical archive-integrity bug and rebuilt the archive; removed 6 dead three-phase-bootstrap `R/` files; restructured AGENTS.md/TODO.md to current-state-only and created `DEVLOG.md` for dated history. See `DEVLOG.md`'s 2026-08-17 entries for full detail.

---

## v0.2.0 — Complete

✓ **Bootstrap workflow** — Three-phase bootstrap (WSDL seed → parquet enrich → curate) with supporting R functions
✓ **Tier 1 (HH, HL, CA, LT)** — Curated YAML specs + descriptive/strict YAML variants + known-issues registry
✓ **R package** — 21 exported functions (validation, vocabulary, field name utilities) + 5 vignettes
✓ **Documentation** — why-opus, using-opus, technical-notes articles + Quarto reference site
✓ **Test data** — Parquet samples for each Tier 1 table
✓ **Git history** — Clean three-phase commits with milestone tags
✓ **Package build** — devtools::check() passing; .rbuildignore optimized
✓ **Zero R-package dependency on `icesDatras`/`icesVocab`** (2026-08-06) — direct, cross-verified web-service calls instead (`op_datras_field_list()` in `R/field_names.R`, direct HTTP in `R/vocab.R`)

---

## Backlog

- [ ] **File `data-raw/ICES_ISSUE_REPORT.md` with ICES** — 10 confirmed issues, drafted but not yet sent (longest-standing open item in this project). Venue undecided (informal imbus discussion first, per existing strategy, or direct GitHub/DIG submission?).
- [ ] **Decide `inst/*.parquet`'s fate (D1)** — stale relative to corrections made since its 2026-07-31 generation (e.g. `DateofCalculation`), provenance was unclear until traced to `data-raw/GENERATE_test_data_ns_ibts_2026q1.R` (a narrow single-survey/quarter extract from obus's own local files, not a broad sample). A draft resampling script, `data-raw/archive_07_build_test_samples.R`, exists on disk untracked, pending this decision — its own header comment is also wrong ("no script anywhere in this repo previously built these files") and needs fixing regardless of what else happens to it. Until resolved, treat `.datras/*.parquet` (not `inst/*.parquet`) as the only reliable source for yaml/issue-report/documentation work.
- [ ] Decide `vignettes/articles/using-opus.qmd`'s fate (untracked, severely stale — rewrite from scratch or drop; `why-opus.qmd`/`technical-notes.md` may already cover the ground).
- [ ] Fix `inst/DATRAS-data-dict-legacy.yaml`'s `source:` stanzas (point to nonexistent `{TABLE}_legacy.parquet`).
- [ ] Stop baking hard `\n` line breaks into `description`/`details` string values (`format_long_text()` in `spec_02_curate_dict.R`) — use a folded (`>`) scalar instead, matching data-dict's own canonical examples.
- [ ] Add `conflicts` to the three `relationships` entries where real overlapping non-key columns exist (e.g. `RecordHeader`'s meaning differs HH vs. HL).
- [ ] Fix the literal `<U+2192>` text (not a real arrow) in both YAMLs' `origin:` field (line 10).
- [ ] Fix `tests/testthat/test_validation.R`'s file-existence check (`file.exists("HH.parquet")` → `system.file(...)`) — 6 of 14 tests always silently skip right now.
- [ ] Fix `DESCRIPTION`'s "Data-only package (no computational functions)" claim against its own 21 exported functions.
- [ ] Fix `HH.StartTime`'s details ("same as StatRec above" — wrong name, wrong direction; same bug in the legacy YAML).
- [ ] Glossary: add `icesVocab`, `WSDL`, `WoRMS`/`AphiaID`, the internal rule codes (`M01`/`S24`/`D01`/`D04`), `CPUE`, `OSPAR`, `SeaDataNet` — all used repeatedly, never defined.
- [ ] Minor cleanup pass: trailing `.0` on range values, flow-scalar vs. block-scalar inconsistency at the table/dataset level, `HL.SubsamplingFactor`'s stale row-count citation (and spot-check others for the same drift), two tiny case mismatches (`HH.ThermoCline`, `LT.LTSRC`), delete the now-fully-dead `scripts/build-dictionary.sh`.
- [ ] Consider making `col_labels`'s apply loop (`spec_02_curate_dict.R`) reject unexpected keys instead of silently dropping them — this exact silent-drop hid a real fix on its first attempt (`DEVLOG.md`, 2026-08-16).

Full evidence/detail behind every item above is in `DEVLOG.md`.

---

## Immediate: Tier 1 Validation + Known-Issues Escalation

- [ ] **Known-issues registry refinement:**
  - [ ] Restructure for two-level escalation: field-level gaps vs. systemic patterns
  - [ ] Inventory findings from 2026-08-02 session (7 D-level issues across HH/HL/CA/LT)
  - [ ] Prioritize escalation candidates for imbus feedback
  
- [ ] **imbus/ICES liaison (WP2 handoff):**
  - [ ] Define escalation format: memo, GitHub Issues, or direct registry submission?
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
