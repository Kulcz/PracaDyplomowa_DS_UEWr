# LTeX: enabled=false
# ============================================================
# 07 - Warstwa 2 z planu DS: PCA + klastrowanie
# Cel: typologia profili bibliometrycznych (k-means + walidacja silhouette/gap)
#
# Decyzje metodyczne (2026-06-13):
#  - Cechy klastrowania: metryki o PELNYM pokryciu wszystkich 4 uczelni
#    (h_index_wos, sum_IF, if_per_pub, n_pub). NIE uzywamy sum_MEiN/if_to_mein,
#    bo SGGW=100% NA -> drop_na wyrzucilby cale SGGW z typologii (bias).
#  - Zmienne grupujace do walidacji zewnetrznej (chi2): uczelnia, stanowisko
#    (dawniej dyscyplina - usunieta po zmianie koncepcji proby).
# Input:  Dane/master/profiles_features.csv
# Output: Wykresy/klastrowanie/*.png, output/clusters.rds, output/klaster_profile.csv
# ============================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(readr)
library(here)
library(fs)
library(FactoMineR)
library(factoextra)
library(cluster)
library(patchwork)

set.seed(42)

stopifnot(file_exists(here("Dane", "master", "profiles_features.csv")))
df <- read_csv(here("Dane", "master", "profiles_features.csv"), show_col_types = FALSE)

# Cechy o pelnym pokryciu (zob. nota metodyczna) - bez metryk MEiN.
cechy_klaster <- c("h_index_wos", "sum_IF", "if_per_pub", "n_pub")

df <- df %>%
  mutate(
    uczelnia   = factor(uczelnia, levels = c("upwr", "sggw", "urk", "uwm")),
    stanowisko = factor(stanowisko,
                        levels = c("asystent", "adiunkt", "profesor uczelni", "profesor"))
  ) %>%
  drop_na(all_of(cechy_klaster))

X <- df %>% select(all_of(cechy_klaster)) %>% scale()

PLOT_DIR <- here("Wykresy", "klastrowanie"); dir_create(PLOT_DIR)
OUT_DIR  <- here("output");                   dir_create(OUT_DIR)

cat(sprintf("[START] n = %d profili, %d cech\n", nrow(X), ncol(X)))
cat("Pokrycie uczelni w probie klastrowania:\n")
print(table(df$uczelnia))

# ---------- 1. PCA ----------
pca <- PCA(X, graph = FALSE, ncp = ncol(X))
eig <- as.data.frame(pca$eig)
cat("\n=== PCA: wariancja wyjaśniona ===\n")
print(round(eig, 2))

p_scree <- fviz_eig(pca, addlabels = TRUE, ylim = c(0, 100)) +
  labs(title = "Scree plot: wariancja wyjaśniona przez komponenty")
ggsave(file.path(PLOT_DIR, "01_pca_scree.png"), p_scree,
       width = 8, height = 5, dpi = 200)

# Biplot kolorowany stanowiskiem (NA stanowiska -> "b.d." na potrzeby wykresu)
stan_lab <- factor(ifelse(is.na(df$stanowisko), "b.d.", as.character(df$stanowisko)),
                   levels = c("asystent", "adiunkt", "profesor uczelni", "profesor", "b.d."))
p_biplot_stan <- fviz_pca_biplot(
  pca,
  geom.ind = "point",
  pointshape = 21, pointsize = 2,
  fill.ind = stan_lab,
  col.var = "black", alpha.var = 0.6, repel = TRUE,
  legend.title = "Stanowisko"
) + labs(title = "PCA biplot — kolor: stanowisko")
ggsave(file.path(PLOT_DIR, "02_pca_biplot_stanowisko.png"), p_biplot_stan,
       width = 9, height = 7, dpi = 200)

p_biplot_ucz <- fviz_pca_biplot(
  pca,
  geom.ind = "point",
  pointshape = 21, pointsize = 2,
  fill.ind = df$uczelnia,
  col.var = "black", alpha.var = 0.6, repel = TRUE,
  legend.title = "Uczelnia"
) + labs(title = "PCA biplot — kolor: uczelnia")
ggsave(file.path(PLOT_DIR, "03_pca_biplot_uczelnia.png"), p_biplot_ucz,
       width = 9, height = 7, dpi = 200)

# ---------- 2. Walidacja k: silhouette + gap statistic ----------
K_MAX <- 8
cat(sprintf("\n=== Walidacja k (zakres 2-%d) ===\n", K_MAX))

p_sil <- fviz_nbclust(X, kmeans, method = "silhouette", k.max = K_MAX, nstart = 25) +
  labs(title = "Średnia szerokość sylwetki (silhouette)")
p_gap <- fviz_nbclust(X, kmeans, method = "gap_stat", k.max = K_MAX,
                      nstart = 25, nboot = 50) +
  labs(title = "Statystyka luki (gap)")

ggsave(file.path(PLOT_DIR, "04_walidacja_k.png"),
       p_sil + p_gap, width = 14, height = 5, dpi = 200)

# Wyciagamy k optymalne z silhouette (argmax)
sil_data <- p_sil$data
k_opt <- as.integer(sil_data$clusters[which.max(sil_data$y)])
cat(sprintf("Wybrane k (max silhouette) = %d\n", k_opt))

# ---------- 3. K-means + profilowanie klastrów ----------
km <- kmeans(X, centers = k_opt, nstart = 50, iter.max = 50)
df$klaster <- factor(km$cluster)

