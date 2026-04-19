# =============================================================================
# A_US_03_build_ccc_county_year.R
# Purpose: Aggregate the imputed CCC event file to a county-year panel with
#          the three headline treatment variables for the Nonviolence Premium
#          design:
#            nonviolent_per_cap  = nonviolent crowd-size / county population
#            violent_per_cap     = violent crowd-size    / county population
#            any_protest_per_cap = (nonviolent + violent) / county population
#          Three violence definitions are carried side by side:
#            v_strict     (any incident flag => violent)
#            v_permissive (protester-instigated only)
#            v_noarrest   (arrests excluded from violence)
#          The resulting panel is the unit of observation for every A_US DiD.
# Inputs:
#   data/intermediate/ccc_events_imputed.rds  (from A_US_02)
#   data/raw/census/co-est2023-alldata.csv    (county pop; TODO: add pull)
# Outputs:
#   data/intermediate/ccc_county_year.rds
#   output/tables/ccc_panel_coverage.csv
#   output/tables/ccc_panel_macros.tex
#   quality_reports/session_logs/<date>_A_US_03_panel.log
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(readr)
  library(tidyr)
  library(stringr)
})

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_US_03_panel.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_US_03 Build CCC county-year panel ===")
message("Run at: ", format(Sys.time()))

events_path <- here("data", "intermediate", "ccc_events_imputed.rds")
if (!file.exists(events_path)) {
  stop("Missing: ", events_path,
       "\n  Run R/A_US_02_impute_ccc_size.R first.")
}
ev <- readRDS(events_path)
message("  Loaded events: ", format(nrow(ev), big.mark = ","))

# ---- Violence definitions (three candidates) -----------------------------
# Carried through all three; analysis picks one as headline, others as robustness.
ev <- ev %>%
  mutate(
    v_strict     = as.integer(pd + ar + ic + ip + ca > 0),
    v_permissive = as.integer(pd + ar + ic > 0),
    v_noarrest   = as.integer(pd + ic > 0)
  )

# ---- Event-level intensity (imputed size) assigned to violent / nonviolent
# columns under each of the three definitions ------------------------------
build_panel <- function(df, flag_col) {
  df %>%
    mutate(
      violent_size    = if_else(.data[[flag_col]] == 1, size_imputed, 0),
      nonviolent_size = if_else(.data[[flag_col]] == 0, size_imputed, 0)
    ) %>%
    group_by(fips_code, year) %>%
    summarise(
      n_events        = n(),
      n_nonviolent    = sum(.data[[flag_col]] == 0, na.rm = TRUE),
      n_violent       = sum(.data[[flag_col]] == 1, na.rm = TRUE),
      size_nonviolent = sum(nonviolent_size, na.rm = TRUE),
      size_violent    = sum(violent_size,    na.rm = TRUE),
      size_total      = sum(size_imputed,    na.rm = TRUE),
      # Lee-style bounds carried forward for HonestDiD sensitivity
      size_total_lo   = sum(size_lo_bound,   na.rm = TRUE),
      size_total_hi   = sum(size_hi_bound,   na.rm = TRUE),
      .groups = "drop"
    )
}

panels <- list(
  strict     = build_panel(ev, "v_strict"),
  permissive = build_panel(ev, "v_permissive"),
  noarrest   = build_panel(ev, "v_noarrest")
)

# ---- Balance panel on full county × year grid ----------------------------
# TODO: replace with authoritative FIPS5 list (tigris::counties(year = 2020))
all_fips  <- sort(unique(ev$fips_code))
all_years <- sort(unique(ev$year))
skeleton  <- expand_grid(fips_code = all_fips, year = all_years)

panels <- lapply(panels, function(p) {
  left_join(skeleton, p, by = c("fips_code", "year")) %>%
    mutate(across(where(is.numeric), ~ replace_na(.x, 0)))
})

