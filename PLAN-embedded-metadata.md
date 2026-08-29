# Plan: embed the data dictionary in the parquet files, retire `catalog.duckdb`

**Drafted:** 2026-08-29. **Status:** proposal + working mock, nothing shipped.
**Spans two packages.** The access layer for the raw archive lives in **opus**
(`op_con()` and the metadata accessors); **obus** consumes it. Sections are
tagged `[opus]` / `[obus]`.

A runnable mock of the whole thing is in the scratchpad — `op_embed_mock.R`
(write side), `op_read_mock.R` (read side), `demo.R` (17-section
demonstration). Every number below was measured, not estimated.

---

## 0. What data-dict gives us, and what it doesn't

`~/garbage/data-dict/` is the **tidyverse `data-dict.yaml` project** — a generic
format spec plus a Rust CLI (v0.0.3, built at
`~/garbage/data-dict/target/release/data-dict`). Checked for embedding support
specifically.

### It has no embedding feature — verified

- **Zero occurrences of `key_value_metadata`** anywhere in `crates/`. It neither
  writes nor reads parquet footer metadata.
- **It never writes parquet.** The only `SerializedFileWriter` uses are in
  `benches/` and one `profile.rs` test fixture. The tool is read-only.
- `source: {parquet: path}` points **dictionary → data**, one-directional. There
  is no data → dictionary path and no `embed`/`extract` command.
- "Embed" in its docs means embedding a *translated predicate into your own
  code*, not metadata into a file.

**So the footer read/write is ours to build.** It is small, and §1 proves it.

### But three features change the plan substantially

The first draft of this plan proposed hand-rolling a YAML→JSON serializer in R
by porting the walking logic out of `spec_04_build_catalog.R`. **That is
unnecessary work.**

| Feature | What it does | Effect |
|---|---|---|
| **`export-spec`** | Renders the dictionary as **fully-resolved JSON** — parsed types, `range` as `{min,max}`, enum `values` + `value_labels` split, constraints, joins, definitions. Same pass as `validate-spec`, so it fails with the same `S##` diagnostics. | **This *is* the payload.** No serializer to write. opus already wraps it as `op_export_spec()`. |
| **`definitions` + `translations`** | Named reusable expressions, each exported with pre-rendered code for `R(tidyverse)`, `R(base)`, `R(data.table)`, `SQL(duckdb)`, `Python(polars)`, **plus per-target semantic caveat notes**. | Rules travel *in the file*, executable in both engines. §3.2. |
| **`relationships`** resolved | The join exported as structured `pairs`, not just a string. opus's dict already declares all three (HL/CA/LT → HH), each an **8-column composite key**, with `conflicts`. | The `.id` key obus lists under "Later" is **already authored** — derive it. §3.3. |

### The rest of the landscape

| Location | What it is | Reuse? |
|---|---|---|
| `~/garbage/dictionary/` | The dictionary's **former home** (`DATRAS-data-dict.yaml`, `contract.md`). | No — superseded. Keep `contract.md` §2/§3/§4 as the source of formulas that should become `definitions` (§3.2). |
| `opus/inst/DATRAS-data-dict.yaml` | **The live dictionary.** 153 448 B, 4 tables / 190 columns, 3 relationships, 14 glossary terms, 1 definition. | **Yes — the payload.** |
| `opus/R/validation.R` | `op_validate_*`, `op_export_*`, `op_render_spec()`, `op_describe_parquet()`, `op_draft_from_parquet()`. | Yes. Its comment that `describe`/`draft` "require branches to be merged" is **stale** — both are in `main` and in the built binary. |
| `opus/data-raw/spec_04_build_catalog.R` | Builds `catalog.duckdb` from the YAML. | **Replaced** (§5) — superseded by `export-spec`, not ported. |

---

## 1. Feasibility — all measured 2026-08-29

Per `AGENTS.md` Working Principle 6, these were run, not reasoned about.

1. **DuckDB reads footer metadata over HTTPS in 0.06–0.12 s.**
   `parquet_kv_metadata('https://heima.hafro.is/~einarhj/datras/raw/HH.parquet')`
   returns against the live server without downloading the 5.4 MB file — a
   footer range request. **The whole plan rests on this.**
2. **`decode(value)`, not `value::VARCHAR`.** The value is a BLOB; the plain
   cast hex-escapes every quote (`\x22`).
3. **`export-spec` runs clean on opus's dictionary**: exit 0, 154 124 B compact
   JSON (S31 `todo` warnings on stderr, as designed).
