# =============================================================================
# 00_download_qog.R
# Purpose: Download the Quality of Government Standard Dataset (time-series,
#          country-year). QoG aggregates CPI, regime, corruption, gender,
#          and fiscal indicators from many sources into a single panel.
# Inputs:  Internet access.
# Outputs: data/raw/qog/qog_std_ts_jan25.csv   (2025 release)
#          data/raw/qog/MANIFEST.yml
# =============================================================================

library(here)
library(digest)

options(timeout = max(600, getOption("timeout")))

message("=== Downloading Quality of Government Standard (time-series) ===\n")
qog_dir <- here("data", "raw", "qog")
dir.create(qog_dir, showWarnings = FALSE, recursive = TRUE)

# QoG mirrors CSVs at https://www.qogdata.pol.gu.se/data/qog_std_ts_<relese>.csv
# Current release (as of early 2025) is jan25. If that 404s, try apr24.
candidates <- c(
  "https://www.qogdata.pol.gu.se/data/qog_std_ts_jan25.csv",
  "https://www.qogdata.pol.gu.se/data/qog_std_ts_apr24.csv",
  "https://www.qogdata.pol.gu.se/data/qog_std_ts_jan23.csv"
)
dest <- file.path(qog_dir, "qog_std_ts.csv")

downloaded <- FALSE
for (url in candidates) {
  ok <- tryCatch({
    download.file(url, dest, mode = "wb", quiet = TRUE); TRUE
  }, error = function(e) FALSE)
  if (ok && file.exists(dest) && file.info(dest)$size > 0) {
    message("  Downloaded: ", url,
            " (", format(file.info(dest)$size, big.mark = ","), " bytes)")
    downloaded <- TRUE; break
  }
}

if (downloaded) {
  writeLines(
    c("# Quality of Government manifest",
      sprintf("downloaded_at: %s",
              format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
      "source: QoG Institute, University of Gothenburg",
      sprintf("md5: %s", digest(file = dest, algo = "md5"))),
    file.path(qog_dir, "MANIFEST.yml")
  )
} else {
  message("  All QoG candidate URLs failed.")
}
