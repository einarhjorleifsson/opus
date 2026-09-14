# DRAFT — not yet filed
#
# Target: https://github.com/ices-tools-prod/icesDatras/issues
# Companion to #63 (HH ragged CSV) and #64 (Aphia/species naming), both filed
# 2026-08-29. Unlike those two, this one is not about the CSV endpoint itself —
# the bytes the server sends are fine; the data loss happens inside
# icesDatras's own type coercion.
#
# Verified current 2026-09-14: the default-branch source of
# R/getDatrasUnaggregated.R still calls `formatDatras(df, fix_types = ...,
# new_names = ...)` without `record=`, and a fresh `remotes::install_github(
# "ices-tools-prod/icesDatras")` (1.5.3) re-run of the reprex below still
# returns 0 fractional values out of 4,101,389 rows.
#
# ---------------------------------------------------------------------------

**Title:** `getDatrasUnaggregated()` silently truncates fractional `NumberAtLength` in HL (9.85 -> 9), because `formatDatras()` is called without `record=`

---

### Summary

HL's `NumberAtLength` (legacy `HLNoAtLngt`) is a **decimal** field — fractional
values arise when subsampled counts are scaled by `SubsamplingFactor`. The
CSV export carries them correctly (e.g. `9.85`, `4.92`, `189,106` fractional
values in the NS-IBTS HL export alone). But `getDatrasUnaggregated()` returns
the column with every fraction truncated to an integer.

The cause: `getDatrasUnaggregated()` calls

```r
df <- formatDatras(df, fix_types = fix_types, new_names = new_names)
```

without passing `record = recordtype`. Inside `applyDatrasTypeSchema()` a
`NULL` record means the **unfiltered** `getDatrasFieldList()` is used, and
`NumberAtLength` exists there twice: `decimal` for HL, but **`int` for CA**
(legacy `CANoAtLngt`). The int coercion runs before the decimal one:

```r
df[int_cols] <- lapply(df[int_cols], as.integer)   # NumberAtLength in here via CA
df[dbl_cols] <- lapply(df[dbl_cols], as.numeric)   # too late: fractions already gone
```

so `as.integer(9.85)` -> `9` for every fractional HL value. Any column whose
name appears with different `DataFormat`s in different record types is
exposed to the same collision.

### Reproducible example

```r
library(icesDatras)  # 1.5.3

d <- getDatrasUnaggregated("HL", "NS-IBTS", "1965:2030", "1:4",
                           data.table.output = FALSE)
sum(d$NumberAtLength %% 1 != 0, na.rm = TRUE)
#> [1] 0          <-- fractions destroyed

# fread alone, on the same file the function downloads, keeps them:
# 189,106 fractional values (9.85, 4.92, 9.33, ...). So does
# formatDatras(df, record = "HL", ...) applied by hand — the bug is
# specifically the missing record= pass-through.

# Note the year/quarter arguments must be range *strings* as above:
# passing integer vectors (1965:2030) vectorizes the URL via paste0()
# and corrupts the zip download.
```

### Evidence that the server is not at fault

- The zip icesDatras downloads is byte-identical in size to a direct
  `download.file` of the same URL (48,705,893 bytes for NS-IBTS HL,
  566,234,045 bytes uncompressed).
- `fread(file, fill = TRUE, blank.lines.skip = TRUE)` on that file yields
  `NumberAtLength` as numeric **with** all 189,106 fractional values.
- `formatDatras(df, record = "HL", fix_types = TRUE)` preserves them;
  `formatDatras(df, fix_types = TRUE)` (record = NULL) destroys them.

### Suggested fix

Pass the record type through:

```r
df <- formatDatras(df, record = recordtype, fix_types = fix_types,
                   new_names = new_names)
```

That is sufficient for this column, since HL's own declaration is `decimal`.
A more robust variant would also have `applyDatrasTypeSchema()` resolve
name collisions explicitly (same name, different types across record types)
rather than relying on caller-supplied filtering.

### Impact

Any HL pull via `getDatrasUnaggregated()` with the default
`fix_types = TRUE` under-reports length-frequency counts wherever
subsampling produced fractional raised numbers. `getHLdata()` (the ASMX
route) is unaffected — it passes `record` correctly.

### Scale, and concrete examples

Measured against the full HL archive (all 29 surveys, ~11.9M rows), 9 surveys
carry fractional `NumberAtLength` values; the worst affected:

| survey | rows | fractional values | share |
|---|---|---|---|
| FR-WCGFS | 38,463 | 23,616 | 61.4% |
| SE-SOUND | 12,542 | 6,426 | 51.2% |
| FR-CGFS | 237,835 | 58,218 | 24.5% |
| EVHOE | 627,514 | 54,405 | 8.7% |
| BITS | 1,512,558 | 86,031 | 5.7% |
| NS-IBTS | ~4.1M | ~190-205k | ~5% |

Examples of real submitted values that arrive as integers instead:

- SE-SOUND 2011 Q3, Sweden, sprat (Sprattus sprattus, 127139): `17.89`,
  `4.47` at 13-19 cm length classes -> truncated to `17`, `4`.
- FR-CGFS 1988 Q4, France, whiting (Merlangius merlangus, 126438): `24.44`,
  `13.33`, `8.89` at 31-33 cm -> `24`, `13`, `8`.
- BITS 1991 Q3, Latvia, sprat (127141): `45.60`, `39.90`, `11.40` at
  21-23 cm -> `45`, `39`, `11`.
- NS-IBTS 1991 Q1, Sweden, whiting (126438): `14.88` -> `14`; poor cod
  (Trisopterus minutus, 154675): `9.33`, `4.67` -> `9`, `4`.
- FR-WCGFS 2018 Q3, France, whiting (126438): `1.94`, `1.07` -> `1`
  (a 49% undercount on the 1.07 value).

For FR-WCGFS and SE-SOUND this is not an edge case: the majority of all
reported length frequencies in those surveys are fractional, so
`getDatrasUnaggregated()` currently misreports most rows of both surveys.
