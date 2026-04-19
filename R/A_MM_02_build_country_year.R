# =============================================================================
# A_MM_02_build_country_year.R
# Purpose: Aggregate the Mass Mobilization events file to a country-year panel
#          with the nonviolence-premium treatment variables:
#            share_nonviolent     = share of protests coded protesterviolence=0
#            avg_participants_lo  = lower bound of participant bracket (avg)
#            avg_participants_hi  = upper bound of participant bracket (avg)
#            avg_participants     = geometric mean of the two
#            intensity_nv         = share_nonviolent * avg_participants
#            intensity_v          = (1 - share_nonviolent) * avg_participants
#          Sensitivity variants (cols with _sr_ / _es_ suffix):
#            state-response-weighted violence (shootings/killings by state)
#            event-severity-weighted violence (multi-code indicators)
# Inputs:
#   data/raw/mm/mmALL_073120_csv.tab              (MM v5.1 events)
# Outputs:
#   data/intermediate/mm_country_year.rds
#   output/tables/mm_panel_coverage.csv
#   output/tables/mm_panel_macros.tex
# =============================================================================

suppressPackageStartupMessages({
  library(here); library(dplyr); library(readr); library(tidyr)
  library(stringr); library(janitor)
})

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_MM_02_panel.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_MM_02 Build MM country-year panel ===")
message("Run at: ", format(Sys.time()))

mm <- read_tsv(here("data", "raw", "mm", "mmALL_073120_csv.tab"),
               guess_max = 200000, show_col_types = FALSE, progress = FALSE) %>%
  clean_names()
message("  Loaded MM rows: ", format(nrow(mm), big.mark = ","))

# MM participant-category -> numeric midpoints. MM v5.1 exports the
# categories as string labels ("50-99", "100-999", ..., ">10000")
# rather than the numeric codes 1..7 used in the codebook
# (MM_users_manual_0515.pdf p.8). Log every unique value seen so a
# future rename does not silently break the join again.
# [LEARN:A_MM-mm] codebook categories 6 (>10,000 and <100,000) and 7
# (>=100,000) are folded into a single ">10000" label in the public
# file; we anchor the upper end at 99,999 for the geometric mean to
# avoid an ever-growing tail pulling avg_participants toward infinity.
if ("participants_category" %in% names(mm)) {
  pcat_values <- sort(unique(as.character(mm$participants_category)))
  message("  Unique participants_category values (first 20): ",
          paste(head(pcat_values, 20), collapse = " | "))
}
pcat_map <- tibble(
  participants_category = c("50-99", "100-999", "1000-1999", "2000-4999",
                            "5000-10000", ">10000"),
  lo = c(    50,    100,  1000,  2000,   5000,  10001),
  hi = c(    99,    999,  1999,  4999,  10000,  99999)
) %>%
  mutate(avg = sqrt(lo * hi))

# Sensitivity: state-response-weighted violence counts a protest as
# "effectively violent" when the state response included lethal force
# (killings=40 or shootings=50 in MM stateresponse1-7 codes). The event-
# severity variant treats a protest as severely violent if both
# protesterviolence=1 AND there is property damage / injuries reported via
# any violent-tagged state response.
state_resp_cols <- grep("^stateresponse\\d+$", names(mm), value = TRUE)
if (length(state_resp_cols) > 0) {
  mm$state_lethal <- apply(
    mm[state_resp_cols], 1,
    function(r) as.integer(any(as.character(r) %in% c("40", "50"),
                               na.rm = TRUE))
  )
} else {
  mm$state_lethal <- 0L
}

mm <- mm %>%
  filter(!is.na(country), !is.na(year)) %>%
  mutate(
    protesterviolence = suppressWarnings(as.integer(protesterviolence)),
    v_sr = pmax(protesterviolence, state_lethal, na.rm = TRUE),
    v_es = as.integer(protesterviolence == 1 & state_lethal == 1)
  )

