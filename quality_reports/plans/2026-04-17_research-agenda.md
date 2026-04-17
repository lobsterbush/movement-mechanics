# Research Agenda — Movement Mechanics
**Date:** 2026-04-17
**Owner:** Charles Crabtree
**Status:** Draft; awaiting author approval on sub-study selection

## Problem
Two live projects need county-level empirical extensions:
- `protests-spending` (Crabtree & Holbein) finds a ~2% threshold above which protest intensity shifts local government spending — but the evidence is confined to one outcome domain (expenditure categories) and one estimator family (TWFE + dose DiD).
- A parallel rebuttal of Chenoweth & Stephan's (2011) 3.5% critical-mass claim needs US-domestic evidence that (a) effects scale continuously with mobilization (not as a cliff at 3.5%), (b) nonviolence discipline does not mechanically produce larger effects, and (c) the critical-mass logic does not transfer cleanly from regime change to routine policy.

The CCC Phase 2 dump (Harvard Dataverse DOI:10.7910/DVN/HTTWYL/TJJZNG, v5.1) plus the 2025–2026 wave of frontier DiD estimators makes it feasible to run a portfolio of tightly-scoped county-level studies that jointly supplement both papers. This plan enumerates the candidates and flags priorities.

## Shared Scaffolding
All sub-studies share:
- **Treatment source:** CCC Phase 1 + Phase 2 events, geocoded to FIPS5, aggregated to county-year. The cleaning pipeline from `protests-spending/R/03_clean_ccc.R` is a direct starting point.
- **Core treatment measures:** `protest_per_cap` (crowd size per capita, time-varying); `any_property_damage`, `any_arrests`, `any_injuries_*` (incident indicators); `issue_tags` / `issues` (topical codes); position indicators (pro/anti where available).
- **SEs:** Clustered by county. HonestDiD sensitivity reported for every DiD point estimate.
- **Panel:** 2017–2024 (7 fiscal / 8 calendar years depending on outcome), balanced or semi-balanced as required by the estimator.
- **Inference safeguards:** pre-trend F-tests, placebo outcomes, specification curves (≥ 320 specs per headline result) following `protests-spending/R/14_multiverse.R`.

## Candidate Sub-studies
### A. Nonviolence Premium? — *supplements the C&S rebuttal directly*
**Question.** Do nonviolent protests produce larger policy responses than protests with property damage, arrests, or injuries, holding intensity constant?
**Design.** Split `protest_per_cap` by CCC incident flags into `nonviolent_per_cap` vs `violent_per_cap`. Run Callaway-Sant'Anna (2021) with each as a continuous dose (via `DIDmultiplegtDYN`), then test whether the gap between them is statistically distinguishable from zero.
**Outcome stack.** Use the `protests-spending` 9-category spending panel as the first outcome stack so results are directly comparable to the existing paper. Add county-level police use-of-force complaints (MPV + Police Scorecard) as a second stack.
**Why it supplements both.** Ties fiscal outcomes to incident type in a way the current paper does not. Provides the C&S rebuttal with a clean within-country test of the nonviolence-discipline claim that avoids NAVCO's cross-case heterogeneity.
**Estimator.** `did::att_gt` with continuous dose via `DIDmultiplegtDYN::did_multiplegt_dyn`; HonestDiD sensitivity; specification curve across (nonviolence definition × spending category × FE × sample).

