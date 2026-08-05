# opus — TODO

**Status:** v0.2.0 complete. Tier 1 (HH, HL, CA, LT) fully curated and documented. Ready for forward work: Tier 2 + imbus coordination.

**Latest:** 2026-08-05 — AGENTS.md and process cleaned up. R function scope clarified (20 exported metadata/validation tools, not "data-only" but metadata-centric per Principle 3).

---

## v0.2.0 — Complete

✓ **Bootstrap workflow** — Three-phase bootstrap (WSDL seed → parquet enrich → curate) with supporting R functions
✓ **Tier 1 (HH, HL, CA, LT)** — Curated YAML specs + descriptive/strict YAML variants + known-issues registry
✓ **R package** — 20 exported functions (validation, vocabulary, field name utilities) + 5 vignettes
✓ **Documentation** — why-opus, using-opus, technical-notes articles + Quarto reference site
✓ **Test data** — Parquet samples for each Tier 1 table
✓ **Git history** — Clean three-phase commits with milestone tags
✓ **Package build** — devtools::check() passing; .rbuildignore optimized

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