4. **JSON, not YAML** — DuckDB can't parse YAML but has native `json_extract`.
   **Do not gzip**: DuckDB has no gunzip scalar, and compressing would break the
   "nothing but a DuckDB client" promise that is the entire point.
5. **The crosswalk is complete and bijective against the actual files** — checked
   column-by-column. File column count = crosswalk row count for all four tables
   (HH 69, HL 29, CA 34, LT 58); no column without an entry, no entry without a
   column, both name columns unique, round-trip lossless. 103 columns actually
   renamed. **This is what makes an embedded mapping sufficient on its own**
   (§6) — a partial one would be worse than none, since `dr_translate()` keeps
   the original name on no match, so an un-renamed column would pass through
   looking translated. The mock asserts it at write time.

### 1.1 The writer matters more than expected — use nanoparquet, not arrow

Testing the write path turned up something the design had assumed away.
**`arrow::write_parquet()` serializes custom metadata twice**: once as the
parquet KV entry, and again — base64-inflated ~1.37× — inside its own
`ARROW:schema` key. Measured on LT with a 120 000 B payload:

| writer | footer keys | footer bytes | file bytes | `DateofCalculation` |
|---|---|---|---|---|
| `arrow::write_parquet` | `datras:dict` + `ARROW:schema` | 120 000 + 164 172 = **284 172** | 3 319 826 | INT32 / DATE ✓ |
| `nanoparquet` (default) | `datras:dict` + `ARROW:schema` | 120 000 + 3 500 = 123 500 | 3 227 346 | INT32 / DATE ✓ |
| **`nanoparquet`, `write_arrow_metadata = FALSE`** | `datras:dict` only | **120 000** | **3 223 828** | INT32 / DATE ✓ |
| DuckDB `COPY … KV_METADATA` | `datras:dict` only | 120 000 | 3 262 427 | INT32, **logical type lost** |

`ARROW:schema` is arrow's own sidecar — **parquet does not require it and
DuckDB never reads it.** Dropping it is free.

**Recommendation: `nanoparquet::write_parquet(df, out, metadata = …,
options = parquet_options(write_arrow_metadata = FALSE))`.** Verified column
classes and data `identical()` to the arrow round-trip, including
`DateofCalculation`'s DATE logical type — the one field where the archive makes
a semantic choice WSDL doesn't express. DuckDB's `COPY` is a viable pure-SQL
alternative but drops that logical type, so it is second choice.

This also means **arrow is not needed on the read path at all** — the read mock
imports only `DBI`, `duckdb`, `jsonlite`.

### 1.2 Real payload sizes, from the mock

All four tables embedded and read back successfully:

| table | dict | coverage | sentinels | known&nbsp;issues | prov. | **total** | file before → after |
|---|---|---|---|---|---|---|---|
| HH | 56 719 | 55 193 | 6 015 | 5 723 | 390 | **124 040** | 5 391 095 → 5 612 317 |
| HL | 35 229 | 57 027 | 2 537 | 4 100 | 392 | **99 285** | 88 849 459 → 84 215 995 |
| CA | 41 209 | 52 832 | 2 953 | 4 619 | 391 | **102 004** | 30 380 698 → 30 850 931 |
| LT | 53 174 | 12 399 | 4 914 | 6 954 | 389 | **77 830** | 3 039 723 → 3 181 749 |

Read honestly: the file-size deltas are **not** just the metadata — switching
writer also changes the encoding. HH/CA/LT grew 1.5–4.7%; **HL, the big one,
shrank 5.2%** despite gaining 99 KB. Net effect is acceptable either way.

**`datras:coverage` is bigger than it should be** — 52–57 KB, roughly as large
as the dictionary itself, because the mock writes one JSON object per
`(Survey, Year, Quarter)` group with repeated keys (972 groups for HH). Store it
column-wise (parallel arrays) or drop the per-group `n_rows` and it falls to a
few KB. Worth doing before publishing; see §8 Q5.

---

## 2. Incidental findings this work must not step around

- **`dr_con()` is pointed at a stale copy.** Its default is
  `…/datras/{type}.parquet`. Both layouts are live: flat `datras/HH.parquet`
  (4 793 543 B) and current `datras/raw/HH.parquet` (5 391 095 B). It reads the
  flat one. §6 replaces it outright.
