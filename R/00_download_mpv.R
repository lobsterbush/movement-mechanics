# =============================================================================
# 00_download_mpv.R
# Purpose: Download a fatal-police-shooting dataset at the incident level for
#          aggregation to the county-year panel. We pull both:
#            1. Washington Post Fatal Force Database v2 (GitHub, stable URL,
#               publicly licensed CC BY-NC-SA).
#            2. Mapping Police Violence dataset URL (may 403 without a User-
#               Agent; we try, and if it fails fall back to (1) alone).
#          Either source gives the A_US "mpv_killings" outcome; we will join
#          them by fips_code x year, deduped by victim name/date.
# Outputs: data/raw/mpv/wapo_fatal_police_shootings.csv
#          data/raw/mpv/MPVDataset.csv              (best-effort)
#          data/raw/mpv/MANIFEST.yml
# =============================================================================

library(here)
library(digest)

message("=== Downloading police-shooting incident data ===\n")

mpv_dir <- here("data", "raw", "mpv")
dir.create(mpv_dir, showWarnings = FALSE, recursive = TRUE)

files <- list(
  list(name = "wapo_fatal_police_shootings.csv",
       url  = "https://raw.githubusercontent.com/washingtonpost/data-police-shootings/master/v2/fatal-police-shootings-data.csv"),
  list(name = "wapo_agencies.csv",
       url  = "https://raw.githubusercontent.com/washingtonpost/data-police-shootings/master/v2/fatal-police-shootings-agencies.csv"),
  list(name = "MPVDataset.csv",
       # Mapping Police Violence posts a live URL; best-effort fetch
       url  = "https://mappingpoliceviolence.org/s/MPVDatasetDownload.csv")
)

safe_download <- function(url, dest, max_tries = 3) {
  if (file.exists(dest)) {
    message("  Already exists: ", basename(dest)); return(invisible(TRUE))
  }
  for (i in seq_len(max_tries)) {
    ok <- tryCatch({
      download.file(url, dest, mode = "wb", quiet = TRUE,
                    headers = c("User-Agent" = "Mozilla/5.0 research"))
      TRUE
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
  invisible(FALSE)
}

manifest <- c("# Police-shooting incident data manifest",
              sprintf("downloaded_at: %s",
                      format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
              "sources:",
              "  - Washington Post Fatal Force Database v2 (CC BY-NC-SA)",
              "  - Mapping Police Violence (best-effort)",
              "files:")

for (f in files) {
  dest <- file.path(mpv_dir, f$name)
  safe_download(f$url, dest)
  if (file.exists(dest) && file.info(dest)$size > 0) {
    manifest <- c(manifest,
                  sprintf("  %s:", f$name),
                  sprintf("    url: %s", f$url),
                  sprintf("    size_bytes: %d", file.info(dest)$size),
                  sprintf("    md5: %s", digest(file = dest, algo = "md5")))
  } else {
    manifest <- c(manifest,
                  sprintf("  %s: NOT_DOWNLOADED", f$name))
  }
}

writeLines(manifest, file.path(mpv_dir, "MANIFEST.yml"))
message("\n  Wrote manifest: data/raw/mpv/MANIFEST.yml")
