# A_MM Triage to 80/100 (Cross-National Nonviolence Premium)
**Date:** 2026-04-18
**Owner:** Charles Crabtree
**Status:** Draft — awaiting approval
**Gate:** ≥ 80/100 on A_MM, same bar as A_US

## Problem
The A_MM pipeline runs end-to-end, but every treatment-side macro is NA or zero because the participant-bracket join in `R/A_MM_02_build_country_year.R` silently fails. The cascade: `avg_participants` becomes all-NA at the event level → `mean(.., na.rm=TRUE)` returns NaN at country-year → the balanced-panel `replace_na(., 0)` forces the whole column to zero → `intensity_nv` = `share_nonviolent * 0` = 0 everywhere → no country crosses the 90th-pct cutoff → `did::att_gt` returns NA → `MMCSPolyarchyATT = NA`, `MMSynthdidNTreated = 0`, and `MMCSRepNonviolentN = 0`. Until `A_MM_02` is fixed, nothing downstream can produce a headline.

Three additional blockers: Archigos/REIGN turnover data is not downloaded, so `leader_turnover` is NA for all 5,420 country-years; `A_MM_08` / `A_MM_09` / `A_MM_10` are stubs (synthdid / augsynth / PanelMatch placeholders with no real estimator call); and `A_MM_07` does not compute or log an arm contrast, so there is no estimand equivalent to the one the A_US paper reports.

## Current State (high-level)
### Pipeline
`R/A_MM_01..12_*.R` exist and executed on 2026-04-18. `data/analysis/a_mm_panel.rds` is 5,420 rows × 35 cols across 166 countries, 1990–2020. V-Dem (99.3% polyarchy coverage), Polity 5 (83.4% polity2 coverage), WDI health / education / population, and QoG CPI all joined successfully. Raw files present: MM events, V-Dem v14, Polity 5 `p5v2018.xls`, QoG, WDI. Missing: Archigos.

### Paper
`paper/A_nonviolence_premium_mm/paper.tex` is a 125-line skeleton with `[TODO]` markers in every section; `statistics.tex` contains the NA / zero macros listed above. References live in the shared `paper/references.bib`, which is already 31-entry / 87% DOI-covered from the A_US pass.

## Proposed Changes
### 1. Fix the `pcat_map` join in `R/A_MM_02_build_country_year.R`
Inspect the actual values of `mm$participants_category` (one of: integer, character `"0050-0099"`-style, or a MM-internal code). Rewrite the join so `avg_participants` is non-zero for the 57.7% of events that do have a bracket. Add a log line that prints the first 20 unique values of `participants_category` so the join failure never goes silent again. Emit a new macro `\MMPanelPctWithBracket` so the paper can report coverage. Do NOT impute the other 42.3% — they remain NA per [LEARN:A_MM-mm] in `MEMORY.md`.

### 2. Rewire `R/A_MM_07_cs_did.R` with a contrast estimand and arm diagnostics
Mirror the A_US_06 fix. Define the headline estimand as the arm contrast $\widehat{\Delta}=\widehat{\mathrm{ATT}}_{\text{nv}}-\widehat{\mathrm{ATT}}_{\text{v}}$ on V-Dem polyarchy. Emit `\MMCSContrastPolyarchy`, `\MMCSContrastSE`, `\MMCSContrastP`, `\MMCSContrastSign`, and arm-diagnostic macros `\MMCSTreatedNV`, `\MMCSTreatedV`, `\MMCSTreatedOverlap`, plus first-year-of-treatment tables for both arms. Rename the existing single-arm macros to `...ATTraw` for transparency. Clustered SEs by country; use the same independent-arm variance approximation with a lower-bound caveat, consistent with A_US.

### 3. Honest placeholder macros for `A_MM_08` / `A_MM_09` / `A_MM_10`
These three scripts will remain stubs this round — a real synthdid / augsynth / PanelMatch pass is a full session of work. Rewrite each so it (a) prints "SKIPPED: stub; see plan item 3" to its session log, (b) emits a single macro flagging that state (e.g. `\MMSynthdidStatus{stub}`), and (c) does not contaminate the paper with a zero-valued numeric. The A_US style of "report what we have, not what we wish we had" is the standard.

