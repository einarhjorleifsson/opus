#' Generate articles/reference.qmd from the package's own Rd files
#'
#' opus documents itself with a plain Quarto site rather than pkgdown (see
#' DEVLOG.md, 2026-08-20: no external R-user audience, and RStudio's
#' BuildType: Package line fights Quarto's website detection). That decision
#' still holds, but it left the site with no function index -- 40 Rd files
#' and nothing on the site pointing at any of them.
#'
#' This closes that gap without reintroducing pkgdown: it reads titles and
#' descriptions straight from man/*.Rd, so the page cannot drift from the
#' roxygen, and writes one Quarto page.
#'
#' The grouping below is hand-maintained, the way a pkgdown reference index
#' would be -- an alphabetical dump of 34 names helps nobody. To keep that
#' curation honest the script FAILS if an exported function belongs to no
#' group, rather than quietly dropping it or appending it to a
#' miscellaneous bucket. Adding an export therefore forces a decision about
#' where it belongs.
#'
#' Usage: Rscript data-raw/build_reference.R

`%||%` <- function(a, b) if (is.null(a)) b else a

OUT <- "articles/reference.qmd"

# Order here is the order on the page: what a reader meets first should be
# what they most likely came for.
GROUPS <- list(
  list(
    title = "The specification",
    blurb = paste(
      "The dictionary as data. Downstream code should reach the yaml through",
      "these rather than parsing it, so there is one place where the shape of",
      "the specification is known."
    ),
    fns = c("op_field_spec", "op_field_name_map", "op_legacy_field_name")
  ),
  list(
    title = "Reading the published archive",
    blurb = paste(
      "The published archive is four parquet files that describe themselves.",
      "These are the way in: resolve the root, query a table lazily, or take",
      "the whole thing as SQL. Every call is a range request rather than a",
      "download, and there is no sidecar catalog to keep in step with the data."
    ),
    fns = c("op_archive", "op_con", "op_catalog", "op_define", "op_rename")
  ),
  list(
    title = "The metadata each file carries",
    blurb = paste(
      "Each file's footer holds its own dictionary, legacy-name crosswalk,",
      "enum labels, sentinel policy, coverage and known issues. All of it is",
      "read from the same file as the data, so it cannot describe a different",
      "vintage of the archive than the one you loaded."
    ),
    fns = c("op_keys", "op_dict", "op_crosswalk", "op_enums", "op_definitions",
            "op_relationships", "op_coverage", "op_surveys", "op_sentinel_meta",
            "op_provenance", "op_known_issues")
  ),
  list(
    title = "Converting DATRAS XML to parquet",
    blurb = paste(
      "The four steps of the conversion, in the order they must run: physical",
      "types, then names, then sentinels, then the semantic types the wire",
      "cannot express. A consumer calling these on its own live fetch gets a",
      "result identical to the published archive rather than a near-miss."
    ),
    fns = c("op_cast_wsdl_types", "op_rename_to_new", "op_strip_sentinels",
            "op_cast_to_spec", "op_wsdl_type_overrides")
  ),
  list(
    title = "Sentinels",
    blurb = paste(
      "DATRAS overloads `-9`: in most fields it means \"not recorded\", in a",
      "few it is a documented answer. These read the registry, resolve it to a",
      "per-column verdict, and measure the result against real data."
    ),
    fns = c("op_sentinels", "op_sentinel_policy", "op_sentinel_audit")
  ),
  list(
    title = "Field names",
    blurb = paste(
      "ICES is renaming DATRAS fields one table at a time. These separate what",
      "ICES *claims* about renames from what survives checking against what the",
      "service actually returns."
    ),
    fns = c("op_datras_field_metadata", "op_datras_field_list",
            "op_datras_rename_crosswalk")
  ),
  list(
    title = "Reading the DATRAS web service",
    blurb = paste(
      "Primary-source readers. Everything that needs to know what ICES really",
      "sends goes through these rather than parsing the service again."
    ),
    fns = c("op_datras_operations", "op_datras_operation_types")
  ),
  list(
    title = "Validation",
    blurb = paste(
      "Is the dictionary well-formed, and does it still describe the data?",
      "These matter more than usual under hand-maintenance -- they are what",
      "makes editing a large yaml by hand safe."
    ),
    fns = c("op_validate_spec", "op_validate_meta", "op_validate_data",
            "op_validate_full", "op_validation_problems", "op_flag_violations")
  ),
  list(
    title = "ICES vocabularies",
    blurb = paste(
      "Code semantics from icesVocab. Keys are tied to each field's *legacy*",
      "name, which is not obvious until it produces a wrong answer."
    ),
    fns = c("op_vocab_resolve_datras_key", "op_vocab_resolve_key",
            "op_vocab_resolve_guid", "op_vocab_get_types", "op_vocab_get_codes",
            "op_vocab_first_usable")
  ),
  list(
    title = "Parquet and export",
    blurb = "Inspecting real data, and rendering the dictionary for other tools.",
    fns = c("op_inspect_parquet", "op_describe_parquet", "op_draft_from_parquet",
            "op_export_spec", "op_export_data", "op_render_spec")
  )
)

