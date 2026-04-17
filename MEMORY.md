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
(Add as `[LEARN:A-...]`, `[LEARN:B-...]`, etc. once work begins.)
