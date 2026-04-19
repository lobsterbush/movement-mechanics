# =============================================================================
# A_MM_09_augsynth.R
# Purpose: Augmented synthetic control (Ben-Michael, Feller, Rothstein 2021)
#          sensitivity to the synthdid A_MM headline. Runs staggered
#          `multisynth()` across all treated countries jointly on each
#          outcome and reports the aggregate ATT.
# Method:
#   - multisynth(form = y ~ treat, unit, time, ...) handles staggered
#     adoption; we set n_leads = 5 and use Ridge augmentation.
#   - Outcomes: V-Dem polyarchy + libdem.
#   - Treatment indicator mirrors A_MM_07 and A_MM_08: first year in
#     which intensity_nv crosses the 90th pct of its positive support.
# Inputs:
#   data/analysis/a_mm_panel.rds
# Outputs:
#   data/analysis/a_mm_augsynth_results.rds
#   output/figures/a_mm_augsynth_paths.pdf
#   output/tables/a_mm_augsynth_summary.csv
#   output/tables/a_mm_augsynth_macros.tex
# =============================================================================

suppressPackageStartupMessages({
  library(here); library(dplyr); library(readr); library(tidyr)
  library(ggplot2); library(ggthemes)
})

if (!requireNamespace("augsynth", quietly = TRUE)) {
  stop("Install 'augsynth' from GitHub (ebenmichael/augsynth).")
}

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_MM_09_augsynth.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_MM_09 augsynth ===")
message("Run at: ", format(Sys.time()))

panel <- readRDS(here("data", "analysis", "a_mm_panel.rds")) %>%
  # V-Dem + Polity joins can introduce duplicate (country, year) rows;
  # collapse to one row per country-year before augsynth.
  group_by(country, year) %>%
  summarise(across(where(is.numeric),
                   ~ suppressWarnings(mean(.x, na.rm = TRUE))),
            .groups = "drop") %>%
  mutate(across(where(is.numeric), ~ ifelse(is.finite(.x), .x, NA_real_)))

# Treatment: first year above 90th-pct nv-intensity, staggered adoption.
pos <- panel$intensity_nv[is.finite(panel$intensity_nv) &
                          panel$intensity_nv > 0]
cutoff <- if (length(pos) > 0) quantile(pos, 0.90, na.rm = TRUE) else NA_real_
panel <- panel %>%
  group_by(country) %>%
  mutate(
    above = as.integer(is.finite(intensity_nv) &
                       intensity_nv >= cutoff &
                       is.finite(cutoff)),
    first_year = suppressWarnings(min(year[above == 1], na.rm = TRUE)),
    first_year = ifelse(is.finite(first_year), first_year, NA_integer_),
    treat = as.integer(!is.na(first_year) & year >= first_year)
  ) %>% ungroup()

outcomes <- c("v2x_polyarchy", "v2x_libdem")

run_multisynth <- function(yname) {
  df <- panel %>% filter(!is.na(.data[[yname]]))
  min_year <- min(df$year, na.rm = TRUE)
  # multisynth rejects always-treated units and units with <=1 pre
  # period; compute first-treated-year and drop them.
  ft <- df %>% group_by(country) %>%
    summarise(first_t = suppressWarnings(min(year[treat == 1],
                                             na.rm = TRUE)),
              .groups = "drop")
  bad <- ft %>%
    filter(is.finite(first_t) & first_t <= min_year + 4)
  df <- df %>% filter(!country %in% bad$country)
  n_treat <- dplyr::n_distinct(df$country[df$treat == 1])
  message(sprintf("  %s: treated countries (post-filter) = %d (dropped %d)",
                  yname, n_treat, nrow(bad)))
  if (n_treat < 2) {
    message(sprintf("    skipping %s (fewer than 2 treated)", yname))
    return(NULL)
  }
  tryCatch(
    augsynth::multisynth(
      form  = as.formula(paste(yname, "~ treat")),
      unit  = country, time = year,
      data  = df,
      n_leads = 5, progfunc = "Ridge", scm = TRUE,
      fixedeff = FALSE
    ),
    error = function(e) {
      message("    multisynth failed: ", e$message); NULL
    }
  )
}

