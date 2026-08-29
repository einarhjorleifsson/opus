# DRAFT — comment to post on ices-tools-prod/icesDatras#63
#
# Not posted. Review and paste into
# https://github.com/ices-tools-prod/icesDatras/issues/63
#
# ---------------------------------------------------------------------------

Since this may take a while to fix upstream, here is a workaround, plus the
evidence for the one thing it has to assume — *which* two columns are missing.

### The one-line cause

`fread(fill = TRUE)` pads short rows at the **end**, so the trailing value goes
into the first unfilled slot (`EDOM`). Reading positionally and binding that
value to the **last** header name instead puts everything back.

### Establishing that column 70 really is `DateofCalculation`

I checked this against an independent copy of the same data — an archive built
from the ASMX XML service — joining on the 8-field composite haul key
(Survey, Year, Quarter, Country, Platform, Gear, StationName, HaulNumber):

* **All 10,379 NS-IBTS rows where CSV column 70 is `-9` have a NULL
  `DateofCalculation` in the XML-derived data.** A perfect correspondence, and
  one no other column would produce. This is the strongest single piece of
  evidence.
* **20,267 of the 25,231 date-valued rows match exactly.** The 4,964 that differ
  all carry an *older* stamp in the CSV, which is consistent with
  `DateofCalculation` being a per-product reprocessing timestamp rather than a
  per-haul fact — so not evidence against the identification.
* For the small `DWS` survey the match is **72 of 72, exactly**.
* Column 70 contains only a `YYYYMMDD` date or `-9` across every survey checked;
  column 69 is uniformly `-9`, consistent with `SurveyIndexArea` being
  unpopulated.

So the absent columns are `EDOM` and `ReasonHaulDisruption`, and the trailing
value is `DateofCalculation`.

### Workaround

```r
read_datras_csv_hh <- function(zip_path) {
  d <- tempfile(); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  utils::unzip(zip_path, exdir = d)
  csv <- list.files(d, pattern = "DATRASDataTable\\.csv$", full.names = TRUE)

  header <- scan(csv, what = "", nlines = 1L, sep = ",", quiet = TRUE,
                 fileEncoding = "UTF-8-BOM")
  body <- utils::read.csv(csv, header = FALSE, skip = 1L, colClasses = "character",
                          stringsAsFactors = FALSE, fileEncoding = "UTF-8-BOM")

  if (length(header) == ncol(body)) {      # already fixed upstream
    names(body) <- header
    return(body)
  }
  # refuse rather than guess if the export changes shape
  stopifnot(length(header) == 72L, ncol(body) == 70L,
            identical(header[70:71], c("EDOM", "ReasonHaulDisruption")))

  names(body) <- c(header[1:69], header[72])   # trailing value -> DateofCalculation
  body$EDOM <- NA_character_
  body$ReasonHaulDisruption <- NA_character_
  body[header]                                  # declared column order
}
```

Checked: `DWS` returns `DateofCalculation` identical to the XML-derived values
for all 72 rows; `SE-SOUND` returns 151 × 72 with the declared column order
preserved and both absent columns `NA`; and a well-formed file passes through
untouched (`HL`, 30/30, returned 11,710 × 30 with no fix applied).

### Caveats

This encodes an assumption about the file as served today, which is why it
`stopifnot()`s on the shape rather than guessing — if the export changes it will
fail loudly instead of silently re-misaligning. It is a stopgap for consumers,
not a substitute for fixing the export or for validating in the package.
