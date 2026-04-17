# =============================================================================
# 00_download_mm.R
# Purpose: Download the Mass Mobilization (Clark & Regan) dataset v5.1 from
#          Harvard Dataverse and record a provenance manifest.
# Inputs:  Internet access.
# Outputs: data/raw/mm/mmALL_073120_csv.tab       (events CSV, tab-sep)
#          data/raw/mm/mmALL_073120_v16.tab       (Stata 14 binary)
#          data/raw/mm/MM_users_manual_0515.pdf   (codebook, file ID TJJZNG)
#          data/raw/mm/MANIFEST.yml               (download provenance)
# =============================================================================

library(here)
library(digest)

message("=== Downloading Mass Mobilization v5.1 from Harvard Dataverse ===\n")

mm_dir <- here("data", "raw", "mm")
dir.create(mm_dir, showWarnings = FALSE, recursive = TRUE)

# Dataverse file IDs (confirmed via API 2026-04-17):
#   mmALL_073120_csv.tab  -> 4291456  (tab-sep events, 15.6 MB)
#   mmALL_073120_v16.tab  -> 4291457  (Stata 14 binary equivalent)
#   MM_users_manual_0515  -> 2775560  (codebook PDF, DOI:10.7910/DVN/HTTWYL/TJJZNG)
mm_files <- list(
  list(id = 4291456L, name = "mmALL_073120_csv.tab",
       kind = "events_tab",   expected_md5 = "e6fa8a2e9d120eff0167a788e8a3ea7f"),
  list(id = 4291457L, name = "mmALL_073120_v16.tab",
       kind = "events_stata", expected_md5 = "2dcd24ba46f8c4cd8556354ee75189a7"),
  list(id = 2775560L, name = "MM_users_manual_0515.pdf",
       kind = "codebook",     expected_md5 = "efb7ca11ee0eadae9122b2b7cee08560")
)

safe_download <- function(url, dest, max_tries = 3) {
  if (file.exists(dest)) {
    message("  Already exists: ", basename(dest))
    return(invisible(TRUE))
  }
  for (i in seq_len(max_tries)) {
    ok <- tryCatch({
      download.file(url, dest, mode = "wb", quiet = TRUE)
      TRUE
    }, error = function(e) {
      message("  Attempt ", i, " failed for ", basename(dest), ": ", e$message)
      FALSE
    })
    if (ok && file.exists(dest) && file.info(dest)$size > 0) {
      message("  Downloaded: ", basename(dest),
              " (", format(file.info(dest)$size, big.mark = ","), " bytes)")
      return(invisible(TRUE))
    }
    Sys.sleep(2)
  }
  warning("Failed to download: ", url)
  invisible(FALSE)
}

manifest <- list(
  source       = "Harvard Dataverse",
  dataset_doi  = "10.7910/DVN/HTTWYL",
  version      = "5.1",
  release_date = "2022-10-10",
  title        = "Mass Mobilization Protest Data",
  authors      = c("Clark, David (Binghamton University)",
                   "Regan, Patrick (University of Notre Dame)"),
  license      = "CC0 1.0",
  downloaded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  files        = list()
)

for (f in mm_files) {
  dest <- file.path(mm_dir, f$name)
  url  <- sprintf("https://dataverse.harvard.edu/api/access/datafile/%d",
                  f$id)
  safe_download(url, dest)

  if (file.exists(dest)) {
    actual_md5 <- digest(file = dest, algo = "md5")
    md5_match  <- isTRUE(actual_md5 == f$expected_md5)
    manifest$files[[f$name]] <- list(
      dataverse_id = f$id,
      kind         = f$kind,
      size_bytes   = file.info(dest)$size,
      md5_actual   = actual_md5,
      md5_expected = f$expected_md5,
      md5_match    = md5_match
    )
    if (!md5_match) {
      message("  WARNING: MD5 mismatch for ", f$name,
              "\n    expected=", f$expected_md5,
              "\n    actual  =", actual_md5)
    } else {
      message("  MD5 verified: ", f$name)
    }
  }
}

# Minimal YAML emitter (no yaml pkg dep) -----------------------------------
yaml_lines <- c(
  "# Mass Mobilization raw-data manifest",
  sprintf("source: %s", manifest$source),
  sprintf("dataset_doi: %s", manifest$dataset_doi),
  sprintf("version: \"%s\"", manifest$version),
  sprintf("release_date: %s", manifest$release_date),
  sprintf("title: \"%s\"", manifest$title),
  "authors:",
  paste0("  - \"", manifest$authors, "\""),
  sprintf("license: %s", manifest$license),
  sprintf("downloaded_at: %s", manifest$downloaded_at),
  "files:"
)
for (nm in names(manifest$files)) {
  f <- manifest$files[[nm]]
  yaml_lines <- c(yaml_lines,
    sprintf("  %s:", nm),
    sprintf("    dataverse_id: %d", f$dataverse_id),
    sprintf("    kind: %s", f$kind),
    sprintf("    size_bytes: %d", f$size_bytes),
    sprintf("    md5_actual: %s", f$md5_actual),
    sprintf("    md5_expected: %s", f$md5_expected),
    sprintf("    md5_match: %s", tolower(as.character(f$md5_match)))
  )
}
writeLines(yaml_lines, file.path(mm_dir, "MANIFEST.yml"))
message("\n  Wrote manifest: data/raw/mm/MANIFEST.yml")

message("\n=== MM download complete ===")