- **The `raw/` archive does *not* carry obus's Tier-3 names, and has no `.id`.**
  `raw/HL.parquet` has `SpeciesSex`/`Valid_Aphia` (not `sex`/`aphia`),
  `raw/CA.parquet` has `Age` (not `age`), no table has `.id`. This **reverses
  two `TODO.md` entries**. `archive_06_consolidate.R`'s header explains why: the
  rename moved upstream into `archive_04`/`05` via `op_rename_to_new()`, and
  opus now publishes current names only.
- **`Quarter` was retyped `enum` → `number(ordinal)` on 2026-08-29** — one of the
  four fields in `dr_settypes()`'s M01 override list, possibly now redundant.
- **The live `raw/` archive is already reachable** —
  `https://heima.hafro.is/~einarhj/datras/raw/HH.parquet` returns 200. What is
  not there yet is the metadata: its footer carries only `ARROW:schema` (5 144 B).

---

## 3. `[opus]` The payload

Five keys, one concern each — so a consumer wanting only the crosswalk parses
~4 KB not 57 KB, and so a rebuild's diff stays legible (`provenance`/`coverage`
change every build; `dict` rarely).

### 3.1 `datras:dict` — `export-spec` output, sliced to one table

Keep this table's entry in `tables`, the `relationships` that touch it, and the
top-level `name`/`version`/`origin`/`glossary`. **Do not re-derive any of it.**

Three additions `export-spec` cannot know, merged per column:

```jsonc
{ "name": "SweepLength",
  "type": "number(quantity)",   // export-spec: opus's curated semantic type
  "units": "m",
  "range": {"min": 0, "max": 850},
  "legacy_name": "SweepLngt",    // added: op_datras_rename_crosswalk()
  "parquet_type": "INT32",       // added: read back from the file itself
  "logical_type": "DATE",        // added: only where one is declared
  "r_type": "integer" }          // added: what DuckDB/R hands back
```

Carrying all three type views is the point. `TODO.md`'s open bug — *"parquet and
xml do NOT return the same types"* — **is** the gap between `type` and `r_type`,
invisible today unless someone runs the class check by hand. The mock renders it
as a four-line table (demo §4). It does not decide which type system is the
public contract — that stays opus's call — but it stops the divergence being
silent.

`parquet_type`/`r_type` **must be read back from the written file**, never
derived from the YAML — deriving them from the spec defeats the purpose.

`legacy_name` is written **once, here, by opus** from the crosswalk — the one
place that legitimately owns it. From then on the file translates its own names
with no external list. Verified complete and bijective against the file (§1.5).

### 3.2 Definitions: rules travel with the data — and the mock found a real bug

opus's dict carries one definition; `export-spec` resolves it into executable
code for five targets with caveats:

```jsonc
{ "name": "linkable_to_hh", "expression": "HaulNumber != -9",
  "kind": "filter", "columns": ["HaulNumber"],
  "translations": [
    {"target": "R(tidyverse)", "code": "HaulNumber != -9L", "notes": [...]},
    {"target": "SQL(duckdb)",  "code": "\"HaulNumber\" <> -9", "notes": [...]}]}
```

So `op_define(ca, "CA", "linkable_to_hh")` filters using the R code the *file*
supplied, and `op_con()` can push the DuckDB spelling down — same rule, one
source, both engines.

**The mock immediately caught that this definition is wrong for the published
archive.** The sentinel policy — in the *same footer* — records
`CA.HaulNumber: strip`, so the `-9`s became NULL during the build. On the real
archive: 5 968 027 rows, **305 276 NULL (5.12%), zero `-9`**. The definition
`HaulNumber != -9` therefore matches nothing it was written to match. It still
filters correctly *by accident* — NA propagates and both dplyr and SQL drop it —
and would break silently the moment the policy changed to `keep`. It should read
`!is.na(HaulNumber)`.

**Neither key alone shows this.** The dictionary looks right; the policy looks
right; only co-locating them reveals the contradiction. That is the strongest
argument for the whole design, and it is `[opus]`'s to fix.

**Candidates to author next**, from `contract.md`, which states them as binding
rules with nowhere to live:

- **§2/§3 the DataType formula**: `SUM(NumberAtLength * SubsamplingFactor)` —
  "the single most common source of silent errors in DATRAS user code".
  **Confirmed expressible**, tested against the real dict: type-checks
  (`number`), resolves its columns, renders to
  `sum(NumberAtLength * SubsamplingFactor, na.rm = TRUE)` and
  `sum("NumberAtLength" * "SubsamplingFactor")`.
- **§4 the CA→HH join guard**: `AreaType = 'H'`.

