# =============================================================================
# A_US_01_audit_ccc.R
# Purpose: Initial data quality audit of CCC Phase 1 + Phase 2 for the
#          Nonviolence Premium analysis (A_US).
#          Answers, per year:
#            - How many events, of which how many have a non-missing size?
#            - How many are geocoded to a FIPS5 county?
#            - How are the five violence indicators populated?
#            - How correlated are the violence indicators?
#            - What share of events are "violent" under three candidate
#              definitions (strict / permissive / arrest-excluded)?
# Inputs:  data/raw/ccc/ccc_compiled.csv                 (Phase 1)
#          data/raw/ccc/ccc_compiled_2021_present.csv    (Phase 2)
# Outputs: output/tables/ccc_audit_yearly.csv
#          output/tables/ccc_audit_violence_cooc.csv
#          output/tables/ccc_audit_macros.tex
#          quality_reports/session_logs/2026-04-17_A_US_01_audit.log
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(readr)
  library(dplyr)
  library(stringr)
  library(lubridate)
  library(tidyr)
})

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_US_01_audit.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_US_01 CCC audit ===")
message("Run at: ", format(Sys.time()))

# ---- Load ------------------------------------------------------------------
phase1_path <- here("data", "raw", "ccc", "ccc_compiled.csv")
phase2_path <- here("data", "raw", "ccc", "ccc_compiled_2021_present.csv")

read_phase <- function(path, label) {
  if (!file.exists(path)) {
    message("  Skipping ", label, " (missing file): ", path)
    return(NULL)
  }
  message("  Reading ", label, " ...")
  x <- read_csv(
    path,
    col_types = cols(
      fips_code           = col_character(),
      date                = col_date(format = ""),
      size_mean           = col_double(),
      size_low            = col_double(),
      size_high           = col_double(),
      property_damage_any = col_double(),
      arrests_any         = col_double(),
      injuries_crowd_any  = col_double(),
      injuries_police_any = col_double(),
      chemical_agents     = col_double(),
      .default            = col_character()
    ),
    locale = locale(encoding = "latin1"),
    progress = FALSE
  )
  x$phase <- label
  message("    rows=", format(nrow(x), big.mark = ","))
  x
}

phases <- list(
  phase1 = read_phase(phase1_path, "phase1"),
  phase2 = read_phase(phase2_path, "phase2")
)
phases <- phases[!sapply(phases, is.null)]
if (length(phases) == 0) stop("No CCC files found.")

# Harmonize issues column across phases (Phase 1 has `issues`, Phase 2 has
# `issue_tags`; Phase 2 also names actors as `organizations`).
harmonize <- function(df) {
  n <- names(df)
  if ("issue_tags"     %in% n) n[n == "issue_tags"]     <- "issues"
  if ("organizations"  %in% n) n[n == "organizations"]  <- "actors"
  names(df) <- n
  df
}
phases <- lapply(phases, harmonize)
common <- Reduce(intersect, lapply(phases, names))
ccc    <- bind_rows(lapply(phases, function(x) x[, common]))
message("  Combined rows: ", format(nrow(ccc), big.mark = ","))

# ---- Clean keys ------------------------------------------------------------
ccc <- ccc %>%
  mutate(
    fips_code = str_pad(str_trim(fips_code), 5, "left", "0"),
    has_fips  = !is.na(fips_code) & nchar(fips_code) == 5 &
                  !fips_code %in% c("   NA", "NA"),
    year      = year(date),
    has_size  = !is.na(size_mean),
    online1   = if ("online" %in% names(ccc)) as.integer(online == "1") else 0L
  )

# ---- Violence flag engineering --------------------------------------------
# CCC codes each incident as present/absent. For the nonviolence premium we
# consider three candidate definitions. All events with no flags set are
# nonviolent under every definition. Property damage with no arrests or
# injuries (e.g., vandalism) is ambiguous; we separate it out.
ccc <- ccc %>%
  mutate(
    pd   = replace_na(property_damage_any, 0),
    ar   = replace_na(arrests_any,         0),
    ic   = replace_na(injuries_crowd_any,  0),
    ip   = replace_na(injuries_police_any, 0),
    ca   = replace_na(chemical_agents,     0),

    # Strict: any incident flag => violent.
    v_strict     = as.integer(pd + ar + ic + ip + ca > 0),

    # Permissive (protester-instigated only): drop chemical agents & police
    # injuries as those can reflect state response.
    v_permissive = as.integer(pd + ar + ic > 0),

    # Arrest-excluded: arrests often follow state policy (e.g., curfews),
    # not protester violence. Keep only property damage and crowd injuries.
    v_noarrest   = as.integer(pd + ic > 0)
  )

