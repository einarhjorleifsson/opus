#' Get ICES Vocabulary Types with Prefix Metadata
#'
#' Fetches the complete code-type list from the ICES Vocabulary service and
#' enriches it with prefix classification. ICES Vocabulary keys may be prefixed
#' with domain codes (e.g., "TS_" for Trawl Survey, "AC_" for Acoustic) or bare
#' (unprefixed).
#'
#' This function and its companions ([op_vocab_resolve_key()],
#' [op_vocab_get_codes()], [op_vocab_first_usable()]) provide a foundation
#' for working with ICES Vocabulary in DATRAS contexts. They handle common
#' pitfalls of vocabulary matching (prefix ambiguity, domain mismatches,
#' empty code-types) and enable both data-dict seeding and downstream
#' validation workflows (e.g., QC checks that submitted values match
#' their field's valid codes).
#'
#' @return
#' A data frame with columns:
#' \describe{
#'   \item{Key}{The full ICES Vocabulary key (e.g., "TS_Sex", "Gear")}
#'   \item{stripped}{The key with any domain prefix removed}
#'   \item{prefix}{Classification: "TS", "AC", or "bare" (unprefixed)}
#'   \item{Description}{The key's description from ICES Vocabulary}
#' }
#'
#' @examples
#' \dontrun{
#'   types <- op_vocab_get_types()
#'   head(types)
#'
#'   # DATRAS example: HL (length) table uses Sex, Gear, and many other fields
#'   # with vocabularies. Get the full type list to examine all available
#'   # prefixes, domains, and which fields have code lists:
#'   str(types)  # Key, stripped, prefix, Description
#' }
#'
#' @export
op_vocab_get_types <- function() {
  types <- icesVocab::getCodeTypeList()
  types$prefix <- ifelse(grepl("^TS_", types$Key), "TS",
                   ifelse(grepl("^AC_", types$Key), "AC", "bare"))
  types$stripped <- sub("^(TS_|AC_)", "", types$Key)
  types[, c("Key", "stripped", "prefix", "Description")]
}


#' Resolve a Field Name to Candidate Vocabulary Keys
#'
#' Given a field name, finds all matching ICES Vocabulary keys across all
#' registered prefixes, ordered by preference: "TS" (Trawl Survey) > "bare"
#' (unprefixed) > "AC" (Acoustic). This ordering is context-specific to
#' DATRAS (trawl-survey data); callers in other domains should build their
#' own preference logic.
#'
#' Returns all candidates, not just the top preference, because some registered
#' code-types have zero usable codes in practice. Callers should iterate
#' through candidates to find one yielding actual codes.
#'
#' The `ambiguous` flag is critical for QC and validation: it signals when
#' a field name matches multiple domains, highlighting where domain knowledge
#' is required to choose the correct vocabulary (or determine that no
#' vocabulary applies). Naive prefix-blind matching would lose this signal
#' and silently pool incompatible code lists.
#'
#' @param field_name Character scalar: the field name to resolve (e.g., "Sex",
#'   "Gear").
#' @param types Data frame: output of [op_vocab_get_types()], with at minimum
#'   columns `stripped`, `prefix`, and `Key`.
#'
#' @return
#' A list with elements:
#' \describe{
#'   \item{candidates}{Character vector of matching ICES Vocabulary keys,
#'     in preference order. Empty if no matches.}
#'   \item{ambiguous}{Logical: TRUE if the field matched under more than one
#'     prefix, indicating potential ambiguity in vocabulary interpretation.}
#' }
#'
#' @examples
#' \dontrun{
#'   types <- op_vocab_get_types()
#'
#'   # PITFALL: DATRAS HL table Sex field matches under BOTH TS_ (trawl: 7 codes
#'   # including Berried/Neutral) and AC_ (acoustic: 4 simpler codes). Naive
#'   # prefix-blind matching would pool both, creating false codes. The ambiguous
#'   # flag alerts you to inspect further.
#'   op_vocab_resolve_key("Sex", types)
#'   # $candidates = c("TS_Sex", "AC_Sex")  [ordered by preference: TS first]
#'   # $ambiguous = TRUE  [field appears under multiple prefixes — CHECK THIS]
#'
#'   # DATRAS: fields with unique prefixes are safer
#'   op_vocab_resolve_key("Gear", types)
#'   # $candidates = c("Gear")  [bare/unprefixed key only]
#'   # $ambiguous = FALSE
#'
#'   # PITFALL: DATRAS HH Survey field (open list of acronyms) shares a name
#'   # with icesVocab Survey (ICES internal 3-digit codes like A1012). These
#'   # are completely unrelated vocabularies, but naive name-matching returns
#'   # the wrong codes. op_vocab_resolve_key returns both candidates; the caller
#'   # must use domain knowledge to pick the right one (or neither).
#'   op_vocab_resolve_key("Survey", types)
#'   # $candidates = c("TS_Survey", "AC_Survey")
#'   # $ambiguous = TRUE  [both exist but may not apply to this field]
#' }
#'
#' @export
op_vocab_resolve_key <- function(field_name, types) {
  matches <- types[types$stripped == field_name, ]
  if (nrow(matches) == 0) {
    return(list(candidates = character(0), ambiguous = FALSE))
  }
  pref_order <- c("TS", "bare", "AC")
  matches <- matches[order(match(matches$prefix, pref_order)), ]
  list(candidates = matches$Key, ambiguous = nrow(matches) > 1)
}