results <- setNames(lapply(outcomes, run_multisynth), outcomes)

extract_avg <- function(obj) {
  if (is.null(obj)) return(tibble(att = NA_real_, se = NA_real_))
  s <- tryCatch(summary(obj), error = function(e) NULL)
  if (is.null(s)) return(tibble(att = NA_real_, se = NA_real_))
  # multisynth's summary() returns `att` as a tibble with Average over
  # all treated units at the top. Pull that row.
  avg_row <- s$att %>%
    dplyr::filter(.data$Level == "Average" |
                  is.na(.data$Time) |
                  .data$Time == max(.data$Time, na.rm = TRUE))
  if (nrow(avg_row) == 0) {
    avg_row <- s$att %>% dplyr::slice_tail(n = 1)
  }
  tibble(att = suppressWarnings(mean(avg_row$Estimate, na.rm = TRUE)),
         se  = suppressWarnings(mean(avg_row$Std.Error, na.rm = TRUE)))
}

summary_tbl <- tibble(outcome = outcomes) %>%
  mutate(stats = lapply(results, extract_avg)) %>%
  unnest(stats)

message("\n-- augsynth summary --")
print(as.data.frame(summary_tbl), row.names = FALSE)

saveRDS(list(results = results, summary = summary_tbl,
             cutoff = cutoff),
        here("data", "analysis", "a_mm_augsynth_results.rds"))
write_csv(summary_tbl, here("output", "tables", "a_mm_augsynth_summary.csv"))

# ---- Plot ATT paths for polyarchy if available --------------------------
poly_obj <- results[["v2x_polyarchy"]]
p <- ggplot() + theme_tufte(base_size = 11) +
  labs(title = "augsynth polyarchy paths (no usable result)")
if (!is.null(poly_obj)) {
  s_poly <- tryCatch(summary(poly_obj)$att, error = function(e) NULL)
  if (!is.null(s_poly) && nrow(s_poly) > 0) {
    p <- s_poly %>%
      filter(!is.na(.data$Time), .data$Level == "Average") %>%
      ggplot(aes(Time, Estimate)) +
      geom_hline(yintercept = 0, linetype = 2, colour = "grey50") +
      geom_vline(xintercept = 0, linetype = 2, colour = "grey50") +
      geom_ribbon(aes(ymin = Estimate - 1.96 * Std.Error,
                      ymax = Estimate + 1.96 * Std.Error),
                  alpha = 0.2) +
      geom_line(size = 0.7) +
      theme_tufte(base_size = 11) +
      labs(x = "Event time (years from first nonviolent treatment)",
           y = "Average polyarchy ATT",
           title = "augsynth multisynth ATT path, V-Dem polyarchy")
  }
}
ggsave(here("output", "figures", "a_mm_augsynth_paths.pdf"),
       p, device = cairo_pdf, width = 6.5, height = 4.0)

# ---- Macros -------------------------------------------------------------
macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
safe_num <- function(x, fmt = "%.4f") {
  if (length(x) == 0 || all(is.na(x))) return("NA")
  sprintf(fmt, x[1])
}
poly_row <- summary_tbl %>% filter(outcome == "v2x_polyarchy")
writeLines(
  c("% Auto-generated by A_MM_09_augsynth.R",
    paste0("% Generated: ", Sys.time()),
    macro("MMAugsynthNOutcomes", length(outcomes)),
    macro("MMAugsynthPolyarchyATT",
          if (nrow(poly_row)) safe_num(poly_row$att) else "NA"),
    macro("MMAugsynthPolyarchySE",
          if (nrow(poly_row)) safe_num(poly_row$se) else "NA")),
  here("output", "tables", "a_mm_augsynth_macros.tex")
)

sink()
