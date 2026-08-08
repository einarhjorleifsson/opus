# opus — TODO

**Status:** v0.2.0 complete. Tier 1 (HH, HL, CA, LT) fully curated and documented. Ready for forward work: Tier 2 + imbus coordination.

**Latest:** 2026-08-06 — Removed `icesDatras`/`icesVocab` R-package dependencies (direct, verified web-service calls instead). Rebuilding the replacement surfaced and fixed 6 confirmed ICES-side `getDatrasFieldList` errors; drafted `inst/ICES_ISSUE_REPORT_20260806.md`. `inst/DATRAS-data-dict.yaml` regenerated and validated (3/3 reproducible runs, `R CMD check` clean, no regressions). See AGENTS.md's Open Items for full detail.

---

## v0.2.0 — Complete

✓ **Bootstrap workflow** — Three-phase bootstrap (WSDL seed → parquet enrich → curate) with supporting R functions
✓ **Tier 1 (HH, HL, CA, LT)** — Curated YAML specs + descriptive/strict YAML variants + known-issues registry
✓ **R package** — 17 exported functions (validation, vocabulary, field name utilities) + 5 vignettes
✓ **Documentation** — why-opus, using-opus, technical-notes articles + Quarto reference site
✓ **Test data** — Parquet samples for each Tier 1 table
✓ **Git history** — Clean three-phase commits with milestone tags
✓ **Package build** — devtools::check() passing; .rbuildignore optimized
✓ **Zero R-package dependency on `icesDatras`/`icesVocab`** (2026-08-06) — direct, cross-verified web-service calls instead (`op_datras_field_list()` in `R/field_names.R`, direct HTTP in `R/vocab.R`)

---

## Immediate: 2026-08-06 session follow-through

- [x] **Decide the fate of same-day pre-dependency-work documents** — deleted 2026-08-07 (`inst/PHASE2_ISSUES_FOR_ICES.md`, `inst/PHASE3_ROADMAP.md`, `inst/DATRAS_PHASE2_ORIGINAL_NAMES.yaml`, `ICESVOCAB_MAPPING_AUDIT.md`, and related CSVs). All were untracked, so nothing was lost from git history.
- [ ] **File `inst/ICES_ISSUE_REPORT_20260806.md` with ICES** — 6 confirmed `getDatrasFieldList`/archive-data issues, drafted but not yet sent. Venue undecided (informal imbus discussion first, per existing strategy, or direct GitHub/DIG submission?).
- [ ] **Raise the `icesDatras` package note separately** — its `getDatrasFieldList()` wrapper silently patches around some of the same ICES errors with an undocumented, unsourced hand-patch; worth telling its maintainers once the ICES-side fix is in motion.
- [x] **Review and commit tonight's diff** — done 2026-08-07/08 as a sequence of reviewable commits (icesDatras/icesVocab removal, seed/curate script updates, known-issues registry fix) rather than one large diff. Remaining: website/vignette artifacts, which still reference the now-corrected HaulNumber claim.

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
