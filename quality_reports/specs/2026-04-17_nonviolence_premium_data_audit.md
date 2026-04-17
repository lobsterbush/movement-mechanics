# Data Quality Audit — Nonviolence Premium (A_US + A_MM)
**Date:** 2026-04-17
**Run by:** `R/00_sync_ccc.R` + `R/00_download_mm.R` + `R/A_US_01_audit_ccc.R` + `R/A_MM_01_audit_mm.R`
**Session log:** `quality_reports/session_logs/2026-04-17_A_US_01_audit.log`, `2026-04-17_A_MM_01_audit.log`
**Verdict:** Both papers are feasible. Three design items need decisions before we build the panels.

## Data on Disk
| Source | Files | Rows | Provenance |
|--------|-------|------|------------|
| CCC Phase 1 + Phase 2 | `ccc_compiled.csv` (72,181 rows), `ccc_compiled_2021_present.csv` (139,823 rows) | 212,004 events | Mirrored from `../protests-spending/data/raw/ccc/` via `R/00_sync_ccc.R`; MANIFEST.yml with MD5 committed. |
| Mass Mobilization v5.1 | `mmALL_073120_csv.tab`, `mmALL_073120_v16.tab`, `MM_users_manual_0515.pdf` | 17,145 events | Harvard Dataverse DOI:10.7910/DVN/HTTWYL, downloaded 2026-04-17; MANIFEST.yml committed. Codebook MD5 verified; tab-delivered events files have size-identical but MD5-different payloads relative to the stored upload checksum (see [LEARN:dataverse] in MEMORY.md). |

## CCC — Findings (Track A_US)
### Coverage
CCC is dense and complete: 99.8% of events geocode to a FIPS5 county across every year in 2017–2024. County reach peaks at 1,647 counties in 2020 and stays > 1,000 every year.

### Violence base rates
Violent events are rare but consistent. Under the strict definition (any of `property_damage_any`, `arrests_any`, `injuries_crowd_any`, `injuries_police_any`, `chemical_agents`), the share of violent events is 1.2–2.5% in most years and spikes to **6.1% in 2020**. Under the permissive (protester-instigated) definition (`pd | ar | ic`) the share is almost identical (because `chemical_agents` and police-injury events are almost always co-coded with at least one protester-instigated flag). The no-arrest definition (`pd | ic` only) runs 0.2–1.2%.

### Co-occurrence
Incident flags are positively but not strongly correlated (pairwise phi 0.16–0.30). The biggest single-flag category is arrests-only (2,795 events), then property-damage-only (789). Only 48 events out of 212,004 trip all five flags. Flags are measuring distinct dimensions of event severity, so the three candidate violence definitions will deliver distinguishable estimates — exactly what the design needs.

### Sample construction
| Step | Events |
|------|--------|
| Raw Phase 1 + 2 | 212,004 |
| + valid FIPS5 | 211,771 |
| + year in 2017–2023 | 171,427 |
| + not online-only | 171,039 |
| + non-missing `size_mean` (core sample) | **70,905** |

Roughly **58% of events are missing `size_mean`, and the missingness grows with time** (60% coverage in 2017 → 30% in 2024). That is the biggest threat to the A_US design if we commit to a crowd-size-weighted continuous treatment.

## MM — Findings (Track A_MM)
### Coverage
17,145 events over 1990–2020-03-31 across ~162 countries. Variable inventory matches the codebook: `country`, `year`, `protest`, `protesterviolence`, `participants` / `participants_category`, `protesterdemand1–4`, `stateresponse1–7`. 31 columns total.

### `protesterviolence`
- Nonviolent (0): 11,723 events (68.4%)
- Violent (1):  4,035 events (23.5%)
- NA:           1,387 events (8.1%)

A 23.5% global violence rate is an order of magnitude higher than CCC's US rate — consistent with MM coding anti-government protests specifically and including regimes with active repression. Perfect for cross-scale comparison with A_US.

### `participants_category`
Seven brackets. Biggest single cell is **`NA` at 42.3%**. Populated brackets:
- 100–999: 18.7%
- 50–99: 14.6%
- 2000–4999: 9.2%
- \>10000: 8.6%
- 5000–10000: 3.7%
- 1000–1999: 2.8%

Critical-mass and dose-gradient work require imputable participant counts. 42% NA is survivable if we (a) treat NA as its own stratum and (b) use event counts as the primary intensity measure with participant-weighted intensity as a robustness check.

### `protesterdemand`
All seven codebook categories present. Dominant: *political behavior / process* (57.7%), then *labor wage dispute* (11.9%), *removal of politician* (10.2%), *price increases / tax policy* (7.6%), *police brutality* (5.9%), *social restrictions* (3.7%), *land / farm issue* (3.1%). Sub-study F (issue–policy alignment) will use these directly.

### `stateresponse`
Seven codebook categories present, dominated by *ignore* (42.8%) and *crowd dispersal* (24.8%). Repression categories (shootings 4.8%, killings 4.3%, beatings 4.2%) are each above 3% — enough to support a separate state-response moderation sub-study later.

## Design Decisions Needed Before Panel Build
1. **CCC intensity measure under high `size_mean` missingness.** Three options: (a) use event counts as primary, size-weighted as robustness; (b) multiply-impute `size_mean` from `size_low`/`size_high`/`size_mean_low`/`size_mean_high` (where available) and event characteristics; (c) restrict the panel to the 70,905 size-observed events and acknowledge the late-period selectivity. My recommendation: (a) event counts as primary treatment, dose-response with observed `size_mean` as the headline intensity robustness check, and HonestDiD sensitivity with imputation bounds as the belt-and-braces.
2. **MM participant NA handling.** Recommendation: treat `participants_category == NA` as its own stratum (dummy variable); use event counts as primary intensity; bracket midpoints as dose-response intensity robustness check.
3. **Violence definition for each paper's headline.** Recommend strict (any flag) as the primary for A_US so readers can compare to the widely-cited CCC incident flags; permissive as A_US robustness. For A_MM use MM's native `protesterviolence` flag directly, with an NA-excluded subsample as robustness.

## Next Scripts After These Three Decisions
- `R/A_US_02_build_panel.R` — CCC events → county-year panel with nonviolent/violent/unknown split.
- `R/A_MM_02_build_panel.R` — MM events → country-year panel with violence share, total event count, participant-weighted intensity.
- `R/A_US_03_merge_outcomes.R` / `R/A_MM_03_merge_outcomes.R` — join Census of Governments / MPV / Open Policing (US) and V-Dem / Polity / WDI (global).
- `R/A_US_04_estimate.R` / `R/A_MM_04_estimate.R` — CS-DiD with violence interaction.
