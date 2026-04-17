# Movement Mechanics
**Status:** Active. Research agenda scaffolded; Nonviolence Premium (A_US + A_MM) queued as the next work.
**Description:** A portfolio of causal tests of how protest movements translate into downstream political, fiscal, and electoral outcomes, run in parallel on two complementary data sources: Crowd Counting Consortium (US county-year) and Mass Mobilization (global country-year). Each sub-study produces a US-domestic and a cross-national leg. Designed to supplement the `protests-spending` paper (Crabtree & Holbein) and a parallel rebuttal of Chenoweth & Stephan's (2011) 3.5% critical-mass claim.
**Authors:** Charles Crabtree (Monash / Korea University); co-authors TBD per sub-study.
**Last Updated:** 2026-04-17

## Tech Stack
- **Language:** R (≥ 4.1.0)
- **Key packages (county-year / CCC):** `tidyverse`, `fixest`, `did` (Callaway-Sant'Anna), `DIDmultiplegtDYN` (de Chaisemartin-D'Haultfœuille), `contdid` (Callaway-Goodman-Bacon-Sant'Anna), `didimputation` (Borusyak-Jaravel-Spiess), `HonestDiD` (Rambachan-Roth), `staggered` (Roth-Sant'Anna), `sf`, `tigris`, `ggplot2`, `ggthemes`.
- **Key packages (country-year / MM):** `synthdid` (Arkhangelsky et al. 2021), `augsynth` (Ben-Michael-Feller-Rothstein), `PanelMatch` (Imai-Kim-Wang), `haven` (Stata imports), `vdemdata`, `countrycode`.
- **Paper(s):** LaTeX (Palatino, 1-in margins, double-spaced, apacite); one manuscript per completed sub-study per track (A_US, A_MM, B_US, B_MM, …), all sharing this repo's bibliography and pipeline.
- **Visualization:** `ggplot2` + `theme_tufte()`; PDF via `cairo_pdf` for papers; PNG (300 dpi, transparent bg) for slides.
- **Standard errors:** Clustered by county (CCC) or country (MM); `HonestDiD` sensitivity for every DiD estimate; block-bootstrap for synthetic designs.
- **Deployment:** No public website yet. Slides (if any) will live at `slides.html` and `index.html` on GitHub Pages once a sub-study is ready to share.

## Data Sources
- **Crowd Counting Consortium (CCC).** Harvard Dataverse. Phase 1 (2017–2020) + Phase 2 (2021–present). ~212K geocoded US protest events with crowd size, issue tags, position tags, and incident indicators (property damage, arrests, injuries). Used for all `*_US` sub-studies.
- **Mass Mobilization (MM), Clark & Regan.** Harvard Dataverse DOI:10.7910/DVN/HTTWYL, v5.1 (2022-10-10). Files: `mmALL_073120_csv.tab`, `mmALL_073120_v16.tab`, `MM_users_manual_0515.pdf` (codebook, file ID TJJZNG). Country-year anti-government protests globally, 1990-01-01 → 2020-03-31. Codes participant brackets, 7 demand types, protester-violence flag, and 7 state-response codes. Used for all `*_MM` sub-studies.
- Outcome-specific sources (Census of Governments, V-Dem, Polity V, WDI, QoG, MPV, Stanford Open Policing, MEDSL, NCSL, Archigos/REIGN) are itemized per sub-study in `quality_reports/plans/`.

## Project Structure
- `R/` — Numbered analysis scripts per sub-study per track: `A_US_01_*.R`, `A_MM_01_*.R`, `B_US_01_*.R`, etc.
- `data/raw/` — Downloaded source files (CCC dumps, outcome data).
- `data/intermediate/` — Cleaned per-source files.
- `data/analysis/` — Merged analysis panels + model results.
- `output/figures/` — Publication PDFs.
- `output/figures/slides/` — PNG for decks.
- `output/tables/` — LaTeX tables and `statistics.tex` macros.
- `paper/` — One subdirectory per sub-study manuscript.
- `quality_reports/` — Plans, specs, session logs.

## Conventions
- All file paths via `here::here()` — no absolute paths.
- snake_case throughout.
- Scripts numbered sequentially within sub-study-track prefix: `A_US_01_*.R` … `A_US_12_*.R`; `A_MM_01_*.R` … `A_MM_12_*.R`; etc.
- Statistics exported to `statistics.tex` for LaTeX macros.
- Slide figures: PNG via `ggsave(dpi = 300, bg = "transparent")`.
- Paper figures: PDF via `ggsave(device = cairo_pdf, width = 6.5)`.
- Bibliographies audited against Crossref (>90% DOI coverage target).

## Relationship to Other Projects
- **`protests-spending`** — established the fiscal-inertia / threshold pattern for local-government spending using CCC. Sub-studies prefixed `*_US` extend that infrastructure to new outcomes and violence-conditional treatments.
- **Chenoweth & Stephan rebuttal (separate repo, in progress)** — challenges the 3.5% cliff claim. Sub-studies prefixed `*_MM` provide a cross-national leg using Mass Mobilization event data, with frontier synthetic and DiD estimators.

## Next Steps
- Approve the research-agenda plan in `quality_reports/plans/2026-04-17_research-agenda.md`.
- Pull the MM v5.1 files (codebook DOI:10.7910/DVN/HTTWYL/TJJZNG; data files in the same dataset) into `data/raw/mm/` and the CCC dumps into `data/raw/ccc/`.
- Scaffold `R/A_US_*.R` and `R/A_MM_*.R` pipelines and the two paper subdirectories.
