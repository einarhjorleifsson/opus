# Issues found in ICES DATRAS web services

**Prepared by:** opus (github.com/einarhjorleifsson/opus)
**Date:** 2026-08-06
**Scope:** ICES's `DATRASWebService.asmx` (both `getDatrasFieldList` and the
Tier 1 data-retrieval operations), the LT (Litter Assessment) archive data,
and (from Issue 7 onward, added 2026-08-08) the icesVocab service where it
concerns DATRAS fields specifically.

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
4. (Issues 7–8) icesVocab's own live `getCodeTypes`/`getCode` responses
   (`https://vocab.ices.dk/services/api/...`), checked field-by-field against
   both the legacy and current DATRAS name for every one of Tier 1's 52 enum
   fields, not a sample -- see Issue 8 for why checking only one name is not
   sufficient
5. (Issue 9, added 2026-08-09) The same icesVocab check extended to all 190
   Tier 1 fields, not just the 52 already typed `enum` -- see Issue 9 for
   why scoping the check to fields already believed to be candidates is
   itself a blind spot

No finding here rests on a single source, and none rest on any third-party
R package's own internal handling of these services -- every claim traces
directly to the live ICES endpoints listed above.

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
previously did, before this cross-verification step existed).

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

## Issue 7: icesVocab publishes no declared link between a vocab key and the DATRAS field it applies to

**Severity: API/documentation gap -- not a data-quality claim in itself, but the direct cause of Issue 8**

icesVocab's own live metadata (`getCodeTypes`, the source behind
`op_vocab_get_types()`) returns four columns per key: `Key`, a
prefix-stripped name, the prefix itself, and a human `Description` of each
individual *code* within that key. None of this declares which DATRAS
field, table, or operation a given key applies to. Checked the other
direction too: `getDatrasFieldList` (Issue 1-3's subject) has no column
referencing an icesVocab key at all. The two services do not cross-reference
each other anywhere.

The practical consequence: there is no ICES-declared way to answer "which
icesVocab key, if any, applies to `HaulVal`?" The only method available to
any consumer -- opus included -- is inferring it by string-matching a vocab
key's prefix-stripped name against the field's own name and hoping it's the
right one. That inference is corroborated after the fact by checking whether
the real archive's values fit the candidate (see Issue 8's evidence), but
nothing about the *lookup* itself is authoritative -- it is a heuristic
wearing the shape of a lookup.

**Recommendation:** Publish an explicit crosswalk -- e.g. an `icesVocabKey`
column added to `getDatrasFieldList`'s existing per-field rows, or a
DATRAS-scoped index on the icesVocab side -- so consumers can resolve a
field to its vocabulary without reverse-engineering it from naming
convention.

---

## Issue 8: icesVocab's domain prefixes are undocumented, and naming collisions cause silent resolution to the wrong survey type's vocabulary

**Severity: Data risk -- resolves silently to the wrong domain, no error or warning either service could raise**

Direct consequence of Issue 7. icesVocab keys carry a domain prefix (`TS_`,
`AC_`, or none), but the service documents nowhere, in any machine-readable
field, what a prefix means or which ICES data collection it scopes to. This
had to be reverse-engineered by inspecting every key under each prefix: `TS_`
keys are unmistakably DATRAS's own domain (`TS_DYFS_Areas`, `TS_EVHOEarea`,
`TS_NIGFSstrata` -- real DATRAS survey acronyms; and DATRAS's own legacy
field abbreviations directly as keys: `TS_HaulVal`, `TS_GearEx`,
`TS_SpecVal`). `AC_` keys are unmistakably the *combined acoustic-trawl
survey* domain -- a different ICES data collection entirely
(`AC_TransducerBeamType`, `AC_PingAxisIntervalUnit`, `AC_OnAxisGainUnit`,
`AC_SaCategory`, `AC_TriwaveCorrection`).

The hazard: `AC_` also carries entries for general survey-operations
concepts that acoustic surveys record too (they tow calibration hauls), and
several of those entries happen to be spelled out in the same plain English
opus separately chose for DATRAS's own curated field names -- a naming
collision between two unrelated parties, not a shared vocabulary. Resolving
by field name alone, without knowing in advance which prefix is DATRAS's
own, lands on `AC_`'s badly incomplete list and produces no error -- both
keys "exist," both return a superficially valid code list, just for the
wrong survey type. Verified live, three pairs:

