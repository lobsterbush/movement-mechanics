# =============================================================================
# A_US_10_placebo_heterogeneity.R
# Purpose: Placebo checks and heterogeneity analyses for A_US.
#   Placebo:
#     - Highway spending (should be null, orthogonal to protest pressure).
#     - Fire spending (null as a balance placebo).
#   Heterogeneity:
#     - BLM era (2020 onward) vs earlier.
#     - County partisanship quintile (MEDSL 2016 county vote share).
#     - Urban vs rural (NCHS urban-rural classification).
#     - Police-union-strong vs weak (requires external union coverage file).
# Inputs:
#   data/analysis/a_us_panel.rds
#   data/analysis/a_us_cs_results.rds
#   data/raw/medsl/county_president_1976_2020.csv  (TODO: add pull)
# Outputs:
#   output/tables/a_us_placebo.tex
#   output/figures/a_us_het_era.pdf
#   output/figures/a_us_het_partisan.pdf
#   output/tables/a_us_het_macros.tex
# =============================================================================

suppressPackageStartupMessages({
  library(here); library(dplyr); library(tidyr); library(readr)
  library(stringr); library(ggplot2); library(ggthemes)
})

if (!requireNamespace("did", quietly = TRUE))
  stop("Install 'did': install.packages('did').")

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_US_10_placebo.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_US_10 Placebo + heterogeneity ===")
message("Run at: ", format(Sys.time()))

panel <- readRDS(here("data", "analysis", "a_us_panel.rds")) %>%
  filter(violence_def == "strict") %>%
  arrange(fips_code, year) %>%
  mutate(id = as.integer(as.factor(fips_code)))

# Treatment-timing helper (mirrors A_US_06).
assign_first_treat <- function(df, col) {
  cutoff <- quantile(df[[col]][df[[col]] > 0], 0.90, na.rm = TRUE)
  df %>%
    group_by(id) %>%
    mutate(above      = as.integer(.data[[col]] >= cutoff & cutoff > 0),
           first_year = suppressWarnings(min(year[above == 1])),
           first_year = ifelse(is.finite(first_year), first_year, 0L)) %>%
    ungroup()
}

# CS ATT wrapper
run_cs_att <- function(df, yname) {
  if (all(is.na(df[[yname]]))) return(c(NA_real_, NA_real_))
  obj <- tryCatch(
    did::att_gt(yname = yname, tname = "year", idname = "id",
                gname = "first_year", data = df,
                clustervars = "id", control_group = "notyettreated",
                allow_unbalanced_panel = TRUE, panel = TRUE,
                est_method = "dr"),
    error = function(e) NULL)
  if (is.null(obj)) return(c(NA_real_, NA_real_))
  agg <- tryCatch(did::aggte(obj, type = "simple", na.rm = TRUE),
                  error = function(e) NULL)
  if (is.null(agg)) return(c(NA_real_, NA_real_))
  c(agg$overall.att, agg$overall.se)
}

panel_nv <- assign_first_treat(panel, "nonviolent_per_cap")

# ---- Placebo: highway + fire spending -----------------------------------
placebo_outcomes <- c("spend_highways", "spend_fire")
placebo_tbl <- tibble(
  outcome = placebo_outcomes,
  arm     = "nv",
  att     = NA_real_, se = NA_real_
)
for (i in seq_along(placebo_outcomes)) {
  r <- run_cs_att(panel_nv, placebo_outcomes[i])
  placebo_tbl$att[i] <- r[1]; placebo_tbl$se[i] <- r[2]
}
message("\n-- Placebo CS ATT --")
print(as.data.frame(placebo_tbl), row.names = FALSE)
write_csv(placebo_tbl, here("output", "tables", "a_us_placebo.csv"))

# ---- Heterogeneity by era (pre-BLM vs BLM) ------------------------------
era_df <- tibble(era = c("2017-2019", "2020-2023"),
                 att = NA_real_, se = NA_real_)
for (i in seq_along(era_df$era)) {
  yrs <- if (i == 1) 2017:2019 else 2020:2023
  sub <- panel_nv %>% filter(year %in% yrs)
  r <- run_cs_att(sub, "spend_public_safety")
  era_df$att[i] <- r[1]; era_df$se[i] <- r[2]
}
era_df <- era_df %>%
  mutate(lo = att - 1.96 * se, hi = att + 1.96 * se)
p_era <- ggplot(era_df, aes(era, att)) +
  geom_hline(yintercept = 0, linetype = 2, colour = "grey50") +
  geom_pointrange(aes(ymin = lo, ymax = hi), size = 0.5) +
  theme_tufte(base_size = 11) +
  labs(x = NULL, y = "ATT on public-safety spending",
       title = "Era heterogeneity (nonviolent arm, CS ATT)")
