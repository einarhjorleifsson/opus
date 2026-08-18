#' Structural consistency check between opus's two issue-tracking documents
#'
#' `inst/DATRAS-known-issues.yaml` (opus's internal escalation registry) and
#' `data-raw/ICES_ISSUE_REPORT.md` (the document meant for ICES) cross-
#' reference each other by hand -- a yaml entry says "Filed as ...
#' Issue N", and the .md's "Suggestion for consideration" section cites
#' yaml `id`s directly. Nothing had ever checked those references stay
#' valid. A 2026-08-18 session found a yaml entry (`icesVocab_gaps`)
#' sitting stale for days after the finding it cited was debunked, and
#' separately found the .md's own Issue 9 mischaracterizing two fields the
#' same day -- neither would have been caught by this script, since both
#' were FACTUAL errors, not broken cross-references. But the *rename* that
#' fixed the first one (`icesVocab_gaps` -> two new ids) is exactly the
#' kind of edit this script exists to catch, if a stray reference to the
#' old name had been left behind anywhere.
#'
#' What this checks (structural, cheap, mechanical -- a linter, not a
#' fact-checker):
#'   1. Every "ICES_ISSUE_REPORT.md Issue N" cited inside the yaml resolves
#'      to a real `## Issue N:` header in the .md.
#'   2. Every yaml `id` cited inside the .md (near the words "known
#'      issue(s)"/"known-issues", the phrasing every real citation uses)
#'      still exists as a real entry in the yaml.
#'   3. No `scope: opus-internal` yaml entry cites an ICES_ISSUE_REPORT.md
#'      issue at all -- opus-internal bugs are never ICES's problem, per
#'      the yaml's own header comment.
#'   4. `## Issue N:` headers in the .md are unique and form a contiguous
#'      1..max sequence (catches a slipped or duplicated number when
#'      adding a new issue by hand).
#'
#' What this does NOT check, deliberately: whether a claim is still TRUE
#' (row counts, "full match" verdicts, whether a redirect exists). That
#' requires re-running the actual verification against live icesVocab/the
#' real archive -- the substantive work this project keeps doing by hand.
#' This script only keeps the bookkeeping between the two documents
#' honest, so a future rename/retirement doesn't leave a silent dangling
#' reference the way `icesVocab_gaps` did.
#'
#' Also prints (informational, never affects exit status) which
#' ICES-facing yaml entries have no Issue reference yet -- the "ready to
#' file" worklist derived by hand during the 2026-08-18 session, now
#' reproducible on demand instead of re-grepping both files each time.
#'
#' Usage: Rscript data-raw/validate_issue_registry_sync.R
#' Exit status: 0 if no structural errors found, 1 otherwise.

KNOWN_ISSUES_YAML <- "inst/DATRAS-known-issues.yaml"
ISSUE_REPORT_MD <- "data-raw/ICES_ISSUE_REPORT.md"

known_issues <- yaml::read_yaml(KNOWN_ISSUES_YAML)
md_lines <- readLines(ISSUE_REPORT_MD, warn = FALSE)
md_text <- paste(md_lines, collapse = "\n")

errors <- character(0)

# -- `## Issue N:` headers: unique, contiguous 1..max ------------------------

header_lines <- grep("^## Issue [0-9]+:", md_lines, value = TRUE)
header_nums <- as.integer(sub("^## Issue ([0-9]+):.*", "\\1", header_lines))

dupes <- unique(header_nums[duplicated(header_nums)])
if (length(dupes) > 0) {
  errors <- c(errors, sprintf(
    "Duplicate '## Issue %s:' header(s) in %s",
    paste(dupes, collapse = ", "), ISSUE_REPORT_MD
  ))
}
missing_nums <- setdiff(seq_len(max(header_nums)), header_nums)
if (length(missing_nums) > 0) {
  errors <- c(errors, sprintf(
    "Gap in Issue numbering: %s missing (max is %d) in %s",
    paste(missing_nums, collapse = ", "), max(header_nums), ISSUE_REPORT_MD
  ))
}

# -- helpers ------------------------------------------------------------------

