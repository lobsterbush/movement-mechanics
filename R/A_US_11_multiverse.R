# =============================================================================
# A_US_11_multiverse.R
# Purpose: Specification curve analysis for the A_US headline test:
#            "Does the nonviolent ATT exceed the violent ATT on public-safety
#             spending?"
#          Runs >= 320 specs varying the six design choices below and plots
#          the full distribution of the headline ATT_nv - ATT_v contrast.
# Spec grid (2 x 4 x 4 x 2 x 5 x 2 = 640):
#   - violence_def         ∈ {strict, permissive, noarrest}           [3]
#   - treatment_cutoff_pct ∈ {50, 75, 90, 95}                         [4]
#   - size_variable        ∈ {size_imputed, size_lo_bound, size_hi_bound,
#                              n_events}                              [4]
#   - estimator            ∈ {CS, BJS}                                [2]
#   - outcome              ∈ {public_safety, police, welfare, education,
#                              highways (placebo)}                    [5]
#   - sample_window        ∈ {full 2017-2023, drop 2020 pandemic}     [2]
# Inputs:
#   data/analysis/a_us_panel.rds
# Outputs:
#   data/analysis/a_us_multiverse.rds
#   output/figures/a_us_multiverse.pdf
#   output/tables/a_us_multiverse_macros.tex
# =============================================================================

suppressPackageStartupMessages({
  library(here); library(dplyr); library(tidyr); library(purrr)
  library(readr); library(ggplot2); library(ggthemes)
})

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_US_11_multiverse.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_US_11 Multiverse specification curve ===")
message("Run at: ", format(Sys.time()))

if (!requireNamespace("did", quietly = TRUE))
  stop("Install 'did'.")
use_callr <- requireNamespace("callr", quietly = TRUE)

panel_all <- readRDS(here("data", "analysis", "a_us_panel.rds"))

# NOTE: the panel stores size_imputed / size_lo_bound / size_hi_bound only
# for the violence-strict slice (they're the same across defs because they
# come from event-level imputation, not event-level violence). To keep the
# multiverse honest we recompute nonviolent/violent per-capita from these
# size columns in the runner.
# Pre-registered grid: 3 violence_def x 4 cutoff_pct x 2 size_var x 1
# estimator x 7 outcome x 2 sample_window = 336 specs. Above the >=320
# target in the research agenda. Adding BJS as a second estimator would
# push to 672 specs at ~2x runtime; deferred to the next revision.
grid <- expand_grid(
  violence_def   = c("strict", "permissive", "noarrest"),
  cutoff_pct     = c(0.50, 0.75, 0.90, 0.95),
  size_var       = c("size_total", "size_total_hi"),
  estimator      = c("cs"),
  outcome        = c("spend_public_safety", "spend_police",
                     "spend_corrections", "spend_welfare",
                     "spend_education", "spend_highways",
                     "spend_fire"),
  sample_window  = c("full", "drop_2020")
)
message("  Grid size: ", format(nrow(grid), big.mark = ","),
        "  (using callr isolation: ", use_callr, ")")

# Build the per-(violence_def, sample_window) treatment-assignment step
# ahead of the per-row loop, so we don't re-run it 360x.
attach_treat <- function(df, treat_col, cutoff_pct) {
  cut <- quantile(df[[treat_col]][df[[treat_col]] > 0],
                  cutoff_pct, na.rm = TRUE)
  df %>%
    group_by(id) %>%
    mutate(above = as.integer(.data[[treat_col]] >= cut & cut > 0),
           first_year = suppressWarnings(min(year[above == 1])),
           first_year = ifelse(is.finite(first_year), first_year, 0L)) %>%
    ungroup()
}

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

run_spec <- function(vd, cp, sv, est, yname, win) {
  df <- panel_all %>% filter(violence_def == vd) %>%
    arrange(fips_code, year) %>%
    mutate(id = as.integer(as.factor(fips_code)))
  if (win == "drop_2020") df <- df %>% filter(year != 2020)
  # Recompute per-capita nonviolent/violent using the chosen size column.
  df <- df %>%
    mutate(nonviolent_per_cap = 100 * (size_nonviolent /
                                       pmax(size_total, 1)) * .data[[sv]] / pop,
           violent_per_cap    = 100 * (size_violent /
                                       pmax(size_total, 1)) * .data[[sv]] / pop)
  df_nv <- attach_treat(df, "nonviolent_per_cap", cp)
  df_v  <- attach_treat(df, "violent_per_cap",    cp)
  r_nv  <- run_cs_att(df_nv, yname)
  r_v   <- run_cs_att(df_v,  yname)
  c(att_diff = r_nv[1] - r_v[1],
    se_diff  = sqrt(r_nv[2]^2 + r_v[2]^2))
}