| Legacy DATRAS field | Correct key (`TS_`) | Wrong key if resolved by the new name (`AC_`) |
|---|---|---|
| `HaulVal` | `TS_HaulVal`, 7 codes: `A,C,I,M,N,S,V` | `AC_HaulValidity`, 2 codes: `I,V` |
| `GearEx` | `TS_GearEx`, 13 codes | `AC_GearExceptions`, 1 code: `B` |
| `SpecVal` | `TS_SpecVal`, 10 codes | `AC_SpeciesValidity`, 2 codes: `0,1` |

Systematic check, not a sample: every one of Tier 1's 52 enum fields
checked against icesVocab under both its legacy and current DATRAS name.
Of the 27 fields that were ever renamed, 21 have a `TS_` key matching the
legacy name and all 21 give a perfect bidirectional match against the real
archive *by name and description* (see the correction below for two where
that turned out not to mean a per-code data match); 10 of those 27 *also*
have an `AC_` key matching the field's *current* (opus-curated) name, and
in every one of those 10 cases `AC_` is a clear subset, wrong for DATRAS.
Across all 52 fields, `AC_` was never once the correct candidate for a
DATRAS field -- not occasionally wrong, categorically inapplicable, for
this database specifically.

**A second, independent ambiguity in the same prefix, found 2026-08-16:**
`TS_` is not even reliably self-contained. At least two `TS_` keys --
`TS_AgeSource` and `TS_AgePrepMet` -- are themselves non-authoritative:
each one's own icesVocab `Description` field is a bare cross-reference
("see SampleType", "see PreparationMethod") to a *different*, non-`TS_`-
prefixed ("bare") domain, not a real code list in its own right. This
wasn't caught by the systematic check above because that check verified
plausibility by name/description match, not by testing the resolved key's
codes against real archive values one-for-one -- `TS_AgeSource`'s and
`TS_AgePrepMet`'s codes have **zero overlap** with what CA's real
`AgeSource`/`AgePrepMet` columns actually contain, while the domains their
own descriptions point to (`SampleType`, `PreparationMethod`) match
exactly, code-for-code, including a literal lowercase `otolith` code in
`SampleType` (not just its description). Two more `TS_` keys carry the
same kind of redirect (`TS_Ship` -> `SHIPC`, `TS_Country` -> `ISO_3166`),
found by scanning every `TS_` key's own Description for a "see "
cross-reference -- neither affects opus's own resolution today, since
`Ship`/`Country` are typed as open string codes in opus's spec, not small
enums, so opus never attempts a vocab-key match for them. The general
hazard remains for any future field, or any other consumer, that resolves
by prefix and by name alone: a `TS_` match is necessary but was already
known not to be sufficient (the `AC_` collision above), and now isn't even
reliably a real code list rather than a pointer to one -- with nothing
machine-readable distinguishing an authoritative `TS_` key from a redirect
one, only a `Description` string a consumer has to already know to check.
Opus's own proposed mapping table below is corrected for these two fields;
`inst/DATRAS-vocab-correction.csv` and `op_vocab_resolve_datras_key()` were
also fixed to point at the redirect targets, not the `TS_` aliases.