Grouping is *not* an obstacle: the formula is a metric, the host supplies
`.by =` / `GROUP BY`, which is the correct division anyway since `contract.md`
§3 requires the multiplication happen per row and only then be summed.

**The real caveat is sentinels, exactly as above.** The R translation carries
`na.rm = TRUE` and DATRAS encodes missing as `-9`. Author each formula's
sentinel guard *in the dictionary beside it*, and check it against the policy.

### 3.3 Relationships: the composite key is already authored

`export-spec` resolves each relationship into structured `pairs`. opus's dict
declares all three, each the 8-column key
`Survey, Year, Quarter, Country, Platform, Gear, StationName, HaulNumber` —
exactly the `.id` key `TODO.md` lists under "Later". It also carries `conflicts`
(`RecordHeader` for HL/CA → HH, `DateofCalculation` for LT → HH) and, on CA→HH,
a note that 4.92% of CA rows are orphaned by the `-9` sentinel.

**Derive `.id` from this, don't hand-code it**, and let join helpers take their
`by =` and conflict list from the file.

### 3.4–3.7 The other four keys

- **`datras:provenance`** (~390 B) — `table`, `n_rows`, `n_cols`, `source`,
  `built_utc`, `opus_version`, `opus_git_sha`, `dict_sha256`,
  `data_dict_cli`, `arrow_version`, `pipeline`. The spec's own `origin`/`version`
  already cover part of this and are populated — carry them through rather than
  duplicate. `dict_sha256` is the addition (§6).
- **`datras:sentinels`** (2.5–6 KB) — per field, `strip`/`keep` + why.
  `archive_06_consolidate.R` **already computes and asserts this**, then discards
  it. Given Working Principle 2, a file that has had sentinels stripped from some
  columns and not others should say so in its own footer. It is also half of the
  cross-check in §3.2.
- **`datras:coverage`** (needs slimming, §1.2) — surveys, year range, and the
  `(Survey, Year, Quarter)` combinations. **Fixes half of `TODO.md`'s open
  `dr_get()` bug**: today `dr_get("HH")` with `surveys = NULL` calls
  `.dr_default_surveys()` → live ICES → `data.frame()` on any network error →
  0 rows, no warning. The mock's `op_surveys()` returns all 29 surveys from the
  footer with no network call at all.
- **`datras:known_issues`** (4–7 KB) — the slice of `DATRAS-known-issues.yaml`
  naming this table (5 for CA).

### Not included

No compression (§1.4). No per-column statistics — parquet already carries
row-group min/max. No `ARROW:schema` — dropped entirely (§1.1).

### One wrinkle: prose comes back as HTML

`export-spec` renders every description to HTML (`"<p>Length of sweep…</p>"`),
deliberately, so web consumers need no Markdown implementation. The mock strips
tags in `op_dict()` and keeps the file faithful to what the tool produced.
Recommend that.

---

## 4. `[opus]` Write side

1. **Fold into `archive_06_consolidate.R`** — same `write_parquet()` call as the
   data, so no window exists where the file lacks its dictionary.
2. **Call `op_export_spec()` and slice per table.** No YAML walking, no
   serializer. This replaces the first draft's plan to port
   `spec_04_build_catalog.R`.
3. **Switch the writer to nanoparquet with `write_arrow_metadata = FALSE`**
   (§1.1). Independently worth doing: it drops `ARROW:schema`, avoids the double
   serialization, and made HL 5% smaller.
4. **Read `parquet_type`/`r_type` back from the written file.**
5. **Assert before publishing** — the mock does all three:
   - crosswalk total and bijective vs the file's columns;
   - `datras:dict` column names identical to the file's, in order;
   - then `op_validate_meta()` / `op_validate_full()` as already prompted.
6. **Fix `linkable_to_hh`** (§3.2) and add a check that every definition's
   sentinel assumptions match `op_sentinel_policy()`.
7. **Slim `datras:coverage`** (§1.2).
8. **Delete `spec_04_build_catalog.R`**; stop staging `catalog.duckdb` (§5).
9. **Fix the stale `describe`/`draft` comment** in `R/validation.R`.

---

## 5. Retiring `catalog.duckdb`

It (1 060 864 B, live at `datras/raw/catalog.duckdb`) gives a SQL-only consumer
three things the footer does not: `SELECT * FROM HH` with no URL;
`COMMENT ON COLUMN` via `duckdb_columns()`; and relational `enum_labels` /
`range_constraints` / `field_constraints`.

