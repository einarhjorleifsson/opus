#' Check every full-fit icesVocab match is fully reflected in the yaml
#'
#' Live, self-contained: resolves every field's icesVocab candidate(s)
#' directly (`op_vocab_resolve_key()` against `op_vocab_get_types()`) and
#' checks real value coverage directly against `.datras/{TABLE}_legacy.parquet`
#' -- it does NOT read `data-raw/DATRAS-vocab-field-audit.csv` or any other
#' cached audit output. That CSV is a point-in-time report (useful on its
#' own terms, referenced by Issue 8/9), but a 2026-08-18 session found it
#' sitting 8 days stale against a rebuilt archive while this validator's
#' first version depended on it -- a cached middleman silently drifting
#' from the truth it was supposed to represent, the same class of problem
#' `details:` completeness was catching for individual fields, just one
#' level up. The live sweep costs about 20 seconds; there's no real
#' performance case for caching it, and caching is exactly what went wrong.
#'
#' What "full-fit" means here, decided fresh each run: `op_vocab_resolve_key()`
#' finds a candidate for the field's legacy name; if multiple, TS_ is
#' preferred over a bare key over AC_ (Issue 8: AC_ is never once correct
#' for a DATRAS field -- if AC_ is the ONLY candidate, that's treated as no
#' valid candidate, not a match); the candidate's own `Description` doesn't
#' start with "see " (a redirect -- Issue 8/9's AgeSource/AgePrepMet/Ship/
#' Country pattern -- needs individual resolution, not a mechanical check);
#' and every real archive value for that field, in every table it appears
#' in, is covered by the candidate's own codes.
#'
#' For every field meeting that bar, checks two things against the yaml
#' (both legacy and curated -- confirms the "pure rename" invariant still
#' holds for these fields specifically, not just trusts it):
#'   1. `values:` is a code -> description map (not a bare list) matching
#'      the vocab's own codes exactly -- the DoorType/DataType lapse.
#'   2. `details:` mentions "vocab" somewhere -- the StandardSpeciesCode
#'      lapse.
#'
#' Also reports (informational, never affects exit status) fields with a
#' candidate that resolves to a redirect, or with real values not fully
#' covered by the candidate's codes -- individual-judgment territory
#' (Issue 9's own Ship/Year/Maturity/StatRec discussion), not a mechanical
#' fix.
#'
#' Usage: Rscript data-raw/validate_vocab_annotations_sync.R
#' Exit status: 0 if every live-confirmed full-fit field is fully
#' documented, 1 otherwise. Requires network access (live icesVocab calls)
#' and a populated .datras/ archive.

suppressMessages({
  devtools::load_all(".", quiet = TRUE)
  library(arrow)
})

CURATED_YAML <- "inst/DATRAS-data-dict.yaml"
LEGACY_YAML  <- "inst/DATRAS-data-dict-legacy.yaml"

dict        <- yaml::read_yaml(CURATED_YAML)
dict_legacy <- yaml::read_yaml(LEGACY_YAML)

flatten <- function(d) {
  rows <- list()
  for (tbl in d$tables) {
    for (col in tbl$columns) {
      rows[[length(rows) + 1]] <- data.frame(
        table = tbl$name, name = col$name,
        type = if (!is.null(col$type)) col$type else NA_character_,
        details = if (!is.null(col$details)) col$details else NA_character_,
        stringsAsFactors = FALSE
      )
      rows[[length(rows)]]$values <- I(list(col$values))
    }
  }
  do.call(rbind, rows)
}

curated <- flatten(dict)
legacy  <- flatten(dict_legacy)
stopifnot(nrow(curated) == nrow(legacy))
curated$legacy_name <- legacy$name
curated$details <- legacy$details  # identical by construction; legacy is primary key for vocab lookup

message("Resolving icesVocab candidates live for ", length(unique(curated$legacy_name)), " distinct field names...")
types <- op_vocab_get_types()

resolve_top_candidate <- function(field_name) {
  r <- op_vocab_resolve_key(field_name, types)
  if (length(r$candidates) == 0) return(NULL)
  pref <- types$prefix[match(r$candidates, types$Key)]
  order_idx <- order(match(pref, c("TS", "bare", "AC")))
  ranked <- r$candidates[order_idx]
  ranked_pref <- pref[order_idx]
  # AC_-only candidate sets are never a valid match for a DATRAS field (Issue 8)
  if (all(ranked_pref == "AC")) return(NULL)
  ranked[ranked_pref != "AC"][1]
}

archive_cache <- new.env()
read_field <- function(table, field) {
  cache_key <- paste(table, field)
  if (!is.null(archive_cache[[cache_key]])) return(archive_cache[[cache_key]])
  # The published archive is current-named (opus dropped the legacy-named
  # copy 2026-08-29); `field` here is a legacy name, so translate it.
  pq <- sprintf(".datras/to_https/raw/%s.parquet", table)
  xw <- op_datras_rename_crosswalk()
  hit <- xw$RecordHeader == table & xw$old_name == field
  pq_field <- if (any(hit)) xw$new_name[hit][1] else field
  v <- tryCatch({
    t <- arrow::read_parquet(pq, col_select = all_of(pq_field))
    unique(as.character(t[[1]][!is.na(t[[1]])]))
  }, error = function(e) NULL)
  archive_cache[[cache_key]] <- v
  v
}

unique_legacy <- unique(curated$legacy_name)
resolved <- data.frame(legacy_name = unique_legacy, candidate = NA_character_,
                        is_redirect = NA, stringsAsFactors = FALSE)