### 4. Fix the C&S replication threshold arithmetic in `R/A_MM_12_cs_replication_paper.R`
After fix (1), `avg_participants` has real values. Audit the threshold: Chenoweth–Stephan's 3.5% is a national-participation threshold on the maximum single protest, not an average across country-year. Rewrite the classification to: (a) compute a per-event pop-share as `avg_participants / wdi_pop_total` at the event level, (b) flag a country-year as "maximalist nonviolent" if the largest nonviolent protest in that country-year exceeds 3.5% of population, and (c) flag "maximalist violent" symmetrically. Emit the headline gap `\MMCSRepHeadlineGap` as the difference in mean Δ polyarchy-lead-5 between the two arms, with a dependent-arm SE caveat.

### 5. Rewrite `paper/A_nonviolence_premium_mm/paper.tex` to the A_US standard
Research-question-first abstract and introduction; three named hypotheses (Nonviolence Premium, Intensity Equivalence, Violence Backlash — same names as A_US so the two-paper series reads as one argument); Theory linking V-Dem polyarchy movement to nonviolent-discipline mechanisms; Data section describing MM v5.1 honestly including the 42.3% participant-bracket missingness [LEARN:A_MM-mm]; Design with the three violence measures (strict `share_nonviolent`, state-response-weighted `share_nonviolent_sr`, event-severity-weighted `share_nonviolent_es`); Results using the contrast macros from (2); Robustness subsections for the stubbed estimators that honestly report them as deferred; Discussion comparing the MM result with the A_US result; Conclusion. Figures already exist from the earlier run (`a_mm_timeseries.pdf`, `a_mm_choropleth.pdf`, `a_mm_vdem_paths.pdf`, `a_mm_honestdid.pdf`, `a_mm_multiverse.pdf`, `a_mm_cs_replication.pdf`). Tables in appendix, references on a new page, author info per personal rule.

### 6. Re-run `A_MM_02 → A_MM_12` end-to-end, then compile
Order: `A_MM_02`, `A_MM_03`, `A_MM_04`, `A_MM_05`, `A_MM_06`, `A_MM_07`, `A_MM_11`, `A_MM_12`. Skip `08..10` (stubs). Verify every `statistics.tex` macro is finite and non-zero where that makes substantive sense. Then `pdflatex && bibtex && pdflatex && pdflatex` in `paper/A_nonviolence_premium_mm/`.

## Out of Scope (deferred to a follow-up)
- Real synthdid, augsynth, and PanelMatch implementations (plan items 3a–c of the original agenda).
- Archigos / REIGN download, which requires the Dataverse CLI and a zip extraction not wired up in `R/00_download_archigos.R`; for this pass `leader_turnover` stays NA and is dropped from the outcome stack.
- Expanding the A_MM multiverse beyond the current 120 cells.
- The A_US residual items 3–6 (DCDH, partisan heterogeneity, HonestDiD-on-contrast, multiverse-to-320); those remain queued after A_MM.

## Verification
- `Rscript R/A_MM_02..12` must complete with non-empty session logs.
- `statistics.tex` macros that were NA or 0 (`MMCSPolyarchyATT`, `MMSynthdidNTreated`, `MMCSRepHeadlineGap`, `MMCSRepNonviolentN`, `MMCSRepViolentN`) must be finite numbers or explicit status flags, not silently NA.
- `paper/A_nonviolence_premium_mm/paper.pdf` compiles with zero LaTeX errors and zero warnings.
- The A_US–A_MM contrast-sign comparison (US: backlash; MM: ?) is reported in the Discussion so the two-paper series tells a coherent story.

## Risks
- The participant-bracket column may not be `participants_category` at all — MM has historically used `participants`, `participants_precise`, or `numpart_cat` across versions. If the join can’t be made to work on this file, we fall back to a binary "any bracket reported" treatment, which halves statistical power but is clean.
- V-Dem polyarchy is a slow-moving index; year-over-year variance is small. Even with a working treatment, the headline CS-DiD may land on a tiny effect with a noisy CI. If so the paper reports the null honestly, as the A_US paper does.
- The stubbed estimators mean the A_MM paper will be thinner than A_US in the Robustness section. This is a known trade-off; the alternative is spending a full day on `synthdid` scaffolding and not shipping anything.
