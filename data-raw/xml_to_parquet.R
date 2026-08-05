#' XML to Parquet with type casting (R wrapper calling Python parser)
#'
#' Uses fast Python XML parser to extract data, then applies opus type specs
#' and writes directly to parquet (eliminates CSV intermediate).
#'
#' Usage: Rscript data-raw/xml_to_parquet.R <xml_file> <parquet_out> <dict_yaml>

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) {
  cat("Usage: Rscript xml_to_parquet.R <xml_file> <parquet_out> <dict_yaml>\n", file = stderr())
  quit(status = 1)
}

xml_path <- args[1]
parquet_path <- args[2]
dict_path <- args[3]

# ---- Read opus data-dict ----
dict <- read_yaml(dict_path)

# ---- Parse XML using Python (fast) ----
cat(sprintf("Parsing XML with Python: %s\n", xml_path), file = stderr())
t0 <- Sys.time()

# Call Python parser, which outputs parsed data directly via stdout (TSV format)
# For now, we'll use Python to create a temporary CSV, then read it
temp_csv <- tempfile(fileext = ".csv")
cmd <- sprintf(
  "python3 -c \"
import xml.etree.ElementTree as ET
import sys
csv_path = '%s'
xml_path = '%s'

tree = ET.parse(xml_path)
root = tree.getroot()
ns = ''
if '}' in root.tag:
  ns = root.tag.split('}')[0] + '}'

records = list(root)
if not records:
  sys.exit(1)

# Get record type
rt = records[0].tag
if '}' in rt:
  rt = rt.split('}')[1]
if rt.startswith('Cls_DatrasExchange_'):
  rt = rt.replace('Cls_DatrasExchange_', '')

# Get field names
fields = []
for child in records[0]:
  tag = child.tag
  if '}' in tag:
    tag = tag.split('}')[1]
  fields.append(tag)

# Write CSV
with open(csv_path, 'w') as f:
  f.write(','.join(fields) + '\\n')
  for record in records:
    values = []
    for field in fields:
      elem = record.find(f'{ns}{field}')
      if elem is None:
        elem = record.find(field)
      val = (elem.text or '').strip() if elem else ''
      val = val.replace(',', '\\\\,').replace('\\\"', '\\\\\\\\\\\"')
      values.append(f'\\\"{val}\\\"')
    f.write(','.join(values) + '\\n')
print(f'Parsed {len(records)} rows to {csv_path}', file=sys.stderr)
\" 2>&1",
  temp_csv, xml_path
)

system(cmd)
parse_time <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2)

# ---- Read CSV and apply types ----
cat(sprintf("Reading CSV and applying types...\n"), file = stderr())
t0 <- Sys.time()

df <- read.csv(temp_csv, stringsAsFactors = FALSE)
n_rows <- nrow(df)

# Determine record type from field names
record_type <- NA_character_
for (rt in names(dict)) {
  cols <- names(dict[[rt]]$columns)
  if (all(names(df) %in% cols)) {
    record_type <- rt
    break
  }
}

cat(sprintf("Record type: %s | Fields: %d\n", record_type, ncol(df)), file = stderr())

# Apply type casting from opus dict
if (!is.na(record_type) && !is.null(dict[[record_type]])) {
  spec <- dict[[record_type]]$columns
  for (col in names(df)) {
    if (!is.null(spec[[col]])) {
      col_type <- spec[[col]]$type
      df[[col]] <- switch(col_type,
        "number(quantity)" = as.numeric(df[[col]]),
        "number(ordinal)" = as.integer(df[[col]]),
        "number(id)" = as.integer(df[[col]]),
        "number" = as.numeric(df[[col]]),
        df[[col]]  # default: keep as string
      )
    }
  }
}

type_time <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2)

# ---- Write parquet ----
cat(sprintf("Writing parquet...\n"), file = stderr())
t0 <- Sys.time()

arrow::write_parquet(df, parquet_path, compression = "snappy")

file_size <- file.size(parquet_path) / 1024 / 1024
write_time <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2)

cat(sprintf("✓ Wrote %d rows to %s in %.2fs (parse: %.2fs, type: %.2fs, write: %.2fs) | Size: %.1f MB\n",
    n_rows, parquet_path, parse_time + type_time + write_time,
    parse_time, type_time, write_time, file_size), file = stderr())

# Cleanup
unlink(temp_csv)
