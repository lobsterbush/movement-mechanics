# =============================================================================
# A_MM_08_synthdid.R
# Purpose: Synthetic DiD (Arkhangelsky et al. 2021) sensitivity check on
#          the A_MM Nonviolence Premium headline. Runs synthdid_estimate
#          per treated country against the never-treated donor pool on
#          V-Dem polyarchy, then aggregates ATTs.
# Method:
#   - Treatment: intensity_nv above the 90th pct of its positive support,
#     matching A_MM_07. Donors = countries that never cross the cutoff.
#   - For each treated country, build a balanced Y[N x T] matrix with the
#     treated unit in the last row and post-treatment years in the last
#     columns; run synthdid::synthdid_estimate; take placebo_se.
#   - Drop treated countries with <3 pre-period observations on the
#     outcome (synthdid is unidentified in that regime).
# Inputs:
#   data/analysis/a_mm_panel.rds
# Outputs:
#   data/analysis/a_mm_synthdid_results.rds
#   output/figures/a_mm_synthdid_paths.pdf
#   output/tables/a_mm_synthdid_summary.csv
#   output/tables/a_mm_synthdid_macros.tex
# =============================================================================

suppressPackageStartupMessages({
  library(here); library(dplyr); library(tidyr); library(readr)
  library(ggplot2); library(ggthemes)
})

if (!requireNamespace("synthdid", quietly = TRUE)) {
  stop("Install 'synthdid' from GitHub (synth-inference/synthdid).")
}

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_MM_08_synthdid.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_MM_08 synthdid ===")
message("Run at: ", format(Sys.time()))

panel <- readRDS(here("data", "analysis", "a_mm_panel.rds")) %>%
  arrange(country, year) %>%
  filter(!is.na(v2x_polyarchy))

# ---- Identify treated vs donor countries ------------------------------
pos <- panel$intensity_nv[is.finite(panel$intensity_nv) &
                          panel$intensity_nv > 0]
cutoff <- if (length(pos) > 0) quantile(pos, 0.90, na.rm = TRUE) else NA_real_
message(sprintf("  Cutoff (90th pct of positive intensity_nv): %.4f",
                ifelse(is.finite(cutoff), cutoff, NA)))

treat_yr <- panel %>%
  group_by(country) %>%
  summarise(first_year = suppressWarnings(
              min(year[is.finite(intensity_nv) &
                       intensity_nv >= cutoff], na.rm = TRUE)),
            .groups = "drop") %>%
  filter(is.finite(first_year))

all_countries  <- sort(unique(panel$country))
treated_names  <- treat_yr$country
donor_names    <- setdiff(all_countries, treated_names)
message("  Treated countries: ", nrow(treat_yr),
        "; donor pool: ", length(donor_names))

# ---- Per-country synthdid ---------------------------------------------
run_one <- function(cn, first_yr) {
  sub <- panel %>%
    filter(country %in% c(cn, donor_names)) %>%
    select(country, year, v2x_polyarchy) %>%
    group_by(country, year) %>%
    summarise(v2x_polyarchy = mean(v2x_polyarchy, na.rm = TRUE),
              .groups = "drop") %>%
    mutate(v2x_polyarchy = ifelse(is.finite(v2x_polyarchy),
                                  v2x_polyarchy, NA_real_)) %>%
    complete(country, year)                   # ensure rectangular

  pre_years  <- sort(unique(sub$year[sub$year <  first_yr]))
  post_years <- sort(unique(sub$year[sub$year >= first_yr]))
  if (length(pre_years) < 3 || length(post_years) < 1) {
    return(list(country = cn, att = NA_real_, se = NA_real_,
                reason = "insufficient pre/post"))
  }

  wide <- sub %>%
    pivot_wider(names_from = year, values_from = v2x_polyarchy)
  # Treated country last row; drop countries with any NA in the years used.
  use_years <- c(pre_years, post_years)
  Y <- as.matrix(wide[, as.character(use_years)])
  rownames(Y) <- wide$country
  ok <- complete.cases(Y)
  Y <- Y[ok, , drop = FALSE]
  if (!(cn %in% rownames(Y))) {
    return(list(country = cn, att = NA_real_, se = NA_real_,
                reason = "treated dropped by completeness"))
  }
  # Move treated country to the last row.
  Y <- rbind(Y[rownames(Y) != cn, , drop = FALSE],
             Y[rownames(Y) == cn, , drop = FALSE])
  N0 <- nrow(Y) - 1L
  T0 <- length(pre_years)
  if (N0 < 10) {
    return(list(country = cn, att = NA_real_, se = NA_real_,
                reason = paste0("only ", N0, " complete donors")))
  }

  est <- tryCatch(synthdid::synthdid_estimate(Y, N0 = N0, T0 = T0),
                  error = function(e) {
                    message("    synthdid_estimate failed: ", e$message); NULL
                  })
  if (is.null(est)) {
    return(list(country = cn, att = NA_real_, se = NA_real_,
                reason = "estimate error"))
  }
  # Placebo SE: resample treated unit from donors.
  se <- tryCatch(sqrt(synthdid::vcov.synthdid_estimate(est,
                                                      method = "placebo")),
                 error = function(e) NA_real_)
  list(country = cn, first_year = first_yr,
       att = as.numeric(est), se = as.numeric(se),
       N0 = N0, T0 = T0, reason = "ok")
}