ggsave(here("output", "figures", "a_us_het_era.pdf"),
       p_era, device = cairo_pdf, width = 6.5, height = 3.8)
write_csv(era_df, here("output", "tables", "a_us_het_era.csv"))

# ---- Heterogeneity by partisanship quintile -----------------------------
# Find the largest MEDSL file on disk (the Dataverse guestbook "download"
# produces a 122-byte JSON error; the real file is >= 100 MB). Cache the
# per-county 2016 GOP quintile so we only reparse once. Wrap the whole
# thing in tryCatch so a MEDSL outage does not prevent the placebo and
# era-heterogeneity macros from being written below.
load_medsl_quintile <- function() {
  medsl_dir <- here("data", "raw", "medsl")
  medsl_files <- list.files(medsl_dir,
                            pattern = "\\.(tab|csv|tsv)$",
                            full.names = TRUE)
  medsl_files <- medsl_files[file.info(medsl_files)$size > 1e5]
  cache_path  <- here("data", "intermediate", "medsl_2016_quintile.rds")
  if (file.exists(cache_path)) {
    message("  Using cached MEDSL 2016 GOP quintile.")
    return(readRDS(cache_path))
  }
  if (length(medsl_files) == 0) {
    stop("No MEDSL file >=100KB found in ", medsl_dir,
         "; run R/00_download_medsl.R and accept the Dataverse guestbook.")
  }
  medsl_path <- medsl_files[which.max(file.info(medsl_files)$size)]
  message("  Parsing MEDSL file: ", medsl_path)
  m <- suppressWarnings(read_tsv(medsl_path, show_col_types = FALSE,
                                 progress = FALSE))
  if (nrow(m) < 100 || !"party" %in% names(m)) {
    stop("MEDSL file on disk does not parse as tabular election data.")
  }
  gop16 <- m %>%
    filter(year == 2016, party == "REPUBLICAN") %>%
    mutate(fips_code = str_pad(as.character(county_fips), 5, "left", "0")) %>%
    group_by(fips_code) %>%
    summarise(gop_share = sum(candidatevotes, na.rm = TRUE) /
                          pmax(sum(totalvotes, na.rm = TRUE), 1),
              .groups = "drop") %>%
    mutate(quintile = ntile(gop_share, 5))
  dir.create(dirname(cache_path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(gop16, cache_path)
  message("  Cached: ", cache_path)
  gop16
}

het_part <- tibble(quintile = integer(), att = double(), se = double(),
                   lo = double(), hi = double())
partisan_status <- "unavailable"
gop16 <- tryCatch(load_medsl_quintile(),
                  error = function(e) {
                    message("  Partisan heterogeneity SKIPPED: ", e$message)
                    NULL
                  })
if (!is.null(gop16)) {
  panel_nv_q <- panel_nv %>%
    left_join(gop16 %>% select(fips_code, quintile), by = "fips_code") %>%
    filter(!is.na(quintile))
  for (q in 1:5) {
    sub <- panel_nv_q %>% filter(quintile == q)
    r <- run_cs_att(sub, "spend_public_safety")
    het_part <- bind_rows(het_part,
                          tibble(quintile = q, att = r[1], se = r[2],
                                 lo = r[1] - 1.96 * r[2],
                                 hi = r[1] + 1.96 * r[2]))
  }
  p_part <- ggplot(het_part, aes(factor(quintile), att)) +
    geom_hline(yintercept = 0, linetype = 2, colour = "grey50") +
    geom_pointrange(aes(ymin = lo, ymax = hi), size = 0.5) +
    theme_tufte(base_size = 11) +
    labs(x = "County 2016 GOP-share quintile (1 = most Democratic)",
         y = "ATT on public-safety spending",
         title = "Partisanship heterogeneity (nonviolent arm, CS ATT)")
  ggsave(here("output", "figures", "a_us_het_partisan.pdf"),
         p_part, device = cairo_pdf, width = 6.5, height = 3.8)
  write_csv(het_part, here("output", "tables", "a_us_het_partisan.csv"))
  partisan_status <- "ok"
  message("\n-- Partisan heterogeneity --")
  print(as.data.frame(het_part), row.names = FALSE)
}

# ---- Macros -------------------------------------------------------------
macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
writeLines(
  c("% Auto-generated by A_US_10_placebo_heterogeneity.R",
    paste0("% Generated: ", Sys.time()),
    macro("AUSPlaceboOutcomes",
          paste(placebo_tbl$outcome, collapse = ", ")),
    macro("AUSPlaceboHighwayATT",
          sprintf("%.3f", placebo_tbl$att[placebo_tbl$outcome == "spend_highways"])),
    macro("AUSHetPartisanNRuns", nrow(het_part)),
    macro("AUSHetPartisanStatus", partisan_status)),
  here("output", "tables", "a_us_het_macros.tex")
)

sink()