# ---- read the Rd files -------------------------------------------------

rd_field <- function(fn, tag) {
  cands <- c(file.path("man", paste0(fn, ".Rd")),
             file.path("man", paste0(gsub("[.]", "-", fn), ".Rd")))
  rd <- cands[file.exists(cands)]
  if (!length(rd)) return(NA_character_)
  p <- tools::parse_Rd(rd[1], encoding = "UTF-8")
  tags <- vapply(p, function(x) attr(x, "Rd_tag") %||% "", character(1))
  hit <- p[tags == tag]
  if (!length(hit)) return(NA_character_)
  txt <- paste(unlist(hit[[1]]), collapse = "")
  Encoding(txt) <- "UTF-8"
  # \link{} and friends survive unlist() as bare markup; the index wants
  # plain prose, and a broken link is worse than no link.
  txt <- gsub("\\[=?[A-Za-z0-9_.]*\\]?\\{([^{}]*)\\}", "\\1", txt)
  txt <- gsub("[\\[\\]]", "", txt)
  trimws(gsub("[[:space:]]+", " ", txt))
}

exports <- sort(getNamespaceExports("opus"))
grouped <- unlist(lapply(GROUPS, `[[`, "fns"))

missing <- setdiff(exports, grouped)
if (length(missing) > 0) {
  stop("build_reference.R: ", length(missing),
       " exported function(s) belong to no group in GROUPS: ",
       paste(missing, collapse = ", "),
       ". Add them to a group -- deciding where a function belongs is the",
       " point of this file.", call. = FALSE)
}
stale <- setdiff(grouped, exports)
if (length(stale) > 0) {
  stop("build_reference.R: GROUPS names ", length(stale),
       " function(s) that are not exported: ", paste(stale, collapse = ", "),
       ".", call. = FALSE)
}

# ---- write the page ----------------------------------------------------

lines <- c(
  "---",
  'title: "Function reference"',
  "---",
  "",
  "::: {.callout-note appearance=\"simple\"}",
  paste("This page is generated from the package's own `man/*.Rd` files by",
        "`data-raw/build_reference.R`, so it cannot drift from the roxygen."),
  "Full documentation for any function is `?name` in an R session.",
  ":::",
  "",
  paste0("opus exports ", length(exports), " functions. The yaml dictionaries ",
         "are the deliverable; these are the tooling around them."),
  ""
)

for (g in GROUPS) {
  lines <- c(lines, paste("##", g$title), "", g$blurb, "",
             "| Function | |", "|---|---|")
  for (fn in g$fns) {
    # The title, not the description: titles are written as one-liners and
    # read as an index entry should. Descriptions are manual prose -- they
    # truncate badly and assume context the index has not established.
    what <- rd_field(fn, "\\title")
    if (is.na(what) || !nzchar(what)) what <- rd_field(fn, "\\description") %||% ""
    lines <- c(lines, sprintf("| `%s()` | %s |", fn, what))
  }
  lines <- c(lines, "")
}

lines <- c(lines,
  "## Where to look next", "",
  paste("- [Approach](approach.qmd) explains what these are *for* -- the",
        "sources they reconcile, and the problems that shaped them."),
  paste("- [Technical notes](technical-notes.qmd) has the code-level detail."),
  "")

con <- file(OUT, open = "w", encoding = "UTF-8")
on.exit(close(con), add = TRUE)
writeLines(lines, con, useBytes = FALSE)
message("Wrote ", OUT, ": ", length(exports), " functions in ",
        length(GROUPS), " groups")
