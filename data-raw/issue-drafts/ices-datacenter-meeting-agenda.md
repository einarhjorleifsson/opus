# DATRAS Metadata Governance — Agenda for Discussion with ICES Datacenter

**Date:** September 2026  
**Participants:** Einar Hjörleifsson (IMBUS/MRI), Vaishav Sinha (ICES Datacenter)  
**Purpose:** Identify and resolve structural gaps between ICES's published DATRAS
metadata sources and the data as actually submitted and served.

---

## Background

IMBUS WP2 is building a reference specification for DATRAS Tier 1 exchange data
(HH, HL, CA, LT). This work required consolidating metadata from four separate
ICES sources: the WSDL, `getDatrasFieldList`, icesVocab, and the DATRAS field
description spreadsheet. The sources frequently disagree with each other and with
the live data. The agenda below covers the issues that require decisions or
corrections on ICES's side.

---

## Agenda

### 1. Single authoritative field specification

**Problem.** There is no single authoritative reference for the DATRAS exchange
format. Four sources exist — WSDL, `getDatrasFieldList`, field description
spreadsheet (dated Excel file), and icesVocab — each maintained independently,
with no stated owner and no process for keeping them in sync. Consumers must
reconcile all four and accept that any one of them may be wrong.

**What we need from ICES.**
- Designate one source as authoritative for: field names, types, descriptions,
  and valid code lists.
- Define a maintenance process: who updates it, how often, and how discrepancies
  between sources are resolved.
- Provide a stable URL or API endpoint for the current version (the current Excel
  file has a dated filename and no permanent link).

---

### 2. Field naming: complete the rename or revert it

**Problem.** DATRAS exchange data (XML, on the wire) still uses legacy field
names (e.g. `Ship`, `GearEx`, `StNo`, `HaulNo`). The field description
spreadsheet uses ICES's intended new names (e.g. `Platform`, `GearExceptions`,
`StationName`, `HaulNumber`). The `getDatrasFieldList` service documents a
rename mapping, but that mapping contains at least six confirmed errors (see
Agenda item 3). The `…NewHeaders` web service operations exist alongside the
old ones, suggesting the migration is in progress but incomplete.

The result is that no consumer can be sure which name to use, or which name a
given documentation source refers to.

**What we need from ICES.**
- A firm timeline for the field rename at the service level (when will the XML
  exchange actually use new names?), or a decision to revert to legacy names
  permanently.
- Until the rename is complete at the service level: a correct, stable mapping
  from legacy names to new names, replacing the current `getDatrasFieldList`
  output (which has confirmed errors).
- Clarify whether the field description spreadsheet is documenting the current
  state (legacy names on the wire) or the intended future state (new names).

---

### 3. Confirmed errors in `getDatrasFieldList`

**Problem.** Six errors have been identified in `getDatrasFieldList`, ICES's own
field-list metadata service:

1. **LT coverage gap** — `getDatrasFieldList` does not return LT field metadata
   at all, despite LT being an active Tier 1 exchange table.
2. **Wrong LT renames** — Several LT fields are documented with incorrect
   new-name targets.
3. **Phantom field** — One field is listed that does not exist in the live WSDL
   or in any real submission.
4. **Unverifiable CA rename** — One CA field rename cannot be confirmed from any
   other source.
5. **Missing entries** — Fields present in the live WSDL are absent from
   `getDatrasFieldList`.
6. **Data-duplication miss** — A field that carries duplicated information is not
   flagged as such.

**What we need from ICES.**
- Confirmation that these errors have been logged with the Datacenter.
- A corrected `getDatrasFieldList` response, or deprecation of the service if it
  is no longer maintained.

---

### 4. Sentinel value policy: −9 means two different things

