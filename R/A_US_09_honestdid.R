# =============================================================================
# A_US_09_honestdid.R
# Purpose: Rambachan-Roth (2023) HonestDiD sensitivity bounds on the CS
#          ATT(g,t) event-study estimates from A_US_06. Reports the maximum
#          violation of parallel trends (M-bar) under which each headline
#          effect remains significantly positive.
# Method:
#   - For each (outcome x arm) pair in `a_us_cs_results.rds`, aggregate to a
#     dynamic event-study via `did::aggte(..., type = "dynamic")`.
#   - Feed into `HonestDiD::createSensitivityResults_relativeMagnitudes()`
#     with Mbarvec = seq(0, 2, by = 0.5).
#   - Produce the robust-CI plot for the headline outcome.
# Inputs:
#   data/analysis/a_us_cs_results.rds
# Outputs:
#   output/figures/a_us_honestdid_publicsafety.pdf
#   output/tables/a_us_honestdid.csv
#   output/tables/a_us_honestdid_macros.tex
# =============================================================================

suppressPackageStartupMessages({
  library(here); library(dplyr); library(readr)
  library(ggplot2); library(ggthemes)
})

needed <- c("did", "HonestDiD")
missing <- needed[!vapply(needed, requireNamespace,
                          logical(1), quietly = TRUE)]
if (length(missing) > 0) stop("Install: ", paste(missing, collapse = ", "))

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_US_09_honest.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_US_09 HonestDiD sensitivity ===")
message("Run at: ", format(Sys.time()))

cs_path <- here("data", "analysis", "a_us_cs_results.rds")
if (!file.exists(cs_path)) {
  stop("Missing ", cs_path, "; run A_US_06_cs_did.R first.")
}
cs <- readRDS(cs_path)

# ---- HonestDiD glue -----------------------------------------------------
# Rambachan-Roth sensitivity tests the null that post-period deviation from
# parallel trends is bounded by M * the worst pre-period violation. For each
# CS object we: (1) aggregate to a dynamic event-study via did::aggte,
# (2) extract the pre/post event-time coefficients and full variance matrix,
# (3) call HonestDiD::createSensitivityResults_relativeMagnitudes.
run_hd <- function(att_obj, label, Mbarvec = seq(0, 2, by = 0.5)) {
  if (is.null(att_obj)) return(NULL)
  es <- tryCatch(did::aggte(att_obj, type = "dynamic", na.rm = TRUE),
                 error = function(e) NULL)
  if (is.null(es) || length(es$egt) < 2) return(NULL)
  pre_idx  <- which(es$egt <  0)
  post_idx <- which(es$egt >= 0)
  if (length(pre_idx) < 1 || length(post_idx) < 1) return(NULL)

  # Use diag-sigma from the reported event-time SEs. A full variance
  # matrix from the influence function would be slightly tighter but
  # relies on did internals that differ across versions.
  sig <- diag(es$se.egt^2)
  sr  <- tryCatch(
    HonestDiD::createSensitivityResults_relativeMagnitudes(
      betahat        = es$att.egt,
      sigma          = sig,
      numPrePeriods  = length(pre_idx),
      numPostPeriods = length(post_idx),
      Mbarvec        = Mbarvec
    ),
    error = function(e) { message("  HD failed: ", e$message); NULL }
  )
  mbar_be <- NA_real_
  if (!is.null(sr) && nrow(sr) > 0) {
    crosses <- sr$lb <= 0 & sr$ub >= 0
    if (any(crosses)) mbar_be <- min(sr$Mbar[crosses])
  }
  list(label = label, sr = sr, mbar_breakeven = mbar_be)
}

hd_list <- lapply(names(cs$results), function(k) run_hd(cs$results[[k]], k))
hd_tbl <- tibble(
  key            = vapply(hd_list,
                          function(x) if (is.null(x)) NA_character_
                                      else x$label, character(1)),
  mbar_breakeven = vapply(hd_list,
                          function(x) if (is.null(x)) NA_real_
                                      else x$mbar_breakeven, numeric(1))
) %>% filter(!is.na(key))

write_csv(hd_tbl, here("output", "tables", "a_us_honestdid.csv"))

