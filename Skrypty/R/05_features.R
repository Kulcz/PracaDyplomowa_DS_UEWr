# LTeX: enabled=false
# ============================================================
# 05 - Feature engineering: warstwa wyprowadzonych miernikow
# Input:  Dane/master/profiles_clean.csv + Dane/openalex/publications.csv
# Output: Dane/master/profiles_features.csv  (gotowe do modelowania)
# ============================================================

library(dplyr)
library(tidyr)
library(readr)
library(here)

profiles <- read_csv(here("Dane", "master", "profiles_clean.csv"), show_col_types = FALSE)
# publications <- read_csv(here("Dane", "openalex", "publications.csv"), show_col_types = FALSE)

# ---------- 1. Cechy wyprowadzone z Omega-PSIR ----------
features <- profiles %>%
  mutate(
    if_per_pub   = sum_IF / pmax(n_pub %||% NA, 1),   # n_pub trzeba dorzucic w 02 jesli dostepne
    mein_per_pub = sum_MEiN / pmax(n_pub %||% NA, 1),
    if_to_mein   = sum_IF / pmax(sum_MEiN, 1)          # proxy internacjonalizacji
  )

# ---------- 2. Cechy z OpenAlex (po zlaczeniu) ----------
# TODO: join z publications.csv:
#   - n_unique_coauthors  (z coauthorship_edges)
#   - avg_authors_per_pub
#   - mean_fwci (Field-Weighted Citation Impact)
#   - fwci_top10_pct (czy w top 10% FWCI per dyscyplina)

# ---------- 3. Zmienne grupujace (faktoryzacja) ----------
features <- features %>%
  mutate(
    uczelnia   = factor(uczelnia, levels = c("upwr","sggw","urk","uwm")),
    dyscyplina = factor(dyscyplina),
    stanowisko = factor(stanowisko, levels = c("asystent","adiunkt","profesor uczelni","profesor"))
  )

write_csv(features, here("Dane", "master", "profiles_features.csv"))
cat("Zapisano features:", nrow(features), "rekordow\n")
