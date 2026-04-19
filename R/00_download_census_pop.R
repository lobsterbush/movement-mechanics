# =============================================================================
# 00_download_census_pop.R
# Purpose: Download Census Bureau Population Estimates Program (PEP)
#          county-level intercensal + vintage files, covering 2010-2023.
# Inputs:  Internet access.
# Outputs: data/raw/census/co-est2020-alldata.csv      (2010-2020 decennial)
#          data/raw/census/co-est2024-alldata.csv      (2020-2024 vintage 2024)
#          data/raw/census/MANIFEST.yml
# =============================================================================

library(here)
library(digest)

message("=== Downloading Census PEP county population ===\n")

pop_dir <- here("data", "raw", "census")
dir.create(pop_dir, showWarnings = FALSE, recursive = TRUE)

files <- list(
  list(name = "co-est2020-alldata.csv",
       url  = "https://www2.census.gov/programs-surveys/popest/datasets/2010-2020/counties/totals/co-est2020-alldata.csv"),
  list(name = "co-est2024-alldata.csv",
       url  = "https://www2.census.gov/programs-surveys/popest/datasets/2020-2024/counties/totals/co-est2024-alldata.csv")
)

safe_download <- function(url, dest, max_tries = 3) {
  if (file.exists(dest)) {
    message("  Already exists: ", basename(dest)); return(invisible(TRUE))
  }
  for (i in seq_len(max_tries)) {
    ok <- tryCatch({
      download.file(url, dest, mode = "wb", quiet = TRUE); TRUE
    }, error = function(e) {
      message("  Attempt ", i, " failed: ", e$message); FALSE
    })
    if (ok && file.exists(dest) && file.info(dest)$size > 0) {
      message("  Downloaded: ", basename(dest),
              " (", format(file.info(dest)$size, big.mark = ","), " bytes)")
      return(invisible(TRUE))
    }
    Sys.sleep(2)
  }
  warning("Failed to download: ", url); invisible(FALSE)
}

manifest <- c(
  "# Census PEP county population manifest",
  sprintf("downloaded_at: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "source: US Census Bureau Population Estimates Program",
  "files:"
)
for (f in files) {
  dest <- file.path(pop_dir, f$name)
  safe_download(f$url, dest)
  if (file.exists(dest)) {
    manifest <- c(manifest,
                  sprintf("  %s:", f$name),
                  sprintf("    url: %s", f$url),
                  sprintf("    size_bytes: %d", file.info(dest)$size),
                  sprintf("    md5: %s", digest(file = dest, algo = "md5")))
  }
}
writeLines(manifest, file.path(pop_dir, "MANIFEST.yml"))
message("  Wrote manifest: data/raw/census/MANIFEST.yml")
