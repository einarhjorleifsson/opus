
<!-- README.md is generated from README.Rmd. Please edit that file -->

# opus

ICES DATRAS Data Dictionary and Known-Issues Registry

## Focus: The YAML

**opus** produces three machine-readable YAML specifications that
document ICES DATRAS as it actually is:

1.  **`DATRAS-imbus.yaml`** — The archive-side specification of Tier 1
    exchange tables (HH, HL, CA, LT), verified against the full
    published archive: field names, types, units, ranges, constraints,
    relationships, and domain glossary. Enum values are restricted to
    codes actually observed in submissions, and physical non-negativity
    bounds are expressed as assertions. Conforms to [data-dict.yaml
    v0.1.0](https://data-dict.tidyverse.org/).

2.  **`DATRAS-ices.yaml`** — ICES’s own documented view of the same
    format, consolidated faithfully from ICES’s four metadata sources
    (WSDL, getDatrasFieldList, icesVocab, the field-description
    spreadsheet) with no corrections applied. Where ICES’s sources
    disagree, the conflict is noted, not resolved. The diff between this
    file and `DATRAS-imbus.yaml` is the corrections story.

3.  **`DATRAS-known-issues.yaml`** — Registry of where ICES’s
    specification and the submitted data part company. Documents type
    mismatches, undocumented codes, incomplete vocabularies, and their
    escalation status.

The R package is **thin tooling** around these YAML files: - Validation
functions for pre-submission checks - Generation scripts (seed from WSDL
→ curate against real data) - Articles and documentation

## Why this approach

- **Portability**: YAML specs are language-agnostic; not locked into R.
- **Minimal maintenance**: No computational code to break or update.
- **Clarity**: YAML-first signals “this is a reference specification,”
  not a convenience library.
- **Upstream focus**: Schema problems are escalated to ICES, not hidden
  in downstream workarounds.
- **Auditable**: Every field spec, correction, and issue traces back to
  real evidence (WSDL, data, or explicit review notes).

## Quick start

### Install

``` r
remotes::install_github("einarhjorleifsson/opus")
```

### Load dictionaries

``` r
library(yaml)

# Data dictionary (archive-side, empirically grounded)
dict_path <- system.file("DATRAS-imbus.yaml", package = "opus")
dict <- yaml::read_yaml(dict_path)

# ICES's own documented view of the format
ices_path <- system.file("DATRAS-ices.yaml", package = "opus")
ices_dict <- yaml::read_yaml(ices_path)

# Known-issues registry
issues_path <- system.file("DATRAS-known-issues.yaml", package = "opus")
issues <- yaml::read_yaml(issues_path)
```

### Validate your submission data

``` r
library(opus)

# Validate DATRAS HH table against spec
result <- op_validate_data(
  data_path = "my_submission.parquet",
  table = "HH",
  dict_path = system.file("DATRAS-imbus.yaml", package = "opus")
)

# Check results
result$valid  # TRUE if all values conform
result$result       # Detailed validation report
```

Available functions:

- `op_validate_spec(dict_path)` — Check YAML spec conformation
- `op_validate_meta(data_path, table, dict_path)` — Validate column
  names/types
- `op_validate_data(data_path, table, dict_path)` — Validate values
  against constraints
- `op_validate_full(data_path, table, dict_path)` — Run all three checks
- `op_inspect_parquet(parquet_path)` — See data-dict CLI’s view of your
  parquet schema

## File reference

**`inst/DATRAS-imbus.yaml`**: - Field definitions (type, range, units,
enums, constraints) - Source: ICES WSDL + icesVocab + field-description
spreadsheet, curated and verified against the real archive - Enum values
restricted to archive-observed codes; a value outside the list in new
data fails validation and needs review (data error or genuinely new
code) - Use when: “Is this value valid?” or “What does this field mean?”

**`inst/DATRAS-ices.yaml`**: - What ICES’s own metadata sources
currently document, uncorrected - Use when: “What does ICES say this
field is?” or “Where do ICES’s sources disagree?”

**`inst/DATRAS-known-issues.yaml`**: - Schema and vocabulary gaps in
ICES’s specifications (incomplete vocabularies, type mismatches,
undocumented codes), and systemic submission patterns a reader of the
archive must know about - Not a QC log: whether a value is plausible in
context is decided downstream, in obus and imbus - Use when: “Why did
validation fail?” to determine if it’s a spec problem or submission
error

## About the project

opus serves three consumers:

- **obus** — the R access layer: reads the archive opus publishes and
  builds the derived catch tables
- **imbus** — EU research project; uses opus to track metadata issues
  with ICES
- **icesDatras** — ICES’s R client for the DATRAS web service; opus does
  not depend on it, and calls the services directly

For implementation details and working principles, see `AGENTS.md` and
vignettes.

## Development notes

- **Never edit the shipped `.yaml` files by hand** — they are
  regenerated by the `data-raw/spec/` pipeline (`spec_02_curate_dict.R`
  → `spec_03_translate_new_names.R`, and `spec_04_build_ices_yaml.R` for
  the ICES view), which is the source of truth
- Scripts in `data-raw/` are grouped by concern: `spec/` (dictionary
  pipeline), `archive/` (download/parse/consolidate), `audit/`
  (on-demand checks), `assets/` (generated outputs)
- Requires `data-dict` CLI for full validation (see
  `data-raw/audit/validate_against_datadict.R`)
- Versioning: patch (0.1.1) for typos; minor (0.2.0) for new content;
  major (1.0.0) when stable

## License

CC0 (public domain)

## Contact

Einar Hjörleifsson (<einar.hjorleifsson@hafogvatn.is>)
