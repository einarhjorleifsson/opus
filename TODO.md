# opus — TODO

**Status:** v0.2.0 complete. Tier 1 (HH, HL, CA, LT) fully curated and documented. Ready for forward work: Tier 2 + imbus coordination.

**Latest:** 2026-08-16 — Adopted `relationships`/`todo`/`definitions` for the first time; found and fixed a real archive-pipeline bug (a blanket sentinel-to-`NA` conversion had been silently destroying meaningful values archive-wide, worst case `HH.Tickler` at 78% of the column) and rebuilt the full 4-table archive from raw XML; six field-level spec fixes (`SwellHeight` x2, `Age`, `DateofCalculation` x3, `Quarter`/`Tickler`/`CatIdentifier`); reconsidered `op_flag_violations()` and added two new report-related functions (21 exported total, not 17); switched documentation architecture from a hand-rolled Quarto generator to data-dict's own `render`. Same-day follow-through: fixed two independent bugs in `.validate_via_dict()` that had made `op_validate_meta()`/`op_validate_data()` non-functional against the shipped dictionary (both now verified working against all four tables); closed a documentation gap the fix surfaced (`Month`'s WSDL-vs-enum divergence, same pattern as `Quarter`/`Tickler`); updated `known-issues.yaml`'s `lt_bts_2025_q1_orphaned` with the 16-row NS-IBTS diagnosis; investigated data-dict's `skill-read`/`skill-create` (generic, not opus-specific, no action needed). Pre-staging review (data-dict example alignment, skill-based audit, full structural review) fixed two more real bugs (`AgeSource`/`AgePrepMet` resolving to redirect-only icesVocab keys instead of `SampleType`/`PreparationMethod`; three CA sampling-flag columns missed by the earlier re-verification pass) and surfaced a large backlog of further findings, not yet fixed — see "Pre-staging review backlog" below and AGENTS.md's Open Items (2026-08-16 entries) for full detail.

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

## Immediate: 2026-08-06 session follow-through

- [x] **Decide the fate of same-day pre-dependency-work documents** — deleted 2026-08-07 (`inst/PHASE2_ISSUES_FOR_ICES.md`, `inst/PHASE3_ROADMAP.md`, `inst/DATRAS_PHASE2_ORIGINAL_NAMES.yaml`, `ICESVOCAB_MAPPING_AUDIT.md`, and related CSVs). All were untracked, so nothing was lost from git history.
- [ ] **File `data-raw/ICES_ISSUE_REPORT.md`** (moved from `inst/ICES_ISSUE_REPORT_20260806.md` 2026-08-08) **with ICES** — 6 confirmed `getDatrasFieldList`/archive-data issues, drafted but not yet sent. Venue undecided (informal imbus discussion first, per existing strategy, or direct GitHub/DIG submission?).
- [x] ~~Raise the `icesDatras` package note separately~~ — dropped 2026-08-09: checked directly against the current official `ices-tools-prod/icesDatras`, and its `getDatrasFieldList()` has no patch of any kind (four lines: fetch, parse, return). The "hand-patch" this item referred to was a personal development fork installed locally at the time, not the official package — nothing to raise with ICES's real maintainers. See AGENTS.md's 2026-08-09 note.
- [x] **Review and commit tonight's diff** — done 2026-08-07/08 as a sequence of reviewable commits (icesDatras/icesVocab removal, seed/curate script updates, known-issues registry fix) rather than one large diff. Remaining: website/vignette artifacts, which still reference the now-corrected HaulNumber claim.

---

## Immediate: 2026-08-16 pre-staging review backlog

Surfaced by a three-part review (data-dict example alignment, skill-read/skill-create audit, full structural review) run before staging the day's work. Two items from this review are already fixed (`AgeSource`/`AgePrepMet` vocab-key redirect, three CA sampling-flag columns) — see AGENTS.md's "Pre-staging review" entry. Everything below is still open:

- [ ] **New archive-integrity bug**: "T"/"F" values in several enum columns stored as literal text `"TRUE"`/`"FALSE"` instead of `"T"`/`"F"` (`HL.SpeciesCodeType` alone: 1.5M of 13.75M rows). Hits HH/HL/CA, never LT. Needs its own root-cause + rebuild cycle, same scale as the `sentinel_replacement_data_loss` fix — don't fold into a smaller task.
- [ ] Remove or repurpose 6 dead `R/` files (`op_apply_curated_spec.R`, `op_audit_yaml_phase2_mismatch.R`, `op_build_final_yaml.R`, `op_check_type_mismatch.R`, `op_enrich_stage2_yaml.R`, `op_minimal_yaml.R`) — superseded, zero callers, but still `@export`-tagged with live man pages.
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
- [ ] Consider making `col_labels`'s apply loop (`spec_02_curate_dict.R`) reject unexpected keys instead of silently dropping them — this exact silent-drop hid the `AgeSource`/`AgePrepMet` fix on the first attempt today.
- [ ] Fix `HH.SwellHeight`/`LT.SwellHeight`'s stale "(DATRAS-known-issues.yaml, not yet filed)" cross-reference (`inst/DATRAS-data-dict.yaml` lines ~825/3239) — the `swell_height_type_mismatch` entry has existed since earlier the same day. Found during the skill-based audit, verified directly, but dropped when this backlog was first written up — re-added 2026-08-16 (post-close status check).
- [ ] Write up the Quarto-generator-reinvention process lesson in AGENTS.md — `op_render_spec()`/`render` was adopted 2026-08-08 (`638c9ac`), but that decision was never recorded here, so a brand-new hand-rolled Quarto generator got built anyway two days later and survived 8 days until this session found and removed it. Said "worth a line" when this was traced; never actually written. Re-added 2026-08-16 (post-close status check).
- [ ] Fix `data-raw/archive_07_build_test_samples.R`'s own header comment ("No script anywhere in this repo previously built these files") — false; `data-raw/GENERATE_test_data_ns_ibts_2026q1.R` (2026-07-31) is the real one, found 2026-08-16. Applies regardless of whatever gets decided about this script's own fate (D1). Re-added 2026-08-16 (post-close status check).

Full evidence/detail for every item above is in AGENTS.md's "Pre-staging review" Open Items entry (2026-08-16).

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
