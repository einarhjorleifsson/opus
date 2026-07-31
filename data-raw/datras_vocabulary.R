# DEPRECATED: This file has been superseded by R/vocab.R, which packages these
# functions as op_vocab_get_types(), op_vocab_resolve_key(), op_vocab_get_codes(),
# and op_vocab_first_usable(). These functions are now exported via the opus package
# and documented with full Roxygen documentation.
#
# This file is kept for reference only and is no longer sourced by any data-raw scripts.
# See DATASET_seed_dict.R for the current pattern: import opus and call the op_vocab_*
# functions directly.
#
# Original documentation (2026-07-23, superseded):
#
# icesVocab code-value lookups for datras_schema's field-level DataFormat/name info.
#
# icesVocab (https://vocab.ices.dk) publishes per-field code lists (e.g. Gear code "GOV" ->
# "Grande Ouverture Verticale") independently of DATRAS's own field-list/WSDL machinery
# (data-raw/datras_operation_types.R). Used here to enrich datras_schema's DescriptionNew
# with what a field's valid codes actually mean, for fields with few enough codes that
# listing them inline is useful (see data-raw/build_datras_schema.R's step 4b).
#
# Key finding (2026-07-23, verified live): icesVocab's own Key values are prefixed --
# e.g. "TS_DataType", "AC_Sex" -- plus some bare keys with no prefix (e.g. "Gear"). "TS_" =
# Trawl Survey (DATRAS's own domain), "AC_" = Acoustic survey (a different ICES data domain
# entirely). Some field names resolve under BOTH prefixes -- confirmed concretely for "Sex":
# TS_Sex has 7 codes (incl. Berried/Neutral/"Not included"), AC_Sex has 4 simpler codes. This
# repo's own dictionary work pools both when needed, but now with domain-aware preference
# ordering: TS_ over bare over AC_ for trawl-survey contexts, rather than undifferentiated
# name-only matching. Since DATRAS is entirely trawl-survey data, the exported functions
# below prefer TS_ over bare over AC_.
