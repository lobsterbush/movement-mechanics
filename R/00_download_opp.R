# =============================================================================
# 00_download_opp.R
# Purpose: Download Stanford Open Policing Project statewide traffic-stop data
#          for the 20 states with county-level records (required for a
#          county-year aggregation). OPP hosts each state as a separate CSV
#          at https://stacks.stanford.edu/file/druid:yg821jf8611/.
# Inputs:  Internet access.
# Outputs: data/raw/opp/<state>_<city>.csv.zip  (one per state)
#          data/raw/opp/MANIFEST.yml
# Notes:
#   - OPP file URLs are constructed as
#     https://stacks.stanford.edu/file/druid:yg821jf8611/yg821jf8611_<state>_statewide_2020_04_01.csv.zip
#     (this was the last refresh as of v1). TODO: bump file-name date stamp
#     when OPP releases a new version.
# =============================================================================

library(here)
library(digest)

message("=== Downloading Stanford Open Policing Project ===\n")

opp_dir <- here("data", "raw", "opp")
dir.create(opp_dir, showWarnings = FALSE, recursive = TRUE)

# Statewide files (subset with county-level geography). The full list has 20
# states; we restrict to those with county identifiers.
states <- c("az", "ca", "co", "ct", "fl", "il", "ma", "md", "mi", "mo",
            "mt", "nc", "nd", "nh", "nj", "ny", "oh", "or", "ri", "sc",
            "tn", "tx", "va", "vt", "wa", "wi")

make_url <- function(st)
  sprintf("https://stacks.stanford.edu/file/druid:yg821jf8611/yg821jf8611_%s_statewide_2020_04_01.csv.zip", st)

safe_download <- function(url, dest, max_tries = 2) {
  if (file.exists(dest)) {
    message("  Already exists: ", basename(dest)); return(invisible(TRUE))
  }
  for (i in seq_len(max_tries)) {
    ok <- tryCatch({
      download.file(url, dest, mode = "wb", quiet = TRUE); TRUE
    }, error = function(e) FALSE)
    if (ok && file.exists(dest) && file.info(dest)$size > 0) {
      message("  Downloaded: ", basename(dest),
              " (", format(file.info(dest)$size, big.mark = ","), " bytes)")
      return(invisible(TRUE))
    }
    Sys.sleep(2)
  }
  message("  [skip] failed: ", basename(dest)); invisible(FALSE)
}

manifest <- c("# Stanford Open Policing manifest",
              sprintf("downloaded_at: %s",
                      format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
              "source: https://openpolicing.stanford.edu",
              "files:")

for (st in states) {
  url  <- make_url(st)
  dest <- file.path(opp_dir, sprintf("%s_statewide.csv.zip", st))
  safe_download(url, dest)
  if (file.exists(dest) && file.info(dest)$size > 0) {
    manifest <- c(manifest,
                  sprintf("  %s: { size_bytes: %d, md5: %s }",
                          basename(dest), file.info(dest)$size,
                          digest(file = dest, algo = "md5")))
  }
}
writeLines(manifest, file.path(opp_dir, "MANIFEST.yml"))
message("\n  Wrote manifest: data/raw/opp/MANIFEST.yml")
