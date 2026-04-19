# =============================================================================
# A_US_05_descriptives.R
# Purpose: Descriptive figures and tables for the A_US Nonviolence Premium
#          paper.
#          1. Time series of nonviolent vs violent per-capita intensity
#             (2017-2023), overlaid with 2020 George-Floyd mobilization.
#          2. Choropleth of mean nonviolent share (2017-2023) by county.
#          3. Balance table: nonviolent vs violent-exposed counties at t=0
#             (covariate means with cluster-robust p-values).
#          4. Intensity distribution panel (log participation per capita).
# Inputs:
#   data/analysis/a_us_panel.rds                 (from A_US_04)
# Outputs:
#   output/figures/a_us_timeseries.pdf
#   output/figures/a_us_choropleth.pdf
#   output/figures/a_us_intensity_dist.pdf
#   output/tables/a_us_balance.tex
#   output/tables/a_us_descriptives_macros.tex
#   quality_reports/session_logs/<date>_A_US_05_descriptives.log
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(ggthemes)
})

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_US_05_descriptives.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_US_05 Descriptives ===")
message("Run at: ", format(Sys.time()))

panel <- readRDS(here("data", "analysis", "a_us_panel.rds")) %>%
  filter(violence_def == "strict")

fig_dir <- here("output", "figures")
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(fig_dir, "slides"), showWarnings = FALSE, recursive = TRUE)
tab_dir <- here("output", "tables")
dir.create(tab_dir, showWarnings = FALSE, recursive = TRUE)

save_both <- function(p, stem, width = 6.5, height = 4.0) {
  ggsave(file.path(fig_dir, paste0(stem, ".pdf")),
         p, device = cairo_pdf, width = width, height = height)
  ggsave(file.path(fig_dir, "slides", paste0(stem, ".png")),
         p, dpi = 300, bg = "transparent",
         width = width, height = height)
}

# ---- (1) Time series: nonviolent vs violent per-capita ------------------
ts <- panel %>%
  group_by(year) %>%
  summarise(
    nonviolent = mean(nonviolent_per_cap, na.rm = TRUE),
    violent    = mean(violent_per_cap,    na.rm = TRUE),
    .groups = "drop"
  ) %>%
  pivot_longer(c(nonviolent, violent),
               names_to = "type", values_to = "mean_per_cap")

p_ts <- ggplot(ts, aes(year, mean_per_cap, linetype = type)) +
  geom_line(size = 0.7) +
  geom_point(size = 1.2) +
  theme_tufte(base_size = 11) +
  labs(x = NULL, y = "Mean participation (% of county pop)",
       linetype = NULL,
       title = "Nonviolent vs violent protest intensity, 2017\u20132023") +
  theme(plot.title = element_text(size = 12),
        legend.position = "bottom")
save_both(p_ts, "a_us_timeseries")

# ---- (2) Choropleth ------------------------------------------------------
# Use tigris::counties(year = 2020) + sf for a proper county choropleth.
county_mean <- panel %>%
  group_by(fips_code) %>%
  summarise(nv_share = sum(size_nonviolent) /
                       pmax(sum(size_nonviolent) + sum(size_violent), 1),
            n_events = sum(n_events),
            .groups = "drop")

have_sf <- requireNamespace("sf", quietly = TRUE) &&
           requireNamespace("tigris", quietly = TRUE)
