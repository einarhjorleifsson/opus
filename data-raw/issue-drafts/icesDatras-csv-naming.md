# FILED — ices-tools-prod/icesDatras#64
#
# https://github.com/ices-tools-prod/icesDatras/issues/64
# Opened 2026-08-29. Kept here as the source text and the evidence behind it;
# the issue itself is the live record.
#
# ---------------------------------------------------------------------------

**Title:** `getDatrasUnaggregated()`: the AphiaID and species-name columns are named differently in HL and CA, and `getDatrasFieldList()` covers neither

---

### Summary

The CSV export behind `getDatrasUnaggregated()` gives the same two concepts four
different names across HL and CA, and they reach the caller unchanged because
`getDatrasFieldList()` has no entry for any of them:

| concept | HL | CA | ASMX XML service |
|---|---|---|---|
| AphiaID | `ValidAphiaID` | `AphiaID` | `Valid_Aphia` in **both** |
| WoRMS scientific name | `ScientificName_WoRMS` | `Species` | not served |

Neither `new_names = TRUE` nor `fix_types = TRUE` can normalise or type these,
because `applyDatrasNameSchema()` and `applyDatrasTypeSchema()` both key off
`getDatrasFieldList()`, and none of `ValidAphiaID`, `AphiaID`,
`ScientificName_WoRMS` or `Species` appears in either its `FieldName` or its
`FieldNameOld` column.

### Reproducible example

```r
library(icesDatras)  # 1.5.3

for (rt in c("HL", "CA")) {
  d <- getDatrasUnaggregated(rt, "DWS", "1965:2030", "1:4", data.table.output = FALSE)
  cat(rt, ":", grep("Aphia|Scientific|^Species$", names(d), value = TRUE), "\n")
}
#> HL : ValidAphiaID ScientificName_WoRMS
#> CA : AphiaID Species

# unchanged by the option that exists to normalise names
options(icesDatras.new_names = TRUE)
#> HL : ValidAphiaID ScientificName_WoRMS
#> CA : AphiaID Species

fl <- getDatrasFieldList()
c("ValidAphiaID", "AphiaID", "ScientificName_WoRMS", "Species") %in%
  c(fl$FieldName, fl$FieldNameOld)
#> [1] FALSE FALSE FALSE FALSE
```

### A related case that *is* covered, and shows the pattern

`NumberAtLength` comes back under two names in the same session:

```r
options(icesDatras.new_names = FALSE)   # the default
#> HL : ... NumberAtLength ...
#> CA : ... CANoAtLngt ...
```

Here the CSV itself is inconsistent — HL already uses the new name while CA
still sends the legacy one. `new_names = TRUE` does fix this one, because the
field list has `CA / CANoAtLngt -> NumberAtLength`. It is the same class of
problem as the table above; it just happens to be covered.

Incidentally, the field list types that shared target name differently per
table — `HL / HLNoAtLngt -> NumberAtLength` is `decimal`, `CA / CANoAtLngt ->
NumberAtLength` is `int`. That may well be intentional (raised HL counts can be
fractional), but it is worth being explicit about, since the two arrive under one
name.

### Why this is worth raising

* **It is a regression against the older route.** The ASMX service uses
  `Valid_Aphia` in both HL and CA, so a consumer moving from XML to the CSV
  download acquires an inconsistency that was not there before.
* **The package's own normalisation cannot reach it.** `new_names` exists
  precisely to give callers one vocabulary; here it silently does nothing for
  four columns, with no signal that it was unable to act.
* **Joining HL to CA needs a rename first**, for a column that identifies the
  same species in both — which is the main reason anyone joins them.

### Possible remedies

1. **Make the export consistent** — one name per concept across record types,
   ideally the ASMX service's `Valid_Aphia`. This is the only fix that also
   helps consumers reading the endpoint directly.
2. **Add the missing entries to `getDatrasFieldList()`**, so
   `applyDatrasNameSchema()`/`applyDatrasTypeSchema()` can act on them at all.
   Worth doing regardless of (1), since it is also what makes them typeable.
3. **Warn when `new_names = TRUE` leaves columns unmapped**, rather than
   returning them silently unchanged. A caller asking for normalised names
   currently has no way to know some were not.

### Environment

```
icesDatras 1.5.3
R 4.5.2 (2025-10-31), macOS (aarch64)
Checked against the live API on 2026-08-29
```
