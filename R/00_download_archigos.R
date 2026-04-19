# =============================================================================
# 00_download_archigos.R
# Purpose: Download Archigos 4.1 leader-tenure data (Goemans, Gleditsch &
#          Chiozza) for country-year executive-turnover indicators.
# Inputs:  Internet access.
# Outputs: data/raw/archigos/Archigos_4.1.txt
#          data/raw/archigos/MANIFEST.yml
# =============================================================================

library(here)
library(digest)

message("=== Downloading Archigos 4.1 ===\n")
ag_dir <- here("data", "raw", "archigos")
dir.create(ag_dir, showWarnings = FALSE, recursive = TRUE)

candidates <- c(
  "https://ksgleditsch.com/data/1March_Archigos_4.1.txt",
  "http://www.rochester.edu/college/faculty/hgoemans/Archigos_4.1.txt"
)
dest <- file.path(ag_dir, "Archigos_4.1.txt")

downloaded <- FALSE
for (url in candidates) {
  if (file.exists(dest)) { downloaded <- TRUE; break }
  ok <- tryCatch({
    download.file(url, dest, mode = "wb", quiet = TRUE); TRUE
  }, error = function(e) FALSE)
  if (ok && file.exists(dest) && file.info(dest)$size > 0) {
    message("  Downloaded from: ", url,
            "\n    size: ", format(file.info(dest)$size, big.mark = ","))
    downloaded <- TRUE; break
  }
}

if (downloaded) {
  writeLines(
    c("# Archigos 4.1 manifest",
      sprintf("downloaded_at: %s",
              format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
      "source: Goemans, Gleditsch & Chiozza, Archigos 4.1",
      sprintf("md5: %s", digest(file = dest, algo = "md5"))),
    file.path(ag_dir, "MANIFEST.yml")
  )
} else {
  message("  All Archigos candidate URLs failed.")
}
