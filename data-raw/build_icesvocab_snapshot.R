#' Full icesVocab catalog snapshot: opus's own direct-HTTP bulk download
#'
#' User's own working pattern for downloading the whole icesVocab catalog
#' (every code-type, every one of its codes) uses the real `icesVocab` R
#' package -- exactly the dependency opus removed 2026-08-06 (see AGENTS.md's
#' Data Sources section). Same idea, built opus's own way instead: loop
#' op_vocab_get_types()'s ~580 code-types through op_vocab_get_codes()
#' (R/vocab.R, plain unauthenticated HTTP, no icesVocab package), bind into
#' one data frame.
#'
#' Why a cached snapshot instead of live per-key calls, as opus has always
#' done for one-off lookups: audits that need codes for MANY types at once
#' (e.g. cross-checking a whole spreadsheet's worth of fields against
#' icesVocab -- see build_field_description_snapshot.R) would otherwise mean
#' hundreds of live HTTP round-trips per run -- slow, fragile to transient
#' network issues, and not reproducible against a fixed point in time.
#' Matches the same hash-stamped provenance convention as
#' archive_02_download.R's getDatrasFieldList snapshot: one file, named with
#' a timestamp and a content hash, so staleness is visible rather than
#' silent (the same reasoning behind flagging inst/*.parquet's own
#' undecided staleness as a real problem -- see TODO.md's D1 item).
#'
#' Does NOT replace op_vocab_get_codes()/op_vocab_resolve_key() for one-off
#' live lookups -- those stay live, simple, and correct for a single field.
#' This is specifically for bulk/audit use.
#'
#' Usage: Rscript data-raw/build_icesvocab_snapshot.R

source("data-raw/archive_01_download_config.R")
source("R/vocab.R")

log_msg("Fetching icesVocab code-type list...")
types <- op_vocab_get_types()
log_msg("  %d code-types registered", nrow(types))

log_msg("Fetching codes for every code-type (one HTTP call per type -- this takes a while)...")
t0 <- Sys.time()
all_codes <- lapply(seq_len(nrow(types)), function(i) {
  codes <- op_vocab_get_codes(types$Key[i])
  if (nrow(codes) == 0) return(NULL)
  codes$type <- types$Key[i]
  codes$type_desc <- types$Description[i]
  codes$guid <- types$Guid[i]
  codes
})
all_codes <- all_codes[!vapply(all_codes, is.null, logical(1))]
snapshot <- do.call(rbind, all_codes)
snapshot <- snapshot[, c("type", "type_desc", "guid", "Key", "Description")]
names(snapshot) <- c("type", "type_desc", "guid", "key", "description")
row.names(snapshot) <- NULL

elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
log_msg("Snapshot: %d/%d code-types have >=1 code, %d total (type, code) rows, %ss",
        length(all_codes), nrow(types), nrow(snapshot), elapsed)

dir.create(DATRAS_SCHEMAS, showWarnings = FALSE, recursive = TRUE)
snapshot_sha <- digest::digest(snapshot, algo = "sha256")
snapshot_file <- file.path(DATRAS_SCHEMAS,
                            sprintf("icesvocab_full_%s_%s.tsv",
                                    format(Sys.time(), "%Y%m%d_%H%M%S"),
                                    substr(snapshot_sha, 1, 8)))
utils::write.table(snapshot, snapshot_file, sep = "\t", quote = FALSE, row.names = FALSE)
log_msg("icesVocab full snapshot: %s (SHA256: %s)", basename(snapshot_file), snapshot_sha)
