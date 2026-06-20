# LTeX: enabled=false
# ============================================================
# 07c - Robustness check warstwy 2: klastrowanie PER UCZELNIA
# Cel: sprawdzic, czy podzial "rdzen wysokoproduktywny vs reszta"
#      odtwarza sie NIEZALEZNIE w kazdej uczelni (replikacja struktury),
#      co jest mocniejszym testem jednorodnosci typologii niz sam
#      test niezaleznosci chi2 z 07 (ten mierzy tylko proporcje).
#
# Decyzje metodyczne (2026-06-18):
#  - Te same 4 cechy pelnego pokrycia co 07 (h_index_wos, sum_IF,
#    if_per_pub, n_pub); bez metryk MEiN (SGGW=100% NA).
#  - STANDARYZACJA NA SKALI PULI (scale() na pelnym X, potem podzial
#    na uczelnie). Standaryzacja wewnatrz uczelni zrobilaby z-score
#    wzgledem wlasnego rozkladu -> centroidy nieporownywalne miedzy
#    uczelniami. Pula = "wysoki IF" znaczy to samo wszedzie.
#  - WYMUSZONE k=2 w kazdej uczelni (porownywalnosc; metoda sylwetki
#    przy n~70 dla UWM bywa niestabilna i moglaby wskazac inne k).
#  - ARI liczone wzgledem przypisania z puli (km_pool), ograniczonego
#    do czlonkow danej uczelni. ARI jest niezmiennicze na etykiety.
# Input:  Dane/master/profiles_features.csv
# Output: output/klaster_per_uczelnia_centroidy.csv  (tabela 4x4 + Pula)
#         output/klaster_per_uczelnia_summary.csv    (n, ARI, sylwetka)
#         output/klaster_per_uczelnia.rds
# ============================================================

library(dplyr)
library(tidyr)
library(readr)
library(here)
library(fs)
library(cluster)

set.seed(42)

stopifnot(file_exists(here("Dane", "master", "profiles_features.csv")))
df <- read_csv(here("Dane", "master", "profiles_features.csv"), show_col_types = FALSE)

cechy <- c("h_index_wos", "sum_IF", "if_per_pub", "n_pub")

df <- df %>%
  mutate(uczelnia = factor(uczelnia, levels = c("upwr", "sggw", "urk", "uwm"))) %>%
  drop_na(all_of(cechy))

# Standaryzacja na skali PULI (zob. nota metodyczna).
X <- scale(as.matrix(df[, cechy]))

OUT_DIR <- here("output"); dir_create(OUT_DIR)

# Czytelne etykiety: cechy (PL) i uczelnie (wersaliki).
etykiety_cech <- c(h_index_wos = "h-index WoS", sum_IF = "Sumaryczny IF",
                   if_per_pub = "IF / publikacje", n_pub = "Liczba publikacji")
etykiety_ucz  <- c(upwr = "UPWr", sggw = "SGGW", urk = "URK", uwm = "UWM")

# Skorygowany indeks Randa (Hubert-Arabie), niezmienniczy na etykiety.
# Implementacja wlasna (zamiast np. mclust::adjustedRandIndex), zeby nie ciagnac
# ciezkiej zaleznosci mclust tylko dla jednej miary; wzor HA jest krotki i
# czytelny, a wynik identyczny.
adj_rand <- function(a, b) {
  tab   <- table(a, b)
  comb2 <- function(x) sum(choose(x, 2))
  n     <- sum(tab)
  idx   <- comb2(as.vector(tab))
  exp   <- comb2(rowSums(tab)) * comb2(colSums(tab)) / choose(n, 2)
  maxi  <- (comb2(rowSums(tab)) + comb2(colSums(tab))) / 2
  (idx - exp) / (maxi - exp)
}

# ---------- 1. Klastrowanie na puli (odtwarza wynik z 07) ----------
set.seed(42)
km_pool <- kmeans(X, centers = 2, nstart = 50, iter.max = 50)
hi_pool <- which.max(rowMeans(km_pool$centers))   # klaster "wysoki dorobek"

cat(sprintf("[PULA] n = %d; klaster wysoki = %d (%d osob)\n",
            nrow(X), hi_pool, sum(km_pool$cluster == hi_pool)))

# ---------- 2. Klastrowanie per uczelnia (k=2 wymuszone) ----------
centroid_rows <- list()
summ_rows     <- list()
km_objs       <- list()

