# Issues found in ICES DATRAS web services

**Prepared by:** opus (github.com/einarhjorleifsson/opus)
**Date:** 2026-08-06
**Scope:** ICES's `DATRASWebService.asmx` (both `getDatrasFieldList` and the
Tier 1 data-retrieval operations) and the LT (Litter Assessment) archive data.

## How this was verified

Every finding below was checked against **at least two independent live
sources**, never against documentation alone:

1. `getDatrasFieldList` — the live field-list metadata endpoint
   (`https://datras.ices.dk/WebServices/DATRASWebService.asmx/getDatrasFieldList`)
2. Each operation's own ASMX description page (e.g.
   `?op=getCAdata`), which embeds a sample response showing the field
   names and types the server's own code actually generates — independent
   of the separately-maintained metadata service in (1)
3. The real Tier 1 archive data (145,958 HH rows, 13,754,042 HL rows,
   5,865,076 CA rows, 75,310 LT rows; 1965–2026, downloaded 2026-08-05)

No finding here rests on a single source, and none rest on the `icesDatras`
R package's own internal patches, which we found to be undocumented,
unsourced from ICES, and in at least one case (see Issue 4) still wrong.

**2026-08-08 re-verification:** Issues 1–3 (LT's real field set, the
`Ship`/`StNo`/`HaulNo` renames, and the phantom `RecordType` field)
independently re-confirmed via a third method not used above: parsing raw
LT exchange XML directly (at least one non-empty file per survey, all 28
surveys) and diffing the resulting real field-tag set against
`inst/DATRAS-data-dict.yaml`'s own legacy-name annotations for all four
Tier 1 tables, not just LT. Zero discrepancies in either direction for HH,
HL, CA, or LT.

---

## Issue 1: `getDatrasFieldList` covers only 22 of LT's 58 real fields

**Severity: Data quality / documentation gap**

The live `getDatrasFieldList` endpoint documents 22 fields under
`RecordHeader = "LT"`. The `getLitterAssessmentOutput` operation's own ASMX
page, and the real archived LT data, both independently show **58** real
fields — an exact match between the two, confirming 58 is correct and the
field-list's 22 is the gap, not the other way round.

The 36 undocumented real fields include ordinary gear, environment, and
timing fields shared with HH/HL/CA (e.g. `SweepLngt`, `GearEx`, `DoorType`,
`TimeShot`, `HaulDur`, `StatRec`, `Rigging`, `Tickler`, `SwellHeight`) — none
of these appear under `RecordHeader = "LT"` in the field-list at all.

**Recommendation:** Extend `getDatrasFieldList`'s LT section to cover all 58
fields `getLitterAssessmentOutput` actually returns.

---

## Issue 2: `getDatrasFieldList` wrongly claims 3 LT legacy fields were never renamed

**Severity: Data quality — actively incorrect, not just incomplete**

Of the 22 LT fields the field-list *does* document, 3 real legacy fields are
claimed to have no rename at all (`FieldNameOld == FieldName`):

| Real legacy field | Field-list's current-name row | Field-list wrongly sets `FieldNameOld` to |
|---|---|---|
| `Ship` | `Platform` | `Platform` (should be `Ship`) |
| `StNo` | `StationName` | `StationName` (should be `StNo`) |
| `HaulNo` | `HaulNumber` | `HaulNumber` (should be `HaulNo`) |

The field-list's own HH, HL, and CA sections correctly document these same
three legacy fields as renamed (`Ship`→`Platform`, `StNo`→`StationName`,
`HaulNo`→`HaulNumber`) — only the LT section claims otherwise. Confirmed
against the real archived LT parquet data (columns are literally named
`Ship`, `StNo`, `HaulNo`, matching HH/HL/CA) and independently against
`getLitterAssessmentOutput`'s own ASMX sample response.

Opus's own resolution of this (LT's `Ship`/`StNo`/`HaulNo` mapped to
`Platform`/`StationName`/`HaulNumber`, matching the other three tables) is
recorded in `inst/DATRAS-data-dict.yaml`'s own field annotations, not here —
this section reports ICES's metadata bug; it isn't opus's naming ledger.

**Recommendation:** Correct the LT section's `FieldNameOld` for `Platform`,
`StationName`, and `HaulNumber` to `Ship`, `StNo`, and `HaulNo` respectively,
matching HH/HL/CA.