# Pulls every "ICES_ISSUE_REPORT.md Issue(s) N[, and M...]" citation out of
# free text. Bounded to the next sentence-ending period so unrelated digits
# elsewhere in a long paragraph are never swept in; the lookaround excludes
# any digit run that's part of a bigger number (row counts, percentages,
# comma-grouped thousands) so "4.92%" or "5,865,076" can never be
# misread as an issue number even if they appear before that period.
extract_issue_numbers <- function(text) {
  if (is.null(text) || length(text) == 0 || is.na(text)) return(integer(0))
  spans <- regmatches(text, gregexpr("ICES_ISSUE_REPORT\\.md Issues?[^.]*", text, perl = TRUE))[[1]]
  if (length(spans) == 0) return(integer(0))
  nums <- unlist(lapply(spans, function(s) {
    as.integer(regmatches(s, gregexpr("(?<![\\d.,])\\d+(?![\\d.,%])", s, perl = TRUE))[[1]])
  }))
  sort(unique(nums))
}

# Flattens every free-text field of one known_violations entry into a
# single blob, so a citation buried in `implication`, `extent`,
# `discovered`, etc. is never missed regardless of which field it lives in.
flatten_entry_text <- function(entry) {
  txt_fields <- entry[vapply(entry, is.character, logical(1))]
  paste(unlist(txt_fields), collapse = " \n ")
}

violations <- known_issues$known_violations
entry_ids <- vapply(violations, function(e) e$id, character(1))

# -- yaml -> .md: every cited Issue N must exist; opus-internal must cite none

filed_worklist <- character(0)
not_filed <- character(0)

for (entry in violations) {
  refs <- extract_issue_numbers(flatten_entry_text(entry))

  if (identical(entry$scope, "opus-internal") && length(refs) > 0) {
    errors <- c(errors, sprintf(
      "'%s' is scope: opus-internal but cites ICES_ISSUE_REPORT.md Issue(s) %s -- opus-internal bugs should never be filed with ICES",
      entry$id, paste(refs, collapse = ", ")
    ))
  }

  bad_refs <- setdiff(refs, header_nums)
  if (length(bad_refs) > 0) {
    errors <- c(errors, sprintf(
      "'%s' cites ICES_ISSUE_REPORT.md Issue(s) %s, which do not exist as '## Issue N:' headers in %s",
      entry$id, paste(bad_refs, collapse = ", "), ISSUE_REPORT_MD
    ))
  }

  if (!identical(entry$scope, "opus-internal")) {
    if (length(refs) > 0) {
      filed_worklist <- c(filed_worklist, sprintf("%-40s -> Issue %s", entry$id, paste(refs, collapse = ", ")))
    } else {
      not_filed <- c(not_filed, entry$id)
    }
  }
}

# -- .md -> yaml: every yaml id cited near "known issue(s)" must still exist -
# (?s) makes `.` cross line breaks: markdown soft-wraps long paragraphs, so
# the marker phrase and the backtick id it introduces are almost always on
# different physical lines even though they're the same sentence.

known_marker_spans <- regmatches(
  md_text,
  gregexpr("(?si)known[- ]issues?.{0,150}", md_text, perl = TRUE)
)[[1]]
cited_ids <- unique(unlist(lapply(known_marker_spans, function(s) {
  regmatches(s, gregexpr("`([a-z][a-z0-9_]*_[a-z0-9_]*)`", s, perl = TRUE))[[1]]
})))
cited_ids <- gsub("`", "", cited_ids)

dangling_ids <- setdiff(cited_ids, entry_ids)
if (length(dangling_ids) > 0) {
  errors <- c(errors, sprintf(
    "%s cites known-issues.yaml id(s) that no longer exist: %s -- renamed or retired without updating this reference?",
    ISSUE_REPORT_MD, paste(dangling_ids, collapse = ", ")
  ))
}

# -- report -------------------------------------------------------------

message("")
message("=== Structural errors (", length(errors), ") ===")
if (length(errors) > 0) {
  for (e in errors) message("  FAIL: ", e)
} else {
  message("  none")
}

message("")
message("=== Filed (", length(filed_worklist), ") ===")
for (f in filed_worklist) message("  ", f)

message("")
message("=== Not yet filed -- ICES-facing candidates with no Issue reference (", length(not_filed), ") ===")
for (n in not_filed) message("  ", n)

message("")
if (length(errors) > 0) {
  message(length(errors), " structural error(s) found.")
  if (!interactive()) quit(status = 1, save = "no")
} else {
  message("OK -- no structural inconsistencies found.")
  if (!interactive()) quit(status = 0, save = "no")
}
