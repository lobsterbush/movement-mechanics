# =============================================================================
# A_US_02_impute_ccc_size.R
# Purpose: Impute CCC event-level crowd size under a five-tier strategy that
#          (a) prefers observed values, (b) falls back on the size_low/size_high
#          range where present, (c) uses a log-OLS model where nothing is
#          coded, and (d) exposes Lee-style hi/lo bounds for HonestDiD-type
#          sensitivity analysis in the downstream nonviolence-premium design.
#
# Five tiers (per event):
#   T1 observed   - size_mean non-missing
#   T2 midpoint   - size_mean missing; both size_low AND size_high present
#   T3 range_low  - size_mean missing; only size_low present; use as conservative
#   T4 range_high - size_mean missing; only size_high present; halve as heuristic
#   T5 model      - nothing present; log-OLS prediction from covariates
#
# Bounds (for HonestDiD sensitivity):
#   size_lo_bound = observed OR 10  (CCC convention; coders rarely log <10)
#   size_hi_bound = observed OR min(predicted * 3, P99 of observed)
#
# Inputs:
#   data/raw/ccc/ccc_compiled.csv                 (Phase 1)
#   data/raw/ccc/ccc_compiled_2021_present.csv    (Phase 2)
# Outputs:
#   data/intermediate/ccc_events_imputed.rds       (events with imputed columns)
#   output/tables/ccc_imputation_tiers.csv
#   output/tables/ccc_imputation_by_year.csv
#   output/tables/ccc_imputation_macros.tex
#   quality_reports/session_logs/<date>_A_US_02_impute.log
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(readr)
  library(dplyr)
  library(stringr)
  library(lubridate)
  library(tidyr)
})

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_US_02_impute.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_US_02 CCC size imputation ===")
message("Run at: ", format(Sys.time()))

# ---- Load both phases -----------------------------------------------------
phase1_path <- here("data", "raw", "ccc", "ccc_compiled.csv")
phase2_path <- here("data", "raw", "ccc", "ccc_compiled_2021_present.csv")

read_phase <- function(path, label) {
  if (!file.exists(path)) stop("Missing: ", path)
  message("  Reading ", label, " ...")
  x <- read_csv(
    path,
    col_types = cols(
      fips_code           = col_character(),
      date                = col_date(format = ""),
      state               = col_character(),
      size_low            = col_double(),
      size_high           = col_double(),
      size_mean           = col_double(),
      property_damage_any = col_double(),
      arrests_any         = col_double(),
      injuries_crowd_any  = col_double(),
      injuries_police_any = col_double(),
      chemical_agents     = col_double(),
      .default            = col_character()
    ),
    locale   = locale(encoding = "latin1"),
    progress = FALSE
  )
  x$phase <- label
  message("    rows=", format(nrow(x), big.mark = ","))
  x
}

p1 <- read_phase(phase1_path, "phase1")
p2 <- read_phase(phase2_path, "phase2")

# Harmonize Phase 2's issue_tags/organizations to Phase 1 naming
nm2 <- names(p2)
nm2[nm2 == "issue_tags"]    <- "issues"
nm2[nm2 == "organizations"] <- "actors"
names(p2) <- nm2

common <- intersect(names(p1), names(p2))
ccc    <- bind_rows(p1[, common], p2[, common])
message("  Combined rows: ", format(nrow(ccc), big.mark = ","))

# ---- Panel-eligible filter (matches A_US_01 core definition) --------------
ccc <- ccc %>%
  mutate(
    fips_code = str_pad(str_trim(fips_code), 5, "left", "0"),
    has_fips  = !is.na(fips_code) & nchar(fips_code) == 5 &
                  !fips_code %in% c("   NA", "NA"),
    year      = year(date),
    online1   = suppressWarnings(as.integer(online == "1")),
    online1   = replace_na(online1, 0L)
  ) %>%
  filter(has_fips, year >= 2017, year <= 2023, online1 != 1)

message("  Panel-eligible events: ", format(nrow(ccc), big.mark = ","))

# ---- Violence flags and BLM tag (model covariates) ------------------------
ccc <- ccc %>%
  mutate(
    pd     = replace_na(property_damage_any, 0),
    ar     = replace_na(arrests_any,         0),
    ic     = replace_na(injuries_crowd_any,  0),
    ip     = replace_na(injuries_police_any, 0),
    ca     = replace_na(chemical_agents,     0),
    v_any  = as.integer(pd + ar + ic + ip + ca > 0),
    is_blm = as.integer(!is.na(issues) &
                          str_detect(issues,
                                     regex("racism|policing|civil.?rights",
                                           ignore_case = TRUE)))
  )

