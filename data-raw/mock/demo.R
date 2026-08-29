#' Demonstration: opus::op_con() + metadata accessors, on real DATRAS data
#' with the metadata actually embedded in the parquet footers.

suppressPackageStartupMessages({ library(dplyr); library(rlang) })
source("mock/op_read_mock.R")
options(opus.archive = "mock/raw")
rule <- function(s) cat("\n\033[1m", s, "\033[0m\n", strrep("-", 74), "\n", sep = "")

rule("1. op_archive() -- the archive is a directory named `raw`, nothing else")
cat("resolved:", op_archive(), "\n")
cat("web twin: same last section ->", "https://heima.hafro.is/~einarhj/datras/raw", "\n")
cat("rejects a non-raw path:\n  ")
cat(tryCatch(op_archive("/tmp/somewhere/else"), error = function(e) conditionMessage(e)), "\n")

rule("2. op_keys() -- what the file carries in its footer")
print(op_keys("HH"))

rule("3. op_dict('HH') -- the dictionary, straight out of the file")
d <- op_dict("HH")
cat("dim:", dim(d), "\n\n")
print(d[c(3, 5, 7, 24, 69), c("name", "legacy_name", "type", "parquet_type", "r_type", "units")],
      row.names = FALSE)

rule("4. Three type views side by side -- the parquet/xml divergence, visible")
print(subset(d, name %in% c("Year", "SweepLength", "DateofCalculation", "Quarter"),
             select = c(name, type, parquet_type, logical_type, r_type)), row.names = FALSE)

rule("5. op_crosswalk() -- legacy <-> current, NO outside list")
xw <- op_crosswalk("HH")
cat("rows:", nrow(xw), " renamed:", sum(xw$old_name != xw$new_name), "\n\n")
print(head(subset(xw, old_name != new_name), 6), row.names = FALSE)

rule("6. op_rename() -- round-trip a real query through both naming schemes")
hh <- op_con("HH") |>
  filter(Survey == "NS-IBTS", Year == 2022, Quarter == 1) |>
  select(Survey, Year, Quarter, Platform, StationName, HaulNumber, SweepLength, BottomDepth) |>
  head(3) |> collect()
cat("current names:\n"); print(as.data.frame(hh), row.names = FALSE)
legacy <- op_rename(hh, "HH", to = "legacy")
cat("\nlegacy names (from the file's own metadata):\n")
print(as.data.frame(legacy), row.names = FALSE)
cat("\nround-trip back to current is lossless:",
    identical(names(op_rename(legacy, "HH", to = "current")), names(hh)), "\n")

rule("7. op_enums() -- code -> label")
e <- op_enums("HH")
cat("enum columns:", length(unique(e$column)), " codes:", nrow(e), "\n\n")
print(head(subset(e, column == "DataType"), 5), row.names = FALSE)

rule("8. op_surveys() -- the survey list WITHOUT a live ICES call")
s <- op_surveys()
cat(length(s), "surveys:", paste(head(s, 12), collapse = ", "), "...\n")

rule("9. op_coverage() -- what is actually in the archive")
cov <- op_coverage("HH")
cat("survey/year/quarter groups:", nrow(cov), "\n\n")
print(head(cov[order(-cov$n_rows), ], 5), row.names = FALSE)

rule("10. op_relationships('CA') -- the 8-column composite key, already authored")
r <- op_relationships("CA")[[1]]
cat(sprintf("%s -> %s (%s)\n", r$left, r$right, r$cardinality))
cat("by:", paste(r$by, collapse = ", "), "\n")
cat("conflicts:", paste(r$conflicts, collapse = ", "), "\n")

rule("11. op_definitions('CA') -- a rule, carried as executable code")
print(op_definitions("CA"), row.names = FALSE)

rule("12. op_define() -- apply it, using the R code the FILE supplied")
ca <- op_con("CA") |> filter(Survey == "BTS", Year == 2004) |>
  select(Survey, Year, HaulNumber, Age, NumberAtLength) |> collect()
cat("rows before:              ", nrow(ca), "\n")
cat("rows after op_define():   ", nrow(op_define(ca, "CA", "linkable_to_hh")), "\n")
cat("HaulNumber IS NA:         ", sum(is.na(ca$HaulNumber)), "\n")
cat("HaulNumber == -9:         ", sum(ca$HaulNumber == -9, na.rm = TRUE), "\n")

rule("13. The cross-check that only works because BOTH keys are in one footer")
cat("The dictionary says CA rows are unlinkable when HaulNumber == -9:\n")
cat("   expression:", op_definitions("CA")$expression, "\n")
cat("The sentinel policy in the SAME footer says that field was stripped:\n")
sm_ca <- op_sentinel_meta("CA")
print(subset(sm_ca, field == "HaulNumber", select = c(field, action, why)), row.names = FALSE)
cat("\nSo on the PUBLISHED archive there is no -9 left to match:\n")
allca <- op_con("CA") |> summarise(
  n = n(), n_na = sum(as.integer(is.na(HaulNumber))),
  n_m9 = sum(as.integer(HaulNumber == -9))) |> collect()
cat(sprintf("   rows %s | HaulNumber NA %s (%.2f%%) | HaulNumber == -9  %s\n",
            format(allca$n, big.mark = ","), format(allca$n_na, big.mark = ","),
            100 * allca$n_na / allca$n, allca$n_m9))
cat("\n=> The definition is written against the SUBMITTED data, not against what\n")
cat("   opus publishes. It still filters correctly here only by accident (NA\n")
cat("   propagates and dplyr/SQL drop it), and would break the moment the\n")
cat("   policy changed to 'keep'. It should read !is.na(HaulNumber).\n")
cat("   Neither key alone shows this. Co-locating them is what surfaces it.\n")

rule("14. op_sentinel_meta() -- what was stripped, what was kept")
sm <- op_sentinel_meta("HL")
cat("sentinel:", sm$value[1], "\n")
print(as.data.frame(table(sm$action)), row.names = FALSE)
cat("\nkept (sentinels still present in the data):\n")
print(subset(sm, action == "keep", select = c(field, action, why)), row.names = FALSE)

rule("15. op_provenance() -- who built this, from what")
p <- op_provenance("HL")
for (n in names(p)) cat(sprintf("  %-16s %s\n", n, p[[n]]))

rule("16. op_known_issues('CA')")
print(op_known_issues("CA")[, c("id", "severity", "field")], row.names = FALSE)

rule("17. Same code against the WEB archive -- only the path changes")
cat("op_con('HH', path = 'https://heima.hafro.is/~einarhj/datras/raw')\n")
cat("op_dict('HH', path = ...)  # one 0.12s footer read, no file download\n")
t0 <- Sys.time()
web <- try(op_keys("HH", path = "https://heima.hafro.is/~einarhj/datras/raw"), silent = TRUE)
if (inherits(web, "try-error")) {
  cat("\n(live archive has no datras: keys yet -- expected, the metadata pass\n",
      " has not been published. The flat ARROW:schema key is all that is there:)\n")
} else print(web)
cat("\nelapsed:", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2), "s\n")

cat("\n")
