# =============================================================================
# 00_sync_ccc.R
# Purpose: Bring the Crowd Counting Consortium dumps already downloaded by
#          protests-spending into this repo's data/raw/ccc/ tree, rather than
#          re-downloading. Records download provenance in a manifest.
# Inputs:  ../protests-spending/data/raw/ccc/ (peer repo)
# Outputs: data/raw/ccc/ccc_compiled.csv                 (Phase 1, 2017-2020)
#          data/raw/ccc/ccc_compiled_2021_present.csv    (Phase 2, 2021+)
#          data/raw/ccc/MANIFEST.yml
# =============================================================================

library(here)
library(digest)

message("=== Syncing CCC data from protests-spending ===\n")

ccc_dir <- here("data", "raw", "ccc")
dir.create(ccc_dir, showWarnings = FALSE, recursive = TRUE)

# Peer repo path; adjust if your local layout differs.
peer_ccc <- normalizePath(
  here("..", "protests-spending", "data", "raw", "ccc"),
  mustWork = FALSE
)

if (!dir.exists(peer_ccc)) {
  stop("Peer CCC directory not found: ", peer_ccc,
       "\n  Clone protests-spending next to movement-mechanics, or adjust this script.")
}

wanted <- c(
  phase1 = "ccc_compiled.csv",
  phase2 = "ccc_compiled_2021_present.csv"
)

manifest_lines <- c(
  "# Crowd Counting Consortium raw-data manifest",
  "source: GitHub nonviolent-action-lab/crowd-counting-consortium (mirrored from protests-spending)",
  sprintf("synced_at: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("peer_repo: %s", peer_ccc),
  "files:"
)

for (lab in names(wanted)) {
  src <- file.path(peer_ccc, wanted[[lab]])
  dst <- file.path(ccc_dir, wanted[[lab]])
  if (!file.exists(src)) {
    warning("Missing source file: ", src)
    next
  }
  if (!file.exists(dst)) {
    file.copy(src, dst)
    message("  Copied: ", basename(dst))
  } else {
    message("  Already present: ", basename(dst))
  }
  md5 <- digest(file = dst, algo = "md5")
  sz  <- file.info(dst)$size
  manifest_lines <- c(
    manifest_lines,
    sprintf("  %s:", wanted[[lab]]),
    sprintf("    phase: %s", lab),
    sprintf("    size_bytes: %d", sz),
    sprintf("    md5: %s", md5)
  )
}

writeLines(manifest_lines, file.path(ccc_dir, "MANIFEST.yml"))
message("\n  Wrote manifest: data/raw/ccc/MANIFEST.yml")
message("=== CCC sync complete ===")