**All three are recoverable, and the trade is worth making**, because the catalog
has a structural flaw the footer does not: it is a *separate file describing
other files*. Nothing forces it to be rebuilt when the parquet is, and a consumer
who downloads `HL.parquet` alone gets no dictionary at all.

- `[opus]` **`op_catalog()` builds the same views, comments and lookup tables in
  an in-memory DuckDB**, read out of the four footers. Same SQL surface, derived
  on demand, structurally incapable of going stale.
- `[opus]` Document the pure-SQL one-liner in the archive README:
  ```sql
  SELECT decode(value) FROM parquet_kv_metadata(
    'https://heima.hafro.is/~einarhj/datras/raw/HH.parquet') WHERE key = 'datras:dict';
  ```
- `[opus]` `data-dict render` produces a **self-contained HTML page** of the
  dictionary. Publishing it beside the archive replaces the browsable half for
  free.

**Do not delete the published catalog until `op_catalog()` exists and is
verified.** Removing it from the build and from the server are two steps, in
that order.

---

## 6. `[opus]` `op_con()` and the metadata accessors

**Decision taken: this lives in opus, not obus.** opus builds and publishes the
archive, so opus owns access to it. That also resolves the naming confusion — one
connection function, one archive, one package.

### The archive is deliberately one thing

`op_con()` addresses **only the four raw exchange tables under a directory whose
last path section is `raw`** — either the local staging dir
(`.datras/to_https/raw`) or its published twin
(`https://heima.hafro.is/~einarhj/datras/raw`). Anything else is an error:

```r
op_archive("/tmp/somewhere/else")
#> Error: An opus archive is a directory named `raw` (the four exchange tables
#>   as staged by archive_06_consolidate.R). Got: /tmp/somewhere/else
```

Local wins when present, else the web; override with `options(opus.archive=)`.
The narrowness is the feature — it is what lets every accessor below assume the
five keys are there.

### The surface (all implemented and exercised in the mock)

| function | returns |
|---|---|
| `op_archive(path)` | resolved archive root; errors unless it ends in `raw` |
| `op_con(table, path)` | lazy `tbl` over one raw table |
| `op_keys(table)` | which metadata keys the footer carries, and their sizes |
| `op_dict(table)` | one row per column: `name`, `legacy_name`, `type`, `parquet_type`, `logical_type`, `r_type`, `units`, `constraints`, `range_min/max`, `label`, `description` |
| `op_crosswalk(table)` | `old_name`/`new_name`, **asserted 1:1 and total** |
| `op_rename(d, table, to)` | rename between schemes using only the file's metadata |
| `op_enums(table, column)` | code → label (HH: 13 enum columns, 205 codes) |
| `op_definitions(table)` / `op_define(d, …)` | list definitions; apply one via its `R(tidyverse)` code |
| `op_relationships(table)` | resolved join `by =` + `conflicts` |
| `op_coverage(table)` / `op_surveys()` | what's in the archive; survey list with no ICES call |
| `op_sentinel_meta(table)` | the applied strip/keep policy |
| `op_provenance(table)` / `op_known_issues(table)` | build facts; issues naming this table |
| `op_catalog()` | in-memory DuckDB catalog (§5) |

One internal `.op_kv(table, key, path)` — a `parquet_kv_metadata()` query with
`decode()` — cached per (file, key), so repeated calls cost one round trip.

### `[obus]` What changes on the obus side

- **`dr_con()` is replaced by `op_con()`** for HH/HL/CA/LT. It currently points
  at the stale flat layout (§2), so this is a fix, not just a move. Either
  re-export `op_con()` or drop `dr_con()` — do not maintain a second one.
- **`dr_translate()` needs no change.** It is already a generic
  rename-by-dictionary utility; `op_crosswalk()` gives it a dictionary sourced
  from the data. Demonstrated round-tripping a real NS-IBTS 2022 Q1 query through
  both naming schemes, losslessly (demo §6).
- **`dr_get(source = "parquet")`** uses `op_surveys()` instead of
  `.dr_default_surveys()`, closing half the open bug.
- **`species` / `length_weight` / `swept_area` stay obus's problem.** They are
  obus-owned lookup tables, not part of the `raw/` archive, and `dr_con()`
  currently promises them. Decide separately (§8 Q2).
- **obus keeps** the live-XML path, `dr_settypes()`, and the domain products.

### The dependency question — needs explicit sign-off

