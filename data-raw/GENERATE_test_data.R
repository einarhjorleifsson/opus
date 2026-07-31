# Generate test parquet datasets for opus validation testing
#
# Sources real Tier 1 exchange data from obus and writes to inst/ for
# inclusion in the opus package for testing validation functions.
# Run this script to regenerate test data when needed.
#
# Note: These are large files kept for testing during development phase.
# Before pushing to GitHub, consider reducing to sample of key validation
# scenarios rather than full archive.

library(dplyr)
library(duckdbfs)

# Tier 1 tables
tables <- c("HH", "HL", "CA", "LT")
obus_path <- "~/R/Pakkar/obus/data-raw/to_https/xml"

message("Generating test datasets from obus source...")

for (table in tables) {
  message("\nProcessing ", table, "...")

  source_path <- file.path(obus_path, table)
  output_path <- file.path("inst", paste0(table, ".parquet"))

  if (!dir.exists(source_path)) {
    warning("Source path not found: ", source_path)
    next
  }

  # Read from duckdb/parquet source, collect to memory, write out
  df <- duckdbfs::open_dataset(source_path) |>
    dplyr::collect()

  duckdbfs::write_dataset(df, output_path)

  message("✓ ", table, ": ", nrow(df), " rows -> ", output_path)
}

message("\n✓ Test datasets generated in inst/")