#' Fetch Code:Meaning Pairs from an ICES Vocabulary Key
#'
#' Retrieves the actual codes and descriptions for a single ICES Vocabulary key.
#' Deprecated codes are excluded. If the key has zero codes (e.g., some
#' registered code-types exist but contain no codes), returns an empty data frame.
#'
#' Beyond data-dict seeding, this function supports validation and QC workflows:
#' you can fetch the valid codes for a field and check submitted values against
#' them. Returns deprecated codes excluded (only current, valid codes), making
#' it safe for validation use.
#'
#' @param key Character scalar: a full ICES Vocabulary key (e.g., "TS_Sex").
#'
#' @return
#' A data frame with columns:
#' \describe{
#'   \item{Key}{The code (e.g., "M", "F")}
#'   \item{Description}{The code's meaning (e.g., "Male", "Female")}
#' }
#' Empty if the key has no usable codes.
#'
#' @examples
#' \dontrun{
#'   # DATRAS HL table: fetch sex codes from trawl-survey domain
#'   codes <- op_vocab_get_codes("TS_Sex")
#'   nrow(codes)  # 7 codes
#'   codes
#'   # Key Description
#'   # -9  Not recorded
#'   # B   Berried female
#'   # F   Female
#'   # M   Male
#'   # N   Neutral
#'   # T   Transitional
#'   # U   Unsexed
#'
#'   # PITFALL: TS_Survey is a registered code-type, but returns zero codes.
#'   # Some ICES Vocabulary keys exist on paper but are empty in practice.
#'   empty <- op_vocab_get_codes("TS_Survey")
#'   nrow(empty)  # 0 codes — not an error, just empty
#'
#'   # PITFALL: DATRAS StatRec field has hundreds of valid ICES stat rectangles.
#'   # op_vocab_get_codes returns all of them, but for practical enums (seed's
#'   # VOCAB_CODE_LIMIT=20), you'd typically filter these out as unusable.
#'   statrecs <- op_vocab_get_codes("StatRec")
#'   nrow(statrecs)  # 200+; too large for an inline enum
#'
#'   # DATRAS HH: fetch gear codes (note: Gear key is bare, not prefixed)
#'   gears <- op_vocab_get_codes("Gear")
#'   nrow(gears)  # 55+ codes in the official list
#'   head(gears)
#'   # Key Description
#'   # BT3 Beam trawl 3 meters
#'   # BT6 Beam trawl 6 meters
#'   # GOV GOV Trawl
#'   # ...
#' }
#'
#' @export
op_vocab_get_codes <- function(key) {
  codes <- tryCatch(icesVocab::getCodeList(key), error = function(e) NULL)
  if (!is.data.frame(codes) || !"Deprecated" %in% names(codes) || nrow(codes) == 0) {
    return(data.frame(Key = character(0), Description = character(0)))
  }
  codes <- codes[!codes$Deprecated, c("Key", "Description")]
  row.names(codes) <- NULL
  codes
}