for (i in seq_along(unique_legacy)) {
  cand <- resolve_top_candidate(unique_legacy[i])
  resolved$candidate[i] <- if (is.null(cand)) NA_character_ else cand
  if (!is.null(cand)) {
    desc <- types$Description[match(cand, types$Key)]
    resolved$is_redirect[i] <- startsWith(tolower(trimws(desc)), "see ")
  }
}

with_candidate <- resolved[!is.na(resolved$candidate), ]
message("  ", nrow(with_candidate), " field(s) with a candidate; ",
        sum(with_candidate$is_redirect), " of those are redirects (excluded from the mechanical check below).")

direct_candidates <- with_candidate[!with_candidate$is_redirect, ]

full_fit_names <- character(0)
fit_report <- list()
for (i in seq_len(nrow(direct_candidates))) {
  fname <- direct_candidates$legacy_name[i]
  key <- direct_candidates$candidate[i]
  codes <- tryCatch(op_vocab_get_codes(key)$Key, error = function(e) character(0))
  tables_with_field <- unique(curated$table[curated$legacy_name == fname])
  missing_total <- 0
  for (tb in tables_with_field) {
    real_vals <- read_field(tb, fname)
    if (is.null(real_vals)) next
    missing_total <- missing_total + length(setdiff(real_vals, codes))
  }
  fit_report[[fname]] <- list(key = key, n_codes = length(codes), missing = missing_total)
  if (missing_total == 0 && length(codes) > 0) full_fit_names <- c(full_fit_names, fname)
}

message("  ", length(full_fit_names), " confirmed full-fit (0 real values outside the vocab, in every table checked).")

errors <- character(0)
partial_report <- character(0)

enum_promotion_candidates <- character(0)

for (fname in unique_legacy) {
  rows <- curated[curated$legacy_name == fname, ]
  already_enum <- all(rows$type == "enum")
  if (fname %in% full_fit_names) {
    key <- fit_report[[fname]]$key
    codes <- tryCatch(op_vocab_get_codes(key)$Key, error = function(e) character(0))
    if (!already_enum) {
      # A full live data-fit today does NOT by itself mean "should be enum" --
      # Year/Maturity/StatRec/DepthStratum are full-fit and deliberately NOT
      # enum (Issue 9: an ever-growing ordinal, scale-dependent, a grid too
      # large to enumerate). Promoting a non-enum field is the same kind of
      # judgment call as Tickler/CatIdentifier once were -- worklisted, never
      # applied mechanically.
      enum_promotion_candidates <- c(enum_promotion_candidates, sprintf(
        "%s (%s): live full-fit against '%s' (%d codes), but not type: enum -- individual judgment call, not auto-applied (same shape as the Year/Maturity/StatRec/DepthStratum exceptions Issue 9 already reasons through)",
        fname, paste(unique(rows$table), collapse = "/"), key, length(codes)))
      next
    }
    for (i in seq_len(nrow(rows))) {
      col_values <- rows$values[[i]]
      is_map <- !is.null(col_values) && !is.null(names(col_values)) && all(names(col_values) != "")
      values_match <- is_map && identical(sort(names(col_values)), sort(codes))
      mentions_vocab <- !is.na(rows$details[i]) && grepl("vocab", rows$details[i], ignore.case = TRUE)
      if (!values_match) {
        errors <- c(errors, sprintf("%s/%s (legacy: %s): values: is not a code->description map matching live '%s' (%d codes)",
                                     rows$table[i], rows$name[i], fname, key, length(codes)))
      }
      if (!mentions_vocab) {
        errors <- c(errors, sprintf("%s/%s (legacy: %s): details: doesn't mention icesVocab's '%s'",
                                     rows$table[i], rows$name[i], fname, key))
      }
    }
  } else if (fname %in% direct_candidates$legacy_name) {
    fr <- fit_report[[fname]]
    if (!is.null(fr) && fr$missing > 0) {
      partial_report <- c(partial_report, sprintf("%s: candidate '%s' (%d codes), %d real value(s) not covered -- needs individual judgment, not a mechanical fix",
                                                    fname, fr$key, fr$n_codes, fr$missing))
    }
  }
}

redirect_report <- sprintf("%s: candidate '%s' is a redirect (icesVocab Description starts with \"see \")",
                            with_candidate$legacy_name[with_candidate$is_redirect],
                            with_candidate$candidate[with_candidate$is_redirect])

message("")
message("=== Structural errors (", length(errors), ") ===")
if (length(errors) > 0) for (e in errors) message("  FAIL: ", e) else message("  none")

message("")
message("=== Worklist: redirects, needs individual resolution (", length(redirect_report), ") ===")
for (r in redirect_report) message("  ", r)

message("")
message("=== Worklist: candidate found but real data isn't fully covered (", length(partial_report), ") ===")
if (length(partial_report) > 0) for (p in partial_report) message("  ", p) else message("  none")

message("")
message("=== Worklist: non-enum fields with a live full-fit, possible enum promotion (", length(enum_promotion_candidates), ") ===")
if (length(enum_promotion_candidates) > 0) for (p in enum_promotion_candidates) message("  ", p) else message("  none")

message("")
if (length(errors) > 0) {
  message(length(errors), " issue(s) found.")
  if (!interactive()) quit(status = 1, save = "no")
} else {
  message("OK -- every live-confirmed full-fit icesVocab match is fully documented (values: map + details: mention).")
  if (!interactive()) quit(status = 0, save = "no")
}
