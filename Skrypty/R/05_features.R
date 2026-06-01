# LTeX: enabled=false
# ============================================================
# 05 - Feature engineering: warstwa wyprowadzonych miernikow
# Input:  Dane/master/profiles_clean.csv
#         Dane/openalex/{author_match,publications,coauthorship_edges}.csv (opcjonalne)
# Output: Dane/master/profiles_features.csv  (gotowe do modelowania)
# ============================================================

library(dplyr)
library(tidyr)
library(readr)
library(here)

profiles <- read_csv(here("Dane", "master", "profiles_clean.csv"), show_col_types = FALSE)

# ---------- 1. Cechy wyprowadzone z Omega-PSIR ----------
features <- profiles %>%
  mutate(
    if_per_pub   = sum_IF   / pmax(n_pub, 1),
    mein_per_pub = sum_MEiN / pmax(n_pub, 1),
    if_to_mein   = sum_IF   / pmax(sum_MEiN, 1)   # proxy internacjonalizacji
  )

# ---------- 2. Cechy z OpenAlex (po zlaczeniu) ----------
# Join laczy 3 zbiory:
#   profiles_clean (author_id Omega) -> author_match (author_id -> openalex_id)
#   -> agregaty z publications.csv (klucz anchor_author_id == openalex_id)
#   -> n_unique_coauthors z coauthorship_edges.csv
# Jesli warstwa OpenAlex (03+04) nie zostala jeszcze uruchomiona - krok pomijany,
# a profiles_features.csv zawiera tylko cechy Omega-PSIR (pipeline 06-10 dziala dalej).
match_file <- here("Dane", "openalex", "author_match.csv")
pubs_file  <- here("Dane", "openalex", "publications.csv")
edges_file <- here("Dane", "openalex", "coauthorship_edges.csv")

# h-index z wektora cytowan: max h takie, ze h prac ma >= h cytowan.
h_index_from_citations <- function(citations) {
  c_sorted <- sort(citations[!is.na(citations)], decreasing = TRUE)
  if (length(c_sorted) == 0) return(0L)
  sum(c_sorted >= seq_along(c_sorted))
}

oa_cols <- c("n_pub_oa", "mean_fwci", "avg_authors_per_pub", "h_index_oa",
             "cited_total", "n_unique_coauthors", "fwci_top10_pct")

if (file.exists(match_file) && file.exists(pubs_file)) {
  matches <- read_csv(match_file, show_col_types = FALSE) %>%
    filter(match_accepted, !is.na(openalex_id)) %>%
    select(author_id, openalex_id)

  pubs <- read_csv(pubs_file, show_col_types = FALSE)

  # Agregaty per autor OpenAlex
  oa_author <- pubs %>%
    group_by(openalex_id = anchor_author_id) %>%
    summarise(
      n_pub_oa            = n(),
      mean_fwci           = mean(fwci, na.rm = TRUE),
      avg_authors_per_pub = mean(n_authors, na.rm = TRUE),
      h_index_oa          = h_index_from_citations(cited_by_count),
      cited_total         = sum(cited_by_count, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(mean_fwci = ifelse(is.nan(mean_fwci), NA_real_, mean_fwci))

  # Liczba unikalnych wspolautorow z edge listy (nieskierowanej, kanonicznej).
  # Autor moze byc w kolumnie a LUB b - zbieramy obie strony.
  if (file.exists(edges_file)) {
    edges <- read_csv(edges_file, show_col_types = FALSE)
    coauth <- bind_rows(
      edges %>% transmute(openalex_id = author_a, partner = author_b),
      edges %>% transmute(openalex_id = author_b, partner = author_a)
    ) %>%
      group_by(openalex_id) %>%
      summarise(n_unique_coauthors = n_distinct(partner), .groups = "drop")
    oa_author <- oa_author %>% left_join(coauth, by = "openalex_id")
  } else {
    oa_author$n_unique_coauthors <- NA_integer_
  }

  # Flaga: czy autor w top 10% sredniego FWCI w probie
  thr_fwci <- quantile(oa_author$mean_fwci, 0.9, na.rm = TRUE)
  oa_author <- oa_author %>%
    mutate(fwci_top10_pct = !is.na(mean_fwci) & mean_fwci >= thr_fwci)

  # Przeniesienie na poziom profilu (Omega author_id)
  oa_per_profile <- matches %>%
    left_join(oa_author, by = "openalex_id") %>%
    select(-openalex_id)

  features <- features %>% left_join(oa_per_profile, by = "author_id")

  matched_n <- sum(!is.na(features$n_pub_oa))
  cat(sprintf("Cechy OpenAlex dolaczone dla %d / %d profili (%.1f%%)\n",
              matched_n, nrow(features), 100 * matched_n / nrow(features)))
} else {
  # Brak warstwy OpenAlex - dokladamy puste kolumny dla spojnosci schematu 06-10
  for (col in oa_cols) features[[col]] <- NA
  message("[05] Brak danych OpenAlex (03+04 nieuruchomione) - cechy OA = NA.")
}

# ---------- 3. Zmienne grupujace (faktoryzacja) ----------
# FINAL 2026-05-26: 1 dyscyplina (rolnictwo i ogrodnictwo), 4 uczelnie Omega-PSIR
# (UPWr A, SGGW A, URK A, UWM B+). Czynnik dyscyplina usuniety - role w analizie
# przejmuje `stanowisko` (gradient kariery). Kategoria MEiN (A/B+) jako zmienna
# kontrolna w 06_eda_anova.
features <- features %>%
  mutate(
    uczelnia    = factor(uczelnia, levels = c("upwr", "sggw", "urk", "uwm")),
    kategoria   = factor(ifelse(uczelnia == "uwm", "B+", "A"), levels = c("A", "B+")),
    stanowisko  = factor(stanowisko, levels = c("asystent", "adiunkt", "profesor uczelni", "profesor"))
  )

write_csv(features, here("Dane", "master", "profiles_features.csv"))
cat("Zapisano features:", nrow(features), "rekordow,", ncol(features), "kolumn\n")
