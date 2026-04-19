# =============================================================================
# A_MM_07_cs_did.R
# Purpose: Callaway-Sant'Anna (2021) ATT(g,t) estimation for the A_MM
#          Nonviolence Premium design (country-year).
# Method:
#   - Binary treatment: first year in which intensity_nv (share_nonviolent
#     * avg_participants) is above the 90th percentile of the pooled
#     nonzero distribution.
#   - Comparison group = not-yet-treated countries.
#   - Outcome stack: V-Dem polyarchy, libdem, partipdem; Polity2 delta;
#     leader_turnover; WDI social spending.
#   - Clustered SEs by country.
# Inputs:
#   data/analysis/a_mm_panel.rds
# Outputs:
#   data/analysis/a_mm_cs_results.rds
#   output/figures/a_mm_cs_event_study.pdf
#   output/tables/a_mm_cs_summary.csv
#   output/tables/a_mm_cs_macros.tex
# =============================================================================

suppressPackageStartupMessages({
  library(here); library(dplyr); library(tidyr); library(readr)
  library(ggplot2); library(ggthemes)
})

if (!requireNamespace("did", quietly = TRUE)) stop("Install 'did'.")

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_MM_07_cs.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_MM_07 Callaway-Sant'Anna country-year ===")
message("Run at: ", format(Sys.time()))

panel <- readRDS(here("data", "analysis", "a_mm_panel.rds")) %>%
  arrange(country, year) %>%
  mutate(id = as.integer(as.factor(country)))

# ---- Treatment assignment: nv / v arms separately -----------------------
assign_first_treat <- function(df, treat_col, cutoff_pct = 0.90) {
  pos <- df[[treat_col]]
  pos <- pos[is.finite(pos) & pos > 0]
  cutoff <- if (length(pos) > 0)
    quantile(pos, cutoff_pct, na.rm = TRUE) else NA_real_
  df %>%
    group_by(id) %>%
    mutate(
      above = as.integer(is.finite(.data[[treat_col]]) &
                         .data[[treat_col]] >= cutoff &
                         is.finite(cutoff)),
      first_year = suppressWarnings(min(year[above == 1], na.rm = TRUE)),
      first_year = ifelse(is.finite(first_year), first_year, 0L)
    ) %>%
    ungroup()
}

panel_nv <- assign_first_treat(panel, "intensity_nv")
panel_v  <- assign_first_treat(panel, "intensity_v")

# ---- Arm diagnostics ----------------------------------------------------
describe_arm <- function(df, arm) {
  treated <- df %>% filter(first_year > 0) %>% distinct(id, first_year)
  yr_tab <- if (nrow(treated)) table(treated$first_year) else
    table(integer(0))
  message(sprintf("  [%s arm] treated countries: %d  (of %d panel ids)",
                  arm, nrow(treated), dplyr::n_distinct(df$id)))
  if (nrow(treated)) {
    message("    first-year distribution: ",
            paste(sprintf("%s=%d", names(yr_tab), as.integer(yr_tab)),
                  collapse = ", "))
  }
  invisible(list(n_treated = nrow(treated),
                 first_year_tab = yr_tab))
}

message("\n-- Arm diagnostics --")
diag_nv <- describe_arm(panel_nv, "nonviolent")
diag_v  <- describe_arm(panel_v,  "violent")
overlap_ids <- intersect(
  panel_nv %>% filter(first_year > 0) %>% pull(id) %>% unique(),
  panel_v  %>% filter(first_year > 0) %>% pull(id) %>% unique()
)
message(sprintf("  treated-set overlap (both arms): %d countries",
                length(overlap_ids)))

# ---- CS-DiD estimation per outcome x arm --------------------------------
outcomes <- c("v2x_polyarchy", "v2x_libdem", "v2x_partipdem",
              "polity2", "wdi_health_pct_gdp", "wdi_edu_pct_gdp")
# Drop leader_turnover from headline stack -- Archigos not yet wired up,
# so it is NA for every country-year (see plan Out of Scope).

run_cs <- function(df, y, arm) {
  if (all(is.na(df[[y]]))) return(NULL)
  if (sum(df$first_year > 0, na.rm = TRUE) < 2) {
    message("  CS skipped (", arm, "/", y, "): <2 treated country-years.")
    return(NULL)
  }
  tryCatch(
    did::att_gt(yname = y, tname = "year", idname = "id",
                gname = "first_year", data = df,
                clustervars = "id",
                control_group = "notyettreated",
                allow_unbalanced_panel = TRUE,
                panel = TRUE, est_method = "reg"),
    error = function(e) {
      message("  CS failed (", arm, "/", y, "): ", e$message); NULL
    }
  )
}

