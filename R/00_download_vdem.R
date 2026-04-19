# =============================================================================
# 00_download_vdem.R
# Purpose: Fetch V-Dem v14 indices (country-year) via the `vdemdata` R
#          package (which ships the v14 dataset). Saves to RDS so downstream
#          scripts do not depend on the package at run-time.
# Inputs:  `vdemdata` (install from GitHub if needed).
# Outputs: data/raw/vdem/vdem_v14.rds
#          data/raw/vdem/MANIFEST.yml
# =============================================================================

library(here)
message("=== Fetching V-Dem v14 ===\n")

vd_dir <- here("data", "raw", "vdem")
dir.create(vd_dir, showWarnings = FALSE, recursive = TRUE)

if (!requireNamespace("vdemdata", quietly = TRUE)) {
  message("  Installing vdemdata from GitHub (vdeminstitute/vdemdata)...")
  tryCatch(
    if (requireNamespace("remotes", quietly = TRUE)) {
      remotes::install_github("vdeminstitute/vdemdata", quiet = TRUE)
    } else {
      install.packages("remotes")
      remotes::install_github("vdeminstitute/vdemdata", quiet = TRUE)
    },
    error = function(e) {
      message("  vdemdata install failed: ", e$message,
              "\n  Falling back to direct CSV download.")
    }
  )
}

vdem_path <- file.path(vd_dir, "vdem_v14.rds")

if (requireNamespace("vdemdata", quietly = TRUE)) {
  vd <- vdemdata::vdem
  saveRDS(vd, vdem_path)
  message("  Saved: ", vdem_path,
          " (", format(file.info(vdem_path)$size, big.mark = ","), " bytes)")
} else {
  # Fallback: try the Dataverse DOI for V-Dem v14 Core
  # V-Dem Core v14 CSV file ID (confirmed 2024-03-07): 7964020
  url <- "https://dataverse.harvard.edu/api/access/datafile/7964020"
  tryCatch({
    download.file(url, file.path(vd_dir, "V-Dem-CY-Core-v14.csv"),
                  mode = "wb", quiet = TRUE)
    message("  Downloaded CY-Core CSV via Dataverse fallback.")
  }, error = function(e) {
    message("  Fallback also failed: ", e$message)
  })
}

writeLines(
  c("# V-Dem raw-data manifest",
    sprintf("downloaded_at: %s",
            format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
    "source: V-Dem Institute, v14 (March 2024 release)"),
  file.path(vd_dir, "MANIFEST.yml")
)
