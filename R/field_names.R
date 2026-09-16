#' Fetch a URL as a single text string, no package dependency beyond base R
#'
#' @keywords internal
.fetch_text <- function(url) {
  con <- url(url)
  on.exit(close(con), add = TRUE)
  paste(readLines(con, warn = FALSE), collapse = "\n")
}

#' Fetch the real field names an ICES DATRAS operation actually returns
#'
#' Thin wrapper over [op_datras_operation_types()] -- the field-name half of
#' the same crawl. Kept as a named internal because
#' [op_datras_field_list()]'s algorithm reads as intended with it, but it
#' holds no parsing logic of its own: there is exactly one implementation of
#' the ASMX crawl, in `R/datras_service.R`.
#'
#' @param operation Character scalar: an ICES DATRAS web service operation
#'   name, e.g. `"getCAdata"`.
#' @return Character vector of field names, in the order the operation
#'   returns them.
#' @keywords internal
.fetch_datras_operation_fields <- function(operation) {
  op_datras_operation_types(operation)$field
}

#' Derive verified Tier 1 legacy field-name mappings, without icesDatras
#'
#' Replaces opus's former use of `icesDatras::getDatrasFieldList()` for
#' building the old-name -> new-name mapping used by the data-raw curation
#' pipeline. Traced 2026-08-06: ICES's own getDatrasFieldList metadata
#' service has confirmed errors and gaps (it's a separately-maintained
#' table, not generated from the live operations themselves), so this
#' function cross-verifies every claim against each operation's own live
#' response before trusting it, rather than taking getDatrasFieldList's
#' word for it the way icesDatras itself does.
#'
#' Algorithm, per table:
#' 1. **confirmed**: getDatrasFieldList documents old name X -> new name Y
#'    for this table, and X is confirmed present in this table's own live
#'    operation response.
#' 2. **cross_table_confirmed**: X isn't confirmed for *this* table, but
#'    some other Tier 1 table has a `confirmed` mapping for the same old
#'    name X -> Y, and this table's real field list also contains X (e.g.
#'    LT's real `Ship`/`StNo`/`HaulNo` columns, which getDatrasFieldList
#'    incorrectly claims are never renamed for LT specifically, even
#'    though it correctly documents Ship->Platform etc. for HH/HL/CA).
#' 3. **no_evidence**: neither of the above; the field is left unrenamed
#'    (old = new). If getDatrasFieldList has a "dangling" row for this
#'    table -- a claimed rename whose old name isn't in this table's real
#'    field list, and that isn't itself explained by tiers 1-2 -- that's
#'    recorded in `note` rather than used to guess a rename, since the
#'    dangling row's *new*-name half is unverified once its *old*-name
#'    half is already shown not to correspond to anything real (see CA's
#'    `IndividualAge`/`AgeRings`, which triggered this exact case: no
#'    other Tier 1 table's data explains it, so it stays `no_evidence`).
#'
#' Confirmed discrepancies as of 2026-08-06 (candidates for an ICES issue --
#' checked directly against the official `ices-tools-prod/icesDatras` on
#' GitHub, 2026-08-09: its `getDatrasFieldList()` has no patch of any kind,
#' so none of these are things "icesDatras already handles"; they're genuine
#' gaps in ICES's own live service that any consumer would hit):
#'   1. LT: getDatrasFieldList documents only 22 of LT's 58 real fields.
#'   2. LT: 3 of those 22 (Platform/StationName/HaulNumber) claim no
#'      rename; real data has Ship/StNo/HaulNo (resolved here via tier 2).
#'   3. LT: documents a RecordHeader/RecordType field that doesn't exist
#'      in LT's real data at all (neither the live response nor the
#'      archive) -- the reverse problem from #1.
#'   4. CA: IndividualAge's documented old name ("AgeRings") isn't a real
#'      field; real name is "Age" (resolved here as `no_evidence`, since
#'      the *new*-name half of that same row is consequently unverified).
#'   5. HH: DateofCalculation is a real field, undocumented under any name.
#'   6. HL: DateofCalculation and Valid_Aphia, same as #5.
#'
#' @param tables Character vector: which RecordHeaders to *return* (default
#'   opus's Tier 1 scope). Resolution always runs over the full Tier 1 set
#'   regardless, because tier 2 borrows evidence across tables; narrowing
#'   this only narrows the output.
#' @return Data frame: RecordHeader, old_name, new_name, source_tier, note.
#' @export
op_datras_field_list <- function(tables = c("HH", "HL", "CA", "LT")) {
  operation_for <- c(HH = "getHHdata", HL = "getHLdata", CA = "getCAdata",
                     LT = "getLitterAssessmentOutput")
  requested <- intersect(tables, names(operation_for))

  # Tier 2 resolves a rename by borrowing another table's `confirmed`
  # mapping, so the evidence pool must always be the full Tier 1 set even
  # when the caller wants one table. Resolving only the requested tables
  # silently degrades the result rather than erroring: asked for "LT" alone,
  # 37 of its 58 fields lose their rename and keep legacy names, because
  # ICES's metadata documents Ship/StNo/HaulNo (and 34 more) as renamed for
  # HH/HL/CA but not for LT. Subset at the end, never at the start.
  tables <- names(operation_for)

  fl <- op_datras_field_metadata()
  fl <- fl[fl$RecordHeader %in% tables, ]
  fl$FieldNameOld[fl$FieldNameOld == "-"] <- fl$FieldName[fl$FieldNameOld == "-"]

  real_fields <- lapply(operation_for[tables], .fetch_datras_operation_fields)
  names(real_fields) <- tables

  confirmed_rows <- lapply(tables, function(rh) {
    sub <- fl[fl$RecordHeader == rh, ]
    sub[sub$FieldNameOld %in% real_fields[[rh]], c("FieldNameOld", "FieldName")]
  })
  cross_table_lookup <- unique(do.call(rbind, confirmed_rows))

  resolve_table <- function(rh) {
    sub <- fl[fl$RecordHeader == rh, ]
    out <- data.frame(RecordHeader = rh, old_name = real_fields[[rh]],
                       new_name = NA_character_, source_tier = NA_character_,
                       note = "", stringsAsFactors = FALSE)
    unresolved <- rep(TRUE, nrow(out))
    for (i in seq_len(nrow(out))) {
      on <- out$old_name[i]
      direct <- sub$FieldName[sub$FieldNameOld == on]
      if (length(direct) == 1) {
        out$new_name[i] <- direct
        out$source_tier[i] <- "confirmed"
        unresolved[i] <- FALSE
        next
      }
      x <- cross_table_lookup$FieldName[cross_table_lookup$FieldNameOld == on]
      if (length(unique(x)) == 1) {
        out$new_name[i] <- unique(x)
        out$source_tier[i] <- "cross_table_confirmed"
        unresolved[i] <- FALSE
      }
    }
    out$new_name[unresolved] <- out$old_name[unresolved]
    out$source_tier[unresolved] <- "no_evidence"

    dangling <- sub[!(sub$FieldNameOld %in% real_fields[[rh]]) &
                      sub$FieldNameOld != sub$FieldName &
                      !(sub$FieldName %in% out$new_name[!unresolved]), ]
    if (nrow(dangling) > 0 && any(unresolved)) {
      notes <- sprintf(
        "ICES documents a field '%s' paired with old-name '%s', not in this operation's live response -- unverified, not used to assign a rename (%d unexplained real field(s) remain: %s).",
        dangling$FieldName, dangling$FieldNameOld,
        sum(unresolved), paste(out$old_name[unresolved], collapse = ", ")
      )
      out$note[unresolved] <- paste(notes, collapse = " | ")
    }
    out
  }

  out <- do.call(rbind, lapply(tables, resolve_table))
  out[out$RecordHeader %in% requested, , drop = FALSE]
}