# ---- Per-year coverage ----------------------------------------------------
year_tbl <- ccc %>%
  filter(!is.na(year)) %>%
  group_by(year) %>%
  summarise(
    n_events          = n(),
    pct_has_fips      = round(100 * mean(has_fips), 1),
    pct_has_size      = round(100 * mean(has_size), 1),
    pct_online_only   = round(100 * mean(online1 == 1, na.rm = TRUE), 2),
    pct_pd            = round(100 * mean(pd == 1), 2),
    pct_ar            = round(100 * mean(ar == 1), 2),
    pct_ic            = round(100 * mean(ic == 1), 2),
    pct_ip            = round(100 * mean(ip == 1), 2),
    pct_ca            = round(100 * mean(ca == 1), 2),
    pct_v_strict      = round(100 * mean(v_strict == 1), 2),
    pct_v_permissive  = round(100 * mean(v_permissive == 1), 2),
    pct_v_noarrest    = round(100 * mean(v_noarrest == 1), 2),
    n_counties        = n_distinct(fips_code[has_fips]),
    .groups = "drop"
  )

message("\n-- Yearly coverage (Phase 1 + Phase 2) --")
print(as.data.frame(year_tbl))

# ---- Violence-flag co-occurrence ------------------------------------------
cooc <- ccc %>%
  summarise(
    n_total         = n(),
    only_pd         = sum(pd == 1 & ar == 0 & ic == 0 & ip == 0 & ca == 0),
    only_ar         = sum(pd == 0 & ar == 1 & ic == 0 & ip == 0 & ca == 0),
    only_ic         = sum(pd == 0 & ar == 0 & ic == 1 & ip == 0 & ca == 0),
    only_ip         = sum(pd == 0 & ar == 0 & ic == 0 & ip == 1 & ca == 0),
    only_ca         = sum(pd == 0 & ar == 0 & ic == 0 & ip == 0 & ca == 1),
    pd_and_ar       = sum(pd == 1 & ar == 1),
    pd_and_ic       = sum(pd == 1 & ic == 1),
    ar_and_ic       = sum(ar == 1 & ic == 1),
    ca_and_ic_or_ip = sum(ca == 1 & (ic == 1 | ip == 1)),
    all_five        = sum(pd == 1 & ar == 1 & ic == 1 & ip == 1 & ca == 1)
  )

message("\n-- Violence-flag co-occurrence --")
print(as.data.frame(cooc))

# ---- Pairwise phi correlations across violence flags ----------------------
vm <- as.matrix(select(ccc, pd, ar, ic, ip, ca))
phi <- suppressWarnings(cor(vm))
message("\n-- Violence-flag correlation matrix --")
print(round(phi, 3))

# ---- Sample-restriction summary for A_US ----------------------------------
# A_US restricts to 2017-2023, FIPS-geocoded, non-online events, events with
# imputable crowd size (size_mean present). Everything else becomes a sample
# decision that needs a robustness check.
a_us_core <- ccc %>%
  filter(has_fips, year >= 2017, year <= 2023, online1 != 1, has_size)

sample_tbl <- tribble(
  ~step,                                              ~n,
  "Raw events (Phase 1 + 2)",                         nrow(ccc),
  "  + valid FIPS5",                                  sum(ccc$has_fips),
  "  + year in 2017-2023",                            sum(ccc$has_fips & ccc$year >= 2017 & ccc$year <= 2023, na.rm = TRUE),
  "  + not online-only",                              sum(ccc$has_fips & ccc$year >= 2017 & ccc$year <= 2023 & ccc$online1 != 1, na.rm = TRUE),
  "  + non-missing size_mean (A_US core sample)",     nrow(a_us_core)
)
message("\n-- A_US core sample construction --")
print(as.data.frame(sample_tbl))

# ---- Export ---------------------------------------------------------------
tab_dir <- here("output", "tables")
dir.create(tab_dir, showWarnings = FALSE, recursive = TRUE)

write_csv(year_tbl, file.path(tab_dir, "ccc_audit_yearly.csv"))
write_csv(cooc,     file.path(tab_dir, "ccc_audit_violence_cooc.csv"))
write_csv(sample_tbl, file.path(tab_dir, "ccc_audit_sample.csv"))

# LaTeX macros for the A_US paper
macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
core_years <- a_us_core$year
macros <- c(
  "% Auto-generated by A_US_01_audit_ccc.R",
  paste0("% Generated: ", Sys.time()),
  macro("CCCNRaw",          format(nrow(ccc), big.mark = ",")),
  macro("CCCNCore",         format(nrow(a_us_core), big.mark = ",")),
  macro("CCCPctHasFips",    sprintf("%.1f", 100 * mean(ccc$has_fips))),
  macro("CCCPctHasSize",    sprintf("%.1f", 100 * mean(ccc$has_size))),
  macro("CCCPctVStrict",    sprintf("%.2f", 100 * mean(a_us_core$v_strict))),
  macro("CCCPctVPermissive",sprintf("%.2f", 100 * mean(a_us_core$v_permissive))),
  macro("CCCPctVNoArrest",  sprintf("%.2f", 100 * mean(a_us_core$v_noarrest))),
  macro("CCCNCountiesCore", format(n_distinct(a_us_core$fips_code), big.mark = ",")),
  macro("CCCYearRange",     paste0(min(core_years), "--", max(core_years)))
)
writeLines(macros, file.path(tab_dir, "ccc_audit_macros.tex"))
message("\nWrote macros: output/tables/ccc_audit_macros.tex")

sink()
message("\nLog: ", log_path)
