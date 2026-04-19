# =============================================================================
# A_US_11b_replot_multiverse.R + A_MM equivalent (inline)
# Purpose: Re-render the multiverse spec curves with readable aesthetics.
#   * Filter specs where se_diff is NA or > p95 (non-identified outliers).
#   * Use a robust y-axis limited to the 1st-99th percentile of att_diff.
#   * Color the point by whether its 95% CI covers zero.
#   * Add a tight dashed zero reference line and a running median.
# Inputs:
#   data/analysis/a_us_multiverse.rds
#   data/analysis/a_mm_multiverse.rds
# Outputs:
#   output/figures/a_us_multiverse.pdf
#   output/figures/a_mm_multiverse.pdf
#   output/figures/slides/a_us_multiverse-1.png (overwritten)
#   output/figures/slides/a_mm_multiverse-1.png (overwritten)
# =============================================================================

suppressPackageStartupMessages({
  library(here); library(dplyr); library(readr)
  library(ggplot2); library(ggthemes)
})

# Accent palette from CLAUDE.md ---------------------------------------------
accent   <- "#3730a3"
neg_col  <- "#be123c"
pos_col  <- "#059669"
null_col <- "#94a3b8"

replot_mv <- function(rds_path, pdf_path, png_path, title, ylab) {
  if (!file.exists(rds_path)) {
    message("  missing: ", rds_path); return(invisible(NULL))
  }
  mv <- readRDS(rds_path)
  # Two multiverse schemas: A_US uses att_diff/se_diff; A_MM uses att/se.
  if ("att_diff" %in% names(mv))      { mv$att <- mv$att_diff; mv$se <- mv$se_diff }
  if (!"att" %in% names(mv) || !"se" %in% names(mv)) {
    message("  schema mismatch: ", rds_path); return(invisible(NULL))
  }
  clean <- mv %>%
    filter(is.finite(att), is.finite(se)) %>%
    filter(se <= quantile(se, 0.95, na.rm = TRUE)) %>%
    mutate(lo = att - 1.96 * se, hi = att + 1.96 * se,
           covers_zero = lo <= 0 & hi >= 0,
           sign_col = case_when(
             !covers_zero & att < 0 ~ neg_col,
             !covers_zero & att > 0 ~ pos_col,
             TRUE                   ~ null_col
           )) %>%
    arrange(att) %>%
    mutate(rank = row_number())

  ylim <- quantile(c(clean$lo, clean$hi), probs = c(0.02, 0.98), na.rm = TRUE)
  n_total <- nrow(mv)
  n_shown <- nrow(clean)
  frac_null <- round(100 * mean(clean$covers_zero, na.rm = TRUE), 1)

  p <- ggplot(clean, aes(rank, att)) +
    geom_hline(yintercept = 0, linetype = 2, colour = "grey40") +
    geom_linerange(aes(ymin = pmax(lo, ylim[1]),
                       ymax = pmin(hi, ylim[2]),
                       colour = sign_col),
                   alpha = 0.45, linewidth = 0.4) +
    geom_point(aes(colour = sign_col), size = 1.1, alpha = 0.9) +
    scale_colour_identity() +
    coord_cartesian(ylim = ylim) +
    theme_tufte(base_size = 11) +
    theme(plot.title = element_text(face = "plain"),
          plot.subtitle = element_text(colour = "grey45", size = 9),
          axis.text = element_text(colour = "grey30")) +
    labs(
      x = sprintf("Specification (of %d; SE-outliers trimmed to %d)",
                  n_total, n_shown),
      y = ylab,
      title = title,
      subtitle = sprintf("%.1f%% of plotted specs have a 95%% CI that covers zero; dashed line = 0",
                         frac_null)
    )
  ggsave(pdf_path, p, device = cairo_pdf, width = 6.5, height = 4.0)
  # PNG for slides
  ggsave(png_path, p, dpi = 220, bg = "white",
         width = 6.5, height = 4.0)
  message("  ", pdf_path, " and ", png_path, " updated (", n_shown,
          " specs plotted of ", n_total, ").")
  invisible(p)
}

# A_US ----------------------------------------------------------------------
replot_mv(
  rds_path = here("data", "analysis", "a_us_multiverse.rds"),
  pdf_path = here("output", "figures", "a_us_multiverse.pdf"),
  png_path = here("output", "figures", "slides", "a_us_multiverse-1.png"),
  title    = "U.S. county-year: nonviolence-premium specification curve",
  ylab     = expression(ATT[nv] - ATT[v] ~ "(US$ / capita)")
)

# A_MM ----------------------------------------------------------------------
replot_mv(
  rds_path = here("data", "analysis", "a_mm_multiverse.rds"),
  pdf_path = here("output", "figures", "a_mm_multiverse.pdf"),
  png_path = here("output", "figures", "slides", "a_mm_multiverse-1.png"),
  title    = "Cross-national: nonviolence-premium specification curve",
  ylab     = expression(ATT[nv] - ATT[v] ~ "(V-Dem polyarchy, 0\u20131)")
)