#' Build a rename-ready legacy -> new name crosswalk for one or more tables
#'
#' Thin wrapper around [op_datras_field_list()] for callers that need a
#' clean, collision-free 1:1 `old_name` -> `new_name` map to actually rename
#' columns with (`data-raw/spec/spec_03_translate_new_names.R`,
#' `data-raw/archive_06_split_legacy_new.R`) -- as opposed to
#' [op_datras_field_list()]'s own broader, diagnostic purpose (reporting
#' every candidate rename along with its confidence tier, for auditing).
#'
#' Applies one documented, opus-side correction on top of
#' [op_datras_field_list()]'s raw output: LT's real `Depth` column is
#' cross-table-inferred to rename to `BottomDepth` (HH's own confirmed
#' rename for the same old name), but LT genuinely has its own separate,
#' real `BottomDepth` column too -- byte-for-byte duplicate values, but two
#' distinct fields (ICES-side redundancy, not a naming variant; see
#' `data-raw/ICES_ISSUE_REPORT.md`, Issue 6). Renaming `Depth` -> `BottomDepth`
#' here would collide two real LT columns into one name. Left unrenamed
#' (`old_name == new_name == "Depth"`) instead.
#'
#' @param tables Character vector: which RecordHeaders to resolve (default
#'   opus's Tier 1 scope).
#' @return Data frame: RecordHeader, old_name, new_name -- exactly one row
#'   per real column, safe to use directly as a rename map (no table's
#'   new_name values collide with each other).
#' @export
op_datras_rename_crosswalk <- function(tables = c("HH", "HL", "CA", "LT")) {
  fl <- op_datras_field_list(tables)

  lt_depth <- fl$RecordHeader == "LT" & fl$old_name == "Depth"
  if (any(lt_depth)) fl$new_name[lt_depth] <- fl$old_name[lt_depth]

  # Guard, not a soft check: confirm no table ends up with a rename
  # collision (two old_names mapping to the same new_name) -- would break
  # any 1:1 rename applied directly from this crosswalk. Checks generally
  # rather than just re-testing the one known LT/Depth case, in case a
  # similar collision ever turns up elsewhere.
  for (rh in unique(fl$RecordHeader)) {
    sub <- fl[fl$RecordHeader == rh, ]
    dup <- sub$new_name[duplicated(sub$new_name)]
    if (length(dup) > 0) {
      stop("op_datras_rename_crosswalk(): table '", rh, "' has colliding ",
           "new_name(s): ", paste(unique(dup), collapse = ", "),
           " -- not safe to use as a rename map.", call. = FALSE)
    }
  }

  fl[, c("RecordHeader", "old_name", "new_name")]
}