### B. Critical-Mass Gradient vs Cliff — *supplements the C&S rebuttal directly*
**Question.** Does the response to protest intensity exhibit a cliff at ~3.5% of county population (C&S's cutoff), a cliff elsewhere, or a smooth gradient?
**Design.** Use continuous DiD (Callaway-Goodman-Bacon-Sant'Anna 2024 via `contdid`, fallback `DIDmultiplegtDYN`) to estimate the full ACRT curve across the participation-rate distribution. Apply Hahn-Ridder-style threshold tests at p10–p99 of participation to pinpoint any discontinuity. Report the empirical CDF of county-level participation rates so readers can see how many counties clear 3.5% (likely very few — itself a useful rebuttal fact).
**Outcome stack.** Spending categories from `protests-spending`; electoral outcomes (incumbent vote share, turnout) from MIT MEDSL + state SOS data; state-policy adoptions from NCSL bill-tracker feeds.
**Why it supplements both.** Directly generalizes the ~2% threshold finding in `protests-spending` and makes it legible to the C&S literature. Expected headline: the C&S cliff is an artifact of categorical coding; US county evidence shows a gradient.
**Estimator.** `contdid::cont_did` primary; `DIDmultiplegtDYN` fallback; Borusyak-Jaravel-Spiess (`didimputation`) for efficiency comparison.

### C. Protest–Police Nexus
**Question.** Do protests shift downstream police behavior (use-of-force complaints, stops, arrests, officer-involved shootings) in addition to police budgets?
**Design.** Sun-Abraham event study around each county's first above-p75 protest year, stratified by protest type (racial justice vs other). Use `fixest::sunab()` + `HonestDiD`.
**Outcome stack.** Mapping Police Violence (OIS), Stanford Open Policing Project (stops), FBI UCR NIBRS (arrests), Police Scorecard composites.
**Why it supplements.** Pairs the budget result in `protests-spending` with a behavioral one — addresses the obvious referee objection that budget cuts may not translate to actual policing changes.
**Estimator.** Sun-Abraham; imputation estimator cross-check; HonestDiD.

### D. Counter-Mobilization Cancellation
**Question.** Do counter-protests in the same county-year cancel each other out (the Ebbinghaus-style backlash story) or do they compound salience and amplify both effects?
**Design.** Construct `aligned_intensity` and `opposing_intensity` from CCC issue/position tags (e.g., pro-BLM vs blue-lives; pro-choice vs pro-life; pro-Israel vs pro-Palestine; climate vs anti-climate). Estimate TWFE with interaction `aligned × opposing` and additively with absolute intensity. Borrow the Butts (2023) spatial-DiD approach for neighbor-county spillovers.
**Outcome stack.** Spending categories + election returns + issue-specific state policy adoptions.
**Why it supplements.** Provides a mechanism for the null linear TWFE in `protests-spending`: maybe averages are null because aligned and opposing protests net out. Also speaks to the C&S rebuttal because counter-mobilization is absent from their model.
**Estimator.** TWFE with interacted dose; Butts (2023) spatial DiD for spillovers; imputation for sensitivity.

### E. Protest–Electoral Sequelae
**Question.** Do protest waves translate into incumbent vote-share declines, turnout shifts, or entry of protest-themed challengers in the following general and midterm elections?
**Design.** Continuous DiD on 2018, 2020, 2022, 2024 county returns with protest intensity in the preceding two years as dose. Local-projections DiD (Dube-Girardi-Jorda-Taylor 2023) for dynamic multipliers at 1-, 2-, and 4-year horizons.
**Outcome stack.** MEDSL county-level presidential, House, gubernatorial, and ballot-measure returns; Ballotpedia challenger data.
**Why it supplements.** Sances (2023) documented opinion shifts after Floyd; this completes the opinion → ballot → policy chain that the current spending paper only covers from the policy end.
**Estimator.** Local-projections DiD (`lpdid` package) primary; CS-DiD cross-check.

### F. Issue–Policy Alignment
**Question.** Do issue-specific protest waves shift issue-specific policy — not just aggregate spending? E.g., do climate marches move state renewable-portfolio standards? Do abortion rallies move state trigger-law status?
**Design.** Six-panel CS-DiD, one per issue (climate, abortion, immigration, gun, labor, racial justice), with issue-filtered intensity as the treatment and issue-aligned state policy adoption (NCSL + State Legislation Tracker API) as the outcome.
**Outcome stack.** NCSL bill status feeds; State Net; Ballotpedia state legislation.
**Why it supplements.** Demonstrates that the threshold finding in `protests-spending` generalizes across issue domains, and gives the C&S rebuttal fine-grained evidence that critical mass is issue- and institution-specific rather than universal.
**Estimator.** CS-DiD per issue; meta-analysis pooling issues with random effects.

## Recommended Priority
1. **B. Critical-Mass Gradient vs Cliff** — most direct supplement to both anchor papers; uses data already pulled for `protests-spending`; a publishable result sits at least one estimator away from what's already on the disk.
2. **A. Nonviolence Premium?** — second, because it reuses the same panel and pipeline and directly tackles C&S's signature claim.
3. Remaining four sub-studies (C, D, E, F) as a follow-on research program after A and B are locked.

## What I Need from You
- Approval (or edits) on the sub-study menu — especially whether to swap any of C–F with a different outcome domain.
- Confirmation that B and A are the right two to front-load, or a different prioritization.
- Co-author assignments per sub-study (Holbein for A/B? New collaborators for C–F?).
- A decision on whether to pursue these as separate journal articles or as chapters of a single monograph — the repo structure supports either.

## Out of Scope for This Plan
- Rewriting any of `protests-spending`.
- Replication or re-estimation of anything in the C&S rebuttal repo.
- Cross-national extensions. The CCC covers only the US; cross-national work would need NAVCO or GDELT.

## Next Step
On approval, generate a detailed sub-study-specific plan (data pulls, estimator choice, figure list, statistical-power calculations) for whichever sub-study we start first, and scaffold its `R/{A,B}_01_*.R` through `R/{A,B}_10_*.R` script stubs.