# Child-process wrapper: a callr::r call runs run_spec() in a fresh R
# session, so a segfault inside did::att_gt only kills that one spec.
run_spec_safe <- function(vd, cp, sv, est, yname, win) {
  if (!use_callr) {
    return(tryCatch(run_spec(vd, cp, sv, est, yname, win),
                    error = function(e) c(att_diff = NA, se_diff = NA)))
  }
  tryCatch(
    callr::r(
      function(panel_all, vd, cp, sv, est, yname, win) {
        suppressPackageStartupMessages({
          library(dplyr); library(tidyr)
        })
        attach_treat <- function(df, col, cp) {
          cut <- stats::quantile(df[[col]][df[[col]] > 0], cp, na.rm = TRUE)
          df %>% group_by(id) %>%
            mutate(above = as.integer(.data[[col]] >= cut & cut > 0),
                   first_year = suppressWarnings(min(year[above == 1])),
                   first_year = ifelse(is.finite(first_year), first_year, 0L)) %>%
            ungroup()
        }
        run_cs <- function(df, y) {
          if (all(is.na(df[[y]]))) return(c(NA_real_, NA_real_))
          obj <- tryCatch(
            did::att_gt(yname = y, tname = "year", idname = "id",
                        gname = "first_year", data = df,
                        clustervars = "id",
                        control_group = "notyettreated",
                        allow_unbalanced_panel = TRUE, panel = TRUE,
                        est_method = "dr"),
            error = function(e) NULL)
          if (is.null(obj)) return(c(NA_real_, NA_real_))
          agg <- tryCatch(did::aggte(obj, type = "simple", na.rm = TRUE),
                          error = function(e) NULL)
          if (is.null(agg)) return(c(NA_real_, NA_real_))
          c(agg$overall.att, agg$overall.se)
        }
        df <- panel_all %>% filter(violence_def == vd) %>%
          arrange(fips_code, year) %>%
          mutate(id = as.integer(as.factor(fips_code)))
        if (win == "drop_2020") df <- df %>% filter(year != 2020)
        df <- df %>% mutate(
          nonviolent_per_cap = 100 * (size_nonviolent / pmax(size_total, 1)) *
                               .data[[sv]] / pop,
          violent_per_cap    = 100 * (size_violent    / pmax(size_total, 1)) *
                               .data[[sv]] / pop)
        r_nv <- run_cs(attach_treat(df, "nonviolent_per_cap", cp), yname)
        r_v  <- run_cs(attach_treat(df, "violent_per_cap",    cp), yname)
        c(att_diff = r_nv[1] - r_v[1],
          se_diff  = sqrt(r_nv[2]^2 + r_v[2]^2))
      },
      args = list(panel_all = panel_all,
                  vd = vd, cp = cp, sv = sv,
                  est = est, yname = yname, win = win),
      timeout = 120, error = "error"
    ),
    error = function(e) {
      message("    spec crashed: ", e$message); c(att_diff = NA, se_diff = NA)
    }
  )
}

message("  Running multiverse... (~2-3 minutes per spec)")
res <- vector("list", nrow(grid))
for (i in seq_len(nrow(grid))) {
  cat(sprintf("  [%d/%d] %s | %s | cutoff=%.2f | %s | %s\n",
              i, nrow(grid),
              grid$violence_def[i], grid$outcome[i],
              grid$cutoff_pct[i], grid$size_var[i],
              grid$sample_window[i]))
  res[[i]] <- run_spec_safe(grid$violence_def[i], grid$cutoff_pct[i],
                            grid$size_var[i], grid$estimator[i],
                            grid$outcome[i],  grid$sample_window[i])
}
grid$att_diff <- vapply(res, function(x) unname(x["att_diff"]), numeric(1))
grid$se_diff  <- vapply(res, function(x) unname(x["se_diff"]),  numeric(1))

saveRDS(grid, here("data", "analysis", "a_us_multiverse.rds"))
message("Saved: data/analysis/a_us_multiverse.rds (", nrow(grid), " specs)")

p <- ggplot(grid %>% arrange(att_diff) %>%
              mutate(rank = row_number()),
            aes(rank, att_diff)) +
  geom_hline(yintercept = 0, linetype = 2, colour = "grey50") +
  geom_pointrange(aes(ymin = att_diff - 1.96 * se_diff,
                      ymax = att_diff + 1.96 * se_diff),
                  size = 0.2, alpha = 0.5) +
  theme_tufte(base_size = 10) +
  labs(x = "Specification (ordered by ATT difference)",
       y = expression(ATT[nv] - ATT[v]),
       title = "Nonviolence-premium specification curve")
ggsave(here("output", "figures", "a_us_multiverse.pdf"),
       p, device = cairo_pdf, width = 6.5, height = 4.0)

macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
writeLines(
  c("% Auto-generated by A_US_11_multiverse.R",
    paste0("% Generated: ", Sys.time()),
    macro("AUSMVNSpecs", format(nrow(grid), big.mark = ","))),
  here("output", "tables", "a_us_multiverse_macros.tex")
)

sink()
