#' Write a parsed dictionary to YAML with opus's canonical post-processing
#'
#' Wraps [yaml::write_yaml()] with the two text-level post-processors opus's
#' spec pipeline applies to every dictionary it writes:
#'
#' 1. `description:`/`details:` scalars are converted to folded (`>-`) block
#'    style, matching data-dict's own canonical examples. `write_yaml()` has
#'    no option for this -- it emits plain or single-quoted style depending
#'    on content, never `>` -- so this rewrites the already-written file's
#'    raw text. Safe because a line break inside a folded scalar collapses to
#'    one space when parsed, exactly as it does in the plain/quoted styles it
#'    replaces: only delimiters and `''` un-escaping change, never the parsed
#'    value (verified via a full parsed-value round-trip comparison,
#'    2026-08-18). `>-` (strip chomping), not bare `>`, because bare `>`
#'    keeps one trailing newline the original value never had.
#' 2. Number-looking `examples` on `string` columns are single-quoted
#'    (`'74E9'`), which the data-dict spec requires (S12: a string example
#'    that reads as a number counts only if quoted) but `write_yaml()` does
#'    not preserve. Only `string` columns are touched -- `number(id)`
#'    examples stay unquoted numbers.
#'
#' Both are verbatim extractions of what `data-raw/spec/spec_02_curate_dict.R`
#' and `spec_03_translate_new_names.R` used to each carry inline; they exist
#' here once so every dictionary the pipeline writes gets identical
#' treatment (Working Principle 7b).
#'
#' @param dict List: parsed data-dict dictionary (as from
#'   [yaml::read_yaml()] or built in R).
#' @param path Character scalar: file path to write.
#' @return `path`, invisibly.
#'
#' @examples
#' \dontrun{
#'   op_write_dict_yaml(dict, "inst/DATRAS-imbus.yaml")
#' }
#'
#' @export
op_write_dict_yaml <- function(dict, path) {
  yaml::write_yaml(dict, path)
  fold_long_scalars(path)
  quote_number_like_string_examples(path)
  invisible(path)
}

# Post-processor 1: fold `description:`/`details:` scalars to `>-` blocks.
# See op_write_dict_yaml() for why this is text-level and why it is safe.
fold_long_scalars <- function(outfile) {
  lines <- readLines(outfile)
  key_indent <- function(s) nchar(regmatches(s, regexpr("^\\s*", s))[[1]])
  out <- character(0)
  i <- 1
  while (i <= length(lines)) {
    line <- lines[i]
    m <- regexec("^(\\s*)(description|details): (.*)$", line)
    parts <- regmatches(line, m)[[1]]
    if (length(parts) == 0 || parts[4] %in% c("|-", ">", ">-", "|", "|+")) {
      out <- c(out, line); i <- i + 1; next
    }
    indent <- parts[2]; key <- parts[3]; first_val <- parts[4]
    this_indent <- nchar(indent)
    block <- c(first_val)
    j <- i + 1
    while (j <= length(lines) && nchar(lines[j]) > 0 && key_indent(lines[j]) > this_indent) {
      block <- c(block, sub("^\\s+", "", lines[j]))
      j <- j + 1
    }
    if (grepl("^'", block[1])) {
      block[1] <- sub("^'", "", block[1])
      last <- length(block)
      block[last] <- sub("'$", "", block[last])
      block <- gsub("''", "'", block, fixed = TRUE)
    }
    out <- c(out, paste0(indent, key, ": >-"), paste0(indent, "  ", block))
    i <- j
  }
  writeLines(out, outfile)
}

# Post-processor 2: quote number-looking `examples` on `string` columns.
# Scans the written file's text: on hitting `type: string`, finds that
# column's `examples:` block (before the next `- name: `) and quotes any
# unquoted value that reads as a number/hex code.
quote_number_like_string_examples <- function(outfile) {
  lines <- readLines(outfile)
  i <- 1
  while (i <= length(lines)) {
    if (grepl("^\\s+type: string\\s*$", lines[i])) {
      j <- i + 1
      while (j <= length(lines) && !grepl("^\\s+- name: ", lines[j])) {
        if (grepl("^\\s+examples:\\s*$", lines[j])) {
          j <- j + 1
          while (j <= length(lines) && grepl("^\\s+- ", lines[j])) {
            match <- regexpr("- (.+)$", lines[j])
            if (match > 0) {
              value <- regmatches(lines[j], match)
              value <- sub("^- ", "", value)
              if (!grepl("^['\"]", value) && (grepl("^[0-9A-Fa-f]+$", value) || grepl("^[0-9A-Fa-f]*[E|D]", value))) {
                indent <- regmatches(lines[j], regexpr("^\\s+", lines[j]))
                lines[j] <- paste0(indent, "- '", value, "'")
              }
            }
            j <- j + 1
          }
          break
        }
        j <- j + 1
      }
    }
    i <- i + 1
  }
  writeLines(lines, outfile)
}
