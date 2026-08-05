#' Generate DATRAS Data Dictionary Website
#'
#' Builds a multi-page Quarto website with field dashboards:
#' - Landing page: overview + known issues
#' - One page per table (HH, HL, CA, LT)
#' - Each table has tabs for every field
#' - Each field card shows: type, constraints, description, details, known issues, enum values
#'
#' Usage:
#'   Rscript data-raw/generate_datras_dictionary.R
#'
#' Output:
#'   inst/DATRAS-data-dict-website/
#'
#' Open in browser:
#'   open inst/DATRAS-data-dict-website/index.html

source("data-raw/generate_datras_website.R")
