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
Prefix scripts, figures, tables, and manuscript subdirs with the sub-study letter so parallel work does not collide:

| Prefix | Working title | Status |
|--------|---------------|--------|
| A | Nonviolence Premium? | Proposed |
| B | Critical-Mass Gradient vs Cliff | Proposed |
| C | Protest–Police Nexus | Proposed |
| D | Counter-Mobilization Cancellation | Proposed |
| E | Protest–Electoral Sequelae | Proposed |
| F | Issue–Policy Alignment | Proposed |

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
| Callaway-Sant'Anna (2021) | `did` | Staggered binary treatment, heterogeneous effects |
| Sun-Abraham event study | `fixest::sunab()` | Quick event studies, drop-in TWFE replacement |
| de Chaisemartin-D'Haultfœuille | `DIDmultiplegtDYN` | Continuous treatment with switchers |
| Callaway-Goodman-Bacon-Sant'Anna (2024) | `contdid` | Dose-response curves, continuous DiD (package known buggy on dplyr ≥ 1.2; see `protests-spending/MEMORY.md`) |
| Borusyak-Jaravel-Spiess imputation | `didimputation` | Efficient DiD under parallel trends |
| Roth-Sant'Anna (2023) HonestDiD | `HonestDiD` | Sensitivity of DiD results to parallel-trends violations |
| Butts (2023) spatial DiD | `bacondecomp` + custom | Neighbor spillovers |

---

## Commands
```bash
# Run a sub-study pipeline end to end (example: sub-study A)
cd /path/to/movement-mechanics
for f in R/A_*.R; do Rscript "$f"; done

# Single script
Rscript R/A_01_clean_ccc.R

# Compile a sub-study paper
cd paper/A_nonviolence_premium && pdflatex paper.tex && bibtex paper && pdflatex paper.tex && pdflatex paper.tex
```

---

## Quality Thresholds
| Score | Gate | Meaning |
|-------|------|---------|
| 80 | Commit | Good enough to save |
| 90 | PR | Ready for sharing |
| 95 | Excellence | Publication-ready |
