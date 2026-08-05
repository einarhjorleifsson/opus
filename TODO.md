# opus — TODO

**Status:** v0.2.0 complete. Tier 1 (HH, HL, CA, LT) curated with two-YAML validation approach. R functions + validation article ready.

**Latest:** 2026-08-05 — Cleanup and git reorganization complete. Three-phase git history established (v0.1.0-phase1, v0.1.0-phase2, v0.2.0). Removed redundant working notes and prototype scripts. Ready for forward-looking work.

---

## Completed

✓ **Phase 1** — YAML seeded from ICES WSDL + getDatrasFieldList + icesVocab
✓ **Phase 2** — ICES XML downloaded and parsed to parquet (Tier 1: HH/HL/CA/LT)
✓ **Phase 3** — YAML curated, enriched with icesVocab, validated against real data
✓ **Cleanup** — Removed iteration notes, prototype scripts, YAML variants; updated .gitignore
✓ **Git organization** — Three-phase commits + tags marking milestones

---

## SESSION 2026-08-02 FINDINGS

### Known-Issues Registry (Priority: Strategic)

- [ ] **Restructure known-issues.yaml for two-level escalation:**
  - Level 1: Field-level issues (HaulValidity incomplete, GearExceptions incomplete, etc.)
  - Level 2: Architectural/systemic issues (vocabulary governance patterns, domain-prefix confusion, naming inconsistencies)
  - Currently "a bit short" — captures individual gaps but not institutional patterns
  
- [ ] **Investigate naming mysteries:**
  - [ ] SpeciesSex (HL) / IndividualSex (CA) / TS_Sex — are these semantically identical? Why three names for 7 identical codes with no unified vocab?
  - [ ] Document pattern: field names changed (GearEx → GearExceptions, Sex → SpeciesSex/IndividualSex) but icesVocab keys weren't updated in parallel
  
- [ ] **Domain-prefix architectural issue:**
  - [ ] icesVocab uses TS_ (Trawl Survey) and AC_ (Acoustic) domains
  - [ ] DATRAS uses codes from both domains with no explicit cross-domain mapping
  - [ ] Flag as systemic: vocabulary design assumes domain isolation but real use is cross-domain
  
- [ ] **Type divergence escalation:**
  - [ ] Confirm WSDL vs getDatrasFieldList divergence with ICES (Year, Distance fields)
  - [ ] Investigate whether getDatrasFieldList can be auto-synced with WSDL (currently hand-maintained, drifts from reality)

### Escalation Protocol

- [ ] **Define liaison strategy with imbus/ICES:**
  - [ ] Does WP2 synthesize findings into strategic memo, or does registry go directly?
  - [ ] Should findings be prioritized (critical gaps vs. cosmetic inconsistencies)?
  - [ ] Track ICES response: when does HaulValidity get all 7 codes added to icesVocab?
  
- [ ] **Consider temporal tracking:**
  - [ ] Log dates when issues are reported to ICES
  - [ ] Track when ICES resolves each issue (vocabulary completion, type alignment, naming clarification)
  - [ ] Measure opus's impact on ICES data governance improvement

---

## Tier 1 — Remaining

- [ ] Spot-check `.qmd` render (data-raw/DATASET_dict_to_qmd.R)
- [ ] Domain-expert review of borderline range/constraint calls
- [ ] Enum audit findings review (enum_field_inventory.csv, enum_enrichment_analysis.md)

## Tier 2 — FL, CPUEL, CPUEA, IDX

- [ ] Verify WSDL coverage; seed if complete, hand-curate if gaps
- [ ] Follow Tier 1 workflow: corrections, type measures, known-issues filing
- [ ] Repeat enum audit for Tier 2 fields

## Tier 3 — obus contracts

- [ ] Hand-authored only (no seed/curate pipeline). Start after Tier 1+2 stable.

## imbus coordination

- [ ] Report known-issues findings to ICES Datacenter; track response status
- [ ] Share enum audit results (35/52 fields with vocab, 4 with gaps, 1 with empty vocab)
- [ ] Highlight architectural patterns: vocabulary governance is systemic issue, not random gaps
