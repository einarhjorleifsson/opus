# opus — TODO

**Status:** v0.2.0 complete. Tier 1 (HH, HL, CA, LT) fully curated and documented. Ready for forward work: Tier 2 + imbus coordination.

*Detailed dated development history lives in `DEVLOG.md`, not here. This file tracks only current backlog state.*

**Latest:** 2026-08-17 — Full day: fixed the `read.delim()` T/F-to-logical bug and the 4th-data-source/`NAMESPACE` work (see prior entries below), then a field-gap audit (`data-raw/build_field_gap_audit.R`, now permanent tooling) cross-referencing real sentinel usage, icesVocab coverage, and the field-description spreadsheet against opus's own spec — cross-referencing two individually-thorough prior audits that had never been checked against each other. Found and fixed: 13 fields where `-9` was mis-framed as "unpopulated" (one, `LT.TYPPL`, was 99.8% sentinel); a general Mandatory→`required` mechanism covering 35 previously-undeclared fields, which along the way caught and repaired an already-live silent-constraint-loss bug (`HH.HaulNo`/`HH.Year`); `Year`/`SpecCode`'s type divergence, filed as Issue 12 after sitting unfiled since 2026-08-02; and `known-issues.yaml`'s two-level (`field-level`/`systemic`/`opus-internal`) restructure, designed around today's own findings rather than guessed at abstractly. See `DEVLOG.md`'s 2026-08-17 entries for full detail.

**Also 2026-08-17 (continued):** worked the Backlog below. Dropped `why-opus.qmd` (disputed flagship example) and `using-opus.qmd` (documented a defunct project phase) rather than fix either; removed the four stale `inst/*.parquet` samples instead of regenerating them (confirmed drifted: CA's `IndividualAge`/`Age`, LT's `GearEx`/`GearExceptions`); fixed the arrow-mojibake, `StatRec` above/below+name, `test_validation.R` skip-check, and `DESCRIPTION` claim bugs; deleted the dead `build-dictionary.sh`. `devtools::check()` clean throughout. See `DEVLOG.md`'s second 2026-08-17 entry.

**2026-08-18:** cleared the rest of the Backlog below. Added `conflicts:` to all 3 `relationships` (empirically checked -- found and fixed a real `spec_03` bug along the way, a `conflicts` array silently collapsing to a scalar on the yaml round-trip); fixed all genuinely-integer-typed range values' trailing `.0` (55 of ~85, by real column type, not blanket); `col_labels` now rejects unexpected keys; glossary gained 7 entries; `HH.ThermoCline`/`LT.LTSRC`'s case-variant rows documented. Switched to real folded (`>-`) scalar style project-wide (314 fields, verified value-preserving column-by-column). The user's own spot-check then caught a real bug (`TimeShot`'s zero-padding claim was backwards), which prompted a full stale-citation audit across all 190 fields: found and fixed 9 more fields citing stale/wrong totals (`HH.Turbidity`, `LT.OSPARArea`/`MSFDArea`/`PARAM`/`EEZ`/`NMArea`, `HH`+`LT.WindSpeed`, `LT.LT_Items`, `HL.SubFactor`), plus 3 HH-LT comparison citations (`LT.HaulVal`/`Rigging`/`SwellHeight`) whose denominators had drifted — discovering along the way that **LT has 44,255 duplicate composite keys** (HH has zero), left as an open structural finding, not chased further. `devtools::check()` clean throughout. See `DEVLOG.md`'s 2026-08-18 entry for full detail.

---

## v0.2.0 — Complete

✓ **Bootstrap workflow** — Three-phase bootstrap (WSDL seed → parquet enrich → curate) with supporting R functions
✓ **Tier 1 (HH, HL, CA, LT)** — Curated YAML specs + descriptive/strict YAML variants + known-issues registry
✓ **R package** — 22 exported functions (validation, vocabulary, field name utilities)
✓ **Documentation** — technical-notes article + Quarto reference site (why-opus.qmd/using-opus.qmd dropped 2026-08-17 -- one had a disputed flagship example and thinly restated AGENTS.md otherwise, the other documented a defunct project phase; see DEVLOG.md)
~~Test data — Parquet samples for each Tier 1 table~~ — dropped 2026-08-17, not fixed: confirmed never regenerated since 2026-07-31 and had drifted from the real archive (CA's `IndividualAge`/`Age`, LT's `GearEx`/`GearExceptions`); see DEVLOG.md
✓ **Git history** — Clean three-phase commits with milestone tags
✓ **Package build** — devtools::check() passing; .rbuildignore optimized
✓ **Zero R-package dependency on `icesDatras`/`icesVocab`** (2026-08-06) — direct, cross-verified web-service calls instead (`op_datras_field_list()` in `R/field_names.R`, direct HTTP in `R/vocab.R`)

---

## Backlog

- [ ] **File `data-raw/ICES_ISSUE_REPORT.md` with ICES** — 12 confirmed issues, drafted but not yet sent (longest-standing open item in this project). Venue undecided (informal imbus discussion first, per existing strategy, or direct GitHub/DIG submission?) — and per the imbus/ICES liaison item below, the venue doesn't actually exist yet either.
- [ ] `Gear`'s enum `values` map re-serializes in a different (but content-identical) key order on every `spec_02`/`spec_03` re-run -- cosmetically noisy diffs, confirmed harmless (2026-08-17) but never root-caused.
- [ ] `LT` has 44,255 duplicate composite keys (HH has zero) -- found 2026-08-18 while re-verifying HH-LT comparison citations; not investigated further, possibly related to `LT.DateofCalculation`'s own conflict with HH (see `relationships`) if a haul's multiple LT rows were processed at different times.

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
