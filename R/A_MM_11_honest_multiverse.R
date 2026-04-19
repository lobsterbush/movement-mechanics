# =============================================================================
# A_MM_11_honest_multiverse.R
# Purpose: HonestDiD sensitivity on the A_MM CS estimates and a specification
#          curve for the V-Dem polyarchy headline contrast.
# Spec grid (5 x 4 x 4 x 3 x 2 = 480):
#   - violence_measure ∈ {share_nv, state_resp_weighted, event_severity}   [3]
#   - cutoff_pct        ∈ {50, 75, 90, 95}                                 [4]
#   - estimator         ∈ {CS, synthdid, augsynth, panelmatch}             [4]
#   - outcome           ∈ {polyarchy, libdem, partipdem, polity2, turnover}[5]
#   - sample_window     ∈ {1990-2019 full, drop 2011 Arab Spring surge}    [2]
# Inputs:
#   data/analysis/a_mm_panel.rds
#   data/analysis/a_mm_cs_results.rds
# Outputs:
#   data/analysis/a_mm_multiverse.rds
#   output/figures/a_mm_honestdid.pdf
#   output/figures/a_mm_multiverse.pdf
#   output/tables/a_mm_multiverse_macros.tex
# =============================================================================

suppressPackageStartupMessages({
  library(here); library(dplyr); library(tidyr); library(readr)
  library(ggplot2); library(ggthemes)
})

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_MM_11_hd_mv.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_MM_11 HonestDiD + multiverse ===")
message("Run at: ", format(Sys.time()))

if (!requireNamespace("did", quietly = TRUE)) stop("Install 'did'.")

panel_all <- readRDS(here("data", "analysis", "a_mm_panel.rds"))

# For speed we restrict the grid to the CS estimator (synthdid/augsynth/
# panelmatch are reported separately in A_MM_08/09/10). Violence measures
# map to share_nonviolent / share_nonviolent_sr / share_nonviolent_es built
# in A_MM_02.
grid <- expand_grid(
  violence_measure = c("share_nonviolent", "share_nonviolent_sr",
                       "share_nonviolent_es"),
  cutoff_pct       = c(0.50, 0.75, 0.90, 0.95),
  outcome          = c("v2x_polyarchy", "v2x_libdem", "v2x_partipdem",
                       "polity2", "leader_turnover"),
  sample_window    = c("full", "drop_arab_spring")
)
message("  Grid size: ", format(nrow(grid), big.mark = ","))

run_cs_att <- function(df, yname) {
  if (all(is.na(df[[yname]]))) return(c(NA_real_, NA_real_))
  obj <- tryCatch(
    did::att_gt(yname = yname, tname = "year", idname = "id",
                gname = "first_year", data = df,
                clustervars = "id", control_group = "notyettreated",
                allow_unbalanced_panel = TRUE, panel = TRUE,
                est_method = "dr"),
    error = function(e) NULL)
  if (is.null(obj)) return(c(NA_real_, NA_real_))
  agg <- tryCatch(did::aggte(obj, type = "simple", na.rm = TRUE),
                  error = function(e) NULL)
  if (is.null(agg)) return(c(NA_real_, NA_real_))
  c(agg$overall.att, agg$overall.se)
}

run_spec <- function(vm, cp, yname, win) {
  df <- panel_all %>% arrange(country, year) %>%
    mutate(id = as.integer(as.factor(country)))
  if (win == "drop_arab_spring") df <- df %>% filter(!year %in% 2011:2012)
  intensity_nv <- df[[vm]] * df$avg_participants
  intensity_v  <- (1 - df[[vm]]) * df$avg_participants
  df$int_nv <- intensity_nv
  df$int_v  <- intensity_v
  attach <- function(df, col) {
    cut <- quantile(df[[col]][df[[col]] > 0], cp, na.rm = TRUE)
    df %>% group_by(id) %>%
      mutate(above = as.integer(.data[[col]] >= cut & cut > 0),
             first_year = suppressWarnings(min(year[above == 1])),
             first_year = ifelse(is.finite(first_year), first_year, 0L)) %>%
      ungroup()
  }
  r_nv <- run_cs_att(attach(df, "int_nv"), yname)
  r_v  <- run_cs_att(attach(df, "int_v"),  yname)
  c(att = r_nv[1] - r_v[1],
    se  = sqrt(r_nv[2]^2 + r_v[2]^2))
}

