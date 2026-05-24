# LTeX: enabled=false
# ============================================================
# 03 - Matching profili Omega-PSIR do OpenAlex Author ID
# Strategia: search po (imie+nazwisko, ROR uczelni) -> fuzzy match
# Input:  Dane/master/profiles_clean.csv
# Output: Dane/openalex/author_match.csv (+ raport match_rate)
# ============================================================

library(dplyr)
library(stringr)
library(httr2)
library(jsonlite)
library(stringdist)
library(readr)
library(fs)
library(here)

# ROR-y polskich uczelni rolniczych — do potwierdzenia w tygodniu 4
ROR <- c(
  upwr = "00bs9pb59",   # Uniwersytet Przyrodniczy we Wroclawiu (do weryfikacji)
  sggw = "01dr6c206",   # SGGW (do weryfikacji)
  urk  = "05j0czf65",   # Uniwersytet Rolniczy w Krakowie (do weryfikacji)
  uwm  = "02b6qw903"    # UWM Olsztyn (do weryfikacji)
)
# UWAGA: ROR-y trzeba zweryfikować na https://ror.org/search

OPENALEX_BASE <- "https://api.openalex.org"
MAILTO <- "grzegorz.kulczycki@gmail.com"  # polite pool

profiles <- read_csv(here("Dane", "master", "profiles_clean.csv"), show_col_types = FALSE)

# ---------- Helper: pojedyncze zapytanie ----------
search_openalex_author <- function(name, ror) {
  req <- request(paste0(OPENALEX_BASE, "/authors")) |>
    req_url_query(
      search = name,
      filter = paste0("affiliations.institution.ror:", ror),
      `per-page` = 25,
      mailto = MAILTO
    ) |>
    req_retry(max_tries = 3) |>
    req_throttle(rate = 10 / 1)  # 10 req/s

  resp <- tryCatch(req_perform(req), error = function(e) NULL)
  if (is.null(resp)) return(NULL)
  resp_body_json(resp)$results
}

# ---------- Helper: dopasowanie fuzzy ----------
best_match <- function(name, candidates) {
  if (length(candidates) == 0) return(NULL)
  names_cand <- map_chr(candidates, "display_name", .default = NA)
  d <- stringdist(tolower(name), tolower(names_cand), method = "jw")
  i <- which.min(d)
  list(
    openalex_id = candidates[[i]]$id,
    matched_name = names_cand[i],
    similarity = 1 - d[i]
  )
}

# ---------- Petla matchingowa ----------
matches <- profiles %>%
  mutate(idx = row_number()) %>%
  rowwise() %>%
  mutate(
    ror = ROR[uczelnia],
    candidates_n = NA_integer_,
    openalex_id = NA_character_,
    matched_name = NA_character_,
    similarity = NA_real_
  )

# TODO: zaimplementowac petle z progress barem (purrr::map z pb)
# Dla kazdego profilu: search_openalex_author(profil, ror) -> best_match(profil, ...)
# Threshold akceptacji: similarity >= 0.85 (Jaro-Winkler)
# Zapis do Dane/openalex/author_match.csv

cat("TODO: implementacja petli matchingowej (tydzien 4 harmonogramu)\n")
