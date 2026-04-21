# =============================================================================
# A_MM_04_merge_polity_turnover.R
# Purpose: Join Polity V regime indicators and Archigos/REIGN executive
#          turnover events to the MM + V-Dem panel. Outcomes needed:
#            polity2              (Polity V combined score)
#            regtrans             (regime transition indicator)
#            leader_turnover      (binary: new leader in country-year)
#            irregular_turnover   (binary: irregular exit per Archigos)
# Inputs:
#   data/intermediate/mm_vdem.rds
#   data/raw/polity/p5v2018.xls        (TODO: add pull)
#   data/raw/archigos/Archigos_4.1.txt (TODO: add pull)
# Outputs:
#   data/intermediate/mm_polity.rds
#   output/tables/mm_polity_macros.tex
# =============================================================================

suppressPackageStartupMessages({
  library(here); library(dplyr); library(readr); library(tidyr)
})

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_MM_04_polity.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_MM_04 Merge Polity + turnover ===")
message("Run at: ", format(Sys.time()))

panel <- readRDS(here("data", "intermediate", "mm_vdem.rds"))

# ---- Polity 5 -----------------------------------------------------------
# p5v2018.xls is the long-format country-year file. Key columns we need:
#   country  scode  ccode  year  polity2  regtrans
polity_path <- here("data", "raw", "polity", "p5v2018.xls")
if (file.exists(polity_path) &&
    requireNamespace("readxl", quietly = TRUE)) {
  pol <- readxl::read_excel(polity_path, sheet = 1) %>%
    select(country, year, polity2, regtrans)
  if (requireNamespace("countrycode", quietly = TRUE)) {
    pol$iso3c <- countrycode::countrycode(pol$country, "country.name",
                                          "iso3c", warn = FALSE)
    if (!"iso3c" %in% names(panel)) {
      panel$iso3c <- countrycode::countrycode(panel$country, "country.name",
                                              "iso3c", warn = FALSE)
    }
    pol <- pol %>% filter(!is.na(iso3c)) %>%
      select(iso3c, year, polity2, regtrans)
    panel <- left_join(panel, pol, by = c("iso3c", "year"))
  } else {
    panel <- left_join(panel, pol, by = c("country", "year"))
  }
  message("  Polity 5 merged: polity2 non-missing = ",
          round(100 * mean(!is.na(panel$polity2)), 1), "%")
} else {
  panel$polity2  <- NA_real_
  panel$regtrans <- NA_real_
  message("  Polity file missing or readxl unavailable; polity2 = NA.")
}

# ---- Archigos / REIGN turnover -----------------------------------------
# Archigos is a leader-spell file (one row per leader-country with start/
# end dates). We explode to leader-year, count leader changes per year.
# Join keys: COW numeric ccode -> iso3c via countrycode, then merge on
# (iso3c, year). The MM panel uses country names, so we build iso3c on
# the panel as well (if not already present from the Polity merge).
archigos_path <- here("data", "raw", "archigos", "Archigos_4.1.txt")
if (file.exists(archigos_path) &&
    requireNamespace("countrycode", quietly = TRUE)) {
  ag <- tryCatch(
    read_tsv(archigos_path, show_col_types = FALSE, progress = FALSE),
    error = function(e) { message("  Archigos parse failed: ", e$message); NULL }
  )
  if (!is.null(ag) && all(c("leader", "startdate", "enddate", "ccode",
                            "exit") %in% names(ag))) {
    ag <- ag %>%
      mutate(
        start_year = as.integer(substr(startdate, 1, 4)),
        end_year   = as.integer(substr(enddate,   1, 4)),
        iso3c      = countrycode::countrycode(
                       ccode, origin = "cown",
                       destination = "iso3c", warn = FALSE)
      ) %>%
      filter(!is.na(iso3c), !is.na(end_year))

    # Binary: a leader's spell ENDED in this country-year (i.e. turnover).
    # Count: number of distinct leaders whose spell ended in the year.
    turnover <- ag %>%
      group_by(iso3c, year = end_year) %>%
      summarise(
        leader_turnover_count = dplyr::n_distinct(leader),
        irregular_turnover    = as.integer(any(
                                  grepl("[Ii]rregular",
                                        as.character(exit)))),
        .groups = "drop"
      ) %>%
      mutate(leader_turnover = as.integer(leader_turnover_count > 0))

    # Ensure the panel has iso3c; build it if the Polity merge did not.
    if (!"iso3c" %in% names(panel)) {
      panel$iso3c <- countrycode::countrycode(
        panel$country, origin = "country.name",
        destination = "iso3c", warn = FALSE)
    }
    panel <- left_join(panel, turnover, by = c("iso3c", "year")) %>%
      mutate(
        leader_turnover       = replace_na(leader_turnover,       0L),
        leader_turnover_count = replace_na(leader_turnover_count, 0L),
        irregular_turnover    = replace_na(irregular_turnover,    0L)
      )
    message("  Archigos merged: country-years with any turnover = ",
            format(sum(panel$leader_turnover == 1, na.rm = TRUE),
                   big.mark = ","),
            " / irregular = ",
            format(sum(panel$irregular_turnover == 1, na.rm = TRUE),
                   big.mark = ","))
  } else {
    panel$leader_turnover       <- NA_real_
    panel$leader_turnover_count <- NA_real_
    panel$irregular_turnover    <- NA_real_
    message("  Archigos columns missing; leaving turnover NA.")
  }
} else {
  panel$leader_turnover       <- NA_real_
  panel$leader_turnover_count <- NA_real_
  panel$irregular_turnover    <- NA_real_
  message("  Archigos file missing or countrycode unavailable; turnover NA.")
}

saveRDS(panel, here("data", "intermediate", "mm_polity.rds"))
message("Saved: data/intermediate/mm_polity.rds")

macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
turnover_pct <- if ("leader_turnover" %in% names(panel)) {
  100 * mean(!is.na(panel$leader_turnover))
} else {
  NA_real_
}
turnover_n <- if ("leader_turnover" %in% names(panel)) {
  sum(panel$leader_turnover == 1, na.rm = TRUE)
} else {
  NA_integer_
}
writeLines(
  c("% Auto-generated by A_MM_04_merge_polity_turnover.R",
    paste0("% Generated: ", Sys.time()),
    macro("MMPolityPctNonMiss",
          sprintf("%.1f", 100 * mean(!is.na(panel$polity2)))),
    macro("MMArchigosPctNonMiss",
          if (is.finite(turnover_pct)) sprintf("%.1f", turnover_pct) else "NA"),
    macro("MMArchigosTurnoverN",
          if (!is.na(turnover_n)) format(turnover_n, big.mark = ",") else "NA")),
  here("output", "tables", "mm_polity_macros.tex")
)

sink()
