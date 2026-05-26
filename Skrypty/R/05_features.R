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
    if_per_pub   = sum_IF   / pmax(n_pub, 1),
    mein_per_pub = sum_MEiN / pmax(n_pub, 1),
    if_to_mein   = sum_IF   / pmax(sum_MEiN, 1)   # proxy internacjonalizacji
  )

# ---------- 2. Cechy z OpenAlex (po zlaczeniu) ----------
# TODO: join z publications.csv:
#   - n_unique_coauthors  (z coauthorship_edges)
#   - avg_authors_per_pub
#   - mean_fwci (Field-Weighted Citation Impact)
#   - fwci_top10_pct (czy w top 10% FWCI w probie)
#   - h_index_oa (policzony z listy cited_by_count works)

# ---------- 3. Zmienne grupujace (faktoryzacja) ----------
# FINAL 2026-05-26: 1 dyscyplina (rolnictwo i ogrodnictwo), 4 uczelnie Omega-PSIR
# (UPWr A, SGGW A, URK A, UWM B+). Czynnik dyscyplina usuniety - role w analizie
# przejmuje `stanowisko` (gradient kariery). Kategoria MEiN (A/B+) jako zmienna
# kontrolna w 06_eda_anova.
features <- features %>%
  mutate(
    uczelnia    = factor(uczelnia, levels = c("upwr","sggw","urk","uwm")),
    kategoria   = factor(ifelse(uczelnia == "uwm", "B+", "A"), levels = c("A","B+")),
    stanowisko  = factor(stanowisko, levels = c("asystent","adiunkt","profesor uczelni","profesor"))
  )

write_csv(features, here("Dane", "master", "profiles_features.csv"))
cat("Zapisano features:", nrow(features), "rekordow\n")
