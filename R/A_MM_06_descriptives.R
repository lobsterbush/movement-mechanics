# =============================================================================
# A_MM_06_descriptives.R
# Purpose: Descriptive figures and tables for the A_MM Nonviolence Premium
#          paper.
#          1. Global time series of mean share_nonviolent by year, overlaid
#             with Arab Spring (2011-12) and BLM/2020 shocks.
#          2. Choropleth of 1990-2019 mean share_nonviolent by country.
#          3. V-Dem polyarchy trajectories: nonviolent-dominant vs
#             violent-dominant country paths.
# Inputs:
#   data/analysis/a_mm_panel.rds
# Outputs:
#   output/figures/a_mm_timeseries.pdf
#   output/figures/a_mm_choropleth.pdf
#   output/figures/a_mm_vdem_paths.pdf
#   output/tables/a_mm_descriptives_macros.tex
# =============================================================================

suppressPackageStartupMessages({
  library(here); library(dplyr); library(tidyr); library(readr)
  library(ggplot2); library(ggthemes)
})

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_MM_06_desc.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_MM_06 Descriptives ===")
message("Run at: ", format(Sys.time()))

panel <- readRDS(here("data", "analysis", "a_mm_panel.rds"))
fig_dir <- here("output", "figures")
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(fig_dir, "slides"), showWarnings = FALSE, recursive = TRUE)

save_both <- function(p, stem, width = 6.5, height = 4.0) {
  ggsave(file.path(fig_dir, paste0(stem, ".pdf")),
         p, device = cairo_pdf, width = width, height = height)
  ggsave(file.path(fig_dir, "slides", paste0(stem, ".png")),
         p, dpi = 300, bg = "transparent",
         width = width, height = height)
}

# ---- (1) Time series of mean share_nonviolent --------------------------
ts <- panel %>%
  filter(n_events > 0) %>%
  group_by(year) %>%
  summarise(mean_share_nv = mean(share_nonviolent, na.rm = TRUE),
            n_countries   = n_distinct(country),
            .groups = "drop")

p_ts <- ggplot(ts, aes(year, mean_share_nv)) +
  geom_line(size = 0.7) +
  geom_point(size = 1.2) +
  theme_tufte(base_size = 11) +
  labs(x = NULL, y = "Mean share of nonviolent protests",
       title = "Global mean of country-year nonviolent share (MM, 1990\u20132020)")
save_both(p_ts, "a_mm_timeseries")

country_mean <- panel %>%
  filter(n_events > 0) %>%
  group_by(country) %>%
  summarise(nv_share = mean(share_nonviolent, na.rm = TRUE),
            n_events_total = sum(n_events), .groups = "drop")

# ---- (2) Choropleth: rnaturalearth + sf ---------------------------------
have_world <- requireNamespace("rnaturalearth", quietly = TRUE) &&
              requireNamespace("sf", quietly = TRUE) &&
              requireNamespace("countrycode", quietly = TRUE)
if (have_world) {
  world <- rnaturalearth::ne_countries(returnclass = "sf", scale = "medium")
  world$iso3c <- world$iso_a3
  country_mean$iso3c <- countrycode::countrycode(country_mean$country,
                                                 "country.name", "iso3c",
                                                 warn = FALSE)
  world_dat <- dplyr::left_join(world, country_mean, by = "iso3c")
  p_map <- ggplot(world_dat) +
    geom_sf(aes(fill = nv_share), colour = "grey70", size = 0.05) +
    scale_fill_gradient(low = "#d0d4db", high = "#1f3b66",
                        na.value = "white",
                        limits = c(0, 1),
                        name = "Mean nonviolent share") +
    theme_tufte(base_size = 10) +
    theme(axis.text = element_blank(), axis.ticks = element_blank(),
          panel.grid = element_blank(),
          legend.position = "bottom") +
    labs(title = "Country-year mean nonviolent share, 1990\u20132020")
  save_both(p_map, "a_mm_choropleth", height = 4.5)
} else {
  p_map <- country_mean %>%
    arrange(nv_share) %>%
    mutate(country = factor(country, levels = country)) %>%
    ggplot(aes(country, nv_share)) +
    geom_col(fill = "grey60") + coord_flip() +
    theme_tufte(base_size = 7) +
    labs(x = NULL, y = "Mean share nonviolent",
         title = "Install `rnaturalearth`+`sf`+`countrycode` for a real choropleth")
  save_both(p_map, "a_mm_choropleth", height = 10)
}

# ---- (3) V-Dem paths by tercile of nonviolent share ---------------------
if ("v2x_polyarchy" %in% names(panel) &&
    any(!is.na(panel$v2x_polyarchy))) {
  terciles <- country_mean %>%
    mutate(tercile = ntile(nv_share, 3)) %>%
    select(country, tercile)
  paths <- panel %>%
    left_join(terciles, by = "country") %>%
    filter(!is.na(tercile)) %>%
    group_by(year, tercile) %>%
    summarise(mean_polyarchy = mean(v2x_polyarchy, na.rm = TRUE),
              .groups = "drop") %>%
    mutate(group = factor(tercile, labels =
              c("Bottom NV tercile", "Mid NV tercile", "Top NV tercile")))
  p_vd <- ggplot(paths, aes(year, mean_polyarchy,
                            linetype = group, colour = group)) +
    geom_line(size = 0.7) +
    scale_colour_grey(start = 0.2, end = 0.7) +
    theme_tufte(base_size = 11) +
    labs(x = NULL, y = "Mean V-Dem polyarchy",
         colour = NULL, linetype = NULL,
         title = "Polyarchy trajectories by nonviolent-share tercile") +
    theme(legend.position = "bottom")
  save_both(p_vd, "a_mm_vdem_paths")
}

macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
writeLines(
  c("% Auto-generated by A_MM_06_descriptives.R",
    paste0("% Generated: ", Sys.time()),
    macro("MMDescMeanShareNV",
          sprintf("%.3f", mean(ts$mean_share_nv, na.rm = TRUE)))),
  here("output", "tables", "a_mm_descriptives_macros.tex")
)
message("Wrote macros: output/tables/a_mm_descriptives_macros.tex")

sink()
