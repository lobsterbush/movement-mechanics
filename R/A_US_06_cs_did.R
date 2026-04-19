# =============================================================================
# A_US_06_cs_did.R
# Purpose: Headline Callaway-Sant'Anna (2021) ATT(g,t) estimation for the
#          Nonviolence Premium design (A_US).
#          Runs att_gt separately for each outcome in the 9-category
#          spending stack + police-behavior outcomes, for both the
#          nonviolent and violent treatment arms. Reports the difference of
#          ATT(g,t) across arms as the headline test.
#          Uses the "strict" violence definition as headline; permissive
#          and noarrest variants are available via violence_def filtering.
# Method notes:
#   - Treatment timing: first period with nonviolent_per_cap above the
#     90th percentile of the (pooled, county-year) nonzero distribution.
#     Same threshold on violent_per_cap for the violent arm.
#   - Staggered adoption is handled via the control_group = "notyettreated"
#     option in did::att_gt.
#   - SEs clustered by county via clustervars = "fips_code".
#   - Never-treated counties used as clean controls where available.
# Inputs:
#   data/analysis/a_us_panel.rds  (from A_US_04)
# Outputs:
#   data/analysis/a_us_cs_results.rds
#   output/figures/a_us_cs_event_study.pdf
#   output/tables/a_us_cs_main.tex
#   output/tables/a_us_cs_macros.tex
#   quality_reports/session_logs/<date>_A_US_06_cs.log
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(ggthemes)
})

if (!requireNamespace("did", quietly = TRUE)) {
  stop("Install 'did' first: install.packages('did').")
}

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_US_06_cs.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_US_06 Callaway-Sant'Anna ATT(g,t) ===")
message("Run at: ", format(Sys.time()))

panel <- readRDS(here("data", "analysis", "a_us_panel.rds")) %>%
  filter(violence_def == "strict") %>%
  arrange(fips_code, year) %>%
  mutate(id = as.integer(as.factor(fips_code)))

# ---- Treatment timing: first year above 90th pct of nonzero per-cap ------
assign_first_treat <- function(df, treat_col) {
  cutoff <- quantile(df[[treat_col]][df[[treat_col]] > 0], 0.90, na.rm = TRUE)
  df %>%
    group_by(id) %>%
    mutate(
      above = as.integer(.data[[treat_col]] >= cutoff & cutoff > 0),
      first_year = suppressWarnings(min(year[above == 1], na.rm = TRUE)),
      first_year = ifelse(is.finite(first_year), first_year, 0L)
    ) %>%
    ungroup()
}

panel_nv <- assign_first_treat(panel, "nonviolent_per_cap")
panel_v  <- assign_first_treat(panel, "violent_per_cap")

outcomes <- c("spend_public_safety", "spend_police", "spend_fire",
              "spend_corrections", "spend_highways", "spend_health",
              "spend_welfare", "spend_parks_rec", "spend_education",
              "mpv_killings", "opp_stops_per_cap")

run_cs <- function(df, yname, arm) {
  if (all(is.na(df[[yname]]))) return(NULL)
  tryCatch(
    did::att_gt(
      yname         = yname,
      tname         = "year",
      idname        = "id",
      gname         = "first_year",
      data          = df,
      clustervars   = "id",
      control_group = "notyettreated",
      allow_unbalanced_panel = TRUE,
      panel         = TRUE,
      est_method    = "dr"
    ),
    error = function(e) {
      message("  CS failed for ", arm, "/", yname, ": ", e$message); NULL
    }
  )
}

# ---- Per-arm diagnostics (treated N, first-year distribution, share of
#      event volume that is violent in treated units) ---------------------
describe_arm <- function(df, arm) {
  treated <- df %>% filter(first_year > 0) %>% distinct(id, first_year)
  yr_tab <- if (nrow(treated)) table(treated$first_year) else table(integer(0))
  if ("size_violent" %in% names(df) && "size_total" %in% names(df)) {
    vshare <- df %>%
      filter(id %in% treated$id, year >= first_year, year > 0) %>%
      summarise(share = sum(size_violent, na.rm = TRUE) /
                        pmax(sum(size_total, na.rm = TRUE), 1)) %>%
      pull(share)
  } else {
    vshare <- NA_real_
  }
  message(sprintf("  [%s arm] treated counties: %d  (of %d panel ids)",
                  arm, nrow(treated), dplyr::n_distinct(df$id)))
  message("    first-year distribution: ",
          paste(sprintf("%s=%d", names(yr_tab), as.integer(yr_tab)),
                collapse = ", "))
  message(sprintf("    mean size_violent / size_total in treated post: %.4f",
                  vshare))
  invisible(list(n_treated = nrow(treated),
                 first_year_tab = yr_tab,
                 violent_share_treated = vshare))
}

message("\n-- Arm diagnostics (strict violence_def) --")
diag_nv <- describe_arm(panel_nv, "nonviolent")
diag_v  <- describe_arm(panel_v,  "violent")
overlap_ids <- intersect(
  panel_nv %>% filter(first_year > 0) %>% pull(id) %>% unique(),
  panel_v  %>% filter(first_year > 0) %>% pull(id) %>% unique()
)
message(sprintf("  treated-set overlap (both arms): %d counties",
                length(overlap_ids)))

results <- list()
for (y in outcomes) {
  message("  Running CS-DiD for: ", y)
  results[[paste0(y, "__nv")]] <- run_cs(panel_nv, y, "nv")
  results[[paste0(y, "__v")]]  <- run_cs(panel_v,  y, "v")
}

