# Research Agenda — Movement Mechanics (CCC + MM)
**Date:** 2026-04-17
**Owner:** Charles Crabtree
**Status:** Active; Nonviolence Premium (A_US and A_MM) is the next work to execute

## Problem
Two live projects need causal empirical extensions:
- `protests-spending` (Crabtree & Holbein) — US county-year evidence that protest intensity shifts local government spending above a ~2% participation threshold.
- A parallel rebuttal of Chenoweth & Stephan's (2011) 3.5% critical-mass claim — needs independent, event-level data and frontier DiD estimators.

This repo hosts a portfolio of sub-studies that supplement both anchor papers. Each sub-study is run once on each of two complementary data sources, so every claim has both a US-domestic (sub-national) and a global (cross-national) leg.

## Data Tracks
### Track CCC — US, County-Year
- **Source:** Crowd Counting Consortium. Harvard Dataverse (separate DOI from MM).
- **Unit:** county-year, FIPS5, 2017–2024, ~212K events.
- **Key variables:** `crowd_size_est`, `any_property_damage`, `any_arrests`, `any_injuries_*`, `issue_tags` / `issues`, event position tags.
- **Cleaning pipeline:** reuse `protests-spending/R/03_clean_ccc.R`; symlink or fork cleaned `.rds` into `data/intermediate/`.
- **Outcome data available:** Census of Governments expenditures; Mapping Police Violence; Stanford Open Policing; FBI UCR NIBRS; MEDSL county returns; NCSL state bill tracker.

### Track MM — Global, Country-Year
- **Source:** Mass Mobilization Data (Clark & Regan, Binghamton / Notre Dame). Harvard Dataverse DOI:10.7910/DVN/HTTWYL, version 5.1.
- **Specific files:**
  - `mmALL_073120_csv.tab` — 15.6 MB tab-separated events, 1990-01-01 to 2020-03-31.
  - `mmALL_073120_v16.tab` — 15.5 MB Stata 14 binary equivalent.
  - `MM_users_manual_0515.pdf` — codebook (file ID TJJZNG, 122 KB). **Download first**; every cleaning decision must cite a codebook page.
