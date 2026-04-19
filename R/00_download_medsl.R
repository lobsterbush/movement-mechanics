# =============================================================================
# 00_download_medsl.R
# Purpose: Download the MIT Election Data & Science Lab (MEDSL) county-level
#          presidential returns 1976-2020 from the Harvard Dataverse.
# Inputs:  Internet access.
# Outputs: data/raw/medsl/countypres_2000-2020.csv
#          data/raw/medsl/MANIFEST.yml
# =============================================================================

library(here)
library(digest)

message("=== Downloading MEDSL county presidential returns ===\n")

medsl_dir <- here("data", "raw", "medsl")
dir.create(medsl_dir, showWarnings = FALSE, recursive = TRUE)

# Dataverse file IDs (from DOI 10.7910/DVN/VOQCHQ; confirmed via API):
#   countypres_2000-2024.tab -> 13573089
# NOTE: MEDSL's Dataverse attaches a Guestbook (#458) that blocks anonymous
# direct-download via the API. Set a Dataverse API key via
#   Sys.setenv(DATAVERSE_KEY = "...")
# before running, OR download the file manually from
#   https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/VOQCHQ
# and place it at data/raw/medsl/countypres_2000-2024.tab.
api_key <- Sys.getenv("DATAVERSE_KEY", unset = NA)
files <- list(
  list(name = "countypres_2000-2024.tab",
       url  = if (!is.na(api_key) && nchar(api_key) > 0) {
         sprintf("https://dataverse.harvard.edu/api/access/datafile/13573089?key=%s",
                 api_key)
       } else {
         "https://dataverse.harvard.edu/api/access/datafile/13573089"
       })
)

safe_download <- function(url, dest, max_tries = 3) {
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
  invisible(FALSE)
}

manifest <- c("# MEDSL county presidential manifest",
              sprintf("downloaded_at: %s",
                      format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
              "source: MEDSL county presidential returns (Harvard Dataverse)",
              "files:")

for (f in files) {
  dest <- file.path(medsl_dir, f$name)
  safe_download(f$url, dest)
  if (file.exists(dest) && file.info(dest)$size > 0) {
    manifest <- c(manifest,
                  sprintf("  %s: { size_bytes: %d, md5: %s }",
                          f$name, file.info(dest)$size,
                          digest(file = dest, algo = "md5")))
  }
}

writeLines(manifest, file.path(medsl_dir, "MANIFEST.yml"))
message("  Wrote manifest: data/raw/medsl/MANIFEST.yml")