#' Find the First Vocabulary Key with Usable Codes
#'
#' Combines [op_vocab_resolve_key()], [op_vocab_get_codes()], and fallthrough
#' logic to locate the first candidate key that yields at least one usable code.
#' Tries candidates in preference order until finding one with codes; returns
#' an NA key with empty codes if none do.
#'
#' This is the primary entry point for vocabulary lookup: call this when you
#' need codes for a field without already knowing the exact ICES Vocabulary key.
#' It automates the fallthrough logic (e.g., TS_Sex → AC_Sex if TS has no codes),
#' but still surfaces ambiguity flags for QC. Use in seeding workflows (to populate
#' data-dict enums) and validation workflows (to build field-level code validators).
#'
#' @param field_name Character scalar: the field name to look up.
#' @param types Data frame: output of [op_vocab_get_types()].
#'
#' @return
#' A list with elements:
#' \describe{
#'   \item{key}{The ICES Vocabulary key that succeeded, or NA_character_
#'     if none had usable codes.}
#'   \item{codes}{A data frame with columns `Key` and `Description`,
#'     containing the actual codes. Empty if no key succeeded.}
#'   \item{ambiguous}{Logical: TRUE if the field name matched under
#'     more than one prefix.}
#' }
#'
#' @examples
#' \dontrun{
#'   types <- op_vocab_get_types()
#'
#'   # DATRAS seeding workflow: for HL table, find usable codes for Sex field.
#'   # Tries TS_Sex first (trawl survey context); returns it because it has codes
#'   sex_vocab <- op_vocab_first_usable("Sex", types)
#'   sex_vocab$key        # "TS_Sex"
#'   sex_vocab$ambiguous  # TRUE (also has AC_Sex) — check for domain conflicts
#'   nrow(sex_vocab$codes)  # 7 codes total
#'
#'   # PITFALL: DATRAS LT (litter) PARAM field has codes like A2, A3, A5 in
#'   # real data, but they DON'T appear in icesVocab's PARAM list (which has
#'   # 1,938 official codes like 'LT-TOT'). This returns a valid vocabulary
#'   # match, but it's incomplete/wrong for real submissions. The function
#'   # can't detect this mismatch; it's a known discrepancy for DATRAS QC.
#'   param_vocab <- op_vocab_first_usable("PARAM", types)
#'   "A2" %in% param_vocab$codes$Key  # FALSE — real value missing from vocab
#'
#'   # DATRAS: field with many codes (StatRec has 200+); first_usable still finds
#'   # it, but callers typically exclude fields with >20 codes from enum lists
#'   statrec_vocab <- op_vocab_first_usable("StatRec", types)
#'   statrec_vocab$key   # a valid key with >20 codes
#'   nrow(statrec_vocab$codes)  # 200+; filtered out for practical enums
#'
#'   # PITFALL: DATRAS HH Survey field (open list of survey acronyms) has a name
#'   # collision with icesVocab Survey (internal ICES codes). This returns codes,
#'   # but they're completely wrong for the field. Prefix ordering (TS_ preferred)
#'   # doesn't help here—the problem is semantic, not syntactic.
#'   survey_vocab <- op_vocab_first_usable("Survey", types)
#'   survey_vocab$key  # TS_Survey or AC_Survey, but neither is what HH needs
#'   # The real Survey codes in HH are short acronyms like "NS-IBTS" (open list,
#'   # not enumerable), so this vocabulary match is a red herring.
#'
#'   # DATRAS: field with no matching vocabulary (e.g., custom local fields)
#'   # returns NA key with empty code frame
#'   unknown <- op_vocab_first_usable("CustomField", types)
#'   is.na(unknown$key)   # TRUE
#'   nrow(unknown$codes)  # 0
#' }
#'
#' @export
op_vocab_first_usable <- function(field_name, types) {
  resolved <- op_vocab_resolve_key(field_name, types)
  for (key in resolved$candidates) {
    codes <- op_vocab_get_codes(key)
    if (nrow(codes) > 0) return(list(key = key, codes = codes, ambiguous = resolved$ambiguous))
  }
  list(key = NA_character_, codes = op_vocab_get_codes(NA_character_), ambiguous = resolved$ambiguous)
}
