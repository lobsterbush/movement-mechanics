# =============================================================================
# A_US_04_merge_outcomes.R
# Purpose: Attach the A_US outcome stack to the CCC county-year panel:
#          1. Census of Governments F33 spending by function
#             (public safety, police, fire, corrections, highways, health,
#              welfare, parks & rec, education). Source file: Census COG
#             Individual Unit Files (one ZIP per year under data/raw/cog/).
#          2. Washington Post Fatal Force Database (county-year killings),
#             as a high-quality MPV proxy.
#          3. Stanford Open Policing stop rates (if pulled).
# Inputs:
#   data/intermediate/ccc_county_year.rds              (from A_US_03)
#   data/raw/cog/*_Individual_Unit_File.zip            (from 00_download_cog.R)
#   data/raw/mpv/wapo_fatal_police_shootings.csv       (from 00_download_mpv.R)
#   data/raw/opp/*.csv.zip                             (optional)
# Outputs:
#   data/analysis/a_us_panel.rds
#   output/tables/a_us_outcome_coverage.csv
#   output/tables/a_us_outcome_macros.tex
# =============================================================================

suppressPackageStartupMessages({
  library(here); library(dplyr); library(readr); library(tidyr)
  library(stringr); library(lubridate)
})

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_US_04_merge.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_US_04 Merge outcomes ===")
message("Run at: ", format(Sys.time()))

panel <- readRDS(here("data", "intermediate", "ccc_county_year.rds"))
message("  CCC county-year rows: ", format(nrow(panel), big.mark = ","))

# ---- 1) Census of Governments F33 spending ------------------------------
# F33 item codes we need (current-operations expenditures, thousand-dollar
# units). Source: Census COG F33 Classification Manual,
#   https://www2.census.gov/govs/pubs/classification/2006_classification_manual.pdf
cog_codes <- tribble(
  ~bucket,               ~codes,
  "spend_police",        c("E62"),
  "spend_fire",          c("E24"),
  "spend_corrections",   c("E04", "E05"),
  "spend_public_safety", c("E04", "E05", "E24", "E29", "E62"),
  "spend_highways",      c("E44"),
  "spend_health",        c("E32", "E36"),
  "spend_welfare",       c("E74", "E75", "E77", "E79"),
  "spend_parks_rec",     c("E61"),
  "spend_education",     c("E12", "E16")
)

parse_one_cog_year <- function(zip_path) {
  year_from_name <- as.integer(str_extract(basename(zip_path), "^\\d{4}"))
  if (is.na(year_from_name) || !file.exists(zip_path)) return(NULL)

  tdir <- tempfile("cog_"); dir.create(tdir)
  on.exit(unlink(tdir, recursive = TRUE), add = TRUE)

  inner <- utils::unzip(zip_path, list = TRUE)
  pid_name <- grep("Fin_PID",   inner$Name, value = TRUE)[1]
  dat_name <- grep("FinEstDAT", inner$Name, value = TRUE)[1]
  if (is.na(pid_name) || is.na(dat_name)) return(NULL)
  utils::unzip(zip_path, files = c(pid_name, dat_name), exdir = tdir)

  pid_raw <- readLines(file.path(tdir, pid_name),
                       warn = FALSE, encoding = "latin1")
  # Layout of the 12-char ID code (confirmed via the 2021 public-use tech doc):
  #   chars 1-2:  state FIPS
  #   char  3:    unit type (0=state, 1=county, 2=city, 3=twp, 4=sd, 5=isd)
  #   chars 4-6:  county FIPS (for county governments and dependent units)
  #   chars 7-12: within-county unit identifier
  pid <- tibble(
    id_code     = substr(pid_raw, 1, 12),
    state_fips  = substr(pid_raw, 1, 2),
    type_code   = substr(pid_raw, 3, 3),
    county_fips = substr(pid_raw, 4, 6)
  ) %>%
    filter(type_code == "1") %>%          # county governments only
    mutate(fips_code = paste0(state_fips, county_fips)) %>%
    select(id_code, fips_code)

  # Data file: 32-char fixed-width records
  #   chars 1-12:  ID code
  #   chars 13-15: item code
  #   chars 16-27: amount (thousands of dollars, 12 chars right-padded)
  #   chars 28-31: year
  #   char  32:    imputation flag
  dat_raw <- readLines(file.path(tdir, dat_name),
                       warn = FALSE, encoding = "latin1")
  dat <- tibble(
    id_code   = substr(dat_raw, 1, 12),
    item_code = str_trim(substr(dat_raw, 13, 15)),
    amount    = suppressWarnings(as.numeric(str_trim(substr(dat_raw, 16, 27))))
  )

  county_dat <- inner_join(dat, pid, by = "id_code")
  # Long codebook: each (bucket, item_code) pair on its own row.
  code_long <- cog_codes %>% tidyr::unnest_longer(codes) %>%
    rename(item_code = codes)
  bucket_long <- county_dat %>%
    inner_join(code_long, by = "item_code") %>%
    group_by(bucket, fips_code) %>%
    summarise(amount = sum(amount, na.rm = TRUE), .groups = "drop")

  bucket_wide <- bucket_long %>%
    pivot_wider(names_from = bucket, values_from = amount,
                values_fill = 0) %>%
    mutate(year = year_from_name)

  message("    COG ", year_from_name, " -> ",
          format(nrow(bucket_wide), big.mark = ","), " counties")
  bucket_wide
}