# ---- HonestDiD on the arm contrast for the headline outcome -------------
# Build a per-horizon contrast event-study for spend_public_safety by
# pairing nv and v event-time coefficients at the same event time. If
# either arm is missing a coefficient at event time e, we drop that e.
run_hd_contrast <- function(cs_results, outcome,
                            Mbarvec = seq(0, 2, by = 0.25)) {
  nv_obj <- cs_results[[paste0(outcome, "__nv")]]
  v_obj  <- cs_results[[paste0(outcome, "__v")]]
  if (is.null(nv_obj) || is.null(v_obj)) return(NULL)
  es_nv <- tryCatch(did::aggte(nv_obj, type = "dynamic", na.rm = TRUE),
                    error = function(e) NULL)
  es_v  <- tryCatch(did::aggte(v_obj,  type = "dynamic", na.rm = TRUE),
                    error = function(e) NULL)
  if (is.null(es_nv) || is.null(es_v)) return(NULL)
  common_e <- intersect(es_nv$egt, es_v$egt)
  if (length(common_e) < 2) return(NULL)
  i_nv <- match(common_e, es_nv$egt)
  i_v  <- match(common_e, es_v$egt)
  betahat <- es_nv$att.egt[i_nv] - es_v$att.egt[i_v]
  se_diff <- sqrt(es_nv$se.egt[i_nv]^2 + es_v$se.egt[i_v]^2)
  # HonestDiD wants a joint sigma; diag is the correct independent-arm
  # approximation given arm-disjoint treated sets reported in A_US_06.
  sig <- diag(se_diff^2)
  pre_idx  <- which(common_e <  0)
  post_idx <- which(common_e >= 0)
  if (length(pre_idx) < 1 || length(post_idx) < 1) return(NULL)
  sr <- tryCatch(
    HonestDiD::createSensitivityResults_relativeMagnitudes(
      betahat        = betahat,
      sigma          = sig,
      numPrePeriods  = length(pre_idx),
      numPostPeriods = length(post_idx),
      Mbarvec        = Mbarvec
    ),
    error = function(e) { message("  HD-contrast failed: ", e$message); NULL }
  )
  mbar_be <- NA_real_
  if (!is.null(sr) && nrow(sr) > 0) {
    crosses <- sr$lb <= 0 & sr$ub >= 0
    if (any(crosses)) mbar_be <- min(sr$Mbar[crosses])
  }
  list(sr = sr, mbar_breakeven = mbar_be,
       betahat = betahat, se_diff = se_diff, common_e = common_e)
}

hd_contrast <- run_hd_contrast(cs$results, "spend_public_safety")
if (!is.null(hd_contrast) && !is.null(hd_contrast$sr) &&
    nrow(hd_contrast$sr) > 0) {
  p_c <- ggplot(hd_contrast$sr, aes(Mbar)) +
    geom_hline(yintercept = 0, linetype = 2, colour = "grey50") +
    geom_ribbon(aes(ymin = lb, ymax = ub), alpha = 0.25) +
    geom_line(aes(y = (lb + ub) / 2)) +
    theme_tufte(base_size = 11) +
    labs(x = expression(bar(M)),
         y = "HonestDiD robust 95% CI (arm contrast)",
         title = "HonestDiD sensitivity: ATT_nv - ATT_v on public safety")
  ggsave(here("output", "figures", "a_us_honestdid_contrast.pdf"),
         p_c, device = cairo_pdf, width = 6.5, height = 4)
}

# Plot the first non-null sensitivity curve (headline: public safety, NV arm).
headline_key <- "spend_public_safety__nv"
hl <- hd_list[[which(vapply(hd_list,
                            function(x) !is.null(x) && x$label == headline_key,
                            logical(1)))[1]]]
if (!is.null(hl) && !is.null(hl$sr) && nrow(hl$sr) > 0) {
  p <- ggplot(hl$sr, aes(Mbar)) +
    geom_hline(yintercept = 0, linetype = 2, colour = "grey50") +
    geom_ribbon(aes(ymin = lb, ymax = ub), alpha = 0.25) +
    geom_line(aes(y = (lb + ub) / 2)) +
    theme_tufte(base_size = 11) +
    labs(x = expression(bar(M)),
         y = "HonestDiD robust 95% CI for ATT",
         title = "Public-safety spending (nonviolent arm): HonestDiD sensitivity")
  ggsave(here("output", "figures", "a_us_honestdid_publicsafety.pdf"),
         p, device = cairo_pdf, width = 6.5, height = 4)
}

macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
be_headline <- if (!is.null(hl)) hl$mbar_breakeven else NA
be_contrast <- if (!is.null(hd_contrast))
  hd_contrast$mbar_breakeven else NA_real_
writeLines(
  c("% Auto-generated by A_US_09_honestdid.R",
    paste0("% Generated: ", Sys.time()),
    macro("AUSHDNSpecs", nrow(hd_tbl)),
    macro("AUSHDBreakevenPubSafety",
          if (is.finite(be_headline)) sprintf("%.2f", be_headline) else "NA"),
    macro("AUSHDBreakevenContrast",
          if (is.finite(be_contrast)) sprintf("%.2f", be_contrast) else "NA")),
  here("output", "tables", "a_us_honestdid_macros.tex")
)

sink()
