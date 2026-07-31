# Wrapper around the `data-dict` CLI (~/garbage/data-dict, Rust, language-
# agnostic -- opus's own R usage is incidental, not something the CLI itself
# knows or cares about) to test a real dataset against inst/DATRAS-data-dict.yaml.
# Exploratory/dev tool, not part of opus's shipped content (opus ships no R
# functions, ever -- AGENTS.md's Working principles, rule 7) -- lives in
# data-raw/, sourced by hand when wanted, never in R/.
#
# Why a temp copy of the dict, not inst/DATRAS-data-dict.yaml directly: the
# `validate-meta`/`validate-data` subcommands both require the table being
# checked to declare a `source: parquet: <path>` (spec.md, "Source"), but
# opus's shipped yaml deliberately has none -- a machine-specific absolute
# path baked into the shipped dictionary would tie it to one person's local
# archive layout, which cuts against the whole point of a portable,
# language-agnostic spec. So this function injects `source` into an in-
# memory copy for just the one table being tested, writes THAT to a
# tempfile, points the CLI at it, and leaves inst/DATRAS-data-dict.yaml
# untouched.
#
# data-dict is a fast-moving, pre-1.0 tool (AGENTS.md's Format section) --
# this wrapper deliberately only leans on its --help-documented interface
# (subcommand, <DICT>, --table, --json) and passes the parsed JSON straight
# through rather than building a typed model of its result shape, so it
# doesn't silently break the next time that shape changes. Confirmed once,
# 2026-07-29, against the release binary's own --help text for validate-meta/
# validate-data/types -- not read further into the CLI's Rust source.

validate_against_dict <- function(data_path,
                                   table,
                                   level = c("data", "meta"),
                                   dict_path = "inst/DATRAS-data-dict.yaml",
                                   cli_bin = "~/garbage/data-dict/target/release/data-dict") {
  level <- match.arg(level)
  cli_bin <- path.expand(cli_bin)
  if (!file.exists(cli_bin)) {
    stop(
      "data-dict CLI not found at ", cli_bin, " -- build it first:\n",
      "  cd ~/garbage/data-dict && cargo build --release -p data-dict-cli",
      call. = FALSE
    )
  }

  # handlers = list(seq = as.list): without this, yaml::read_yaml() silently
  # simplifies any single-item YAML sequence (e.g. `constraints: [required]`)
  # into a length-1 atomic vector, indistinguishable from a bare scalar --
  # yaml::write_yaml() then re-serializes it AS a scalar (`constraints:
  # required`), which the CLI correctly rejects (it expects an array).
  # Confirmed 2026-07-29 by round-tripping inst/DATRAS-data-dict.yaml without
  # this handler and hitting exactly that error against real HH data. Forcing
  # every sequence to stay a list, regardless of length or uniformity,
  # preserves the original structure through the read-modify-write done here.
  dict <- yaml::read_yaml(dict_path, handlers = list(seq = function(x) as.list(x)))
  table_names <- vapply(dict$tables, function(t) t$name, character(1))
  ti <- which(table_names == table)
  if (length(ti) != 1) {
    stop("Table '", table, "' not found in ", dict_path, call. = FALSE)
  }

  # Per spec.md's Source section: parquet may be a file path or a glob.
  # Passed through as given -- not resolved/validated here.
  dict$tables[[ti]]$source <- list(parquet = path.expand(data_path))

  tmp_dict <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp_dict), add = TRUE)
  yaml::write_yaml(dict, tmp_dict)

  subcommand <- if (level == "data") "validate-data" else "validate-meta"
  args <- c(subcommand, tmp_dict, "--table", table, "--json")

  # stdout and stderr captured separately (not merged) so a stray diagnostic
  # line on stderr can never corrupt the --json payload on stdout.
  err_file <- tempfile()
  on.exit(unlink(err_file), add = TRUE)
  stdout_lines <- system2(cli_bin, args, stdout = TRUE, stderr = err_file)
  status <- attr(stdout_lines, "status")
  status <- if (is.null(status)) 0L else status
  stderr_lines <- if (file.exists(err_file)) readLines(err_file, warn = FALSE) else character(0)

  raw_stdout <- paste(stdout_lines, collapse = "\n")
  parsed <- tryCatch(
    jsonlite::fromJSON(raw_stdout, simplifyVector = FALSE),
    error = function(e) NULL
  )

  list(
    command      = paste(c(cli_bin, args), collapse = " "),
    exit_status  = status,
    result       = parsed,       # NULL if stdout wasn't valid JSON -- check raw_stdout/stderr
    raw_stdout   = stdout_lines,
    stderr       = stderr_lines
  )
}

# Example (not run automatically):
#
# res <- validate_against_dict(
#   data_path = "~/R/Pakkar/obus/data-raw/to_https/HH.parquet",
#   table     = "HH",
#   level     = "data"
# )
# res$result       # parsed --json output, shape owned by the CLI, not this wrapper
# res$exit_status  # 0 typically means "ran successfully" -- check $result for pass/fail,
#                   # not exit_status alone (confirm against a real run before relying on this)