#' Extract legacy field name from column details
#'
#' Parses the "Legacy field name:" prefix from a column's details field to
#' extract the old ICES field name. Used for backward compatibility and
#' cross-referencing with ICES's own field-list metadata (fetched directly
#' via [op_datras_field_list()], not the icesDatras package).
#'
#' @param details Character string from a column's `details` field in data-dict.yaml
#'
#' @return Character: legacy field name, or `NA_character_` if not found
#'
#' @examples
#' \dontrun{
#'   # Typical usage: extract from parsed YAML
#'   details <- "Legacy field name: SweepLngt (verified via op_datras_field_list())..."
#'   op_legacy_field_name(details)
#'   # Returns "SweepLngt"
#' }
#'
#' @details
#' Format: The legacy name is stored as a fixed-prefix line in the details field:
#' `Legacy field name: \{OldName\} (verified via op_datras_field_list()).`
#'
#' This approach:
#' - Complies with data-dict v0.1.0 spec (details is free-text)
#' - Is human-readable AND machine-readable (regex extraction)
#' - Survives YAML round-trips (write_yaml → read_yaml)
#' - Requires no non-standard YAML keys
#'
#' See `vignettes/articles/technical-notes.md` for design rationale.
#'
#' @export
op_legacy_field_name <- function(details) {
  if (is.null(details) || is.na(details)) {
    return(NA_character_)
  }

  m <- regexec("Legacy field name: (\\w+)", details)
  match <- regmatches(details, m)

  if (length(match) > 0 && length(match[[1]]) > 1) {
    match[[1]][2]
  } else {
    NA_character_
  }
}