if ("participants_category" %in% names(mm)) {
  mm <- mm %>%
    mutate(participants_category =
             stringr::str_trim(as.character(participants_category))) %>%
    left_join(pcat_map, by = "participants_category")
  # Audit: how many events were matched by the join.
  pct_matched <- 100 * mean(!is.na(mm$avg))
  message(sprintf("  pcat_map join matched %.1f%% of events (%d / %d)",
                  pct_matched, sum(!is.na(mm$avg)), nrow(mm)))
  if (pct_matched < 10) {
    warning("pcat_map matched <10% of events: participants_category labels ",
            "may have changed in a newer MM release; see log for values.")
  }
} else {
  mm$lo <- NA_real_; mm$hi <- NA_real_; mm$avg <- NA_real_
  pct_matched <- 0
}

# ---- Country-year aggregation ------------------------------------------
cy <- mm %>%
  group_by(country, year) %>%
  summarise(
    n_events        = n(),
    n_nonviolent    = sum(protesterviolence == 0, na.rm = TRUE),
    n_violent       = sum(protesterviolence == 1, na.rm = TRUE),
    share_nonviolent = n_nonviolent / pmax(n_events, 1),
    share_nonviolent_sr = 1 - sum(v_sr == 1, na.rm = TRUE) / pmax(n_events, 1),
    share_nonviolent_es = 1 - sum(v_es == 1, na.rm = TRUE) / pmax(n_events, 1),
    avg_participants_lo = mean(lo,  na.rm = TRUE),
    avg_participants_hi = mean(hi,  na.rm = TRUE),
    avg_participants    = mean(avg, na.rm = TRUE),
    n_state_lethal      = sum(state_lethal == 1, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    intensity_nv    = share_nonviolent       * avg_participants,
    intensity_v     = (1 - share_nonviolent) * avg_participants,
    intensity_nv_sr = share_nonviolent_sr    * avg_participants,
    intensity_nv_es = share_nonviolent_es    * avg_participants
  )

message("\n  Country-year rows: ", format(nrow(cy), big.mark = ","),
        "  (countries=", n_distinct(cy$country),
        "; years=", n_distinct(cy$year), ")")

# ---- Balance panel on all country-year cells ---------------------------
# Every country that ever appears x every year in the observed MM range.
all_countries <- sort(unique(cy$country))
all_years     <- seq(min(cy$year, na.rm = TRUE), max(cy$year, na.rm = TRUE))
skeleton      <- expand_grid(country = all_countries, year = all_years)

# Zero-fill event-count columns only (a country-year with no MM events
# truly has zero events). Leave the bracket-mean columns NA: a
# country-year with zero events has no meaningful avg_participants, and
# forcing it to zero biases the nonviolent-intensity cutoff.
count_cols <- c("n_events", "n_nonviolent", "n_violent", "n_state_lethal")
panel <- left_join(skeleton, cy, by = c("country", "year")) %>%
  mutate(across(any_of(count_cols), ~ replace_na(.x, 0L)))

message("  Balanced panel rows: ", format(nrow(panel), big.mark = ","))

# ---- Export ------------------------------------------------------------
dir.create(here("data", "intermediate"), showWarnings = FALSE, recursive = TRUE)
saveRDS(panel, here("data", "intermediate", "mm_country_year.rds"))
message("Saved: data/intermediate/mm_country_year.rds")

cov_tbl <- panel %>%
  group_by(year) %>%
  summarise(
    n_countries_any_event = sum(n_events > 0),
    share_nv_avg          = mean(share_nonviolent[n_events > 0], na.rm = TRUE),
    avg_intensity_nv      = mean(intensity_nv[n_events > 0],     na.rm = TRUE),
    .groups = "drop"
  )
write_csv(cov_tbl, here("output", "tables", "mm_panel_coverage.csv"))

macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
writeLines(
  c("% Auto-generated by A_MM_02_build_country_year.R",
    paste0("% Generated: ", Sys.time()),
    macro("MMPanelNCountryYear",
          format(nrow(panel), big.mark = ",")),
    macro("MMPanelNCountries",
          format(n_distinct(panel$country), big.mark = ",")),
    macro("MMPanelYearRange",
          paste0(min(panel$year), "--", max(panel$year))),
    macro("MMPanelMeanShareNV",
          sprintf("%.3f",
                  mean(panel$share_nonviolent[panel$n_events > 0], na.rm = TRUE))),
    macro("MMPanelPctWithBracket",
          sprintf("%.1f", pct_matched))),
  here("output", "tables", "mm_panel_macros.tex")
)
message("Wrote macros: output/tables/mm_panel_macros.tex")

sink()