if (have_sf) {
  suppressMessages({
    counties_sf <- tigris::counties(year = 2020, cb = TRUE,
                                    progress_bar = FALSE) %>%
      dplyr::select(fips_code = GEOID, geometry)
    # Drop Alaska/Hawaii/territories for a compact Lower-48 map.
    counties_sf <- counties_sf %>%
      filter(!substr(fips_code, 1, 2) %in% c("02", "15", "60", "66",
                                             "69", "72", "78"))
    county_sf <- dplyr::left_join(counties_sf, county_mean, by = "fips_code")
  })
  p_map <- ggplot(county_sf) +
    geom_sf(aes(fill = nv_share), colour = NA) +
    scale_fill_gradient(low = "grey85", high = "#1f3b66",
                        na.value = "white",
                        limits = c(0, 1),
                        name = "Nonviolent share") +
    theme_tufte(base_size = 10) +
    theme(axis.text = element_blank(),
          axis.ticks = element_blank(),
          panel.grid = element_blank(),
          legend.position = "bottom") +
    labs(title = "Mean nonviolent share of protest participation, 2017\u20132023")
  save_both(p_map, "a_us_choropleth", height = 4.2)
} else {
  # Fallback: rank plot (no geography).
  p_map <- ggplot(county_mean %>% filter(n_events > 0),
                  aes(x = reorder(fips_code, nv_share), y = nv_share)) +
    geom_point(alpha = 0.2, size = 0.3) +
    theme_tufte(base_size = 10) +
    labs(x = "County (ordered)", y = "Nonviolent share of participation",
         title = "Install `sf` + `tigris` for a real choropleth") +
    theme(axis.text.x = element_blank(),
          axis.ticks.x = element_blank())
  save_both(p_map, "a_us_choropleth", height = 3.6)
}

# ---- (3) Intensity distribution -----------------------------------------
p_dist <- panel %>%
  filter(any_protest_per_cap > 0) %>%
  ggplot(aes(log1p(any_protest_per_cap))) +
  geom_histogram(bins = 60, fill = "grey60", colour = "white") +
  theme_tufte(base_size = 11) +
  labs(x = "log(1 + protest participation, % of county population)",
       y = "County-years",
       title = "Distribution of county-year protest intensity")
save_both(p_dist, "a_us_intensity_dist")

# ---- (4) Balance table --------------------------------------------------
# Compare ever-nonviolent-exposed vs ever-violent-exposed counties on
# pre-period (2017) covariates. Outcome-column set depends on what A_US_04
# attached; we use the six spending outcomes plus MPV killings where present.
bal_cols <- intersect(
  c("pop", "spend_public_safety", "spend_police", "spend_welfare",
    "spend_education", "spend_highways", "mpv_killings"),
  names(panel))

county_exp <- panel %>%
  group_by(fips_code) %>%
  summarise(
    ever_nv = as.integer(any(nonviolent_per_cap > 0)),
    ever_v  = as.integer(any(violent_per_cap    > 0)),
    .groups = "drop"
  )

base_year <- min(panel$year, na.rm = TRUE)
bal <- panel %>%
  filter(year == base_year) %>%
  left_join(county_exp, by = "fips_code") %>%
  select(fips_code, ever_nv, ever_v, all_of(bal_cols)) %>%
  pivot_longer(all_of(bal_cols), names_to = "variable",
               values_to = "value") %>%
  group_by(variable) %>%
  summarise(
    mean_ever_nv = mean(value[ever_nv == 1], na.rm = TRUE),
    mean_ever_v  = mean(value[ever_v  == 1], na.rm = TRUE),
    mean_never   = mean(value[ever_nv == 0 & ever_v == 0], na.rm = TRUE),
    # Wilcoxon test on the NV-vs-violent contrast.
    p_nv_vs_v    = suppressWarnings(tryCatch(
      wilcox.test(value[ever_nv == 1], value[ever_v == 1])$p.value,
      error = function(e) NA_real_)),
    .groups = "drop"
  )
write_csv(bal, file.path(tab_dir, "a_us_balance.csv"))
message("\n-- Balance (pre-period ever-NV vs ever-V counties) --")
print(as.data.frame(bal), row.names = FALSE)

macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
writeLines(
  c("% Auto-generated by A_US_05_descriptives.R",
    paste0("% Generated: ", Sys.time()),
    macro("AUSDescNYears", length(unique(panel$year))),
    macro("AUSDescMaxNonviolent",
          sprintf("%.3f", max(ts$mean_per_cap[ts$type == "nonviolent"]))),
    macro("AUSDescMaxViolent",
          sprintf("%.3f", max(ts$mean_per_cap[ts$type == "violent"])))),
  file.path(tab_dir, "a_us_descriptives_macros.tex")
)
message("Wrote macros: output/tables/a_us_descriptives_macros.tex")

sink()