results <- list()
for (y in outcomes) {
  message("  Running CS-DiD for: ", y)
  results[[paste0(y, "__nv")]] <- run_cs(panel_nv, y, "nv")
  results[[paste0(y, "__v")]]  <- run_cs(panel_v,  y, "v")
}

summarise_cs <- function(obj) {
  if (is.null(obj)) return(tibble(att = NA_real_, se = NA_real_))
  agg <- tryCatch(did::aggte(obj, type = "simple", na.rm = TRUE),
                  error = function(e) NULL)
  if (is.null(agg)) return(tibble(att = NA_real_, se = NA_real_))
  tibble(att = agg$overall.att, se = agg$overall.se)
}

summary_tbl <- tibble(key = names(results)) %>%
  mutate(outcome = sub("__.*", "", key),
         arm     = sub(".*__",  "", key),
         stats   = lapply(results, summarise_cs)) %>%
  unnest(stats) %>% select(-key)

message("\n-- CS-DiD summary --")
print(as.data.frame(summary_tbl), row.names = FALSE)

# ---- Arm contrast -------------------------------------------------------
contrast_tbl <- summary_tbl %>%
  select(outcome, arm, att, se) %>%
  pivot_wider(names_from = arm, values_from = c(att, se)) %>%
  mutate(
    att_diff = att_nv - att_v,
    se_diff  = sqrt(se_nv^2 + se_v^2),
    z_diff   = att_diff / se_diff,
    p_diff   = 2 * pnorm(-abs(z_diff)),
    sign     = ifelse(is.na(att_diff), "na",
               ifelse(att_diff > 0, "premium",
               ifelse(att_diff < 0, "backlash", "null")))
  )

message("\n-- Contrast summary (ATT_nv - ATT_v) --")
print(as.data.frame(contrast_tbl %>%
                      select(outcome, att_nv, att_v, att_diff,
                             se_diff, p_diff, sign)),
      row.names = FALSE, digits = 4)

saveRDS(list(results = results, summary = summary_tbl,
             contrast = contrast_tbl,
             panel_nv = panel_nv, panel_v = panel_v),
        here("data", "analysis", "a_mm_cs_results.rds"))
write_csv(summary_tbl, here("output", "tables", "a_mm_cs_summary.csv"))
write_csv(contrast_tbl, here("output", "tables", "a_mm_cs_contrast.csv"))

# ---- Macros -------------------------------------------------------------
macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
safe_num <- function(x, fmt = "%.3f") {
  if (length(x) == 0 || all(is.na(x))) return("NA")
  sprintf(fmt, x[1])
}
nv_poly <- summary_tbl  %>% filter(outcome == "v2x_polyarchy", arm == "nv")
v_poly  <- summary_tbl  %>% filter(outcome == "v2x_polyarchy", arm == "v")
c_poly  <- contrast_tbl %>% filter(outcome == "v2x_polyarchy")
writeLines(
  c("% Auto-generated by A_MM_07_cs_did.R",
    paste0("% Generated: ", Sys.time()),
    macro("MMCSNVPolyarchyATTraw",
          if (nrow(nv_poly)) safe_num(nv_poly$att) else "NA"),
    macro("MMCSVPolyarchyATTraw",
          if (nrow(v_poly)) safe_num(v_poly$att) else "NA"),
    macro("MMCSContrastPolyarchy",
          if (nrow(c_poly)) safe_num(c_poly$att_diff) else "NA"),
    macro("MMCSContrastSE",
          if (nrow(c_poly)) safe_num(c_poly$se_diff) else "NA"),
    macro("MMCSContrastP",
          if (nrow(c_poly)) safe_num(c_poly$p_diff, "%.4f") else "NA"),
    macro("MMCSContrastSign",
          if (nrow(c_poly)) as.character(c_poly$sign) else "NA"),
    macro("MMCSTreatedNV", diag_nv$n_treated),
    macro("MMCSTreatedV",  diag_v$n_treated),
    macro("MMCSTreatedOverlap", length(overlap_ids)),
    # Backward-compat: keep the old macro name alive.
    macro("MMCSPolyarchyATT",
          if (nrow(nv_poly)) safe_num(nv_poly$att) else "NA")),
  here("output", "tables", "a_mm_cs_macros.tex")
)
message("Wrote macros: output/tables/a_mm_cs_macros.tex")

sink()
