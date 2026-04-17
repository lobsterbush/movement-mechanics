# Project Memory
Corrections and learned facts that persist across sessions. When a mistake is corrected, append a `[LEARN:category]` entry below.

---

## Pre-seeded from `protests-spending`
- `[LEARN:data-id]` DOI:10.7910/DVN/HTTWYL is **Mass Mobilization** (Clark & Regan), NOT Crowd Counting Consortium. File ID `TJJZNG` within it is the MM codebook PDF (`MM_users_manual_0515.pdf`). Earlier session conflated the two. CCC lives on a separate Dataverse. Always confirm dataset identity via the Dataverse API (`/api/datasets/:persistentId?persistentId=doi:...`) before downloading.
- `[LEARN:ccc]` CCC Dataverse Phase 1 uses column `issues`; Phase 2 uses `issue_tags`. Must rename before binding. Also: `actors` → `organizations`.
- `[LEARN:ccc]` CCC Phase 2 is monthly-updated; always record download date and version in raw-data metadata.
- `[LEARN:contdid]` `contdid` v0.1.0 is incompatible with dplyr ≥ 1.2 / tibble ≥ 3.3. Fails with "'-' only defined for equally-sized data frames". Wait for upstream fix or use `DIDmultiplegtDYN` instead.
- `[LEARN:r-env]` `here::here()` resolves from the first root marker (needs `.here` or `.Rproj`). Scripts must be run from the project directory.
- `[LEARN:estimation]` Linear TWFE with continuous protest intensity can mask a nonlinear threshold. Always run dose-response quartiles and threshold sweeps before concluding null.
- `[LEARN:treatment]` BLM-specific treatment introduces severe compositional confounding (urbanization, ARPA). All-protest intensity is the cleaner measure; report BLM as robustness.
- `[LEARN:writing]` Never claim "monotonically" unless strictly monotonic at every point. Use "generally strengthen" or "robust across thresholds".

## Sub-study-specific learnings
- `[LEARN:dataverse]` Harvard Dataverse delivers ingested tabular files (`.tab`) whose MD5 differs from the stored-upload MD5 on the file record (the stored hash is of the original `.csv`/`.dta` submission). File **size** still matches exactly, so verify integrity via size + row/column counts, not only MD5. MM events files triggered this on 2026-04-17; the codebook PDF verified cleanly.
- `[LEARN:A_US-ccc]` CCC `size_mean` missingness is 40–70% depending on year and rises over time (60% populated in 2017 → 30% in 2024). Any design that hinges on crowd-size-weighted intensity without an imputation strategy will silently select on post-2020 observability. Event counts are the safest primary treatment; size is a robustness check.
- `[LEARN:A_US-ccc]` Strict, permissive, and no-arrest violence definitions in CCC yield almost identical aggregate violence shares (1–3% in normal years, ~6% in 2020). They separate sharply only in the Q4 tail, which is the relevant tail for the nonviolence premium. Always report all three.
- `[LEARN:A_MM-mm]` MM `participants_category` is 42.3% NA. Treat NA as its own category in the panel — dropping NAs would eject nearly half the global protest record.
- `[LEARN:A_MM-mm]` MM's native `protesterviolence` flag is 23.5% violent / 68.4% nonviolent / 8.1% NA. This is an order of magnitude higher than CCC's US rate, consistent with MM restricting coverage to anti-government protests. The cross-scale contrast is a feature, not a bug.