message("  Running MM multiverse...")
res <- vector("list", nrow(grid))
for (i in seq_len(nrow(grid))) {
  res[[i]] <- tryCatch(
    run_spec(grid$violence_measure[i], grid$cutoff_pct[i],
             grid$outcome[i], grid$sample_window[i]),
    error = function(e) c(att = NA, se = NA))
}
grid$att <- vapply(res, `[`, numeric(1), "att")
grid$se  <- vapply(res, `[`, numeric(1), "se")
saveRDS(grid, here("data", "analysis", "a_mm_multiverse.rds"))
message("Saved: data/analysis/a_mm_multiverse.rds")

# HonestDiD on the headline V-Dem polyarchy CS object ---------------------
cs_path <- here("data", "analysis", "a_mm_cs_results.rds")
p_hd <- ggplot() + theme_tufte(base_size = 11) +
  labs(title = "HonestDiD sensitivity skipped (no CS results on disk yet)")
if (file.exists(cs_path) && requireNamespace("HonestDiD", quietly = TRUE)) {
  cs <- readRDS(cs_path)
  obj <- cs$results[["v2x_polyarchy"]]
  if (!is.null(obj)) {
    es <- tryCatch(did::aggte(obj, type = "dynamic", na.rm = TRUE),
                   error = function(e) NULL)
    if (!is.null(es) && length(es$egt) >= 2) {
      pre  <- sum(es$egt <  0); post <- sum(es$egt >= 0)
      sig  <- diag(es$se.egt^2)
      sr <- tryCatch(
        HonestDiD::createSensitivityResults_relativeMagnitudes(
          betahat = es$att.egt, sigma = sig,
          numPrePeriods = pre, numPostPeriods = post,
          Mbarvec = seq(0, 2, by = 0.5)),
        error = function(e) NULL)
      if (!is.null(sr)) {
        p_hd <- ggplot(sr, aes(Mbar)) +
          geom_hline(yintercept = 0, linetype = 2, colour = "grey50") +
          geom_ribbon(aes(ymin = lb, ymax = ub), alpha = 0.25) +
          geom_line(aes(y = (lb + ub) / 2)) +
          theme_tufte(base_size = 11) +
          labs(x = expression(bar(M)),
               y = "Robust 95% CI",
               title = "V-Dem polyarchy: HonestDiD sensitivity")
      }
    }
  }
}
ggsave(here("output", "figures", "a_mm_honestdid.pdf"), p_hd,
       device = cairo_pdf, width = 6.5, height = 4.0)

p_mv <- ggplot(grid %>% arrange(att) %>% mutate(rank = row_number()),
               aes(rank, att)) +
  geom_hline(yintercept = 0, linetype = 2, colour = "grey50") +
  geom_pointrange(aes(ymin = att - 1.96 * se, ymax = att + 1.96 * se),
                  size = 0.2, alpha = 0.5) +
  theme_tufte(base_size = 10) +
  labs(x = "Specification (ordered by contrast)",
       y = "ATT nonviolent \u2212 violent",
       title = "Cross-national nonviolence-premium specification curve")
ggsave(here("output", "figures", "a_mm_multiverse.pdf"), p_mv,
       device = cairo_pdf, width = 6.5, height = 4.0)

macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
writeLines(
  c("% Auto-generated by A_MM_11_honest_multiverse.R",
    paste0("% Generated: ", Sys.time()),
    macro("MMMVNSpecs", format(nrow(grid), big.mark = ","))),
  here("output", "tables", "a_mm_multiverse_macros.tex")
)

sink()