# Profile klastrów: srednia kazdej cechy w skali oryginalnej
profile <- df %>%
  group_by(klaster) %>%
  summarise(
    n = n(),
    across(all_of(cechy_klaster), ~ round(mean(.x, na.rm = TRUE), 2)),
    .groups = "drop"
  )
cat("\n=== Profile klastrów (oryginalna skala) ===\n")
print(profile)
write_csv(profile, file.path(OUT_DIR, "klaster_profile.csv"))

# Wizualizacja klastrów na PCA
p_clust <- fviz_cluster(
  list(data = X, cluster = km$cluster),
  geom = "point",
  ellipse.type = "convex",
  palette = "Set2"
) + labs(title = sprintf("Klastry k-means (k = %d) w przestrzeni PC1-PC2", k_opt))
ggsave(file.path(PLOT_DIR, "05_kmeans_clusters.png"), p_clust,
       width = 9, height = 7, dpi = 200)

# Heatmapa centroidow (skala standaryzowana - dla porownania cech)
centr_std <- as.data.frame(km$centers) %>%
  mutate(klaster = factor(seq_len(nrow(km$centers)))) %>%
  pivot_longer(-klaster, names_to = "cecha", values_to = "z")

p_centroidy <- ggplot(centr_std, aes(x = klaster, y = cecha, fill = z)) +
  geom_tile() +
  geom_text(aes(label = sprintf("%.2f", z)), size = 3.5) +
  scale_fill_gradient2(low = "#3C5488", mid = "white", high = "#E64B35",
                       midpoint = 0) +
  labs(title = sprintf("Centroidy klastrów (z-scores, k = %d)", k_opt),
       x = "Klaster", y = NULL, fill = "z") +
  theme_minimal(base_size = 12)
ggsave(file.path(PLOT_DIR, "06_centroidy_heatmap.png"), p_centroidy,
       width = 7, height = 5, dpi = 200)

# ---------- 4. Porównanie z Ward hierarchical ----------
hc <- hclust(dist(X), method = "ward.D2")
df$klaster_ward <- factor(cutree(hc, k = k_opt))

p_dend <- fviz_dend(hc, k = k_opt, cex = 0.4, color_labels_by_k = TRUE,
                    rect = TRUE, show_labels = FALSE) +
  labs(title = sprintf("Dendrogram Warda (k = %d)", k_opt))
ggsave(file.path(PLOT_DIR, "07_dendrogram_ward.png"), p_dend,
       width = 12, height = 6, dpi = 200)

# Zgodność k-means vs Ward (cross-table + Cramer's V)
ct_km_ward <- table(km = df$klaster, ward = df$klaster_ward)
cat("\n=== Cross-table: k-means vs Ward ===\n"); print(ct_km_ward)

cramers_v <- function(tab) {
  chi <- suppressWarnings(chisq.test(tab))
  n <- sum(tab)
  k <- min(nrow(tab), ncol(tab))
  sqrt(as.numeric(chi$statistic) / (n * (k - 1)))
}
cat(sprintf("Cramer's V (k-means vs Ward) = %.3f\n", cramers_v(ct_km_ward)))

# ---------- 5. chi2: klaster vs uczelnia / stanowisko ----------
# Walidacja zewnetrzna: czy typologia profili pokrywa sie z afiliacja / rola.
cat("\n=== chi2 niezależności: klaster vs uczelnia / stanowisko ===\n")
ct_ucz  <- table(klaster = df$klaster, uczelnia = df$uczelnia)
# stanowisko: wykluczamy NA (table domyslnie pomija NA)
df_stan <- df %>% filter(!is.na(stanowisko)) %>% mutate(stanowisko = droplevels(stanowisko))
ct_stan <- table(klaster = df_stan$klaster, stanowisko = df_stan$stanowisko)

print(ct_ucz)
chi_ucz <- suppressWarnings(chisq.test(ct_ucz))
cat(sprintf("chi2 vs uczelnia: X2 = %.2f, df = %d, p = %.4g, Cramer's V = %.3f\n",
            chi_ucz$statistic, chi_ucz$parameter, chi_ucz$p.value,
            cramers_v(ct_ucz)))

print(ct_stan)
chi_stan <- suppressWarnings(chisq.test(ct_stan))
cat(sprintf("chi2 vs stanowisko: X2 = %.2f, df = %d, p = %.4g, Cramer's V = %.3f\n",
            chi_stan$statistic, chi_stan$parameter, chi_stan$p.value,
            cramers_v(ct_stan)))

# ---------- 6. Zapis ----------
saveRDS(
  list(
    pca       = pca,
    k_opt     = k_opt,
    kmeans    = km,
    hclust    = hc,
    df        = df,                 # df z dolaczonymi kolumnami klaster / klaster_ward
    profile   = profile,
    crosstabs = list(km_ward = ct_km_ward, ucz = ct_ucz, stan = ct_stan),
    cramers_v = list(
      km_ward = cramers_v(ct_km_ward),
      ucz     = cramers_v(ct_ucz),
      stan    = cramers_v(ct_stan)
    )
  ),
  file.path(OUT_DIR, "clusters.rds")
)

cat(sprintf("\nZapisano: %s\nWykresy : %s\n",
            file.path(OUT_DIR, "clusters.rds"), PLOT_DIR))
