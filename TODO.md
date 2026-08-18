# opus — TODO

**Status:** v0.2.0 complete. Tier 1 (HH, HL, CA, LT) fully curated and documented. Ready for forward work: Tier 2 + imbus coordination.

*Detailed dated development history lives in `DEVLOG.md`, not here. This file tracks only current backlog state.*

**Latest:** 2026-08-18 — see `DEVLOG.md` for full detail.

---

## v0.2.0 — Complete

✓ **Bootstrap workflow** — Three-phase bootstrap (WSDL seed → parquet enrich → curate) with supporting R functions
✓ **Tier 1 (HH, HL, CA, LT)** — Curated YAML specs + descriptive/strict YAML variants + known-issues registry
✓ **R package** — 22 exported functions (validation, vocabulary, field name utilities)
✓ **Documentation** — technical-notes article + Quarto reference site (why-opus.qmd/using-opus.qmd dropped 2026-08-17, see DEVLOG.md)
~~Test data — Parquet samples for each Tier 1 table~~ — dropped 2026-08-17, see DEVLOG.md
✓ **Git history** — Clean three-phase commits with milestone tags
✓ **Package build** — devtools::check() passing; .rbuildignore optimized
✓ **Zero R-package dependency on `icesDatras`/`icesVocab`** (2026-08-06) — direct, cross-verified web-service calls instead (`op_datras_field_list()` in `R/field_names.R`, direct HTTP in `R/vocab.R`)

---

## Immediate: Tier 1 Validation + Known-Issues Escalation

- [ ] **Known-issues registry refinement:**
  - [x] ~~Restructure for two-level escalation: field-level gaps vs. systemic patterns~~ — done 2026-08-17: added a `scope` field (`field-level`/`systemic`/`opus-internal`) to all 8 `known_violations` entries, designed around today's own findings (`icesVocab_gaps`/`datras_field_list_type_divergence` are the systemic examples) rather than guessed at in the abstract.
  - [ ] Inventory findings from 2026-08-02 session (7 D-level issues across HH/HL/CA/LT)
  - [ ] Prioritize escalation candidates for imbus feedback — now filterable by the new `scope: systemic` tag, not yet actually done

- [ ] **imbus/ICES liaison (WP2 handoff):**
  - [ ] File `data-raw/ICES_ISSUE_REPORT.md` with ICES (13 confirmed issues, drafted) — held deliberately, not just stuck: the venue doesn't exist yet (next item), and ongoing work keeps surfacing more issues worth folding in before one filing.
  - [ ] Define escalation format: memo, GitHub Issues, or direct registry submission? -- checked 2026-08-17: `vignettes/imbus-interim-note-mockup.qmd` is explicitly a mockup, "not live yet". The escalation channel itself doesn't exist yet, not just an undecided choice among existing ones -- a bigger decision than opus can resolve unilaterally (imbus liaison structure, per this file's own WP2/WP3 scope boundary).
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