`AGENTS.md` Working Principle 1 says names and types come from opus, never
guessed. Reading them from the footer **does not violate that** — the footer
content *is* opus's spec, produced by opus's own `export-spec` run.

> **Proposal:** the parquet path reads its spec from the file; the xml path keeps
> using `op_field_spec()`. opus becomes a build-time dependency of the archive
> and a runtime dependency only of `source = "xml"`.

**Measured honestly: there is no skew today.** The installed opus (0.2.0) ships a
dictionary byte-identical to the source (`sha256 22fff43c…`), and the archive was
rebuilt from it in the same commit (`13bd44d`). So this is **not a fix for a
present bug** and should not be sold as one.

What it buys is a guarantee rather than a coincidence. Today the two agree
because one person rebuilt both in one sitting; nothing enforces it. Update opus
without a rebuild, or install a different opus than the archive was built with,
and the parquet path types the archive by a spec that never described it —
silently, since both sides look healthy alone. `dict_sha256` turns that from
undetectable into a warning.

---

## 7. Sequence — status

**Implemented and verified 2026-08-29. opus only; nothing in obus was touched.**

1. [x] Five `datras:` keys written in `archive_06_consolidate.R` from
   `op_export_spec()`, via `data-raw/archive_06_metadata.R`. Writer switched to
   nanoparquet with `write_arrow_metadata = FALSE`; coverage slimmed 3.5x
   (HH 55,193 -> 15,925 B). All four tables rebuilt: data byte-identical to the
   pre-write archive, `op_validate_meta()` clean, footers carry exactly the five
   keys and no `ARROW:schema`.
2. [x] `R/archive.R` — 16 exported functions (`op_archive`, `op_con`, `op_keys`,
   `op_dict`, `op_crosswalk`, `op_rename`, `op_enums`, `op_definitions`,
   `op_define`, `op_relationships`, `op_coverage`, `op_surveys`,
   `op_sentinel_meta`, `op_provenance`, `op_known_issues`, `op_catalog`).
   `DBI`/`dplyr`/`duckdb` moved to `Imports`; nanoparquet to `Suggests`.
3. [x] `linkable_to_hh` corrected and **reframed**: `HaulNumber IS NOT NULL`,
   documented as naming which rows a haul-level join reaches, explicitly *not* a
   data-quality filter. See §3.2.
6. [x] `op_relationships()` — the 8-field composite key, derived from the
   embedded relationship rather than hand-coded.
7. [~] `contract.md` formulas: HL's `count_at_length` / `total_number`
   authored. **The AreaType guard was not** — see §3.2.
8. [x] `op_catalog()`, verified row-for-row against the file it replaces.
9. [x] `spec_04_build_catalog.R` deleted; `datras-data-dict.html` rendered into
   `to_https/`; staged `catalog.duckdb` removed. `AGENTS.md` and `TODO.md`
   updated.
10. [x] **Published 2026-08-29.** All four parquet live at
    `…/datras/raw/`, byte-identical to staged, footers verified over https;
    `raw/catalog.duckdb` now 404s; the rendered dictionary is live at
    `…/datras/raw/datras-data-dict.html`. `dict_sha256` agrees across source
    YAML, installed opus and the published files.
11. [ ] Deferred to a later obus session, by decision: replacing `dr_con()`,
    `dr_get(source="parquet")` using `op_surveys()`, `dr_check_types()`.

## 8. Open questions

**Only Q1 needs sign-off before work starts.**

1. **The dependency decision in §6** — *needs an explicit answer.* Evidence: no
   skew exists today, so it is a choice about guarantees, not a repair.
2. **`species` / `length_weight` / `swept_area`** — obus-owned, outside the
   `raw/` archive, but `dr_con()` promises them and breaks either way until
   settled. Republish with `data-dict draft`-seeded dictionaries, or drop?
3. **Key prefix `datras:` or `opus:`?** Recommend `datras:`, with
   `datras:provenance` naming opus explicitly. Cheap now, awkward after first
   publish — decide at step 1.
4. ~~**Is the DataType formula expressible?**~~ **Resolved — yes**, tested (§3.2).
5. **How much coverage detail to keep?** It is currently as large as the
   dictionary (§1.2). Recommend column-wise arrays and dropping per-group
   `n_rows` unless something needs it.
6. **HTML prose** (§3) — recommend stripping in `op_dict()`; pure read-side,
   changeable any time.
7. **Legacy dictionary prose too?** Recommend `legacy_name` only — the full
   legacy dict roughly doubles the payload for little gain.
