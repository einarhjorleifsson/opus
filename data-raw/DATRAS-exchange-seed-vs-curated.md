# Seed → Curated: what changed

Diff between `data-raw/seed/DATRAS-exchange-dict-seed.yaml` (raw, web-only,
uncorrected) and `inst/DATRAS-data-dict.yaml` (curated by
`data-raw/DATASET_curate_dict.R`).

| # | Location | Change |
|---|---|---|
| 1 | Document header | Added `$learn_more` (spec-recommended, silences an S09 warning) |
| 2 | Document header | `description` rewritten: dropped "SEED ONLY / not yet curated" framing, points at the curation script instead |
| 3 | `HL.Valid_Aphia` | `type: string` → `type: number(id)`, with a `details` pointer |
| 4 | `CA.Valid_Aphia` | `type: string` → `type: number(id)`, with a `details` pointer |

Two real content corrections, both the same known WSDL/reality mismatch, applied once per table.

---

### 1–2. Header

```diff
 $version: 0.1.0
+$learn_more: http://data-dict.tidyverse.org/
 name: datras_exchange
 label: ICES DATRAS Exchange Data (Tier 1 -- raw haul-grain submissions)
 description: 'Direct per-haul submissions to ICES DATRAS: HH (haul), HL (length),
-  CA (age), LT (litter). SEED ONLY, from ICES''s own live WSDL + getDatrasFieldList()
-  + icesVocab -- no local/curated content; blank where ICES currently publishes nothing.
-  Not yet curated -- see AGENTS.md.'
+  CA (age), LT (litter). Curated from data-raw/seed/DATRAS-exchange-dict-seed.yaml
+  -- see data-raw/DATASET_curate_dict.R for the corrections applied and why.'
```

### 3. `HL.Valid_Aphia`

```diff
   - name: Valid_Aphia
-    type: string
+    type: number(id)
+    details: 'See known issue valid_aphia_type_mismatch (DATRAS-known-issues.yaml,
+      not yet filed): ICES''s WSDL declares this field character, but the live service
+      always returns it numeric -- it''s a WoRMS AphiaID (an identifier, hence number(id),
+      not a quantity).'
```

### 4. `CA.Valid_Aphia`

```diff
   - name: Valid_Aphia
-    type: string
+    type: number(id)
+    details: 'See known issue valid_aphia_type_mismatch (DATRAS-known-issues.yaml,
+      not yet filed): ICES''s WSDL declares this field character, but the live service
+      always returns it numeric -- it''s a WoRMS AphiaID (an identifier, hence number(id),
+      not a quantity).'
```

Everything else in the 190-field, 4-table document is byte-identical between
seed and curated — exactly the minimal, traceable diff the workflow is meant
to produce.
