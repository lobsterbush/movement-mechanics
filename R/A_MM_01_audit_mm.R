# =============================================================================
# A_MM_01_audit_mm.R
# Purpose: Initial data quality audit of the Mass Mobilization (Clark & Regan)
#          v5.1 events file for the Nonviolence Premium analysis (A_MM).
#          Answers:
#            - What columns exist in the distributed events file?
#            - Country × year coverage (how many country-years have any event?)
#            - Distribution of participant-size brackets
#            - Distribution of the protesterviolence flag
#            - Distribution of the 7 state-response codes
#            - Distribution of the 7 demand-type codes
#            - NA rates on every variable we plan to use
# Inputs:  data/raw/mm/mmALL_073120_csv.tab  (tab-separated)
# Outputs: output/tables/mm_audit_variables.csv
#          output/tables/mm_audit_yearly.csv
#          output/tables/mm_audit_violence.csv
#          output/tables/mm_audit_state_response.csv
#          output/tables/mm_audit_demands.csv
#          output/tables/mm_audit_macros.tex
#          quality_reports/session_logs/<date>_A_MM_01_audit.log
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(readr)
  library(dplyr)
  library(stringr)
  library(tidyr)
  library(janitor)
})

log_path <- here("quality_reports", "session_logs",
                 format(Sys.Date(), "%Y-%m-%d_A_MM_01_audit.log"))
dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE)
sink(log_path, split = TRUE)

message("=== A_MM_01 Mass Mobilization audit ===")
message("Run at: ", format(Sys.time()))

mm_path <- here("data", "raw", "mm", "mmALL_073120_csv.tab")
if (!file.exists(mm_path)) {
  stop("MM tab file not found: ", mm_path,
       "\n  Run R/00_download_mm.R first.")
}

message("  Reading ", mm_path, " ...")
mm <- read_tsv(mm_path, guess_max = 200000,
               show_col_types = FALSE, progress = FALSE)
mm <- clean_names(mm)
message("  rows=", format(nrow(mm), big.mark = ","),
        "  cols=", ncol(mm))

# ---- Variable inventory ---------------------------------------------------
var_inventory <- tibble(
  variable  = names(mm),
  class     = vapply(mm, function(x) class(x)[1], character(1)),
  n_na      = vapply(mm, function(x) sum(is.na(x)), integer(1)),
  pct_na    = round(100 * vapply(mm, function(x) mean(is.na(x)), numeric(1)), 2),
  n_unique  = vapply(mm, function(x) dplyr::n_distinct(x), integer(1))
)
message("\n-- Variable inventory (head) --")
print(as.data.frame(head(var_inventory, 40)))

# ---- Identify the variables we need ---------------------------------------
# MM codebook canonical names: country, year, protest, protestnumber,
# startday, startmonth, startyear, endday, endmonth, endyear, protesterviolence,
# participants, participants_category, protesteridentity, protesterdemand1..4,
# stateresponse1..7.
# Clark & Regan sometimes deliver these with slight variant casings, so we
# match on a normalized stem.
find_var <- function(stems, available) {
  pat <- paste0("^", paste(stems, collapse = "|"), "$")
  hit <- grep(pat, available, value = TRUE, ignore.case = TRUE)
  if (length(hit) == 0) NA_character_ else hit[1]
}

vcountry <- find_var(c("country"), names(mm))
vyear    <- find_var(c("year"),    names(mm))
vprotest <- find_var(c("protest"), names(mm))
vviol    <- find_var(c("protesterviolence", "protester_violence"), names(mm))
vpart    <- find_var(c("participants", "participants_category",
                       "participantscategory"), names(mm))
vdemand  <- grep("^protesterdemand[0-9]+$", names(mm), value = TRUE)
vresp    <- grep("^stateresponse[0-9]+$",   names(mm), value = TRUE)

key_vars <- c(country = vcountry, year = vyear, protest = vprotest,
              violence = vviol,   participants = vpart)
message("\n-- Key variable mapping --")
print(key_vars)
message("  demand columns: ", paste(vdemand, collapse = ", "))
message("  state-response columns: ", paste(vresp,   collapse = ", "))

# ---- Country × year coverage ----------------------------------------------
if (!is.na(vcountry) && !is.na(vyear) && !is.na(vprotest)) {
  cy_tbl <- mm %>%
    mutate(is_protest = .data[[vprotest]] == 1 | .data[[vprotest]] == "1") %>%
    filter(isTRUE(is_protest) | is_protest %in% TRUE) %>%
    group_by(year = .data[[vyear]]) %>%
    summarise(
      n_events    = n(),
      n_countries = n_distinct(.data[[vcountry]]),
      .groups = "drop"
    ) %>%
    arrange(year)

  message("\n-- Yearly coverage (protest == 1) --")
  print(as.data.frame(cy_tbl), row.names = FALSE)
} else {
  cy_tbl <- tibble()
  message("WARNING: cannot build yearly coverage \u2014 key variables missing.")
}

