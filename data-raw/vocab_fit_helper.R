# Shared by data-raw/build_vocab_correction.R and
# data-raw/build_vocab_field_audit.R: given a field's real archive values
# and a set of candidate icesVocab keys (from op_vocab_resolve_key()),
# picks the best-fitting candidate and reports exactly how it fits or
# doesn't. Factored out once rather than duplicated in both scripts --
# copy-pasting this exact kind of real-data-vs-vocab comparison logic is
# what caused a real bug earlier this session (a hand-rolled copy of
# op_legacy_field_name()'s regex silently drifting from the real function).
#
# "Best" = fewest real values NOT covered by that candidate's codes
# (`missing`) -- ties are not expected to matter here (a real difference in
# fit is the whole point), but the first candidate seen wins a tie, same as
# before this was factored out.

#' @param real_vals Character vector: distinct real values observed for this field.
#' @param candidates Character vector: candidate icesVocab keys to try.
#' @param get_codes Function: key -> character vector of that vocab's codes
#'   (e.g. a cached wrapper around op_vocab_get_codes()).
#' @return List: key (best candidate), missing (real values it doesn't
#'   cover), unused (its codes never seen in real_vals), fit ("full" if
#'   missing is empty, else "partial").
pick_best_vocab_match <- function(real_vals, candidates, get_codes) {
  best <- NULL
  best_missing <- Inf
  best_missing_codes <- character(0)
  best_unused_codes <- character(0)
  for (cand in candidates) {
    codes <- get_codes(cand)
    missing <- setdiff(real_vals, codes)
    unused <- setdiff(codes, real_vals)
    if (length(missing) < best_missing) {
      best_missing <- length(missing)
      best <- cand
      best_missing_codes <- missing
      best_unused_codes <- unused
    }
  }
  list(
    key = best, missing = best_missing_codes, unused = best_unused_codes,
    fit = if (best_missing == 0) "full" else "partial"
  )
}