#' Build field name mapping from data-dict YAML
#'
#' Extracts legacy → new field name mappings for all columns in a parsed
#' data-dict YAML. Useful for building equivalence tables, validating
#' coverage, or generating documentation.
#'
#' @param dict List: parsed DATRAS-imbus.yaml (from `yaml::read_yaml()`)
#' @param table_name Character: optional filter to one table (HH, HL, CA, LT)
#'
#' @return Data frame with columns:
#' \describe{
#'   \item{RecordHeader}{Table name (HH, HL, CA, LT)}
#'   \item{new_name}{Current field name (from YAML column `name`)}
#'   \item{old_name}{Legacy field name (extracted from `details`), or NA}
#'   \item{has_legacy}{Logical: TRUE if a legacy name was found}
#' }
#'
#' @examples
#' \dontrun{
#'   dict <- yaml::read_yaml("inst/DATRAS-imbus.yaml")
#'   mapping <- op_field_name_map(dict)
#'
#'   # All HH table field renames
#'   hh_map <- op_field_name_map(dict, table_name = "HH")
#'
#'   # Count coverage
#'   sum(hh_map$has_legacy)  # How many HH fields have legacy name documented?
#' }
#'
#' @details
#' Iterates over all tables and columns, extracts legacy names via
#' `op_legacy_field_name()`, and returns as a flat data frame for
#' easier analysis/reporting.
#'
#' @export
op_field_name_map <- function(dict, table_name = NULL) {
  rows <- list()
  row_count <- 0

  for (table in dict$tables) {
    if (!is.null(table_name) && table$name != table_name) {
      next
    }

    for (col in table$columns) {
      old <- op_legacy_field_name(col$details)
      row_count <- row_count + 1
      rows[[row_count]] <- data.frame(
        RecordHeader = table$name,
        new_name = col$name,
        old_name = old,
        has_legacy = !is.na(old),
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0) {
    # Return empty data frame with correct columns
    data.frame(
      RecordHeader = character(),
      new_name = character(),
      old_name = character(),
      has_legacy = logical(),
      stringsAsFactors = FALSE
    )
  } else {
    do.call(rbind, rows)
  }
}

#' Build a combined old-name / new-name / type spec from opus's shipped dictionary
#'
#' Reads `inst/DATRAS-imbus.yaml` (opus's curated, archive-grounded
#' dictionary, keyed by current field names) and pairs each column with its
#' legacy (ICES on-the-wire) name, which [op_translate_dict_names()] stamps
#' into the column's `details` as `Legacy field name: {old}.` at build time.
#' Reads only the one YAML file opus ships -- no live ICES web-service calls,
#' no second dictionary file -- so it's cheap enough to call on every use.
#'
#' @param table_name Character scalar: restrict to one RecordHeader (`"HH"`,
#'   `"HL"`, `"CA"`, `"LT"`). `NULL` (default) returns all four.
#'
#' @return Data frame: `RecordHeader`, `old_name` (ICES's legacy,
#'   on-the-wire name), `new_name` (opus's current curated name), `type`
#'   (the raw data-dict spec vocabulary string -- `"string"`, `"enum"`,
#'   `"number(id)"`, `"number(ordinal)"`, `"number(quantity)"`, ... --
#'   unmodified; mapping this to an R storage type is left to the caller,
#'   consistent with opus shipping metadata rather than performing data
#'   transformation itself).
#'
#' @examples
#' \dontrun{
#'   opus::op_field_spec("CA")
#' }
#'
#' @export
op_field_spec <- function(table_name = NULL) {
  dict <- yaml::read_yaml(system.file("DATRAS-imbus.yaml", package = "opus"))

  table_names <- vapply(dict$tables, function(t) t$name, character(1))

  rows <- list()
  for (tname in table_names) {
    if (!is.null(table_name) && tname != table_name) next

    tbl <- dict$tables[[which(table_names == tname)]]
    for (col in tbl$columns) {
      old_name <- op_legacy_field_name(col$details)
      if (is.na(old_name)) {
        stop(sprintf(
          paste0("op_field_spec(): %s.%s carries no 'Legacy field name:' stamp ",
                 "in its details -- the shipped dictionary is expected to be ",
                 "self-contained for both naming schemes. Rebuild it via ",
                 "data-raw/spec/spec_03_translate_new_names.R."),
          tname, col$name
        ), call. = FALSE)
      }
      rows[[length(rows) + 1]] <- data.frame(
        RecordHeader = tname,
        old_name = old_name,
        new_name = col$name,
        type = col$type,
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0) {
    return(data.frame(
      RecordHeader = character(), old_name = character(),
      new_name = character(), type = character(),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

#' Translate a parsed DATRAS dictionary from legacy to current field names
#'
#' A pure rename of a parsed data-dict dictionary (an R list, as from
#' [yaml::read_yaml()]): every type/units/range/examples/constraints/label
#' value carries over unchanged; only column `name`s differ. Also:
#'
#' * translates column references inside `relationships` joins and
#'   `conflicts`, table `definitions` expressions, and any `assert`
#'   constraint expressions (column- and table-level);
#' * stamps each column's `details` with `Legacy field name: {old}.`, so the
#'   renamed dictionary stays self-contained for both naming schemes --
#'   [op_legacy_field_name()] reads the stamp back, and [op_field_spec()]
#'   depends on it.
#'
#' The rename map is [op_datras_rename_crosswalk()], ground-truthed against
#' the dictionary's real columns first: every column must resolve to exactly
#' one new name, and the crosswalk must not carry names the dictionary lacks
#' -- a mismatch fails loudly rather than silently renaming only some
#' columns. This is the ONLY step in opus's spec pipeline that introduces
#' new names; seeding and curation are keyed by legacy names throughout.
#'
#' @param dict List: parsed dictionary keyed by legacy (ICES on-the-wire)
#'   field names.
#' @param crosswalk Data frame from [op_datras_rename_crosswalk()];
#'   injectable so a caller translating several dictionaries resolves it
#'   once.
#'
#' @return The same dictionary, keyed by current names.
#'
#' @examples
#' \dontrun{
#'   legacy <- yaml::read_yaml("data-raw/seed/DATRAS-curated-legacy.yaml")
#'   current <- op_translate_dict_names(legacy)
#' }
#'
#' @export
op_translate_dict_names <- function(dict, crosswalk = op_datras_rename_crosswalk()) {
  dict <- rewrap_singleton_arrays(dict)

  # Ground-truth the crosswalk against the dictionary's real columns: every
  # column must resolve to exactly one new name, and the crosswalk must not
  # carry names the dictionary lacks.
  for (tbl in dict$tables) {
    expected_old <- vapply(tbl$columns, function(c) c$name, character(1))
    xw <- crosswalk[crosswalk$RecordHeader == tbl$name, ]

    only_in_dict <- setdiff(expected_old, xw$old_name)
    only_in_crosswalk <- setdiff(xw$old_name, expected_old)

    if (length(only_in_dict) > 0 || length(only_in_crosswalk) > 0) {
      stop(sprintf(
        paste0("op_translate_dict_names(): table %s: crosswalk doesn't match the ",
               "dictionary's real columns.\n  In dict, not in crosswalk: %s\n  ",
               "In crosswalk, not in dict: %s"),
        tbl$name, paste(only_in_dict, collapse = ", "), paste(only_in_crosswalk, collapse = ", ")
      ), call. = FALSE)
    }
    message("Ground-truthed ", tbl$name, ": all ", length(expected_old),
            " legacy names resolve to exactly one new name")
  }

  # Rename every column, stamp its legacy name into details, translate any
  # column-level assert expressions.
  rename_maps <- list()
  for (ti in seq_along(dict$tables)) {
    tname <- dict$tables[[ti]]$name
    xw <- crosswalk[crosswalk$RecordHeader == tname, ]
    rename_map <- setNames(xw$new_name, xw$old_name)
    rename_maps[[tname]] <- rename_map

    for (ci in seq_along(dict$tables[[ti]]$columns)) {
      col <- dict$tables[[ti]]$columns[[ci]]
      old_name <- col$name
      col$name <- unname(rename_map[[old_name]])

      stamp <- sprintf("Legacy field name: %s.", old_name)
      col$details <- if (is.null(col$details)) stamp else paste(stamp, col$details)

      if (!is.null(col$constraints)) {
        col$constraints <- lapply(col$constraints, function(k) {
          if (is.list(k) && !is.null(k$assert)) {
            k$assert <- translate_dict_expr(k$assert, rename_map)
          }
          k
        })
      }
      dict$tables[[ti]]$columns[[ci]] <- col
    }
  }

  # Translate relationships' join expressions and conflicts (table.column
  # tokens), same crosswalk data applied to text instead of `name` fields.
  if (!is.null(dict$relationships)) {
    token_pattern <- "([A-Za-z_][A-Za-z0-9_]*)\\.([A-Za-z_][A-Za-z0-9_]*)"

    translate_join <- function(join_expr) {
      m <- gregexpr(token_pattern, join_expr, perl = TRUE)
      tokens <- regmatches(join_expr, m)[[1]]
      regmatches(join_expr, m)[[1]] <- vapply(tokens, function(tok) {
        parts <- strsplit(tok, ".", fixed = TRUE)[[1]]
        new_col <- rename_maps[[parts[1]]][[parts[2]]]
        if (is.null(new_col)) {
          stop("No rename mapping for '", tok, "' in a relationship's join -- ",
               "crosswalk/relationships have drifted apart.", call. = FALSE)
        }
        paste0(parts[1], ".", new_col)
      }, character(1))
      join_expr
    }

    for (ri in seq_along(dict$relationships)) {
      dict$relationships[[ri]]$join <- translate_join(dict$relationships[[ri]]$join)
    }

    # `conflicts` columns: every one is, by construction, a column HH also
    # has, so HH's own rename map resolves them. Re-wrap as a list
    # explicitly: read_yaml() parses a one-item YAML sequence back as a
    # length-1 character vector, which write_yaml() would render as a bare
    # scalar instead of an array.
    for (ri in seq_along(dict$relationships)) {
      conf <- dict$relationships[[ri]]$conflicts
      if (is.null(conf)) next
      dict$relationships[[ri]]$conflicts <- as.list(vapply(conf, function(old) {
        new_col <- rename_maps[["HH"]][[old]]
        if (is.null(new_col)) {
          stop("No rename mapping for conflicts column '", old, "' -- ",
               "crosswalk/relationships have drifted apart.", call. = FALSE)
        }
        new_col
      }, character(1), USE.NAMES = FALSE))
    }

    # Ground-truth: every translated reference must exist on its
    # (already-renamed) table.
    for (rel in dict$relationships) {
      tokens <- regmatches(rel$join, gregexpr(token_pattern, rel$join, perl = TRUE))[[1]]
      for (tok in tokens) {
        parts <- strsplit(tok, ".", fixed = TRUE)[[1]]
        tbl <- dict$tables[[which(vapply(dict$tables, function(t) t$name, character(1)) == parts[1])]]
        if (!(parts[2] %in% vapply(tbl$columns, function(c) c$name, character(1)))) {
          stop("Translated relationship references '", tok, "', not a real column of ",
               parts[1], call. = FALSE)
        }
      }
    }
    message("Translated ", length(dict$relationships), " relationship join(s) to curated names")
  }

  # Translate table-level constraints' assert expressions and table
  # definitions' expressions. Both are single-table (bare column names, not
  # table.column-qualified): whole-word identifier tokens that match one of
  # THAT table's own legacy column names get renamed; tokens that aren't
  # column names (operators, function names) never match the rename map and
  # pass through untouched.
  for (ti in seq_along(dict$tables)) {
    tbl <- dict$tables[[ti]]
    rename_map <- rename_maps[[tbl$name]]

    if (!is.null(tbl$constraints)) {
      tbl$constraints <- lapply(tbl$constraints, function(k) {
        if (is.list(k) && !is.null(k$assert)) {
          k$assert <- translate_dict_expr(k$assert, rename_map)
        }
        k
      })
    }

    if (!is.null(tbl$definitions)) {
      for (di in seq_along(tbl$definitions)) {
        tbl$definitions[[di]]$expr <- translate_dict_expr(tbl$definitions[[di]]$expr, rename_map)
      }
    }

    dict$tables[[ti]] <- tbl
  }

  dict
}

# yaml::read_yaml() silently collapses a single-element YAML sequence back
# into a bare scalar on read (confirmed directly: `constraints:\n- required`
# round-trips to a plain character "required", not a length-1 list) -- a
# data-dict spec violation on write-back, since the spec requires an array
# here regardless of length. A length>1 sequence round-trips fine as a plain
# atomic vector, and a NAMED length-1 map (e.g. RecordHeader's
# `values: {HH: ...}`) round-trips fine too and must NOT be touched.
# Constraints that are assertion MAPS (list entries carrying `$assert`) are
# likewise already lists and must not be re-wrapped -- only bare atomic
# scalars need it.
rewrap_singleton_arrays <- function(dict) {
  array_fields <- c("constraints", "examples", "values")
  for (ti in seq_along(dict$tables)) {
    for (ci in seq_along(dict$tables[[ti]]$columns)) {
      col <- dict$tables[[ti]]$columns[[ci]]
      for (f in array_fields) {
        v <- col[[f]]
        if (!is.null(v) && length(v) == 1 && is.null(names(v)) && is.atomic(v)) {
          col[[f]] <- list(v)
        }
      }
      dict$tables[[ti]]$columns[[ci]] <- col
    }
  }
  dict
}

# Whole-word identifier translation within a single-table expression
# (definition `expr`, column/table `assert`): replaces tokens that match one
# of the table's legacy column names; every other token passes through.
translate_dict_expr <- function(expr, rename_map) {
  identifier_pattern <- "[A-Za-z_][A-Za-z0-9_]*"
  m <- gregexpr(identifier_pattern, expr, perl = TRUE)
  tokens <- regmatches(expr, m)[[1]]
  regmatches(expr, m)[[1]] <- vapply(tokens, function(tok) {
    if (tok %in% names(rename_map)) unname(rename_map[[tok]]) else tok
  }, character(1))
  expr
}
