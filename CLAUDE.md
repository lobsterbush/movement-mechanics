# CLAUDE.MD — Movement Mechanics
**Project:** Movement Mechanics — county-level causal tests of protest impact
**Author:** Charles Crabtree, Monash University / Korea University
**Branch:** main

---

## Core Principles
- **Plan first** — enter plan mode before non-trivial tasks; save plans to `quality_reports/plans/`.
- **Verify after** — run scripts and confirm output at the end of every task.
- **Quality gates** — nothing ships below 80/100.
- **[LEARN] tags** — when corrected, save `[LEARN:category] wrong → right` to [MEMORY.md](MEMORY.md).
- **One sub-study at a time** — this repo hosts a research agenda; do not start a new sub-study before the prior one clears the 80/100 gate.

Cross-session context lives in [MEMORY.md](MEMORY.md); plans and session logs are in [quality_reports/](quality_reports/).

---

## Folder Structure
```
movement-mechanics/
├── CLAUDE.md                    # This file
├── WARP.md                      # Project metadata
├── .claude/                     # Rules, hooks
├── R/                           # Analysis scripts, prefixed by sub-study (A_, B_, ...)
├── data/
│   ├── raw/                     # CCC dumps, outcome sources
│   ├── intermediate/            # Cleaned per-source .rds
│   └── analysis/                # Merged panels + results .rds
├── output/
│   ├── figures/                 # Publication PDFs
│   ├── figures/slides/          # Title-free PNG for reveal.js
│   └── tables/                  # LaTeX tables + statistics.tex
├── paper/                       # Per-sub-study manuscripts
├── quality_reports/             # Plans, specs, session logs
└── templates/                   # Session log, quality report templates
```

---

## Sub-study Naming
Every sub-study runs on both data tracks where the outcomes support it. Prefix scripts, figures, tables, and manuscript subdirs with `<letter>_<track>` so parallel work never collides:

| Prefix | Working title | Data track | Status |
|--------|---------------|------------|--------|
| A_US | Nonviolence Premium (CCC, US county-year) | CCC | **Next** |
| A_MM | Nonviolence Premium (MM, global country-year) | MM  | **Next** |
| B_US | Critical-Mass Gradient vs Cliff | CCC | Queued |
| B_MM | Critical-Mass Gradient vs Cliff | MM  | Queued |
| C_US | Protest–Police Nexus | CCC | Queued |
| D_US / D_MM | Counter-Mobilization Cancellation | both | Queued |
| E_US / E_MM | Protest–Electoral / Executive Sequelae | both | Queued |
| F_US / F_MM | Issue–Policy Alignment | both | Queued |

A_US and A_MM are companion papers written on a shared theoretical frame. Ship them together.

See `quality_reports/plans/2026-04-17_research-agenda.md` for full descriptions.

---

## R Code Standards
- **Paths:** `here::here()` only — no absolute paths.
- **Packages:** `library()` at the top of every script; record versions with `renv` once a sub-study is locked.
- **SE convention:** Clustered by county. Use `HonestDiD` sensitivity for all DiD estimates.
- **Figures (publication):** PDF via `ggsave(device = cairo_pdf, width = 6.5)`.
- **Figures (slides):** PNG, 300 dpi, 10–12" wide, transparent bg, title-free.
- **Theme:** `theme_tufte()` for publication; custom `theme_slide()` for decks.

### Project Palette
```r
accent     <- "#3730a3"   # indigo
accent2    <- "#6366f1"   # lighter indigo
muted      <- "#94a3b8"   # slate
neg_col    <- "#be123c"   # rose — significant negative
pos_col    <- "#059669"   # emerald — significant positive
null_col   <- "#94a3b8"   # slate — not significant
text_col   <- "#334155"   # slate-700 — annotations
warn       <- "#d97706"   # amber — warnings
```

Palette matches `protests-spending` so figures can be used across both projects without restyling.

---

## Estimator Cheat Sheet
| Estimator | R package | Use when |
|-----------|-----------|----------|
| Callaway-Sant'Anna (2021) | `did` | Staggered binary treatment, heterogeneous effects. Works for both tracks. |
| Sun-Abraham event study | `fixest::sunab()` | Quick event studies, drop-in TWFE replacement. Both tracks. |
| de Chaisemartin-D'Haultfœuille | `DIDmultiplegtDYN` | Continuous treatment with switchers. Both tracks. |
| Callaway-Goodman-Bacon-Sant'Anna (2024) | `contdid` | Dose-response curves, continuous DiD. Package known buggy on dplyr ≥ 1.2 — see `MEMORY.md`. |
| Borusyak-Jaravel-Spiess imputation | `didimputation` | Efficient DiD under parallel trends. Both tracks. |
| Synthetic DiD (Arkhangelsky et al. 2021) | `synthdid` | **MM track primary** — small-N country panels with unit heterogeneity. |
| Augmented synthetic control | `augsynth` | **MM track** — when synthetic control pre-trend fit is poor. |
| Imai-Kim-Wang matching | `PanelMatch` | **MM track** — dynamic TSCS with many covariates. |
| Local-projections DiD (DGJT 2023) | `lpdid` | Dynamic multipliers over 1-, 2-, 4-year horizons. Both tracks. |
| Roth-Sant'Anna (2023) HonestDiD | `HonestDiD` | Sensitivity of DiD results to parallel-trends violations. Both tracks. |
| Butts (2023) spatial DiD | `bacondecomp` + custom | Neighbor spillovers. CCC track only. |

---

## Commands
```bash
# Run a sub-study pipeline end to end
cd /path/to/movement-mechanics
for f in R/A_US_*.R; do Rscript "$f"; done   # CCC nonviolence premium
for f in R/A_MM_*.R; do Rscript "$f"; done   # MM nonviolence premium

# Single script
Rscript R/A_US_03_split_by_violence.R

# Compile a sub-study paper
cd paper/A_nonviolence_premium_us && pdflatex paper.tex && bibtex paper && pdflatex paper.tex && pdflatex paper.tex
cd paper/A_nonviolence_premium_mm && pdflatex paper.tex && bibtex paper && pdflatex paper.tex && pdflatex paper.tex
```

---

## Quality Thresholds
| Score | Gate | Meaning |
|-------|------|---------|
| 80 | Commit | Good enough to save |
| 90 | PR | Ready for sharing |
| 95 | Excellence | Publication-ready |