cog_zips <- list.files(here("data", "raw", "cog"),
                       pattern = "Individual_Unit_File.zip$",
                       full.names = TRUE)
if (length(cog_zips) > 0) {
  message("  Parsing COG ZIPs: ", length(cog_zips))
  cog_list <- lapply(cog_zips, function(z)
    tryCatch(parse_one_cog_year(z),
             error = function(e) { message("    failed: ", basename(z),
                                           " / ", e$message); NULL }))
  cog <- bind_rows(cog_list)
  if (!is.null(cog) && nrow(cog) > 0) {
    message("  Joined COG rows: ", format(nrow(cog), big.mark = ","))
    panel <- left_join(panel, cog, by = c("fips_code", "year"))
  } else {
    message("  COG parsed empty; spending outcomes will be NA.")
  }
} else {
  message("  No COG zips found; run R/00_download_cog.R.")
}
spending_cols <- c("spend_public_safety", "spend_police", "spend_fire",
                   "spend_corrections", "spend_highways", "spend_health",
                   "spend_welfare", "spend_parks_rec", "spend_education")
for (col in spending_cols) {
  if (!col %in% names(panel)) panel[[col]] <- NA_real_
}

# ---- 2) Washington Post Fatal Force (MPV-equivalent) --------------------
wapo_path <- here("data", "raw", "mpv", "wapo_fatal_police_shootings.csv")
if (file.exists(wapo_path)) {
  wapo <- read_csv(wapo_path, show_col_types = FALSE, progress = FALSE) %>%
    mutate(
      date = suppressWarnings(ymd(date)),
      year = year(date)
    )
  pep_path <- here("data", "raw", "census", "co-est2020-alldata.csv")
  if (file.exists(pep_path)) {
    crosswalk <- read_csv(pep_path,
                          locale = locale(encoding = "latin1"),
                          show_col_types = FALSE, progress = FALSE) %>%
      filter(as.integer(SUMLEV) == 50) %>%
      transmute(
        fips_code = paste0(str_pad(STATE, 2, "left", "0"),
                           str_pad(COUNTY, 3, "left", "0")),
        state = STNAME,
        county_norm = str_to_lower(
          str_replace(CTYNAME,
                      "\\s(County|Parish|Borough|Census Area|City and Borough|Municipality)$",
                      ""))
      ) %>%
      mutate(state_ab = state.abb[match(state, state.name)]) %>%
      filter(!is.na(state_ab))

    wapo_cnt <- wapo %>%
      filter(!is.na(county), !is.na(state), !is.na(year)) %>%
      mutate(county_norm = str_to_lower(county)) %>%
      left_join(crosswalk %>% select(state_ab, county_norm, fips_code),
                by = c("state" = "state_ab", "county_norm")) %>%
      filter(!is.na(fips_code)) %>%
      count(fips_code, year, name = "mpv_killings")
    panel <- left_join(panel, wapo_cnt, by = c("fips_code", "year")) %>%
      mutate(mpv_killings = replace_na(mpv_killings, 0))
    message("  Joined WaPo fatal shootings: ",
            format(sum(panel$mpv_killings, na.rm = TRUE), big.mark = ","),
            " total county-year killings")
  } else {
    panel$mpv_killings <- NA_real_
    message("  PEP crosswalk missing; WaPo FIPS join skipped.")
  }
} else {
  panel$mpv_killings <- NA_real_
  message("  WaPo file missing; run R/00_download_mpv.R.")
}
panel$mpv_shootings <- panel$mpv_killings  # alias

# ---- 3) Stanford Open Policing (optional pass-through) ------------------
panel$opp_stops_per_cap     <- NA_real_
panel$opp_search_rate       <- NA_real_
panel$ps_use_of_force_score <- NA_real_

# ---- Export -------------------------------------------------------------
dir.create(here("data", "analysis"), showWarnings = FALSE, recursive = TRUE)
saveRDS(panel, here("data", "analysis", "a_us_panel.rds"))
message("\nSaved: data/analysis/a_us_panel.rds (",
        format(nrow(panel), big.mark = ","), " rows)")

cov_tbl <- panel %>%
  summarise(across(
    c(all_of(spending_cols), mpv_killings,
      opp_stops_per_cap, opp_search_rate, ps_use_of_force_score),
    ~ round(100 * mean(!is.na(.x) & .x > 0), 1),
    .names = "pct_nonmiss_nonzero_{.col}"
  )) %>%
  pivot_longer(everything(), names_to = "column",
               values_to = "pct_nonmiss_nonzero")
message("\n-- Outcome non-missing-and-nonzero rates --")
print(as.data.frame(cov_tbl), row.names = FALSE)
write_csv(cov_tbl, here("output", "tables", "a_us_outcome_coverage.csv"))

macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
writeLines(
  c("% Auto-generated by A_US_04_merge_outcomes.R",
    paste0("% Generated: ", Sys.time()),
    macro("AUSPanelNRows",    format(nrow(panel), big.mark = ",")),
    macro("AUSPanelNCounties",
          format(n_distinct(panel$fips_code), big.mark = ",")),
    macro("AUSPanelYearRange",
          paste0(min(panel$year), "--", max(panel$year))),
    macro("AUSMPVKillingsTotal",
          format(sum(panel$mpv_killings, na.rm = TRUE), big.mark = ","))),
  here("output", "tables", "a_us_outcome_macros.tex")
)
message("Wrote macros: output/tables/a_us_outcome_macros.tex")

sink()
