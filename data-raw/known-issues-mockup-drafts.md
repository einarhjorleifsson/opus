# Known-issues mockup drafts

Not filed anywhere yet — draft write-ups only, parked here to pick up once
the reporting mechanism (GitHub issues on opus, a row in
`DATRAS-known-issues.yaml`, something else) is actually decided. Each is
written in the shape a GitHub issue would take (title + body) since that's
the leading candidate, but nothing here is committed to that.

Grounded in real curation findings only — see `DATASET_curate_dict.R` for
`valid_aphia_type_mismatch` and `dateofcalculation_type_mismatch`, and
`AGENTS.md`'s Open items for the LT classification finding.

---

## 1. `valid_aphia_type_mismatch`

```markdown
Title: Valid_Aphia declared `character` in WSDL, but live service always returns numeric (HL, CA)

In both HL and CA, ICES's WSDL declares `Valid_Aphia` as `string`. The live
DATRAS web service, however, always returns it numeric.

`Valid_Aphia` is a WoRMS AphiaID — a taxonomic identifier, not free text or a
quantity — so the declared type doesn't match either the value actually
returned or the field's own semantic role.

Cross-checked against icesDatras's independent WSDL crawl
(`build_datras_schema.R`), which carries the same override.

Question for ICES Datacenter: is this a known gap in the WSDL documentation,
or is there a reason `character` is intentional that we're missing?
```

---

## 2. `dateofcalculation_type_mismatch`

```markdown
Title: DateofCalculation typed inconsistently across Tier 1 operations —
character for LT, int/decimal for HH/HL/CA

DateofCalculation is the same fact everywhere it appears: an 8-digit
YYYYMMDD "last recalculated" stamp inserted by ICES Datacenter, present on
HH, HL, CA, and LT alike. For HH/HL/CA, the WSDL declares it int/decimal.
For LT's own retrieval operation (getLitterAssessmentOutput), the WSDL
declares it character.

Verified against real LT data (2026-07-29, 79,451 litter records): the
value is the identical 8-digit YYYYMMDD stamp (e.g. "20260625"), same digit
order (month before day) as HH/HL/CA — it's the same kind of value, just
returned as a string by that one operation.

Question for ICES Datacenter: is this an oversight specific to
getLitterAssessmentOutput's WSDL entry, or does something upstream of the
exchange layer genuinely format this field differently for LT?
```

---

## 3. `lt_classification_ambiguity`

```markdown
Title: LT's own documentation is inconsistent about whether it's a raw
submission or a computed "assessment output"

opus currently groups HH, HL, CA, LT together as raw, per-haul submissions
with no ICES-side computation. Looking at LT specifically, two things in
ICES's own source/docs cut against that:

1. icesDatras's getLTassessment() -- the function this data is actually
   fetched through -- documents itself as returning "Litter assessment
   output... the raw data are also included in this file." HH/HL/CA's
   equivalent functions are plainly named/documented as "get X data," not
   as an assessment product.

2. A comment in icesDatras's own getDatrasFieldList.R notes that LT's
   public field-list URL covers only "upload-spec" fields, while
   getLTassessment() actually returns many additional HH-style columns
   (ShootLatitude, BottomDepth, Distance, TowDirection, WindSpeed, etc.)
   that aren't in that URL's list at all -- suggesting the live service
   joins in the haul's own HH record when building what it calls the
   assessment output, rather than LT being independently submitted.

Checked the live WSDL directly (2026-07-29): only three litter operations
exist at all (getLitterAssessmentOutput, ...ByUpdateDate,
getSubmissionStatus_LitterData) -- no getLTdata paralleling
getHHdata/getHLdata/getCAdata, so this isn't a case of missing a more-raw
alternative.

Question for ICES Datacenter: is LT intentionally a hybrid -- litter-specific
fields joined with the haul's own HH data at request time -- and if so,
could that be stated in LT's own documentation rather than only inferable
from a roxygen comment and a WSDL field-list discrepancy?
```
