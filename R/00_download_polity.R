# =============================================================================
# 00_download_polity.R
# Purpose: Download Polity 5 annual regime data (1800-2018) from Center for
#          Systemic Peace.
# Inputs:  Internet access.
# Outputs: data/raw/polity/p5v2018.xls
#          data/raw/polity/MANIFEST.yml
# =============================================================================

library(here)
library(digest)

message("=== Downloading Polity 5 ===\n")
pol_dir <- here("data", "raw", "polity")
dir.create(pol_dir, showWarnings = FALSE, recursive = TRUE)

url  <- "http://www.systemicpeace.org/inscr/p5v2018.xls"
dest <- file.path(pol_dir, "p5v2018.xls")

ok <- tryCatch({
  download.file(url, dest, mode = "wb", quiet = TRUE); TRUE
}, error = function(e) {
  message("  Polity download failed: ", e$message); FALSE
})

if (ok && file.exists(dest)) {
  message("  Downloaded: p5v2018.xls (",
          format(file.info(dest)$size, big.mark = ","), " bytes)")
  writeLines(
    c("# Polity 5 manifest",
      sprintf("downloaded_at: %s",
              format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
      "source: Center for Systemic Peace, Polity 5 Annual",
      sprintf("md5: %s", digest(file = dest, algo = "md5"))),
    file.path(pol_dir, "MANIFEST.yml")
  )
}
