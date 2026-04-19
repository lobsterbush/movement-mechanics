# A_US Triage to 80/100 (Nonviolence Premium)
**Date:** 2026-04-18
**Owner:** Charles Crabtree
**Status:** Draft — awaiting approval before execution
**Gate:** ≥ 80/100 on A_US before touching A_MM (per `CLAUDE.md`)

## Problem
The A_US pipeline runs end-to-end, but the `statistics.tex` macros and session logs show four symptoms that block the commit gate:
1. Headline CS ATT on public-safety spending is **larger for the violent arm** (`AUSCSVpubSafetyATT = 12,797`, se ≈ 7,511) than for the nonviolent arm (`AUSCSNVpubSafetyATT = 2,210`, se ≈ 2,690). The paper is framed as a nonviolence *premium*; the raw macros imply the opposite. We never compute the actual estimand — the arm contrast `ATT_nv − ATT_v` — or its SE.
2. `AUSDCDHNSpecs = 0` (`R/A_US_07_dcdh_continuous.R`) because `results[[k]] <- NULL` silently removes list entries; the macro therefore counts nothing even when the script runs.
3. `AUSHDBreakevenPubSafety = 0.00` (`R/A_US_09_honestdid.R`) because the HonestDiD pipe is applied to a single-arm CS estimate that is already insignificant (|att/se| ≈ 0.8), so the robust CI straddles zero at every $\bar M$.
4. `AUSHetPartisanNRuns = 0` (`R/A_US_10_placebo_heterogeneity.R`) because the MEDSL path check `countypres_2000-2024.tab` silently skips. The downloader (`R/00_download_medsl.R`) writes to a different filename.

A fifth quality gap is baked into the pre-registration: `AUSMVNSpecs = 120`, below the agenda's ≥320 target.

## Current State (high-level)
### Pipeline
`R/A_US_01..12_*.R` exist and executed on 2026-04-18. `data/analysis/a_us_panel.rds` is the 47,859-row, 2,279-county, 2017–2023 panel. `data/analysis/a_us_cs_results.rds` holds the CS objects from A_US_06. Session logs for A_US_07, A_US_08, A_US_09 are 0 bytes because those scripts `stop()` on missing packages *before* `sink()` opens, or `tryCatch` swallows every failure into NULL.

### Paper
`paper/A_nonviolence_premium_us/paper.tex` is a skeleton with `[TODO]` markers in Intro, Theory, Design, Results, Discussion, Conclusion, and Appendix. `statistics.tex` is live but contains the misleading macros above. `../references.bib` is 3.4 KB (well short of the >90% DOI-audited target).

### MEMORY.md
Already records: CCC `size_mean` observability flip at 2020, strict/permissive/noarrest violence flags being near-identical except in the 2020 tail, and the event-level imputation model fitting R² ≈ 0.067. These constrain which robustness results we should foreground in the paper.

## Proposed Changes
### 1. Fix the headline estimand in `R/A_US_06_cs_did.R`
Add a per-outcome `(att_nv, att_v, att_diff, se_diff, p_diff)` table and emit four new macros: `\AUSCSContrastPubSafety`, `\AUSCSContrastSE`, `\AUSCSContrastP`, `\AUSCSContrastSign`. Use the independent-arm variance approximation `se_diff = sqrt(se_nv^2 + se_v^2)` (treatment sets are near-disjoint under 90th-pct cutoffs) and report the overlap count as a diagnostic. Keep the single-arm macros but rename them to `...ATTraw` so the paper body defaults to the contrast.

### 2. Diagnose the violent-arm inflation
Add a log block in `A_US_06` that prints, per arm: number of treated counties, first-treatment year distribution, and mean of `size_violent / size_total` in treated units. Expected failure mode (per `MEMORY.md` [LEARN:treatment]): the 90th-pct cutoff on `violent_per_cap` selects ≈5–10 high-profile 2020 cities (NYC, Minneapolis, Portland) whose Census-of-Governments public-safety spending jumps for unrelated ARPA reasons. Two mitigations: (a) raise the cutoff only for the violent arm so both arms have comparable treated-N, or (b) condition on `year != 2020` as the headline and report full-sample as robustness. Choose based on the diagnostic print.

### 3. Fix `R/A_US_07_dcdh_continuous.R`
Replace `results <- list(); results[[k]] <- run_dcdh(...)` (which drops NULL) with `results[[k]] <- list(obj = run_dcdh(...))`, then compute `n_success <- sum(!vapply(results, function(r) is.null(r$obj), logical(1)))` and emit `\AUSDCDHNSpecs{n_success}` plus a per-(outcome, arm) success/fail CSV. Wire the extracted dCdH point estimates through to `statistics.tex` — currently the script saves an RDS but never emits numeric macros.

