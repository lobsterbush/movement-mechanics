# Movement Mechanics
**Status:** Draft (research agenda; no empirical scripts yet).
**Description:** County-level causal tests of how protest movements translate into downstream political, fiscal, and electoral outcomes, using Crowd Counting Consortium Phase 1+2 event data and frontier TWFE/DiD estimators. Designed to supplement the `protests-spending` paper (Crabtree & Holbein) and a parallel rebuttal of Chenoweth & Stephan's (2011) 3.5% critical-mass claim.
**Authors:** Charles Crabtree (Monash / Korea University); co-authors TBD per sub-study.
**Last Updated:** 2026-04-17

## Tech Stack
- **Language:** R (≥ 4.1.0)
- **Key packages:** `tidyverse`, `fixest`, `did` (Callaway-Sant'Anna), `DIDmultiplegtDYN` (de Chaisemartin-D'Haultfœuille), `contdid` (Callaway-Goodman-Bacon-Sant'Anna), `didimputation` (Borusyak-Jaravel-Spiess), `HonestDiD` (Rambachan-Roth), `staggered` (Roth-Sant'Anna), `sf`, `tigris`, `ggplot2`, `ggthemes`
- **Paper(s):** LaTeX (Palatino, 1-in margins, double-spaced, apacite); one manuscript per completed sub-study, all sharing this repo's bibliography and data pipeline.
- **Visualization:** `ggplot2` + `theme_tufte()`; PDF via `cairo_pdf` for papers; PNG (300 dpi, transparent bg) for slides.
- **Standard errors:** Clustered by county throughout; `HonestDiD` sensitivity for DiD estimates.
- **Deployment:** No public website yet. Slides (if any) will live at `slides.html` and `index.html` on GitHub Pages once a sub-study is ready to share.

## Data Sources
- **Crowd Counting Consortium (CCC), Harvard Dataverse DOI:10.7910/DVN/HTTWYL** — Phase 1 (2017–2020) + Phase 2 (2021–present). 212K+ geocoded protest events with crowd size, issue tags, position tags, incident indicators (property damage, arrests, injuries).
- Outcome-specific sources vary by sub-study; see `quality_reports/plans/`.

## Project Structure
- `R/` — Numbered analysis scripts (01–nn), one pipeline per sub-study prefix (`A_`, `B_`, ...).
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
- Scripts numbered sequentially within sub-study prefix: `A_01_*.R`, `A_02_*.R`, etc.
- Statistics exported to `statistics.tex` for LaTeX macros.
- Slide figures: PNG via `ggsave(dpi = 300, bg = "transparent")`.
- Paper figures: PDF via `ggsave(device = cairo_pdf, width = 6.5)`.
- Bibliographies audited against Crossref (>90% DOI coverage target).

## Relationship to Other Projects
- **`protests-spending`** — established the fiscal-inertia / threshold pattern for local government spending. This repo extends the same CCC treatment to other outcome domains and other estimators.
- **Chenoweth & Stephan rebuttal (TBD repo)** — challenges the 3.5% cliff finding. This repo contributes county-level evidence on (a) whether effects scale continuously vs cliff, (b) whether nonviolence discipline matters, and (c) whether critical-mass logic transfers from regime change to routine policy.

## Next Steps
- Finalize which two sub-studies to pursue first (see `quality_reports/plans/2026-04-17_research-agenda.md`).
- Pull the CCC Phase 2 dump from Harvard Dataverse (DOI:10.7910/DVN/HTTWYL/TJJZNG, version 5.1) into `data/raw/`.
- Set up shared CCC cleaning scripts that both `protests-spending` and this repo can reuse.