# ---- Violence flag --------------------------------------------------------
if (!is.na(vviol)) {
  viol_tbl <- mm %>%
    count(.data[[vviol]], name = "n") %>%
    mutate(pct = round(100 * n / sum(n), 2)) %>%
    rename(protesterviolence = 1)
  message("\n-- protesterviolence distribution --")
  print(as.data.frame(viol_tbl), row.names = FALSE)
} else {
  viol_tbl <- tibble()
  message("WARNING: protesterviolence column not found.")
}

# ---- Participant brackets -------------------------------------------------
if (!is.na(vpart)) {
  part_tbl <- mm %>%
    count(.data[[vpart]], name = "n") %>%
    mutate(pct = round(100 * n / sum(n), 2)) %>%
    rename(participants_category = 1)
  message("\n-- Participants-category distribution --")
  print(as.data.frame(part_tbl), row.names = FALSE)
} else {
  part_tbl <- tibble()
  message("WARNING: participants column not found.")
}

# ---- Demand types ---------------------------------------------------------
demand_tbl <- tibble()
if (length(vdemand) > 0) {
  demand_tbl <- mm %>%
    select(all_of(vdemand)) %>%
    pivot_longer(everything(), names_to = "slot", values_to = "demand") %>%
    filter(!is.na(demand), demand != "", demand != ".") %>%
    count(demand, name = "n") %>%
    mutate(pct = round(100 * n / sum(n), 2)) %>%
    arrange(desc(n))
  message("\n-- Demand-type distribution (across demand slots 1-n) --")
  print(as.data.frame(demand_tbl), row.names = FALSE)
}

# ---- State response types -------------------------------------------------
resp_tbl <- tibble()
if (length(vresp) > 0) {
  resp_tbl <- mm %>%
    select(all_of(vresp)) %>%
    pivot_longer(everything(), names_to = "slot", values_to = "response") %>%
    filter(!is.na(response), response != "", response != ".") %>%
    count(response, name = "n") %>%
    mutate(pct = round(100 * n / sum(n), 2)) %>%
    arrange(desc(n))
  message("\n-- State-response distribution (across slots 1-n) --")
  print(as.data.frame(resp_tbl), row.names = FALSE)
}

# ---- Export ---------------------------------------------------------------
tab_dir <- here("output", "tables")
dir.create(tab_dir, showWarnings = FALSE, recursive = TRUE)

write_csv(var_inventory, file.path(tab_dir, "mm_audit_variables.csv"))
write_csv(cy_tbl,        file.path(tab_dir, "mm_audit_yearly.csv"))
write_csv(viol_tbl,      file.path(tab_dir, "mm_audit_violence.csv"))
write_csv(part_tbl,      file.path(tab_dir, "mm_audit_participants.csv"))
write_csv(demand_tbl,    file.path(tab_dir, "mm_audit_demands.csv"))
write_csv(resp_tbl,      file.path(tab_dir, "mm_audit_state_response.csv"))

# ---- LaTeX macros ---------------------------------------------------------
macro <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
years_with_events <- cy_tbl$year[cy_tbl$n_events > 0]
pct_violent <- if (!is.na(vviol) && nrow(viol_tbl) > 0)
  100 * sum(viol_tbl$n[viol_tbl$protesterviolence %in% c(1, "1", TRUE)]) /
        sum(viol_tbl$n) else NA_real_

macros <- c(
  "% Auto-generated by A_MM_01_audit_mm.R",
  paste0("% Generated: ", Sys.time()),
  macro("MMNEvents",         format(nrow(mm), big.mark = ",")),
  macro("MMNCountries",      if (!is.na(vcountry))
                                format(n_distinct(mm[[vcountry]]), big.mark = ",")
                              else "NA"),
  macro("MMYearRange",       if (length(years_with_events) > 0)
                                paste0(min(years_with_events), "--",
                                       max(years_with_events))
                              else "NA"),
  macro("MMPctViolent",      if (is.finite(pct_violent))
                                sprintf("%.2f", pct_violent) else "NA"),
  macro("MMNDemandCategories",   length(vdemand)),
  macro("MMNResponseCategories", length(vresp))
)
writeLines(macros, file.path(tab_dir, "mm_audit_macros.tex"))
message("\nWrote macros: output/tables/mm_audit_macros.tex")

sink()