# ---- Tier assignment ------------------------------------------------------
ccc <- ccc %>%
  mutate(
    has_mean = !is.na(size_mean),
    has_lo   = !is.na(size_low),
    has_hi   = !is.na(size_high),
    size_tier = case_when(
      has_mean                ~ "T1_observed",
      has_lo & has_hi         ~ "T2_midpoint",
      has_lo & !has_hi        ~ "T3_range_low",
      !has_lo & has_hi        ~ "T4_range_high",
      TRUE                    ~ "T5_model"
    )
  )

tier_tbl <- ccc %>%
  count(size_tier, name = "n") %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  arrange(size_tier)
message("\n-- Tier counts --")
print(as.data.frame(tier_tbl), row.names = FALSE)

# ---- Tier 1-4: direct computation -----------------------------------------
# Tier 3 (only low) uses the lower bound as a conservative point estimate.
# Tier 4 (only high) halves the upper bound; this is a heuristic but CCC
# upper bounds are typically the "could be up to X" coding, so /2 approximates
# the observed mean-to-high ratio (see T1 events: mean ~= 0.45 * high on avg).
ccc <- ccc %>%
  mutate(
    size_direct = case_when(
      size_tier == "T1_observed"   ~ size_mean,
      size_tier == "T2_midpoint"   ~ (size_low + size_high) / 2,
      size_tier == "T3_range_low"  ~ size_low,
      size_tier == "T4_range_high" ~ size_high / 2,
      TRUE                         ~ NA_real_
    )
  )

# Sanity check: T1 mean/high ratio (informs the T4 heuristic)
t1_ratio <- ccc %>%
  filter(size_tier == "T1_observed", !is.na(size_high), size_high > 0) %>%
  summarise(ratio = mean(size_mean / size_high, na.rm = TRUE)) %>%
  pull(ratio)
message("  T1 mean/high ratio (sanity check for T4 heuristic): ",
        sprintf("%.3f", t1_ratio))

# ---- Tier 5: log-OLS imputation model -------------------------------------
# Train on T1 events (observed). Predict for T5. We use log1p for numerical
# stability and to accommodate rare zero-size codes.
message("\n-- Fitting imputation model on T1 events --")

train <- ccc %>%
  filter(size_tier == "T1_observed", size_mean >= 1) %>%
  mutate(
    y_ln  = log(size_mean),
    state = ifelse(is.na(state), "XX", state)
  )
message("    training n: ", format(nrow(train), big.mark = ","))

# Features: year (factor), state (factor), violence flags, BLM tag. We keep
# the model intentionally lean so it generalizes; predicting crowd size at
# the event level is inherently noisy.
fit <- lm(y_ln ~ factor(year) + factor(state) + pd + ar + ic + ip + ca + is_blm,
          data = train)
r2  <- summary(fit)$r.squared
message("    model R^2: ", sprintf("%.3f", r2))

# Back-transformation bias correction: E[Y | X] = exp(Xb + sigma^2 / 2).
sigma2 <- sum(resid(fit)^2) / fit$df.residual
message("    residual sigma^2: ", sprintf("%.3f", sigma2))

# For prediction, keep states in the training factor levels; anything new
# becomes the reference (coef=0).
train_states <- levels(factor(train$state))
train_years  <- levels(factor(train$year))

ccc <- ccc %>%
  mutate(
    state_for_pred = ifelse(is.na(state), "XX", state),
    state_for_pred = ifelse(state_for_pred %in% train_states,
                            state_for_pred, train_states[1]),
    year_for_pred  = as.character(year),
    year_for_pred  = ifelse(year_for_pred %in% train_years,
                            year_for_pred, train_years[1])
  )

ccc$y_ln_hat <- predict(
  fit,
  newdata = ccc %>%
    transmute(year  = factor(year_for_pred,  levels = train_years),
              state = factor(state_for_pred, levels = train_states),
              pd, ar, ic, ip, ca, is_blm)
)
ccc <- ccc %>%
  mutate(
    size_model = pmax(1, exp(y_ln_hat + sigma2 / 2))  # Duan-style bias correction
  )

# ---- Final imputed point estimate & bounds --------------------------------
# T1 P99 caps the hi bound so imputations cannot exceed credible maxima.
t1_p99 <- quantile(train$size_mean, 0.99, na.rm = TRUE)
message("  T1 P99 (hi-bound cap): ", format(round(t1_p99), big.mark = ","))