# ---- Merge county population --------------------------------------------
# Census PEP files ship as wide "one row per county, one column per year".
# co-est2020-alldata.csv covers 2010-2020 (columns POPESTIMATE2010..2020);
# co-est2024-alldata.csv covers 2020-2024 (columns POPESTIMATE2020..2024).
# We stack into long form, join on fips_code x year, compute per-capita.
read_pep <- function(path, years_wanted) {
  if (!file.exists(path)) return(NULL)
  df <- suppressWarnings(readr::read_csv(
    path,
    locale = readr::locale(encoding = "latin1"),
    show_col_types = FALSE, progress = FALSE
  ))
  df <- df %>%
    filter(as.integer(SUMLEV) == 50) %>%            # county rows only
    mutate(
      fips_code = paste0(str_pad(STATE,  2, "left", "0"),
                         str_pad(COUNTY, 3, "left", "0"))
    )
  year_cols <- intersect(paste0("POPESTIMATE", years_wanted), names(df))
  long <- df %>%
    select(fips_code, all_of(year_cols)) %>%
    pivot_longer(-fips_code, names_to = "year", values_to = "pop") %>%
    mutate(year = as.integer(sub("POPESTIMATE", "", year)))
  long
}

pop_2010s <- read_pep(here("data", "raw", "census",
                           "co-est2020-alldata.csv"), 2010:2019)
pop_2020s <- read_pep(here("data", "raw", "census",
                           "co-est2024-alldata.csv"), 2020:2024)
pop <- bind_rows(pop_2010s, pop_2020s)
if (is.null(pop) || nrow(pop) == 0) {
  message("  Census pop missing; using placeholder population = 100,000.")
  attach_per_cap <- function(p) p %>%
    mutate(pop = 100000,
           nonviolent_per_cap  = 100 * size_nonviolent / pop,
           violent_per_cap     = 100 * size_violent    / pop,
           any_protest_per_cap = 100 * size_total      / pop)
} else {
  message("  Joined Census PEP population: ",
          format(nrow(pop), big.mark = ","), " county-years")
  attach_per_cap <- function(p) {
    left_join(p, pop, by = c("fips_code", "year")) %>%
      mutate(
        pop = ifelse(is.na(pop) | pop == 0, 100000, pop),
        nonviolent_per_cap  = 100 * size_nonviolent / pop,
        violent_per_cap     = 100 * size_violent    / pop,
        any_protest_per_cap = 100 * size_total      / pop
      )
  }
}
panels <- lapply(panels, attach_per_cap)

# ---- Stack for downstream estimation ------------------------------------
panel <- bind_rows(
  panels$strict     %>% mutate(violence_def = "strict"),
  panels$permissive %>% mutate(violence_def = "permissive"),
  panels$noarrest   %>% mutate(violence_def = "noarrest")
)

message("\n  Long-form panel rows: ", format(nrow(panel), big.mark = ","),
        " (3 defs x county-year)")

# ---- Coverage diagnostics -----------------------------------------------
cov_tbl <- panel %>%
  group_by(violence_def, year) %>%
  summarise(
    n_county_year           = n(),
    n_county_year_any       = sum(any_protest_per_cap > 0),
    share_violent_nonzero   = mean(violent_per_cap > 0),
    share_nonviolent_nonzero = mean(nonviolent_per_cap > 0),
    .groups = "drop"
  )
message("\n-- Coverage by year x violence def --")
print(as.data.frame(cov_tbl), row.names = FALSE)

# ---- Export -------------------------------------------------------------
dir.create(here("data", "intermediate"), showWarnings = FALSE, recursive = TRUE)
saveRDS(panel, here("data", "intermediate", "ccc_county_year.rds"))
message("\nSaved: data/intermediate/ccc_county_year.rds")

write_csv(cov_tbl, here("output", "tables", "ccc_panel_coverage.csv"))

macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
macros <- c(
  "% Auto-generated by A_US_03_build_ccc_county_year.R",
  paste0("% Generated: ", Sys.time()),
  macro("CCCPanelNCountyYear",
        format(n_distinct(paste(panel$fips_code, panel$year)), big.mark = ",")),
  macro("CCCPanelNCounties",
        format(n_distinct(panel$fips_code), big.mark = ",")),
  macro("CCCPanelYearRange",
        paste0(min(panel$year), "--", max(panel$year))),
  macro("CCCPanelShareAnyProtest",
        sprintf("%.2f", 100 * mean(panel$any_protest_per_cap > 0)))
)
writeLines(macros, here("output", "tables", "ccc_panel_macros.tex"))
message("Wrote macros: output/tables/ccc_panel_macros.tex")

sink()
