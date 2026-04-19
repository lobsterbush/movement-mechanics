# =============================================================================
# A_MM_10_panelmatch.R
# Purpose: PanelMatch (Imai, Kim, Wang 2023) matched-difference sensitivity
#          for the A_MM Nonviolence Premium. Matches each treated
#          country-year to never-treated country-years with the same
#          pre-treatment outcome trajectory and reports the average
#          post-treatment ATT over horizons 0:4.
# Inputs:
#   data/analysis/a_mm_panel.rds
# Outputs:
#   data/analysis/a_mm_panelmatch_results.rds
#   output/tables/a_mm_panelmatch_summary.csv
#   output/tables/a_mm_panelmatch_macros.tex
# =============================================================================

suppressPackageStartupMessages({
  library(here); library(dplyr); library(readr); library(tidyr)
})

if (!requireNamespace("PanelMatch", quietly = TRUE)) {
  stop("Install 'PanelMatch'.")
}

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_MM_10_pm.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_MM_10 PanelMatch ===")
message("Run at: ", format(Sys.time()))

panel <- readRDS(here("data", "analysis", "a_mm_panel.rds")) %>%
  # Collapse duplicate (country, year) rows introduced upstream.
  group_by(country, year) %>%
  summarise(across(where(is.numeric),
                   ~ suppressWarnings(mean(.x, na.rm = TRUE))),
            .groups = "drop") %>%
  mutate(across(where(is.numeric), ~ ifelse(is.finite(.x), .x, NA_real_)))

# PanelMatch requires integer unit id + integer time.
# indicator the same way as A_MM_07 / A_MM_08 / A_MM_09: first year in
# which intensity_nv crosses the 90th pct of its positive support.
pos <- panel$intensity_nv[is.finite(panel$intensity_nv) &
                          panel$intensity_nv > 0]
cutoff <- if (length(pos) > 0) quantile(pos, 0.90, na.rm = TRUE) else NA_real_

panel <- panel %>%
  arrange(country, year) %>%
  mutate(id = as.integer(as.factor(country)),
         year = as.integer(year)) %>%
  group_by(country) %>%
  mutate(
    treat = as.integer(is.finite(intensity_nv) &
                       intensity_nv >= cutoff &
                       is.finite(cutoff))
  ) %>% ungroup()

outcomes <- c("v2x_polyarchy", "v2x_libdem")

# PanelMatch's data.frame needs no NAs in the treatment column; treat NA
# as 0 (not treated).
panel$treat[is.na(panel$treat)] <- 0L
panel_df <- as.data.frame(panel)

run_pm <- function(yname) {
  df <- panel_df
  keep <- !is.na(df[[yname]])
  df <- df[keep, , drop = FALSE]
  if (length(unique(df$id[df$treat == 1])) < 2) {
    message(sprintf("  %s: too few treated; skipping", yname)); return(NULL)
  }
  pm <- tryCatch(
    PanelMatch::PanelMatch(
      panel.data   = PanelMatch::PanelData(df, unit.id = "id",
                                           time.id = "year",
                                           treatment = "treat",
                                           outcome = yname),
      lag          = 4,
      refinement.method = "mahalanobis",
      covs.formula = as.formula(paste("~ I(lag(", yname, ", 1:4))")),
      qoi          = "att",
      lead         = 0:4,
      match.missing = TRUE,
      size.match   = 5,
      forbid.treatment.reversal = FALSE
    ),
    error = function(e) {
      message(sprintf("  PanelMatch %s failed: %s", yname, e$message)); NULL
    }
  )
  if (is.null(pm)) return(NULL)
  pe <- tryCatch(PanelMatch::PanelEstimate(
                   sets = pm,
                   panel.data = PanelMatch::PanelData(df, unit.id = "id",
                                                      time.id = "year",
                                                      treatment = "treat",
                                                      outcome = yname),
                   number.iterations = 500),
                 error = function(e) {
                   message(sprintf("  PanelEstimate %s failed: %s",
                                   yname, e$message)); NULL
                 })
  pe
}

results <- setNames(lapply(outcomes, run_pm), outcomes)

extract_pe <- function(pe) {
  if (is.null(pe)) return(tibble(lead = NA_integer_,
                                 att = NA_real_, se = NA_real_))
  s <- summary(pe)
  if (!is.matrix(s)) return(tibble(lead = NA_integer_,
                                   att = NA_real_, se = NA_real_))
  lead_int <- suppressWarnings(
    as.integer(sub("^t\\+", "", rownames(s))))
  tibble(lead = lead_int,
         att  = as.numeric(s[, "estimate"]),
         se   = as.numeric(s[, "std.error"]))
}

summary_tbl <- bind_rows(
  lapply(names(results), function(nm) {
    extract_pe(results[[nm]]) %>% mutate(outcome = nm)
  })
) %>% select(outcome, lead, att, se)

message("\n-- PanelMatch per-lead summary --")
print(as.data.frame(summary_tbl), row.names = FALSE)

saveRDS(list(results = results, summary = summary_tbl,
             cutoff = cutoff),
        here("data", "analysis", "a_mm_panelmatch_results.rds"))
write_csv(summary_tbl, here("output", "tables", "a_mm_panelmatch_summary.csv"))

# ---- Macros (report lead-4 for polyarchy) -------------------------------
macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
safe_num <- function(x, fmt = "%.4f") {
  if (length(x) == 0 || all(is.na(x))) return("NA")
  sprintf(fmt, x[1])
}
lead4 <- summary_tbl %>%
  filter(outcome == "v2x_polyarchy", lead == 4)
writeLines(
  c("% Auto-generated by A_MM_10_panelmatch.R",
    paste0("% Generated: ", Sys.time()),
    macro("MMPMNOutcomes", length(outcomes)),
    macro("MMPMPolyarchyATTLeadFour",
          if (nrow(lead4)) safe_num(lead4$att) else "NA"),
    macro("MMPMPolyarchySELeadFour",
          if (nrow(lead4)) safe_num(lead4$se) else "NA")),
  here("output", "tables", "a_mm_panelmatch_macros.tex")
)

sink()