ccc <- ccc %>%
  mutate(
    # Imputed point: use direct if available, else model.
    size_imputed = coalesce(size_direct, size_model),

    # Conservative lower bound: observed or 10.
    size_lo_bound = coalesce(size_mean, 10),

    # Aggressive upper bound for missing: 3x model prediction, capped at T1 P99.
    size_hi_bound = case_when(
      !is.na(size_mean)     ~ size_mean,
      !is.na(size_direct)   ~ pmin(size_direct, t1_p99),
      TRUE                  ~ pmin(3 * size_model, t1_p99)
    )
  )

# ---- Per-year tier shares -------------------------------------------------
year_tbl <- ccc %>%
  group_by(year, size_tier) %>%
  summarise(n = n(), .groups = "drop_last") %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  ungroup() %>%
  arrange(year, size_tier)
message("\n-- Tier share by year --")
print(as.data.frame(year_tbl), row.names = FALSE)

# ---- Comparison of imputed vs observed-only totals ------------------------
compare_tbl <- ccc %>%
  group_by(year) %>%
  summarise(
    n_events        = n(),
    total_observed  = sum(size_mean,     na.rm = TRUE),
    total_direct    = sum(size_direct,   na.rm = TRUE),
    total_imputed   = sum(size_imputed,  na.rm = TRUE),
    total_lo_bound  = sum(size_lo_bound, na.rm = TRUE),
    total_hi_bound  = sum(size_hi_bound, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    ratio_imp_obs = round(total_imputed / total_observed, 2),
    ratio_hi_lo   = round(total_hi_bound / total_lo_bound, 2)
  )
message("\n-- Aggregate intensity comparison by year --")
print(as.data.frame(compare_tbl), row.names = FALSE)

# ---- Export ---------------------------------------------------------------
dir.create(here("data", "intermediate"), showWarnings = FALSE, recursive = TRUE)
dir.create(here("output", "tables"),     showWarnings = FALSE, recursive = TRUE)

keep_cols <- c(
  "phase", "date", "year", "state", "fips_code",
  "issues", "size_text", "size_low", "size_high", "size_mean", "size_cat",
  "pd", "ar", "ic", "ip", "ca", "v_any", "is_blm",
  "size_tier", "size_direct", "size_model",
  "size_imputed", "size_lo_bound", "size_hi_bound"
)
keep_cols <- intersect(keep_cols, names(ccc))

events_out <- ccc[, keep_cols]
saveRDS(events_out, here("data", "intermediate", "ccc_events_imputed.rds"))
message("\nSaved: data/intermediate/ccc_events_imputed.rds (",
        format(nrow(events_out), big.mark = ","), " rows)")

write_csv(tier_tbl,    here("output", "tables", "ccc_imputation_tiers.csv"))
write_csv(year_tbl,    here("output", "tables", "ccc_imputation_by_year.csv"))
write_csv(compare_tbl, here("output", "tables", "ccc_imputation_compare.csv"))

macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
macros <- c(
  "% Auto-generated by A_US_02_impute_ccc_size.R",
  paste0("% Generated: ", Sys.time()),
  macro("CCCImpNEligible",  format(nrow(ccc), big.mark = ",")),
  macro("CCCImpPctT1",      sprintf("%.1f",
                                   100 * mean(ccc$size_tier == "T1_observed"))),
  macro("CCCImpPctT2",      sprintf("%.1f",
                                   100 * mean(ccc$size_tier == "T2_midpoint"))),
  macro("CCCImpPctT3",      sprintf("%.1f",
                                   100 * mean(ccc$size_tier == "T3_range_low"))),
  macro("CCCImpPctT4",      sprintf("%.1f",
                                   100 * mean(ccc$size_tier == "T4_range_high"))),
  macro("CCCImpPctT5",      sprintf("%.1f",
                                   100 * mean(ccc$size_tier == "T5_model"))),
  macro("CCCImpModelRsq",   sprintf("%.3f", r2)),
  macro("CCCImpT1P99",      format(round(t1_p99), big.mark = ",")),
  macro("CCCImpRatioImpObs",
        sprintf("%.2f", sum(ccc$size_imputed)  / sum(ccc$size_mean, na.rm = TRUE))),
  macro("CCCImpRatioHiLo",
        sprintf("%.2f", sum(ccc$size_hi_bound) / sum(ccc$size_lo_bound)))
)
writeLines(macros, here("output", "tables", "ccc_imputation_macros.tex"))
message("Wrote macros: output/tables/ccc_imputation_macros.tex")

sink()