**Problem.** ICES uses −9 as a general "no information" sentinel across DATRAS
fields. However, in at least five enum fields, −9 is documented in icesVocab as
a substantive code with a real meaning (e.g. `Tickler`: −9 = "No ticklers are
allowed"; `PlusGr`: −9 = "No plus group"). In the remaining fields, −9 means
absence of information and should be treated as null.

The same value cannot mean both "missing" and "real answer" within the same data
system without an explicit, field-by-field policy. Currently no such policy is
published. Consumers must guess.

**What we need from ICES.**
- A field-by-field declaration: for each field where −9 appears, does it mean
  "no information" (strip to null on download) or a substantive code (retain)?
- This declaration should be incorporated into the authoritative specification
  (see item 1).
- If −9 is a substantive code for a field, it should appear in icesVocab with a
  label that clearly distinguishes it from the "no information" sentinel (e.g.
  "No ticklers are allowed", not "Not known").

---

### 5. icesVocab code lists are not scoped to DATRAS

**Problem.** icesVocab code lists are cross-domain — they cover ICES data
products beyond DATRAS. For many fields, the full icesVocab list contains codes
that are not applicable to DATRAS submissions and have never appeared in real
exchange data. Example: `PreparationMethod` (mapped to icesVocab key
`PreparationMethod`) has many codes in the vocabulary; DATRAS submissions contain
only a small subset. Pointing submitters at the full list is misleading and
creates unnecessary ambiguity about what is valid.

**What we need from ICES.**
- For each DATRAS field that references an icesVocab key: a published,
  DATRAS-scoped subset of valid codes.
- Either as a filtered view in icesVocab, or as part of the authoritative field
  specification (item 1).
- Where a field has no icesVocab representation at all (codes defined only by
  convention or archive observation), this should be stated explicitly.

---

### 6. "Mandatory" is ambiguous between upload and download

**Problem.** The field description spreadsheet marks many fields as `Mandatory`.
However, the same fields contain large proportions of null values in the
downloaded exchange data, because sentinel values (−9) submitted by countries are
treated as "no information" and resolved to null on download.

"Mandatory" cannot simultaneously mean "must be present in a submission" and
"will be present in a download" when the download strips the only allowed value
for that field.

Two concrete examples: `SweepLngt` is Mandatory in the spreadsheet but null in
~40% of HH downloads. `Tickler` is non-mandatory but −9 in ~78% of HH downloads,
where that −9 is a real documented answer.

**What we need from ICES.**
- A clear distinction between upload-mandatory (what a submitting country must
  provide) and download-guaranteed (what a data consumer can rely on being
  present after ICES processing).
- For upload-mandatory fields where −9 is the only permissible value when the
  information is unavailable: state this explicitly in the specification, so that
  neither submitters nor consumers are confused.

---

### 7. Undocumented values in live submissions

**Problem.** Two field values appear in live DATRAS downloads that are not
documented in icesVocab or the field description spreadsheet:

- `HH.ThermoCline` = `"y"` (3 rows in the archive). icesVocab `TS_ThermoCline`
  has no code `"y"`; the documented codes are `"Y"` and `"N"` (case-sensitive).
  This may be a case-sensitivity issue or a genuine undocumented code.
- `LT.LTSRC` = `"sba"` (1 row). Not present in any icesVocab list for this field.

**What we need from ICES.**
- Confirm whether `ThermoCline = "y"` is a case-sensitivity error in the ICES
  system (should be `"Y"`) or a legitimate code that should be added to the
  vocabulary.
- Confirm whether `LTSRC = "sba"` is a data-entry error that should be flagged
  back to the submitting country, or a code that should be added to the vocabulary.

---

## Summary: what this meeting needs to produce

| Item | Decision needed |
|------|----------------|
| 1. Single spec | Who owns it; what format; stable URL |
| 2. Field naming | Complete rename timeline, or revert; corrected crosswalk |
| 3. `getDatrasFieldList` errors | Acknowledgement; corrected output or deprecation |
| 4. Sentinel policy | Field-by-field −9 declaration |
| 5. icesVocab scoping | DATRAS-scoped code subsets per field |
| 6. Mandatory definition | Upload-mandatory vs download-guaranteed |
| 7. Undocumented values | `ThermoCline = "y"` and `LTSRC = "sba"` disposition |

---

*Prepared by IMBUS WP2 (Einar Hjörleifsson, MRI) based on systematic audit of
DATRAS Tier 1 metadata conducted September 2026. Supporting evidence available
on request: full field-gap audit, known-issues registry, and the consolidated
reference artifact (Excel/DuckDB) produced from the four ICES metadata sources.*
