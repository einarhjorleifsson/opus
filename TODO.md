# opus — TODO

**Status:** v0.2.0 complete. Tier 1 (HH, HL, CA, LT) fully curated and documented. Ready for forward work: Tier 2 + imbus coordination.

*Detailed dated development history lives in `DEVLOG.md`, not here. This file tracks only current backlog state.*

**Latest:** 2026-08-20 — see `DEVLOG.md` for full detail.

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

## Forward: Tier 2 (FL, CPUEL, CPUEA, IDX)

- [ ] Assess WSDL coverage (complete vs. gaps)
- [ ] Decide: seed from WSDL or direct hand-author (depends on confidence in source)
- [ ] Follow Tier 1 workflow if seeding (bootstrap + curate + audit)
- [ ] Test parquet availability for validation data

## Future: Tier 3 (obus contracts)

- [ ] Hand-authored specs (no ICES source); deferred until Tier 1+2 stable
- [ ] Coordinate with obus team on contract-specific constraints and enums
