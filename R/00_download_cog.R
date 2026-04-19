# =============================================================================
# 00_download_cog.R
# Purpose: Download Census of Governments (COG) Annual Survey of State and
#          Local Government Finances Individual Unit files. The COG F33
#          schedule gives county-level spending by function (police, fire,
#          corrections, highways, health, welfare, parks, education).
# Inputs:  Internet access.
# Outputs: data/raw/cog/IndFin<YY>a.zip    (one zip per year)
#          data/raw/cog/MANIFEST.yml
# Notes:
#   - The Census posts these zips at:
#     https://www2.census.gov/programs-surveys/gov-finances/tables/<YEAR>/
#       <YEAR>_Individual_Unit_File.zip  (years 2014-2023).
#     Years 2003-2013 use a different pattern and are not pulled here.
# =============================================================================

library(here)
library(digest)

message("=== Downloading Census of Governments F33 (Individual Unit files) ===\n")

cog_dir <- here("data", "raw", "cog")
dir.create(cog_dir, showWarnings = FALSE, recursive = TRUE)

# Annual survey years we need (A_US panel: 2017-2023; pre-period: 2014-2016).
years <- 2014:2023

urls <- sprintf(
  "https://www2.census.gov/programs-surveys/gov-finances/tables/%d/%d_Individual_Unit_File.zip",
  years, years
)
names(urls) <- sprintf("%d_Individual_Unit_File.zip", years)

safe_download <- function(url, dest, max_tries = 3) {
  if (file.exists(dest)) {
    message("  Already exists: ", basename(dest)); return(invisible(TRUE))
  }
  for (i in seq_len(max_tries)) {
    ok <- tryCatch({
      download.file(url, dest, mode = "wb", quiet = TRUE); TRUE
    }, error = function(e) {
      message("  Attempt ", i, " failed for ", basename(dest), ": ",
              e$message); FALSE
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

manifest <- c("# Census of Governments F33 manifest",
              sprintf("downloaded_at: %s",
                      format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
              "source: US Census Bureau, Annual Survey of State and Local Government Finances",
              "files:")

for (nm in names(urls)) {
  dest <- file.path(cog_dir, nm)
  safe_download(urls[[nm]], dest)
  if (file.exists(dest)) {
    manifest <- c(manifest,
                  sprintf("  %s:", nm),
                  sprintf("    url: %s", urls[[nm]]),
                  sprintf("    size_bytes: %d", file.info(dest)$size),
                  sprintf("    md5: %s", digest(file = dest, algo = "md5")))
  }
}

writeLines(manifest, file.path(cog_dir, "MANIFEST.yml"))
message("\n  Wrote manifest: data/raw/cog/MANIFEST.yml")
