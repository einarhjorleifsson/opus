# DATRAS read-route benchmarks, 2026-09-14

Exploratory console session (R 4.5.2, aarch64-apple-darwin, 14 cores;
duckdb 1.4.0 + `webbed` community extension, data.table 1.18.6,
icesDatras 1.5.3). Nothing here is shipped code; this file preserves
the measurements behind the DEVLOG entry of the same date.

## XML parse: full HL archive tree (.datras/xml/HL, 973 files, 13.56 GB, 14,423,771 rows)

| reader | elapsed |
|---|---|
| `archive_04_parse_phase2.R`'s per-file Python/`ElementTree` -> TSV -> `read.delim` | 549 s |
| `webbed::read_xml(glob, all_varchar=true, union_by_name=true)`, cold cache | 296 s |
| same, warm cache | 175 s |
| `read_xml(glob, columns=<explicit VARCHAR map>, union_by_name=true)`, cold cache | 23 s |
| same, warm cache | 16 s |

The explicit `columns=` map was built from `op_datras_operation_types("getHLdata")`
with every field declared VARCHAR (the pipeline's "parse as character, cast
later via WSDL" design). Default (sampled) type inference is **not** safe:
it inferred `SpecCodeType` as INTEGER from early `W` values and errored on a
later `U` (HL_NS-IBTS_1989_Q1, HL_NS-IBTS_2017_Q3).

Correctness: parsed -> `op_cast_wsdl_types()` -> `op_rename_to_new()` ->
`op_strip_sentinels()` -> `op_cast_to_spec()` was compared against the
existing reference parquet for all 973 files: 971 value-identical
(`waldo::compare`, zero tolerance, full-row sorted), 2 with no reference
because both parsers agree the files contain zero records.

## Three-route speed test, HL/DWS (4 cells, 18 MB XML, 20,143 rows; all routes content-identical)

| route | elapsed |
|---|---|
| XML from archive on disk (`read_xml`, explicit columns) + chain | 0.24 s |
| CSV live (one zip for the whole survey) + typed `read_csv` + chain | 1.36 s |
| XML live (4 sequential per-cell ASMX GETs) + `read_xml` + chain | 6.10 s |
| XML live, 4 concurrent backgrounded `curl` + glob `read_xml` + chain | ~4.6 s |

Parallelism bought only ~1.3x: wire size (18 MB XML vs ~2.7 MB zipped CSV
for identical rows), not concurrency, is the bottleneck; the server appears
to throttle per connection. CSV-live is the right default for whole-survey
pulls; XML-live remains necessary only for LT (not served by the CSV API)
and single-cell queries.

## Live NS-IBTS HL head-to-head (4,101,389 rows; 48.7 MB zip, 566 MB CSV)

| route | end-to-end | parse only | typeset |
|---|---|---|---|
| `icesDatras::getDatrasUnaggregated("HL","NS-IBTS","1965:2030","1:4")` | 19.8 s | `fread` 1.13 s | `formatDatras` ~0.005 s |
| `download.file` + unzip + DuckDB `read_csv(columns=<typed>)` + opus chain | 23.8 s | `read_csv` 1.38 s | fused into the read |

End-to-end difference is network jitter; the ~49 MB download dominates both.
Values differ in exactly one column: `icesDatras` silently truncates all
189,106 fractional `NumberAtLength` values (9.85 -> 9) -- see
`data-raw/issue-drafts/icesDatras-numberatlength-truncation.md`. The two
downloaded zips are byte-identical in size (48,705,893 bytes), and `fread`
+ `formatDatras(record="HL")` applied by hand to the same file preserves
the fractions, isolating the bug to `getDatrasUnaggregated()` itself.

## Operational lessons

- `read_xml()` silently parses **truncated** XML and returns a partial row
  count with no error (observed on a `curl -m 20` cut-off: 18,508 of 47,663
  rows, no warning). Any reader built on it must verify completeness first
  (closing root tag or record count).
- DuckDB cannot read the HTTPS URL directly (SSL certificate error via
  httpfs); a tempfile download step (`download.file`) remains necessary.
- DuckDB cannot read inside a zip (gzip only); unzip-to-tempfile stays.
- `read_csv(..., columns=)` must cover every field in the file, including
  ones to be dropped (`ScientificName_WoRMS` was read as VARCHAR, then
  dropped); do **not** pass `nullstr='-9'` (would violate the sentinel
  policy).
- `getDatrasUnaggregated()` must be called with year/quarter as range
  *strings* ("1965:2030"); vector inputs vectorize the URL via `paste0`
  and corrupt the download (observed as an unzip failure).
- LiverWeight is genuinely CSV-API-only: documented in
  `getDatrasFieldList()` and the field-description spreadsheet
  (decimal2, "Weight of liver when sampled"), served by neither
  `getCAdata` nor `getCAdataSp` (34 fields, verified live), and absent
  from every file in `.datras/xml` (grep, 0 hits).