results <- vector("list", nrow(treat_yr))
for (i in seq_len(nrow(treat_yr))) {
  message(sprintf("  [%d/%d] %s (first_year=%d)",
                  i, nrow(treat_yr),
                  treat_yr$country[i], treat_yr$first_year[i]))
  results[[i]] <- run_one(treat_yr$country[i], treat_yr$first_year[i])
}

summary_tbl <- tibble(
  country    = vapply(results, \(r) r$country, character(1)),
  first_year = vapply(results, \(r) if (is.null(r$first_year)) NA_integer_
                                    else as.integer(r$first_year), integer(1)),
  att        = vapply(results, \(r) as.numeric(r$att), numeric(1)),
  se         = vapply(results, \(r) as.numeric(r$se),  numeric(1)),
  reason     = vapply(results, \(r) r$reason, character(1))
)
message("\n-- synthdid per-country summary --")
print(as.data.frame(summary_tbl), row.names = FALSE)

# ---- Aggregate -----------------------------------------------------------
ok <- summary_tbl %>% filter(is.finite(att))
agg_att <- if (nrow(ok) > 0) mean(ok$att) else NA_real_
# Cross-country SE of the mean via IID approximation; placebo SEs are
# per-unit, not jointly drawn, so we use the sample SD of ok$att / sqrt(n).
agg_se  <- if (nrow(ok) > 1) sd(ok$att) / sqrt(nrow(ok)) else NA_real_

message(sprintf("\n  Aggregate ATT (mean across %d treated countries): %.4f (SE %.4f)",
                nrow(ok), agg_att, agg_se))

dir.create(here("output", "tables"), showWarnings = FALSE, recursive = TRUE)
saveRDS(list(results = results, summary = summary_tbl,
             agg_att = agg_att, agg_se = agg_se,
             cutoff = cutoff),
        here("data", "analysis", "a_mm_synthdid_results.rds"))
write_csv(summary_tbl, here("output", "tables", "a_mm_synthdid_summary.csv"))

# ---- Per-country ATT figure ---------------------------------------------
if (nrow(ok) > 0) {
  p <- ok %>%
    arrange(att) %>%
    mutate(country = factor(country, levels = country)) %>%
    ggplot(aes(country, att)) +
    geom_hline(yintercept = 0, linetype = 2, colour = "grey50") +
    geom_pointrange(aes(ymin = att - 1.96 * se,
                        ymax = att + 1.96 * se),
                    size = 0.3) +
    coord_flip() +
    theme_tufte(base_size = 9) +
    labs(x = NULL, y = "Synthdid ATT on V-Dem polyarchy",
         title = "Per-country synthdid ATTs, nonviolent arm")
  # Cap total height at 8.5 inches so a single-page figure fits in the
  # letter-size paper with 1 in margins; scale font down if dense.
  fig_height <- min(8.5, max(3.5, 0.18 * nrow(ok)))
  ggsave(here("output", "figures", "a_mm_synthdid_paths.pdf"),
         p, device = cairo_pdf, width = 6.5, height = fig_height)
} else {
  p <- ggplot() + theme_tufte(base_size = 11) +
    labs(title = "No treated countries survived the synthdid completeness check")
  ggsave(here("output", "figures", "a_mm_synthdid_paths.pdf"),
         p, device = cairo_pdf, width = 6.5, height = 3.5)
}

# ---- Macros -------------------------------------------------------------
macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
writeLines(
  c("% Auto-generated by A_MM_08_synthdid.R",
    paste0("% Generated: ", Sys.time()),
    macro("MMSynthdidNTreated", nrow(treat_yr)),
    macro("MMSynthdidNEstimated", nrow(ok)),
    macro("MMSynthdidATT",
          if (is.finite(agg_att)) sprintf("%.4f", agg_att) else "NA"),
    macro("MMSynthdidSE",
          if (is.finite(agg_se))  sprintf("%.4f", agg_se)  else "NA")),
  here("output", "tables", "a_mm_synthdid_macros.tex")
)

sink()
