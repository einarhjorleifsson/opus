#' Generate skeleton data-dict YAML from parquet files
#'
#' Uses the data-dict CLI `draft` command to create a starting data-dict.yaml
#' from parquet file(s). The output includes:
#' - Inferred column types from actual data
#' - Real examples from the parquet
#' - Helpful TODO comments for human curation
#' - Proper `source:` metadata linking back to parquet
#'
#' The output YAML always passes `validate-spec`, ready for incremental curation.
#'
#' @param parquet_paths Character vector of paths to .parquet files
#' @param output_path Path to write data-dict.yaml (default: "inst/DATRAS-data-dict.yaml")
#' @param verbose Print command and result (default: TRUE)
#'
#' @return Invisibly, the output path. Side effect: writes or appends to YAML file.
#'
#' @export
op_draft_from_parquet <- function(parquet_paths,
                                  output_path = "inst/DATRAS-data-dict.yaml",
                                  verbose = TRUE) {

  # Ensure output directory exists
  output_dir <- dirname(output_path)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # Find data-dict CLI binary (in obus for now)
  cli_path <- file.path(
    system.file(package = "opus"),  # or hardcode path if needed
    "../../../obus/inst/extdata/data-dict-cli/data-dict"
  )

  if (!file.exists(cli_path)) {
    # Fallback: check obus path directly
    cli_path <- "/Users/einarhj/R/Pakkar/obus/inst/extdata/data-dict-cli/data-dict"
  }

  if (!file.exists(cli_path)) {
    stop("data-dict CLI not found. Expected at: ", cli_path)
  }

  # Build command
  cmd <- c(cli_path, "draft", "--output", output_path, parquet_paths)

  if (verbose) {
    cat("Running: ", paste(cmd, collapse = " "), "\n")
  }

  # Execute
  result <- system2(cmd[1], args = cmd[-1], stdout = TRUE, stderr = TRUE)

  if (verbose) {
    cat(paste(result, collapse = "\n"), "\n")
  }

  invisible(output_path)
}