---

## Issue 3: `getDatrasFieldList` documents a LT field that doesn't exist

**Severity: Data quality — inverse of Issues 1–2**

Under `RecordHeader = "LT"` (the metadata service's own table selector — a
different sense of "RecordHeader" from the per-record field below), the
field-list documents a per-record legacy field `RecordType` (current name
`RecordHeader`). Neither `getLitterAssessmentOutput`'s own live sample
response nor the real archived LT data contain any such column — LT
genuinely has no record-type indicator field at all, unlike HH/HL/CA.

**Recommendation:** Either confirm LT is intentionally exempt from carrying
a `RecordType`/`RecordHeader` field and remove the phantom entry from the
field-list, or add the field to the live `getLitterAssessmentOutput`
response if one was intended.

---

## Issue 4: `getDatrasFieldList`'s CA `IndividualAge` row is unverifiable

**Severity: Data quality — orphaned metadata**

The field-list pairs `FieldName = "IndividualAge"` with
`FieldNameOld = "AgeRings"` for CA. `"AgeRings"` is not a real CA field —
confirmed against both the real CA archive and `getCAdata`'s own live ASMX
sample response, both of which show the real field is named `Age`.

Because the row's old-name half is already shown not to correspond to
anything real, its new-name half (`"IndividualAge"`) cannot be trusted to
apply to the real `Age` field either — it may be stale, a typo, or describe
a field removed from `getCAdata` at some point without the field-list being
updated to match. We have deliberately **not** treated `Age` as renamed to
`IndividualAge` on the strength of this row alone (opus's own spec
previously did, inherited from the `icesDatras` R package's own,
undocumented decision to trust this same row — see the note at the end of
this report).

**Recommendation:** Confirm whether `Age` should be documented as
`IndividualAge`, and if so, correct the row's old-name to `Age` (not
`AgeRings`) so the pairing is actually verifiable.

---

## Issue 5: `getDatrasFieldList` is missing `DateofCalculation` (HH) and `DateofCalculation`/`Valid_Aphia` (HL)

**Severity: Documentation gap**

`DateofCalculation` is a real column in both the HH and HL archives
(server-inserted processing timestamp), and `Valid_Aphia` is a real column
in HL (server-validated WoRMS AphiaID) — none of the three appear under
their respective `RecordHeader` in `getDatrasFieldList` at all, under any
name.

**Recommendation:** Add these fields to the field-list's HH and HL
sections.

---

## Issue 6: LT's `Depth` and `BottomDepth` are duplicate columns

**Severity: Data quality — genuine data redundancy, not a metadata issue**

Unlike Issues 1–5, this is not about the field-list metadata service — it's
about the archived data itself. LT's real archive carries **two separate
columns**, `Depth` and `BottomDepth`, that are byte-for-byte identical
across all 75,310 rows (100% populated in both, 0 differences, 0
one-sided nulls — verified directly 2026-08-06). This is not a naming
variant of the same field (as Issue 2's fields are) — both columns
genuinely exist side by side with fully duplicate content.

**Recommendation:** Confirm whether this duplication is intentional (e.g. a
legacy field retained for backward compatibility) or an artifact of how LT
records are assembled, and if the latter, remove the redundant column from
future LT submissions/exports.

---

## A related, non-ICES note: `icesDatras`'s own patch should also be retired

Not an ICES-service issue, but relevant context: the widely-used
`icesDatras` R package's `getDatrasFieldList()` function silently applies
its own hand-typed correction on top of the live endpoint above — a ~40-row
fabricated table for LT, plus a few explicit overrides — undocumented in
its own source and not sourced from ICES. It happens to get Issues 1–2
empirically right (matching real data) via its maintainers' own domain
knowledge, but does **not** resolve Issue 4 (it still trusts the orphaned
`IndividualAge` row), and of course doesn't touch Issues 3, 5, or 6 at all.
We'd suggest the `icesDatras` maintainers retire that patch in favour of
querying each operation's own live ASMX response directly (exactly as this
report's verification method does) once the ICES-side issues above are
fixed — a package-internal workaround stops being useful once its target
service is corrected, and stops being *silently* wrong in the meantime.