for (u in levels(df$uczelnia)) {
  idx <- which(df$uczelnia == u)
  Xu  <- X[idx, , drop = FALSE]

  set.seed(42)
  km_u  <- kmeans(Xu, centers = 2, nstart = 50, iter.max = 50)
  hi_u  <- which.max(rowMeans(km_u$centers))      # lokalny klaster "wysoki"

  # Centroid (z-score, skala puli) klastra wysokiego -> wiersz tabeli 4x4.
  centroid_rows[[u]] <- as.data.frame(t(km_u$centers[hi_u, , drop = FALSE]))[, 1] |>
    (\(v) data.frame(uczelnia = u, as.list(setNames(round(v, 2), cechy)),
                     check.names = FALSE))()

  # ARI vs pula (na tych samych obserwacjach) + sylwetka + licznosci.
  ari      <- adj_rand(km_u$cluster, km_pool$cluster[idx])
  sil_mean <- mean(silhouette(km_u$cluster, dist(Xu))[, "sil_width"])
  n_hi     <- sum(km_u$cluster == hi_u)

  summ_rows[[u]] <- data.frame(
    uczelnia    = u,
    n           = length(idx),
    n_wysoki    = n_hi,
    pct_wysoki  = round(100 * n_hi / length(idx), 1),
    ARI_vs_pula = round(ari, 3),
    silhouette  = round(sil_mean, 3)
  )
  km_objs[[u]] <- km_u

  cat(sprintf("  %-5s n=%3d  wysoki=%3d (%.1f%%)  ARI=%.3f  sil=%.3f\n",
              etykiety_ucz[u], length(idx), n_hi,
              100 * n_hi / length(idx), ari, sil_mean))
}

# ---------- 3. Tabela centroidow 4x4 (+ wiersz Pula jako odniesienie) ----------
centroidy <- bind_rows(centroid_rows)

pool_centroid <- data.frame(
  uczelnia = "PULA",
  as.list(setNames(round(km_pool$centers[hi_pool, ], 2), cechy)),
  check.names = FALSE
)
centroidy_full <- bind_rows(centroidy, pool_centroid) %>%
  mutate(uczelnia = recode(uczelnia, !!!etykiety_ucz)) %>%
  rename(!!!setNames(names(etykiety_cech), etykiety_cech))

summary_tab <- bind_rows(summ_rows) %>%
  mutate(uczelnia = recode(uczelnia, !!!etykiety_ucz))

cat("\n=== Tabela centroidow klastra 'wysoki dorobek' (z-score, skala puli) ===\n")
print(centroidy_full)
cat("\n=== Zgodnosc z pula (ARI) i jakosc rozdzielenia (sylwetka) ===\n")
print(summary_tab)

# Diagnostyka spojnosci wzorca: czy wszystkie centroidy wysokie sa dodatnie?
# Kryterium diagnostyczne replikacji: jesli w KAZDEJ uczelni klaster "wysoki"
# ma dodatnie z-score na WSZYSTKICH 4 cechach, wzorzec "rdzen wysokoproduktywny"
# odtwarza sie spojnie (TAK). Wynik NIE oznaczalby, ze przynajmniej w jednej
# uczelni lokalny klaster "wysoki" jest na ktorejs cesze ponizej sredniej puli -
# czyli wzorzec nie replikuje sie jednolicie.
spojny <- all(as.matrix(centroidy[, cechy]) > 0)
cat(sprintf("\n[WZORZEC] centroidy 'wysoki' dodatnie na wszystkich cechach we wszystkich uczelniach: %s\n",
            ifelse(spojny, "TAK", "NIE")))
cat(sprintf("[WZORZEC] sredni ARI per-uczelnia vs pula = %.3f\n",
            mean(summary_tab$ARI_vs_pula)))

# ---------- 4. Zapis ----------
write_csv(centroidy_full, file.path(OUT_DIR, "klaster_per_uczelnia_centroidy.csv"))
write_csv(summary_tab,    file.path(OUT_DIR, "klaster_per_uczelnia_summary.csv"))
saveRDS(
  list(km_pool = km_pool, hi_pool = hi_pool, km_per_ucz = km_objs,
       centroidy = centroidy_full, summary = summary_tab),
  file.path(OUT_DIR, "klaster_per_uczelnia.rds")
)

cat(sprintf("\nZapisano:\n  %s\n  %s\n  %s\n",
            file.path(OUT_DIR, "klaster_per_uczelnia_centroidy.csv"),
            file.path(OUT_DIR, "klaster_per_uczelnia_summary.csv"),
            file.path(OUT_DIR, "klaster_per_uczelnia.rds")))