### 4. Retarget `R/A_US_09_honestdid.R`
Run HonestDiD on the arm-contrast event study built in change (1), not on the single-arm NV event study. Use `HonestDiD::createSensitivityResults_relativeMagnitudes()` with `Mbarvec = seq(0, 2, 0.25)` and redefine the breakeven as the smallest $\bar M$ at which the 95% robust CI on the *contrast* crosses zero. Emit `\AUSHDBreakevenContrast` and keep `\AUSHDBreakevenPubSafetyNV` for the single-arm check.

### 5. Wire up partisan heterogeneity in `R/A_US_10_placebo_heterogeneity.R`
Point `medsl_path` at the actual filename written by `R/00_download_medsl.R` (use `list.files("data/raw/medsl", full.names = TRUE, pattern = "\\.(tab|csv)$")[1]` with a fallback). Cache the 2016 GOP-share quintile in `data/intermediate/medsl_2016_quintile.rds` so subsequent reruns don't reparse the 200 MB file. If MEDSL is still unavailable, the script should now `stop()` instead of silently emitting `AUSHetPartisanNRuns = 0`.

### 6. Expand `R/A_US_11_multiverse.R` to ≥ 320 specs
Current grid: 3 × 2 × 2 × 1 × 5 × 2 = 120. Restore `cutoff_pct = c(0.50, 0.75, 0.90, 0.95)` and add `estimator = c("cs", "bjs")`, yielding 3 × 4 × 2 × 2 × 5 × 2 = 480. Add a `baseline` filter so the "drop_2020" window only runs against the `full` contrast for reporting economy, and keep the callr isolation. Change the headline outcome in the figure to `ATT_nv − ATT_v` rather than the raw `att_diff`, which is what's already plotted but not clearly documented.

### 7. Hypotheses, named not numbered (per personal rule)
Edit `paper/A_nonviolence_premium_us/paper.tex`:
- **Nonviolence Premium**: $\mathbb E[Y(1,\text{nv}) - Y(0)] > \mathbb E[Y(1,\text{v}) - Y(0)]$ on public-safety spending, conditional on county FE and year FE.
- **Intensity Equivalence** (null): the arm contrast is zero.
- **Violence Backlash** (counter-hypothesis): $\mathbb E[Y(1,\text{nv}) - Y(0)] < \mathbb E[Y(1,\text{v}) - Y(0)]$.

Refer back with "the results support / are consistent with / are inconsistent with" — never "prove".

### 8. Bibliography
Seed `paper/references.bib` with the citations the paper already calls (`\cite{clark_regan_2022}`, `\cite{arkhangelsky2021}`, `\cite{benmichael2021}`, `\cite{imai2023}`, `\cite{rambachan2023}`, `\cite{chenoweth2011}`) plus core CCC / `protests-spending` references. Then run the Crossref DOI audit per the personal rule and target >90% coverage before any commit.

### 9. Paper prose + compile
Fill the `[TODO]` blocks in order: Introduction (research-question-first per personal rule), Theory, Design, Results (pulling from `statistics.tex`), Discussion, Conclusion. Keep all tables in the appendix; figures in the body. Recompile with `pdflatex && bibtex && pdflatex && pdflatex` per the personal rule.

## Verification
- `Rscript R/A_US_06..11` must complete with non-zero session logs.
- `statistics.tex` macros that were NA/0 must be finite and documented.
- `paper/A_nonviolence_premium_us/paper.pdf` must build with zero LaTeX errors.
- The `quality_reports/session_logs/2026-04-18_*` logs must show arm counts, not just ATT tables.

## Out of Scope (Defer Until A_US Clears 80/100)
- Any A_MM fixes. The A_MM failures (A_MM_07 all-NA ATTs, A_MM_08 stub, A_MM_12 zero C&S-maximalist country-years) are real but gated by the one-sub-study-at-a-time rule.
- New outcome pulls (NIBRS, Police Scorecard). The current 11-outcome stack is sufficient for the headline.
- Spec-curve tricks beyond the restored 480-cell grid.

## Risks
- The contrast might still favour the violent arm after (1) and (2). If so, the paper reframes — from "Nonviolence Premium" to "Conditional on intensity, does violence type matter?" — rather than pretending otherwise. `MEMORY.md` already flags this with [LEARN:treatment] (BLM-specific confounding).
- MEDSL download is a 200 MB tab file; first run of (5) will be slow.
- Restoring 480 specs for the multiverse is ~16 CPU-hours of CS-DiD. Spec runner is already callr-isolated, so segfaults won't cascade, but plan for an overnight run.
