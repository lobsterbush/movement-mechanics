# Movement Mechanics
County-level causal tests of how protest movements translate into downstream political, fiscal, and electoral outcomes in the United States, 2017–2024.

## Authors
Charles Crabtree, Senior Lecturer, School of Social Sciences, Monash University and K-Club Professor, University College, Korea University. Co-authors TBD per sub-study.

## Overview
This repository hosts a research agenda rather than a single paper. Each sub-study tests a specific mechanism linking protest activity (measured by the Crowd Counting Consortium) to a concrete policy or political outcome, using heterogeneity-robust difference-in-differences designs. The agenda is designed to supplement two parallel projects:

1. **[`protests-spending`](../protests-spending/)** — establishes a fiscal-inertia / threshold finding for local government spending under all-protest intensity.
2. **Chenoweth & Stephan rebuttal (separate repo, in progress)** — challenges the 3.5% critical-mass claim from *Why Civil Resistance Works* (2011).

Proposed sub-studies include the nonviolence premium, the critical-mass gradient vs cliff, protest–police use-of-force dynamics, counter-mobilization cancellation, protest–electoral sequelae, and issue–policy alignment. See `quality_reports/plans/2026-04-17_research-agenda.md` for the full menu.

## Requirements
- R ≥ 4.1.0 with: `tidyverse`, `fixest`, `did`, `DIDmultiplegtDYN`, `contdid`, `didimputation`, `HonestDiD`, `staggered`, `sf`, `tigris`, `ggplot2`, `ggthemes`, `here`.
- LaTeX (XeLaTeX or pdfLaTeX) for manuscript compilation.
- Optional: Python 3.10+ for API-side data pulls (BLS, Census, NCSL).

## Replication
Each sub-study lives under its letter prefix (`A_`, `B_`, ...). To replicate a locked sub-study:
```bash
git clone https://github.com/<user>/movement-mechanics.git
cd movement-mechanics
# Pull CCC data from Harvard Dataverse (DOI:10.7910/DVN/HTTWYL, v5.1)
Rscript R/00_download_ccc.R
# Run a specific sub-study pipeline
for f in R/A_*.R; do Rscript "$f"; done
# Compile its paper
cd paper/A_nonviolence_premium && pdflatex paper.tex && bibtex paper && pdflatex paper.tex && pdflatex paper.tex
```

Once a sub-study is locked, that sub-study's subdirectory will carry its own README with a frozen replication manifest and AEA-style data/code availability statement.

## Status
Draft. The research agenda is written up; no empirical scripts have been committed yet.
