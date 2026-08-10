#' Build the DATRAS vocab correction proposal
#'
#' For every Tier 1 enum field, guesses the applicable icesVocab key by
#' name-matching (checking BOTH the legacy and current DATRAS field name
#' against the live icesVocab service -- Working Principles 8-9: empirical,
#' exhaustive -- see AGENTS.md), then checks that guess against the real
#' archive values in both directions. Name-matching is a guess, not an
#' ICES-declared fact (see data-raw/ICES_ISSUE_REPORT.md, Issue 7: icesVocab
#' publishes no field-to-key link at all) -- the output table says so
#' explicitly via `resolution_basis` on every row, rather than letting a
#' data-fit outcome read as more authoritative than it is.
#'
#' This exists because `TS_`/`AC_` naming collisions make name-matching
#' unreliable on its own (Issue 8). This script produces opus's own
#' provisional proposal for the correct mapping -- the same proposal sent to
#' ICES as Issues 7-8's concrete recommendation, and the one opus's own
#' tooling (op_vocab_resolve_datras_key(), R/vocab.R) treats as its working
#' default until ICES formalizes something authoritative. One artifact, two
#' uses, by design -- so opus's own assumption can never silently drift from
#' what was actually proposed to ICES.
#'
#' Output: inst/DATRAS-vocab-correction.csv, columns:
#'   table, field, legacy_field       -- which DATRAS field
#'   resolution_basis                 -- "name-match" (a guess; icesVocab
#'                                        declares no link) or "no candidate"
#'   proposed_vocab_key               -- the guessed key, or NA
#'   missing_from_vocab               -- real values the guessed key's codes
#'                                        don't cover (empty if none)
#'   unused_vocab_codes               -- the guessed key's codes never seen
#'                                        in the real archive (empty if none)
#'   data_fit                         -- "full" (guess fits real data both
#'                                        directions), "partial" (doesn't --
#'                                        treat as unresolved, not "close
#'                                        enough"), or "no_candidate"
#'
#' Restructured 2026-08-09 to read inst/DATRAS-data-dict-legacy.yaml (now a
#' real, primary package file, keyed by legacy names throughout -- see
#' data-raw/spec_02_curate_dict.R's own header) directly, rather than
#' reading inst/DATRAS-data-dict.yaml (curated/new names) and round-tripping
#' back to the legacy name via op_legacy_field_name(). Same real data,
#' same 46 full / 6 no_candidate / 0 partial tally either way -- verified,
#' not assumed, when this change was made.
#'
#' Usage: Rscript data-raw/build_vocab_correction.R

source("R/vocab.R")
source("R/field_names.R")
source("data-raw/vocab_fit_helper.R")  # pick_best_vocab_match(), shared with build_vocab_field_audit.R

y <- yaml::read_yaml("inst/DATRAS-data-dict-legacy.yaml")
types <- op_vocab_get_types()
crosswalk <- op_datras_rename_crosswalk()

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
    if (!identical(col$type, "enum")) next

    legacy_name <- col$name
    new_name <- crosswalk$new_name[crosswalk$RecordHeader == tbl$name & crosswalk$old_name == legacy_name]
    if (length(new_name) != 1) {
      stop("No 1:1 crosswalk entry for ", tbl$name, "/", legacy_name,
           " -- inst/DATRAS-data-dict-legacy.yaml and op_datras_rename_crosswalk() have drifted.",
           call. = FALSE)
    }

    real_vals <- get_real_values(col)
    if (length(real_vals) == 0) next

    candidates <- unique(c(
      op_vocab_resolve_key(new_name, types)$candidates,
      op_vocab_resolve_key(legacy_name, types)$candidates
    ))
    candidates <- candidates[!is.na(candidates) & nchar(candidates) > 0]

    if (length(candidates) == 0) {
      rows[[length(rows) + 1]] <- data.frame(
        table = tbl$name, field = new_name, legacy_field = legacy_name,
        resolution_basis = "no candidate", proposed_vocab_key = NA,
        missing_from_vocab = NA, unused_vocab_codes = NA,
        data_fit = "no_candidate", stringsAsFactors = FALSE
      )
      next
    }

    fit <- pick_best_vocab_match(real_vals, candidates, get_codes_cached)

    rows[[length(rows) + 1]] <- data.frame(
      table = tbl$name, field = new_name, legacy_field = legacy_name,
      resolution_basis = "name-match", proposed_vocab_key = fit$key,
      missing_from_vocab = paste(fit$missing, collapse = "|"),
      unused_vocab_codes = paste(fit$unused, collapse = "|"),
      data_fit = fit$fit,
      stringsAsFactors = FALSE
    )
  }
}

out <- do.call(rbind, rows)
out <- out[order(out$table, out$field), ]

write.csv(out, "inst/DATRAS-vocab-correction.csv", row.names = FALSE)

message("Wrote inst/DATRAS-vocab-correction.csv (", nrow(out), " fields)")
message("  data_fit = full:         ", sum(out$data_fit == "full"))
message("  data_fit = partial:      ", sum(out$data_fit == "partial"))
message("  data_fit = no_candidate: ", sum(out$data_fit == "no_candidate"))
