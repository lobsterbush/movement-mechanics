# =============================================================================
# 00_download_wdi.R
# Purpose: Pull World Bank WDI indicators needed for A_MM_05 via the
#          `wbstats` package (direct WDI API), then save as RDS.
# Inputs:  `wbstats` R package.
# Outputs: data/raw/wdi/wdi_indicators.rds
#          data/raw/wdi/MANIFEST.yml
# =============================================================================

library(here)
message("=== Downloading World Bank WDI indicators ===\n")

wdi_dir <- here("data", "raw", "wdi")
dir.create(wdi_dir, showWarnings = FALSE, recursive = TRUE)

if (!requireNamespace("wbstats", quietly = TRUE)) {
  message("  Installing wbstats...")
  tryCatch(install.packages("wbstats", quiet = TRUE,
                            repos = "https://cloud.r-project.org"),
           error = function(e) message("  install failed: ", e$message))
}

indicators <- c(
  health_pct_gdp   = "SH.XPD.CHEX.GD.ZS",     # current health exp, % GDP
  edu_pct_gdp      = "SE.XPD.TOTL.GD.ZS",     # govt expenditure on education, % GDP
  socprot_cov      = "per_allsp.cov_pop_tot", # social-protection coverage
  pop_total        = "SP.POP.TOTL"            # population total
)

dest <- file.path(wdi_dir, "wdi_indicators.rds")

if (requireNamespace("wbstats", quietly = TRUE)) {
  res <- tryCatch(
    wbstats::wb_data(
      indicator = indicators,
      start_date = 1990, end_date = 2023,
      return_wide = TRUE
    ),
    error = function(e) { message("  wb_data failed: ", e$message); NULL }
  )
  if (!is.null(res)) {
    saveRDS(res, dest)
    message("  Saved: ", dest, " (", nrow(res), " rows, ", ncol(res), " cols)")
  }
}

writeLines(
  c("# World Bank WDI manifest",
    sprintf("downloaded_at: %s",
            format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
    "source: World Bank WDI via wbstats R package",
    "indicators:",
    paste0("  ", names(indicators), ": ", indicators)),
  file.path(wdi_dir, "MANIFEST.yml")
)