# ---- Aggregate to overall ATT per arm, per outcome ----------------------
summarise_cs <- function(obj) {
  if (is.null(obj)) return(tibble(att = NA_real_, se = NA_real_, n = NA_integer_))
  agg <- tryCatch(did::aggte(obj, type = "simple", na.rm = TRUE),
                  error = function(e) NULL)
  if (is.null(agg)) return(tibble(att = NA_real_, se = NA_real_, n = NA_integer_))
  tibble(att = agg$overall.att, se = agg$overall.se,
         n = length(obj$group))
}

summary_tbl <- tibble(key = names(results)) %>%
  mutate(
    outcome = sub("__.*", "", key),
    arm     = sub(".*__",  "", key),
    stats   = lapply(results, summarise_cs)
  ) %>%
  unnest(stats) %>%
  select(-key)

message("\n-- CS-DiD summary (overall ATT by outcome x arm) --")
print(as.data.frame(summary_tbl), row.names = FALSE)

# ---- Headline estimand: ATT_nv - ATT_v per outcome ----------------------
# Arms are estimated on near-disjoint treated sets (reported above), so the
# contrast variance is approximated by independent-arm addition. The overlap
# count is logged for transparency; a user who wants the conservative
# dependent-arm variance can inflate se_diff by sqrt(2).
contrast_tbl <- summary_tbl %>%
  select(outcome, arm, att, se) %>%
  pivot_wider(names_from = arm, values_from = c(att, se)) %>%
  mutate(
    att_diff = att_nv - att_v,
    se_diff  = sqrt(se_nv^2 + se_v^2),
    z_diff   = att_diff / se_diff,
    p_diff   = 2 * pnorm(-abs(z_diff)),
    sign     = ifelse(att_diff > 0, "premium",
               ifelse(att_diff < 0, "backlash", "null"))
  )

message("\n-- Contrast summary (ATT_nv - ATT_v) --")
print(as.data.frame(contrast_tbl %>%
                      select(outcome, att_nv, att_v, att_diff,
                             se_diff, p_diff, sign)),
      row.names = FALSE, digits = 4)
write_csv(contrast_tbl, here("output", "tables", "a_us_cs_contrast.csv"))

# ---- Save ---------------------------------------------------------------
dir.create(here("data", "analysis"), showWarnings = FALSE, recursive = TRUE)
saveRDS(list(results = results, summary = summary_tbl),
        here("data", "analysis", "a_us_cs_results.rds"))

write_csv(summary_tbl, here("output", "tables", "a_us_cs_summary.csv"))

# ---- Event-study figure (spending_public_safety exemplar) ---------------
obj_nv <- results[["spend_public_safety__nv"]]
if (!is.null(obj_nv)) {
  es <- tryCatch(did::aggte(obj_nv, type = "dynamic", na.rm = TRUE),
                 error = function(e) NULL)
  if (!is.null(es)) {
    es_df <- tibble(e = es$egt, att = es$att.egt, se = es$se.egt)
    p <- ggplot(es_df, aes(e, att)) +
      geom_hline(yintercept = 0, linetype = 2, colour = "grey50") +
      geom_pointrange(aes(ymin = att - 1.96 * se, ymax = att + 1.96 * se),
                      size = 0.3) +
      theme_tufte(base_size = 11) +
      labs(x = "Event time (years)", y = "ATT(g,t) dynamic",
           title = "Nonviolent arm: event-study, public-safety spending")
    ggsave(here("output", "figures", "a_us_cs_event_study.pdf"),
           p, device = cairo_pdf, width = 6.5, height = 4)
  }
}

# ---- Macros -------------------------------------------------------------
macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
nv_ps <- summary_tbl  %>% filter(outcome == "spend_public_safety", arm == "nv")
v_ps  <- summary_tbl  %>% filter(outcome == "spend_public_safety", arm == "v")
c_ps  <- contrast_tbl %>% filter(outcome == "spend_public_safety")

safe_num <- function(x, fmt = "%.3f") {
  if (length(x) == 0 || all(is.na(x))) return("NA")
  sprintf(fmt, x[1])
}

writeLines(
  c("% Auto-generated by A_US_06_cs_did.R",
    paste0("% Generated: ", Sys.time()),
    # Raw single-arm ATTs (kept for transparency; paper body uses contrast).
    macro("AUSCSNVpubSafetyATTraw",
          if (nrow(nv_ps)) safe_num(nv_ps$att) else "NA"),
    macro("AUSCSVpubSafetyATTraw",
          if (nrow(v_ps)) safe_num(v_ps$att) else "NA"),
    # Headline contrast macros.
    macro("AUSCSContrastPubSafety",
          if (nrow(c_ps)) safe_num(c_ps$att_diff) else "NA"),
    macro("AUSCSContrastSE",
          if (nrow(c_ps)) safe_num(c_ps$se_diff) else "NA"),
    macro("AUSCSContrastP",
          if (nrow(c_ps)) safe_num(c_ps$p_diff, "%.4f") else "NA"),
    macro("AUSCSContrastSign",
          if (nrow(c_ps)) as.character(c_ps$sign) else "NA"),
    # Arm diagnostics.
    macro("AUSCSTreatedNV", diag_nv$n_treated),
    macro("AUSCSTreatedV",  diag_v$n_treated),
    macro("AUSCSTreatedOverlap", length(overlap_ids)),
    macro("AUSCSViolentShareTreatedNV",
          if (is.finite(diag_nv$violent_share_treated))
            sprintf("%.4f", diag_nv$violent_share_treated) else "NA"),
    macro("AUSCSViolentShareTreatedV",
          if (is.finite(diag_v$violent_share_treated))
            sprintf("%.4f", diag_v$violent_share_treated) else "NA")),
  here("output", "tables", "a_us_cs_macros.tex")
)
message("Wrote macros: output/tables/a_us_cs_macros.tex")

sink()
