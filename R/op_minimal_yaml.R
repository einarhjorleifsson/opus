#' Generate minimal type-only YAML from WSDL
#'
#' Creates a temporary YAML with only name + type for each field.
#' Passes through data-dict CLI metatests to enable Phase 2 parsing.
#'
#' @param output_path File path to write minimal YAML
#' @param verbose Print progress
#'
#' @return Invisibly, the list structure (also written to YAML)
#'
#' @export
op_minimal_yaml <- function(output_path = "inst/DATRAS-types-minimal.R", verbose = TRUE) {
  source("data-raw/spec_00_operation_types.R")

  tier1_tables <- c("HH", "HL", "CA", "LT")
  record_operations <- c(
    HH = "getHHdata",
    HL = "getHLdata",
    CA = "getCAdata",
    LT = "getLitterAssessmentOutput"
  )

  # Map WSDL types to data-dict spec types
  wsdl_to_dict_type <- function(wsdl_type) {
    dplyr::case_when(
      wsdl_type == "string" ~ "string",
      wsdl_type == "int" ~ "number",
      wsdl_type == "decimal" ~ "number",
      wsdl_type == "float" ~ "number",
      TRUE ~ NA_character_
    )
  }

  if (verbose) message("Crawling WSDL for Tier 1 field types...")
  valid_ops <- get_datras_operations()

  # Crawl WSDL for each table
  tables_list <- list()

  for (rt in tier1_tables) {
    op <- record_operations[[rt]]
    if (verbose) message("  ", rt, " (from ", op, ")...")

    wsdl_fields <- get_datras_operation_types(op, valid_operations = valid_ops)

    columns_list <- lapply(seq_len(nrow(wsdl_fields)), function(i) {
      list(
        name = wsdl_fields$field[i],
        type = wsdl_to_dict_type(wsdl_fields$type[i])
      )
    })

    tables_list[[length(tables_list) + 1]] <- list(
      name = rt,
      columns = columns_list
    )
  }

  # Construct minimal YAML structure (tables as array, not object)
  minimal_yaml <- list(
    `$version` = "0.1.0",
    `$learn_more` = "http://data-dict.tidyverse.org/",
    name = "datras_exchange",
    label = "ICES DATRAS Exchange Data (Tier 1 -- minimal type-only)",
    description = "Temporary dictionary with types only from WSDL. Used for Phase 2 XML parsing.",
    tables = tables_list
  )

  # Write YAML
  yaml::write_yaml(minimal_yaml, output_path)
  if (verbose) message("Wrote minimal YAML to ", output_path)

  invisible(minimal_yaml)
}

# get_datras_operations()/get_datras_operation_types() come from
# data-raw/spec_00_operation_types.R, sourced at call-time above -- not
# real package globals, so R CMD check can't see them statically.
utils::globalVariables(c("get_datras_operations", "get_datras_operation_types"))
