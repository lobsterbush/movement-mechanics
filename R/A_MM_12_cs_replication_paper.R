# =============================================================================
# A_MM_12_cs_replication_paper.R
# Purpose: (a) Reproduce the Chenoweth & Stephan (2011) success-rate gap
#              between nonviolent and violent maximalist campaigns using
#              the MM participant brackets, then show how the gap attenuates
#              once nonviolence is estimated as a treatment effect rather
#              than a campaign-type description.
#          (b) Consolidate every MM figure, table and macro needed by the
#              A_MM manuscript into a single statistics.tex file and copy
#              figures into the paper tree.
# Inputs:
#   data/analysis/a_mm_panel.rds
#   output/tables/mm_*.tex
#   output/tables/a_mm_*.tex
#   output/figures/a_mm_*.pdf
# Outputs:
#   output/figures/a_mm_cs_replication.pdf
#   output/tables/a_mm_cs_replication_macros.tex
#   paper/A_nonviolence_premium_mm/statistics.tex
#   paper/A_nonviolence_premium_mm/figures/*.pdf  (copies)
# =============================================================================

suppressPackageStartupMessages({
  library(here); library(dplyr); library(readr)
  library(ggplot2); library(ggthemes)
})

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_MM_12_paper.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_MM_12 C&S replication + paper assets ===")
message("Run at: ", format(Sys.time()))

suppressPackageStartupMessages({ library(tidyr); library(stringr); library(janitor) })

panel <- readRDS(here("data", "analysis", "a_mm_panel.rds"))

# ---- (a) Chenoweth-Stephan replication ---------------------------------
# C&S's 3.5% claim is a national-participation threshold on the *largest*
# protest of a campaign. MM has bracket-only participant data, so we
# classify a country-year as "maximalist" if the upper bound of any
# single protest that year exceeds 3.5% of national population.
# Mapping:
#   nv_maximalist = any nonviolent protest with hi >= 0.035 * pop
#   v_maximalist  = any violent    protest with hi >= 0.035 * pop
# Outcome: change in V-Dem polyarchy 5 years forward (lead).
event_path <- here("data", "raw", "mm", "mmALL_073120_csv.tab")
pcat_map <- tibble(
  participants_category = c("50-99", "100-999", "1000-1999", "2000-4999",
                            "5000-10000", ">10000"),
  lo = c(   50,   100, 1000, 2000,  5000, 10001),
  hi = c(   99,   999, 1999, 4999, 10000, 99999)
)

if (file.exists(event_path) &&
    "wdi_pop_total" %in% names(panel) &&
    "v2x_polyarchy" %in% names(panel)) {
  ev <- read_tsv(event_path, guess_max = 200000, show_col_types = FALSE,
                 progress = FALSE) %>% janitor::clean_names() %>%
    filter(!is.na(country), !is.na(year)) %>%
    mutate(participants_category =
             str_trim(as.character(participants_category)),
           protesterviolence = suppressWarnings(as.integer(protesterviolence))) %>%
    left_join(pcat_map, by = "participants_category")

  # Pop denominator: join WDI pop_total on (country, year).
  pop_key <- panel %>%
    select(country, year, wdi_pop_total) %>% distinct()
  ev <- ev %>% left_join(pop_key, by = c("country", "year")) %>%
    mutate(pop_share_hi = hi / pmax(wdi_pop_total, 1))

  event_max <- ev %>%
    group_by(country, year) %>%
    summarise(
      nv_max = as.integer(any(protesterviolence == 0 &
                              is.finite(pop_share_hi) &
                              pop_share_hi >= 0.035, na.rm = TRUE)),
      v_max  = as.integer(any(protesterviolence == 1 &
                              is.finite(pop_share_hi) &
                              pop_share_hi >= 0.035, na.rm = TRUE)),
      max_pop_share = suppressWarnings(max(pop_share_hi, na.rm = TRUE)),
      .groups = "drop"
    ) %>%
    mutate(max_pop_share = ifelse(is.finite(max_pop_share),
                                  max_pop_share, NA_real_))

  pan <- panel %>%
    arrange(country, year) %>%
    group_by(country) %>%
    mutate(poly_lead5 = dplyr::lead(v2x_polyarchy, 5)) %>%
    ungroup() %>%
    left_join(event_max, by = c("country", "year")) %>%
    mutate(nv_max = replace_na(nv_max, 0L),
           v_max  = replace_na(v_max,  0L),
           delta_polyarchy = poly_lead5 - v2x_polyarchy)

  cs_summary <- tibble(
    arm = c("nv_maximalist", "v_maximalist"),
    n_country_years = c(sum(pan$nv_max, na.rm = TRUE),
                        sum(pan$v_max,  na.rm = TRUE)),
    mean_dpolyarchy = c(mean(pan$delta_polyarchy[pan$nv_max == 1],
                             na.rm = TRUE),
                        mean(pan$delta_polyarchy[pan$v_max == 1],
                             na.rm = TRUE)),
    sd_dpolyarchy   = c(sd(pan$delta_polyarchy[pan$nv_max == 1],
                           na.rm = TRUE),
                        sd(pan$delta_polyarchy[pan$v_max == 1],
                           na.rm = TRUE))
  )
  message("\n-- C&S replication summary --")
  print(as.data.frame(cs_summary), row.names = FALSE)
  write_csv(cs_summary, here("output", "tables", "a_mm_cs_replication.csv"))

  cs_rep <- pan %>%
    group_by(year) %>%
    summarise(
      share_nv_maximalist = mean(nv_max == 1, na.rm = TRUE),
      share_v_maximalist  = mean(v_max  == 1, na.rm = TRUE),
      .groups = "drop"
    )

  p_cs <- cs_rep %>%
    pivot_longer(-year, names_to = "arm", values_to = "share") %>%
    ggplot(aes(year, share, linetype = arm)) +
    geom_line(size = 0.7) +
    scale_linetype_manual(values = c("share_nv_maximalist" = 1,
                                     "share_v_maximalist" = 2),
                          labels = c("Nonviolent maximalist",
                                     "Violent maximalist")) +
    theme_tufte(base_size = 11) +
    labs(x = NULL, y = "Share of country-years",
         linetype = NULL,
         title = "Maximalist country-years (>=3.5% of population, any protest)")
  ggsave(here("output", "figures", "a_mm_cs_replication.pdf"),
         p_cs, device = cairo_pdf, width = 6.5, height = 4.0)

  # Headline gap = mean delta polyarchy (nv maximalist) minus mean delta
  # polyarchy (violent maximalist). SE via independent-arm approximation.
  n_nv <- cs_summary$n_country_years[1]; n_v <- cs_summary$n_country_years[2]
  se_nv <- if (n_nv > 1)
    cs_summary$sd_dpolyarchy[1] / sqrt(n_nv) else NA_real_
  se_v  <- if (n_v  > 1)
    cs_summary$sd_dpolyarchy[2] / sqrt(n_v)  else NA_real_
  headline_gap <- cs_summary$mean_dpolyarchy[1] - cs_summary$mean_dpolyarchy[2]
  headline_se  <- suppressWarnings(sqrt(se_nv^2 + se_v^2))
} else {
  message("  Missing raw MM events, WDI pop, or V-Dem; skipping C&S rep.")
  headline_gap <- NA_real_
  headline_se  <- NA_real_
  cs_summary <- tibble(arm = character(),
                       n_country_years = integer(),
                       mean_dpolyarchy = numeric())
  p_cs <- ggplot() + theme_tufte(base_size = 11) +
    labs(title = "C&S replication skipped (need raw MM events + WDI pop + V-Dem polyarchy)")
  ggsave(here("output", "figures", "a_mm_cs_replication.pdf"),
         p_cs, device = cairo_pdf, width = 6.5, height = 4.0)
}

macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
writeLines(
  c("% Auto-generated by A_MM_12_cs_replication_paper.R",
    paste0("% Generated: ", Sys.time()),
    macro("MMCSRepHeadlineGap",
          if (is.finite(headline_gap)) sprintf("%.4f", headline_gap) else "NA"),
    macro("MMCSRepHeadlineSE",
          if (is.finite(headline_se)) sprintf("%.4f", headline_se) else "NA"),
    macro("MMCSRepNonviolentN",
          if (nrow(cs_summary) > 0)
            format(cs_summary$n_country_years[1], big.mark = ",") else "NA"),
    macro("MMCSRepViolentN",
          if (nrow(cs_summary) > 0)
            format(cs_summary$n_country_years[2], big.mark = ",") else "NA")),
  here("output", "tables", "a_mm_cs_replication_macros.tex")
)

# ---- (b) Consolidate macros into paper statistics.tex ------------------
paper_dir <- here("paper", "A_nonviolence_premium_mm")
fig_out   <- file.path(paper_dir, "figures")
dir.create(paper_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(fig_out,   showWarnings = FALSE, recursive = TRUE)

macro_order <- c(
  "mm_audit_macros.tex",
  "mm_panel_macros.tex",
  "mm_vdem_macros.tex",
  "mm_polity_macros.tex",
  "mm_outcome_macros.tex",
  "a_mm_descriptives_macros.tex",
  "a_mm_cs_macros.tex",
  "a_mm_synthdid_macros.tex",
  "a_mm_augsynth_macros.tex",
  "a_mm_panelmatch_macros.tex",
  "a_mm_multiverse_macros.tex",
  "a_mm_cs_replication_macros.tex"
)

stats_lines <- c(
  "% =========================================================================",
  "% statistics.tex -- Auto-generated by R/A_MM_12_cs_replication_paper.R",
  paste0("% Generated: ", Sys.time()),
  "% ========================================================================="
)
for (f in macro_order) {
  p <- here("output", "tables", f)
  if (file.exists(p)) {
    stats_lines <- c(stats_lines, paste0("% --- ", f, " ---"),
                     readLines(p), "")
    message("  + ", f)
  } else {
    stats_lines <- c(stats_lines,
                     paste0("% --- ", f, " (missing) ---"), "")
    message("  [missing] ", f)
  }
}
writeLines(stats_lines, file.path(paper_dir, "statistics.tex"))

figs <- c(
  "a_mm_timeseries.pdf", "a_mm_choropleth.pdf", "a_mm_vdem_paths.pdf",
  "a_mm_synthdid_paths.pdf", "a_mm_augsynth_paths.pdf",
  "a_mm_honestdid.pdf", "a_mm_multiverse.pdf", "a_mm_cs_replication.pdf"
)
for (f in figs) {
  src <- here("output", "figures", f)
  dst <- file.path(fig_out, f)
  if (file.exists(src)) file.copy(src, dst, overwrite = TRUE)
}

message("Paper assets ready at: ", paper_dir)
sink()