- **Unit:** country-year (~162 countries × 30 years ≈ 4,860 country-years) built up from event-level records.
- **Key variables:** protest size brackets (approximate participant ranges), 7 demand categories (labor, land, political behavior/process, police brutality, prices, removal of politicians, social restrictions), protester violence flag, 7 state-response codes (accommodation, arrests, beatings, killings, crowd dispersal, ignore, shootings), start/end date, city.
- **Outcome data available:** V-Dem v14 (electoral/liberal/participatory democracy indices); Polity V regime transitions; Executive turnover (Archigos / REIGN); IMF WEO fiscal series; World Bank WDI social spending; Quality of Government standard dataset.
- **Why MM matters for the C&S rebuttal:** MM is independently coded from NAVCO, has participant counts (C&S's 3.5% is a participation threshold), and covers anti-government protests specifically — the exact frame of Chenoweth & Stephan's maximalist-campaign claim.

## Shared Conventions
- Every sub-study runs on both tracks where the outcome data support it. Sub-study prefixes carry a track suffix (`A_US`, `A_MM`).
- SEs clustered by county (CCC) or country (MM). HonestDiD sensitivity reported for every DiD point estimate.
- Every headline result gets a specification curve of ≥ 320 specs following `protests-spending/R/14_multiverse.R`.
- LaTeX manuscripts: Palatino, 1-in margins, double-spaced, apacite, one per sub-study per track.
- Figures: `ggplot2` + `theme_tufte()`; PDF via `cairo_pdf`; slide PNGs at 300 dpi transparent.

## Active Priority — Nonviolence Premium (A_US + A_MM)
Two companion papers, coordinated in design and timing.

### A_US. Nonviolence Premium (CCC, US county-year)
**Question.** Do nonviolent protests produce larger policy responses than protests with property damage, arrests, or protester-instigated violence, holding intensity and county FE constant?
**Treatment.** Split `protest_per_cap` by CCC incident flags (`any_property_damage`, `any_arrests`, `any_injuries_protester`) into `nonviolent_per_cap` vs `violent_per_cap`, plus three sensitivity definitions (strict, permissive, arrest-excluded).
**Outcome stack.**
1. `protests-spending` 9-category spending panel (direct comparison to Crabtree & Holbein).
2. Police-behavior stack — MPV officer-involved shootings; Police Scorecard use-of-force; Stanford Open Policing stop rates.
3. Placebo outcome — highway spending (should be null).
**Estimator.** Callaway-Sant'Anna (2021) via `did::att_gt` with continuous dose via `DIDmultiplegtDYN::did_multiplegt_dyn`. Borusyak-Jaravel-Spiess imputation (`didimputation`) as efficiency check. HonestDiD sensitivity.
**Headline test.** $H_0: \beta_{\text{nonviolent}} - \beta_{\text{violent}} = 0$. Secondary: dose-response curves differ in shape, not just level.
**Why it supplements both anchor papers.** Turns `protests-spending`'s null-on-violence question into a positive result, and gives the C&S rebuttal a within-country test of nonviolence discipline that NAVCO's cross-case heterogeneity cannot provide.

### A_MM. Nonviolence Premium (MM, global country-year)
**Question.** Same as A_US, one level up. Do nonviolent protest-years produce larger changes in V-Dem / Polity / executive-turnover outcomes than violent protest-years, holding country FE and year FE constant?
**Treatment.** MM event-level `protesterviolence` flag aggregated to country-year: `share_nonviolent` × `avg_participants` (or total brackets). Sensitivity: (a) state-response-weighted violence (treating shootings/killings-by-state as violence-of-the-state), (b) event-severity-weighted violence.
**Outcome stack.**
1. V-Dem electoral democracy index and sub-indices.
2. Polity V regime transitions and executive turnover (Archigos/REIGN).
3. World Bank WDI social spending categories (health, education, social protection) for a fiscal-responsiveness leg mirroring A_US.
**Estimator.** Callaway-Sant'Anna with country-year dose; synthetic DiD (Arkhangelsky et al. 2021) via `synthdid`; augmented synthetic control (Ben-Michael-Feller-Rothstein) via `augsynth`; `PanelMatch` (Imai-Kim-Wang) for sensitivity. Clustered SEs by country; block-bootstrap in synthetic designs.
**Headline test.** $H_0: \beta_{\text{nonviolent}} = \beta_{\text{violent}}$ on V-Dem first-differences. Secondary: replicate C&S's headline success-rate gap with MM's participation brackets and show it vanishes or shrinks.
**Why paired with A_US.** Together they form a two-paper series: one sub-national US test, one cross-national global test. If both converge on a nonviolence-premium null (or a smaller premium than C&S), that's a coordinated rebuttal that is hard to dismiss as context-specific.

## Follow-on Sub-studies (scheduled after A_US + A_MM lock)
### B. Critical-Mass Gradient vs Cliff (B_US + B_MM)
Continuous DiD ACRT curve across participation rates; threshold sweeps p10–p99; empirical CDF of participation rates per data source. Direct C&S rebuttal.

### C. Protest–Police Nexus (C_US only)
Sun-Abraham event study on police behavior (MPV, Open Policing, NIBRS). Pairs budget with behavior. MM doesn't have sub-national police data, so this track is US-only.

### D. Counter-Mobilization Cancellation (D_US + D_MM)
Aligned × opposing intensity; Butts (2023) spatial DiD. Mechanism for the linear TWFE null in `protests-spending`.

### E. Protest–Electoral / Executive Sequelae (E_US + E_MM)
Local-projections DiD (Dube-Girardi-Jorda-Taylor 2023). US: county returns 2018–2024. MM: executive turnover via Archigos / REIGN.

### F. Issue–Policy Alignment (F_US + F_MM)
Six-panel CS-DiD on issue-aligned policy. US: NCSL bill tracker by issue. MM: WDI / QoG outcome by MM demand category (labor demands → labor policy; price protests → subsidy spending).

## Estimator Cheat Sheet (by panel type)
| Panel type | Primary | Sensitivity |
|------------|---------|-------------|
| US county-year (CCC) | `did::att_gt` + `DIDmultiplegtDYN` | `didimputation`, HonestDiD, Sun-Abraham |
| Global country-year (MM) | `synthdid`, `did::att_gt` | `augsynth`, `PanelMatch`, HonestDiD |
| Continuous-dose | `contdid` (when fixed) + `DIDmultiplegtDYN` | threshold sweeps, spline ACRTs |

## Recommended Order
1. **Pull the MM codebook and data.** `R/00_download_mm.R`. Record the Dataverse version (5.1) and the download date in a `data/raw/MM_manifest.yml`.
2. **A_US.** Build the CCC-by-violence split on top of the cleaned CCC panel from `protests-spending`. Target: full pipeline + figures + paper draft within 3 weeks.
3. **A_MM.** Build the MM country-year panel, joined to V-Dem, Polity, WDI. Target: full pipeline + figures + paper draft within 4 weeks. A_US and A_MM share a common theoretical section and introduction.
4. **Joint submission planning.** Decide whether A_US and A_MM go to the same journal (e.g., APSR / AJPS / JOP as companion papers) or different ones (JOP for A_US; World Politics or International Organization for A_MM).
5. **B_US + B_MM next**, after A_US and A_MM clear the 80/100 commit gate.

## What I Need from You
- Approval on the two-paper companion framing for Nonviolence Premium.
- Confirmation of co-author assignments (Holbein on A_US? A different IR collaborator for A_MM?).
- A decision on whether A_US and A_MM share a single paper directory (`paper/A_nonviolence_premium_us/` and `paper/A_nonviolence_premium_mm/`) or are merged into one longer paper with two empirical sections. My recommendation: two separate papers so each can target the appropriate sub-field.
- A call on whether B–F will also run as CCC/MM pairs or whether some should stay single-track.

## Out of Scope
- Rewriting `protests-spending`.
- Re-estimating anything in the existing C&S rebuttal repo.
- Harmonizing CCC and MM event coding into a single merged events file — they measure different populations (all US protest events vs global anti-government protests); cross-dataset work means joint country-year or joint year only.

## Next Step on Approval
Scaffold the two pipelines:
- `R/A_US_01_*.R` through `R/A_US_12_*.R` — CCC cleaning → violence split → CS-DiD estimation → figures → `paper/A_nonviolence_premium_us/paper.tex`.
- `R/A_MM_01_*.R` through `R/A_MM_12_*.R` — MM ingest → country-year panel → V-Dem merge → synthdid + CS-DiD → figures → `paper/A_nonviolence_premium_mm/paper.tex`.
