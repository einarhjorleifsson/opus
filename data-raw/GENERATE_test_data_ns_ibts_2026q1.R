# Generate test parquet datasets for opus validation testing
# Focused: NS-IBTS survey, Year 2026, Quarter 1
#
# This script extracts a realistic subset of DATRAS data for testing
# the validation functions across all four Tier 1 tables (HH, HL, CA, LT).
#
# Data source: obus parquet files
# Output: inst/*.parquet files (tracked via Git LFS)

library(dplyr)
library(duckdbfs)

# Tier 1 tables
tables <- c("HH", "HL", "CA", "LT")
obus_path <- "~/R/Pakkar/obus/data-raw/to_https/xml"
survey <- "NS-IBTS"
year <- 2026
quarter <- 1

message("Generating test datasets for ", survey, " ", year, " Q", quarter, "...")

for (table in tables) {
  message("\nProcessing ", table, "...")

  # Path to obus source (partitioned by Survey and Year)
  source_path <- file.path(obus_path, table,
                           paste0("Survey=", survey),
                           paste0("Year=", year))
  output_path <- file.path("inst", paste0(table, ".parquet"))

  if (!dir.exists(source_path)) {
    warning("Source path not found: ", source_path)
    next
  }

  # Read from parquet source
  df <- duckdbfs::open_dataset(source_path) |>
    # Filter to Q1 data
    dplyr::filter(Quarter == !!quarter) |>
    dplyr::collect()

  if (nrow(df) == 0) {
    warning("No data found for ", survey, " ", year, " Q", quarter, " in table ", table)
    next
  }

  # Write to inst/
  duckdbfs::write_dataset(df, output_path)

  message("✓ ", table, ": ", nrow(df), " rows -> ", output_path)
}

message("\n✓ Test datasets generated in inst/")
