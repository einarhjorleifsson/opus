#' Full-coverage icesVocab audit: every DATRAS Tier 1 field, not just enums
#'
#' `data-raw/build_vocab_correction.R` only ever checks the 52 fields opus
#' has already curated as `type: enum` -- the same blind spot Working
#' Principle 9 ("audit exhaustively") exists to catch. A field never judged
#' enum-like could still have a real (or spuriously matching) icesVocab
#' entry nobody has checked, because "is this field even a candidate" was
#' never itself audited. This script checks all ~190 Tier 1 fields.
#'
#' Two separate, independently-reportable kinds of inference (never
#' collapsed into one "the mapping" -- see AGENTS.md's Working Principles
#' 8-9 and data-raw/ICES_ISSUE_REPORT.md, Issues 7-8):
#'
#' Stage 1 -- NAME-match inference (legacy DATRAS field name <-> icesVocab
#' domain key). Always a guess: icesVocab publishes no declared link
#' between a domain key and the DATRAS field it applies to (Issue 7).
#' `op_vocab_resolve_key()` strips known prefixes (TS_/AC_) from every
#' icesVocab key and matches on the stripped name. Three outcomes, all
#' recorded: zero candidates (expected for most measurement fields, not
#' itself a problem), one candidate (still just a name coincidence, not a
#' verified link), or multiple/ambiguous candidates (the TS_/AC_ collision
#' shape from Issue 8).
#'
#' Stage 2 -- VALUE-match inference (icesVocab's codes <-> the field's real
#' values), attempted only when Stage 1 finds >=1 candidate. A second,
#' independent guess, at the value level rather than the name level:
#'   - Field is `type: enum` with real curated `values:` -- reuse the same
#'     missing-from-vocab/unused-vocab-codes comparison
#'     build_vocab_correction.R uses (factored into
#'     data-raw/vocab_fit_helper.R, shared rather than copy-pasted).
#'   - Field is NOT enum-typed (number/string/etc.) -- no code-overlap check
#'     is meaningful; a continuous measurement can't equal a short discrete
#'     code list. The bare fact "a name match exists for a non-categorical
#'     field" IS the finding, and it's the main new thing this sweep adds
#'     over the existing enum-only audit.
#'
#' Diagnostic/ICES-facing only, per the user's own framing: unlike
#' inst/DATRAS-vocab-correction.csv (opus's own runtime-facing working
#' default for enum fields, read by op_vocab_resolve_datras_key()), this
#' sweep's output isn't read by any opus runtime code -- a non-enum field
#' doesn't need opus to have a working vocab default, since opus doesn't
#' resolve a controlled vocabulary for a plain number. Feeds a new ICES
#' issue instead (see data-raw/ICES_ISSUE_REPORT.md).
#'
#' Reads inst/DATRAS-data-dict-legacy.yaml directly (legacy names, primary
#' throughout -- see spec_02_curate_dict.R's own header) rather than
#' inst/DATRAS-data-dict.yaml plus a name round-trip: icesVocab's own keys
#' are legacy-name-shaped, so every lookup here uses the field's real name
#' directly.
#'
#' Usage: Rscript data-raw/build_vocab_field_audit.R

source("R/vocab.R")
source("data-raw/vocab_fit_helper.R")  # pick_best_vocab_match(), shared with build_vocab_correction.R

y <- yaml::read_yaml("inst/DATRAS-data-dict-legacy.yaml")
types <- op_vocab_get_types()

get_real_values <- function(col) {
  v <- col$values
  if (is.null(v)) return(character(0))
  nm <- names(v)
  if (!is.null(nm) && any(nm != "")) return(nm)
  unlist(v)
}

code_cache <- new.env()
get_codes_cached <- function(key) {
  if (!exists(key, envir = code_cache)) {
    codes <- tryCatch(op_vocab_get_codes(key)$Key, error = function(e) character(0))
    assign(key, codes, envir = code_cache)
  }
  get(key, envir = code_cache)
}

rows <- list()

for (tbl in y$tables) {
  for (col in tbl$columns) {
    legacy_name <- col$name
    field_type <- if (is.null(col$type)) NA_character_ else col$type

    resolved <- op_vocab_resolve_key(legacy_name, types)
    n_candidates <- length(resolved$candidates)
    candidate_keys <- paste(resolved$candidates, collapse = "|")

    if (n_candidates == 0) {
      # Stage 1: no name-based match at all. Expected/boring for most
      # fields -- recorded as a fact, not flagged as a problem.
      rows[[length(rows) + 1]] <- data.frame(
        table = tbl$name, legacy_field = legacy_name, field_type = field_type,
        vocab_candidates_found = 0L, candidate_keys = "", ambiguous = FALSE,
        value_check_applicable = FALSE, data_fit = "no_candidate",
        stringsAsFactors = FALSE
      )
      next
    }

    real_vals <- get_real_values(col)
    is_enum_with_values <- identical(field_type, "enum") && length(real_vals) > 0

    if (is_enum_with_values) {
      # Stage 2, enum branch: does the guessed key's code list actually
      # cover the field's real values, both directions?
      fit <- pick_best_vocab_match(real_vals, resolved$candidates, get_codes_cached)
      rows[[length(rows) + 1]] <- data.frame(
        table = tbl$name, legacy_field = legacy_name, field_type = field_type,
        vocab_candidates_found = n_candidates, candidate_keys = candidate_keys,
        ambiguous = resolved$ambiguous, value_check_applicable = TRUE,
        data_fit = fit$fit, stringsAsFactors = FALSE
      )
    } else {
      # Stage 2, non-enum branch: a name match on a field that isn't even
      # categorical is itself the reportable finding -- no code-overlap
      # check is meaningful for a continuous/free-text field.
      rows[[length(rows) + 1]] <- data.frame(
        table = tbl$name, legacy_field = legacy_name, field_type = field_type,
        vocab_candidates_found = n_candidates, candidate_keys = candidate_keys,
        ambiguous = resolved$ambiguous, value_check_applicable = FALSE,
        data_fit = "not_applicable", stringsAsFactors = FALSE
      )
    }
  }
}

out <- do.call(rbind, rows)
out <- out[order(out$table, out$legacy_field), ]

write.csv(out, "data-raw/DATRAS-vocab-field-audit.csv", row.names = FALSE)

message("Wrote data-raw/DATRAS-vocab-field-audit.csv (", nrow(out), " fields)")
message("  Stage 1 -- zero name-match candidates:        ", sum(out$vocab_candidates_found == 0))
message("  Stage 1 -- candidate(s) found:                 ", sum(out$vocab_candidates_found > 0))
message("    of which ambiguous (TS_/AC_-style collision): ", sum(out$ambiguous))
message("  Stage 2 -- enum, full value fit:               ", sum(out$data_fit == "full"))
message("  Stage 2 -- enum, partial value fit:             ", sum(out$data_fit == "partial"))
message("  Stage 2 -- non-enum field with a name match:    ", sum(out$data_fit == "not_applicable"))