**Recommendation:** Document each vocab domain prefix's scope in a
machine-readable field (which ICES data collection(s) it applies to), and/or
provide a way to scope a vocab lookup to a named collection (e.g. "DATRAS
only") so a consumer cannot silently receive a different survey type's
vocabulary for a same-sounding field name. Separately: where one vocab key
is superseded by or merely aliases another, represent that as a structured
field (e.g. a `supersededBy`/`aliasOf` key) rather than free text inside
`Description` -- a "see X" sentence is invisible to any automated
consumer, including opus's own tooling until this was found by hand.

### Proposed correction (concrete, not just a request)

Rather than only describe the problem, here is opus's own proposal for the
correct DATRAS-field-to-vocab-key mapping. Be precise about what this table
actually is: every "proposed key" below is a **guess by name-matching** --
the field's legacy and current name checked against every live icesVocab
key (Working Principles 8-9: empirical, exhaustive, no skimming), because
that is the only resolution method available at all (Issue 7). "Fits real
data?" records whether that guess happens to fit the real archive's values in both
directions (no real value uncovered, no vocab code unused) -- that's
corroborating evidence for the guess, not proof ICES intended this key for
this field. The full table (`inst/DATRAS-vocab-correction.csv`, generated
by `data-raw/build_vocab_correction.R`) carries this explicitly as its own
`resolution_basis` column on every row, rather than letting a good data fit
read as more authoritative than it is.

This is the same table opus's own tooling now treats as its working default
(`op_vocab_resolve_datras_key()`, `R/vocab.R`) -- one artifact serving both
as this report's recommendation and as opus's internal assumption, so the
two can't silently drift apart. We'd ask ICES to confirm or correct it, and
treat it as provisional -- opus's own best guess, not an ICES-declared fact
-- until ICES formalizes something authoritative per Issue 7's
recommendation above.

| Table | Field (current) | Legacy | Proposed key (name-match guess) | Fits real data? |
|---|---|---|---|---|
| CA | `AgePlusGroup` | `PlusGr` | `TS_PlusGr` | full match |
| CA | `AgePreparationMethod` | `AgePrepMet` | `PreparationMethod` (not `TS_AgePrepMet`, a redirect -- see addendum above) | full match |
| CA | `AgeSource` | `AgeSource` | `SampleType` (not `TS_AgeSource`, a redirect -- see addendum above) | full match |
| CA | `DoorType` | `DoorType` | `TS_DoorType` | full match |
| CA | `Gear` | `Gear` | `Gear` | full match |
| CA | `GearExceptions` | `GearEx` | `TS_GearEx` | full match |
| CA | `GeneticSamplingFlag` | `GenSamp` | *(none)* | no vocab exists |
| CA | `IndividualSex` | `Sex` | `TS_Sex` | full match |
| CA | `LengthCode` | `LngtCode` | `TS_LngtCode` | full match |
| CA | `MaturityScale` | `MaturityScale` | `TS_MaturityScale` | full match |
| CA | `OtolithGrading` | `OtGrading` | `TS_OtGrading` | full match |
| CA | `ParasiteSamplingFlag` | `ParSamp` | *(none)* | no vocab exists |
| CA | `Quarter` | `Quarter` | `TS_Quarter` | full match |
| CA | `RecordHeader` | `RecordType` | *(none)* | no vocab exists |
| CA | `SpeciesCodeType` | `SpecCodeType` | `TS_SpecCodeType` | full match |
| CA | `StomachSamplingFlag` | `StomSamp` | *(none)* | no vocab exists |
| HH | `BycatchSpeciesCode` | `BySpecRecCode` | `TS_BySpecRecCode` | full match |
| HH | `DataType` | `DataType` | `TS_DataType` | full match |
| HH | `DayNight` | `DayNight` | `TS_DayNight` | full match |
| HH | `DoorType` | `DoorType` | `TS_DoorType` | full match |
| HH | `Gear` | `Gear` | `Gear` | full match |
| HH | `GearExceptions` | `GearEx` | `TS_GearEx` | full match |
| HH | `HaulValidity` | `HaulVal` | `TS_HaulVal` | full match |
| HH | `Month` | `Month` | `TS_Month` | full match |
| HH | `PelagicSamplingType` | `PelSampType` | `TS_PelSampType` | full match |
| HH | `Quarter` | `Quarter` | `TS_Quarter` | full match |
| HH | `RecordHeader` | `RecordType` | *(none)* | no vocab exists |
| HH | `Rigging` | `Rigging` | `TS_Rigging` | full match |
| HH | `StandardSpeciesCode` | `StdSpecRecCode` | `TS_StdSpecRecCode` | full match |
| HH | `ThermoCline` | `ThermoCline` | `TS_ThermoCline` | full match |
| HL | `DevelopmentStage` | `DevStage` | `TS_DevStage` | full match |
| HL | `DoorType` | `DoorType` | `TS_DoorType` | full match |
| HL | `Gear` | `Gear` | `Gear` | full match |
| HL | `GearExceptions` | `GearEx` | `TS_GearEx` | full match |
| HL | `LengthCode` | `LngtCode` | `TS_LngtCode` | full match |
| HL | `LengthType` | `LenMeasType` | `TS_LenMeasType` | full match |
| HL | `Quarter` | `Quarter` | `TS_Quarter` | full match |
| HL | `RecordHeader` | `RecordType` | *(none)* | no vocab exists |
| HL | `SpeciesCodeType` | `SpecCodeType` | `TS_SpecCodeType` | full match |
| HL | `SpeciesSex` | `Sex` | `TS_Sex` | full match |
| HL | `SpeciesValidity` | `SpecVal` | `TS_SpecVal` | full match |
| LT | `DataType` | `DataType` | `TS_DataType` | full match |
| LT | `DoorType` | `DoorType` | `TS_DoorType` | full match |
| LT | `Gear` | `Gear` | `Gear` | full match |
| LT | `GearExceptions` | `GearEx` | `TS_GearEx` | full match |
| LT | `HaulValidity` | `HaulVal` | `TS_HaulVal` | full match |
| LT | `LTREF` | `LTREF` | `LTREF` | full match |
| LT | `LTSRC` | `LTSRC` | `LTSRC` | full match |
| LT | `Month` | `Month` | `TS_Month` | full match |
| LT | `Quarter` | `Quarter` | `TS_Quarter` | full match |
| LT | `Rigging` | `Rigging` | `TS_Rigging` | full match |
| LT | `SwellHeight` | `SwellHeight` | `SwellHeight` | full match |

"No vocab exists" (6 fields) is not a gap to fix by force-matching something
-- confirmed empirically that no icesVocab entry exists under either name;
these are legitimately manual/local enums (record-type markers, CA's
Sampling Flag fields).

---

## Issue 9: A full sweep of all 190 Tier 1 fields finds real icesVocab coverage for 5 more fields, invisible without checking every field individually

**Severity: Same root cause as Issue 7 (no declared field-to-key link) -- shown here to hide good, applicable matches, not just cause bad ones**

Issues 7-8 checked Tier 1's 52 fields already curated as `type: enum`.
That scope was itself a blind spot: a field never judged enum-like could
still have real icesVocab coverage nobody had checked, simply because
nothing prompts a consumer to check a field that doesn't already look like
an enum. This issue extends the check to all 190 Tier 1 fields (HH+HL+CA+LT
combined), by legacy name, regardless of current type.

**Results:** 115/190 fields have no name-match candidate at all (expected --
mostly genuine measurements: haul duration, temperatures, depths, etc.).
75/190 have at least one candidate. Of those 75: 46 are the enum fields
Issue 8's table already covers. The remaining 29 are fields NOT currently
typed `enum` that still returned a name match. 16 of those 29 were already
independently discovered and documented in opus's own curation notes
(`Country`, `Survey`, `StatRec`, `AreaType`, `LTPRP`, `LTSZC`, `PARAM`,
`TYPPL`, `SwellHeight`) -- which is itself a useful cross-check: the sweep
independently rediscovers every one of these by the same mechanical
process, corroborating that the method works, not just that it's exhaustive.

The other 13 rows (6 distinct fields, appearing once per table where each
occurs) had never been checked against icesVocab at all before this sweep,
because none had ever been judged enum-worthy. Checked each directly
against the real archive (not just the name match, which alone proves
nothing -- see Issue 7):

| Legacy field | Table(s) | icesVocab key | Real value coverage |
|---|---|---|---|
| `Ship` | HH, HL, CA, LT | `TS_Ship` | **False lead** -- 113 vocab codes, but 88 of 111 real distinct values (79%) aren't among them; a different coding scheme entirely, same shape as the already-known `Survey`/`Country` false leads |
| `Year` | HH, HL, CA, LT | `Year` | 62/62 real distinct years, 0 missing either direction |
| `Maturity` | CA | `TS_Maturity` | 47/47 real values, 0 missing either direction |
| `DepthStratum` | HH | `TS_DepthStratum` | 186/186 real values, 0 missing either direction |
| `Tickler` | HH, LT | `TS_Tickler` | 9/9 real values, 0 missing either direction |
| `CatIdentifier` | HL | `TS_CatIdentifier` | 13/13 real values, 0 missing either direction |

Five of six are genuine, exact, currently-undocumented matches -- not
partial or "close enough," a full bidirectional fit each time. None of
these fields' own ICES field-list descriptions mention icesVocab, and
nothing about `getDatrasFieldList`'s metadata points a consumer toward
checking. They were only discoverable by checking every field against
every vocab key directly and comparing the result against real data --
exactly the gap Issue 7 already describes, now with five additional,
concrete, currently-unused matches as evidence of what that gap costs, not
just what it risks.

**Recommendation:** Same as Issue 7's -- publish the field-to-key
crosswalk. Until then, these five matches (and any others like them) stay
invisible to anyone who doesn't redo this exact full sweep themselves.

---

## Issue 10: icesVocab's own `SwellHeight` code list is used by neither HH's nor LT's real submissions

**Severity: Institutional governance -- a maintained vocabulary that appears unused, not a data-quality problem on submitters' side**

icesVocab has exactly one relevant key for this field: a single, unprefixed
`SwellHeight` entry (not following the usual `TS_`/`AC_` domain-prefix
convention), with 6 non-deprecated codes -- `N` (None, 0m), `L` (Low,
0-1m), `M` (Medium, 1-2m), `H` (High, 2-3m), `VH` (Very high, 3+m), `NR`
(Not recorded). Confirmed there is no second, differently-named key for
the same concept: checked all 580 currently-registered icesVocab keys by
substring match on both `Key` and `Description`, not just the obvious name.

Both HH and LT carry a `SwellHeight` field (LT's own value is a verified
byte-for-byte copy of HH's for the same haul -- 55,914 of 55,914 matched
non-null rows identical, not an independent second measurement). Checked
the full real archive for both, after correcting an unrelated
archive-pipeline bug that had been silently converting this field's own
`-9` sentinel to a null (see opus's own `known-issues.yaml`,
`sentinel_replacement_data_loss` -- opus-internal, not an ICES-side issue):

| Table | Rows | `-9` ("not recorded") | Real measurements | Using any of the 6 vocab codes |
|---|---|---|---|---|
| HH | 145,958 | 108,698 (74.47%) | 37,260 | **0** |
| LT | 75,310 (57,940 non-null) | 19,005 (32.80% of non-null) | 38,935 | **0** |

Every real (non-`-9`) value in both tables is a continuous metric
measurement (HH: 0-60m; LT: 0-25m), never one of the vocab's 6 category
codes. This is not a data-quality problem in the usual sense -- nothing
here is wrong or missing from a submitter's perspective, since neither
table ever attempts to use the coded scheme at all. It reads instead as
ICES maintaining a controlled vocabulary that real DATRAS Tier 1
submissions have never adopted in practice, in either of the two tables
that carry this field.

**Recommendation:** Confirm whether this vocabulary is genuinely intended
for DATRAS Tier 1 submissions at all, or whether it was designed for a
different DATRAS context (or a different ICES data product entirely) that
never fed into HH/LT the way its presence here would suggest. If it is
intended for Tier 1, DATRAS's own submission guidance doesn't appear to
communicate it to data providers, since 100% of real submissions in both
carrying tables use a continuous measurement instead.

---

## Suggestion for consideration (not a bug report)

Everything above documents a confirmed error, gap, or unused feature in
an existing ICES service. This section is different in kind: a design
idea for ICES's own future consideration, not a defect being reported.

### A single surrogate haul identifier, instead of an 8-field composite key

HL, CA, and LT each reference haul-level data in HH via the same 8-field
composite identifier (`Survey`, `Year`, `Quarter`, `Country`,
`Platform`/`Ship`, `Gear`, `StationName`/`StNo`, `HaulNumber`/`HaulNo`).
Beyond the join key itself, this analysis found HL/CA/LT also each carry
a substantial number of additional columns that are literal copies of
HH's own values for the same haul -- confirmed for roughly 30 fields
across the three tables (gear geometry, positions, environmental
readings), at 100% or near-100% match rates.

A single, ICES-assigned surrogate identifier per haul -- present on HH and
carried onto every haul-referencing record in HL/CA/LT -- would let the
8-field composite key, and potentially some of the other repeated
columns, be replaced by one join column. It would also sidestep
composite-key edge cases this analysis found: CA's own well-documented
`-9`/orphaned-record gap (opus's own known issues,
`ca_haulno_unlinkable_to_hh`/`ca_haulno_tail_mismatch`) is a direct
consequence of the
composite key's correctness depending on several independently-submitted
fields all agreeing at once, something a single assigned identifier would
not be exposed to in the same way.

This isn't something opus can adopt unilaterally -- it would require a
real change to ICES's own submission format, not a documentation or
vocabulary fix, so it is offered here as an idea for ICES's own future
consideration rather than a request for immediate action.

**Update, 2026-08-10:** two of the five real matches (`Tickler`, `CatIdentifier`) were re-verified and adopted into opus's own curated spec as `type: enum` -- `inst/DATRAS-data-dict.yaml` now reflects this directly. Included here for the record, not because it changes the finding: this is opus's own downstream reaction to a gap that's still ICES's to close. The other three were deliberately left as-is, each for a distinct, already-documented reason rather than a shared threshold: `Year` is a continuously-advancing ordinal (next year needs a code that doesn't exist yet), not a fixed closed set, regardless of icesVocab happening to enumerate past years as codes; `Maturity`'s own field description says its coding depends on the sibling `MaturityScale` field, so `TS_Maturity`'s 63 codes are plausibly a union across several distinct scales, not one flat list; `DepthStratum`'s own description says strata are survey-specific, in tension with treating one vocab key as universal. None of that applies to `Tickler` (a real gear-count code, not growing) or `CatIdentifier` (already independently documented as "a coded scheme, not a sequence" before this vocab match was even found).
