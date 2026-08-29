# FILED — ices-tools-prod/icesDatras#63
#
# https://github.com/ices-tools-prod/icesDatras/issues/63
# Opened 2026-08-29. Kept here as the source text and the evidence behind it;
# the issue itself is the live record.
#
# ---------------------------------------------------------------------------

**Title:** `getDatrasUnaggregated()`: HH columns are silently mis-assigned — `DateofCalculation` lost, its values appear in `EDOM`

---

### Summary

For `recordtype = "HH"`, `getDatrasUnaggregated()` returns three columns with
wrong contents, without any warning or error:

| column | returned | should be |
|---|---|---|
| `EDOM` | `DateofCalculation` values (e.g. `20130614`) | EDOM values |
| `ReasonHaulDisruption` | all `NA` | its own values |
| `DateofCalculation` | all `NA`, typed `logical` | the dates now in `EDOM` |

`HL` and `CA` are unaffected.

The cause is upstream: the CSV served by `DATRASDownloadAPI.aspx` for HH has a
**72-field header but 70-field data rows**. `fread(..., fill = TRUE)` pads short
rows at the *end*, so the last data value (`DateofCalculation`) is bound to the
70th header name (`EDOM`), and the final two header names get `NA`.

---

### Reproducible example

```r
library(icesDatras)  # 1.5.3

d <- getDatrasUnaggregated("HH", "DWS", "1965:2026", "1:4",
                           data.table.output = FALSE)

str(d[c("EDOM", "ReasonHaulDisruption", "DateofCalculation")])
#> 'data.frame': 72 obs. of 3 variables:
#>  $ EDOM                : int  20130614 20130614 20130808 ...   # <- dates
#>  $ ReasonHaulDisruption: chr  NA NA NA ...
#>  $ DateofCalculation   : logi  NA NA NA ...                    # <- lost
```

`DWS` is used only because it is small (72 rows). The same happens for every
survey checked.

### Verifying without R

```bash
API=https://datras.ices.dk/Data_products/Download/DATRASDownloadAPI.aspx
curl -sL -o hh.zip "$API?recordtype=HH&survey=DWS&year=1965:2026&quarter=1:4"
unzip -p hh.zip | tr -d '\r' | awk -F',' 'NR<=3 {print NR": "NF" fields"}'
#> 1: 72 fields      <- header
#> 2: 70 fields      <- data
#> 3: 70 fields
```

Aligning the header against a data row shows where it breaks — positions 1–69
match, then:

```
  69 SurveyIndexArea       | 69 -9
  70 EDOM                  | 70 20130614     <- a DateofCalculation value
  71 ReasonHaulDisruption  |    (absent)
  72 DateofCalculation     |    (absent)
```

---

### Scope

Checked 2026-08-29 against the live API:

- **HH is affected in every row.** All 37,180 NS-IBTS rows have exactly 70
  fields against a 72-field header. Same 72/70 split for `DWS`, `IS-IDPS`,
  `NL-BSAS` and `SE-SOUND`. It is consistent, not intermittent.
- **HL and CA are internally consistent** — HL 30 fields in all 4,101,389 rows,
  CA 36 in all 2,020,963, headers matching.

So the defect is specific to the HH export.

---

### Why this is worth fixing rather than documenting

The failure is silent and plausible. Row counts are right, the data frame has
the expected 72 columns with the expected names, and nothing errors. A user
reading `DateofCalculation` gets `NA` for every row and has no signal that a
value existed; a user reading `EDOM` gets dates that look like a real code.

`fill = TRUE` is what converts a detectable structural inconsistency into
silently mis-assigned data — without it, `fread()` would raise on the ragged
rows.

---

### Possible remedies

Not mutually exclusive, roughly in order of preference:

1. **Fix the server-side export** so the HH header matches its rows — either
   emit the two missing columns or drop them from the header. This is the only
   fix that also helps consumers who bypass the R package. (Tools that do not
   pad, such as DuckDB's CSV reader, currently fail outright on these files
   rather than mis-binding, so the ragged output is not only an R problem.)
2. **Validate in the package**: compare `length(header)` against the field count
   of the first data row and `stop()` (or `warning()` and drop the unmatched
   header names) instead of padding. Failing loudly is better than returning a
   column of `NA` that used to hold data.
3. **Bind from the right end** as an interim workaround, so the trailing value
   lands in `DateofCalculation` rather than `EDOM` — but only alongside (1) or
   (2), since it encodes an assumption about which columns are missing.

---

### Environment

```
icesDatras 1.5.3
R 4.5.2 (2025-10-31), macOS (aarch64)
Checked against the live API on 2026-08-29
```
